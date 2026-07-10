import os
import shutil
import socket
import subprocess
import textwrap
import time
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_DIR = ROOT / "tests" / "fixtures" / "expected"
TEST_CONTAINER = "hermes-single-setup-e2e"
TEST_PROJECT = "hermes_single_setup_e2e"

TEST_PROFILE = "kaguya-e2e"
TEST_KEY = "***"
TEST_BASE_URL = "http://127.0.0.1:{port}/v1"


def run(cmd, cwd=None, timeout=300, env=None, input_text=None):
    merged = os.environ.copy()
    if env:
        merged.update(env)
    return subprocess.run(
        cmd,
        cwd=cwd,
        env=merged,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def docker_ps_lines():
    result = run(["docker", "ps", "--format", "{{.Names}} {{.Status}}"])
    assert result.returncode == 0, result.stderr
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def wait_initialized(container, timeout=180):
    start = time.time()
    while time.time() - start < timeout:
        result = run(["docker", "exec", container, "test", "-f", "/opt/data/.initialized"], timeout=20)
        if result.returncode == 0:
            return
        time.sleep(2)
    raise AssertionError("setup e2e test container did not become initialized in time")


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def build_setup_e2e_runtime(tmp_path, port):
    runtime = tmp_path / "setup-e2e-runtime"
    shutil.copytree(ROOT, runtime)
    for rel in [".env", ".setup-state.env", "docker-compose.override.yml"]:
        path = runtime / rel
        if path.exists():
            path.unlink()
    soul = runtime / "SOUL.md"
    soul.write_text("setup e2e soul", encoding="utf-8")
    return runtime, soul


def start_model_server(tmp_path, port):
    server = tmp_path / "server.py"
    server.write_text(textwrap.dedent(f'''
        from http.server import BaseHTTPRequestHandler, HTTPServer
        import json
        class H(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path == '/v1/models':
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json')
                    self.end_headers()
                    self.wfile.write(json.dumps({{'data':[{{'id':'gpt-5.4'}}]}}).encode())
                else:
                    self.send_response(404)
                    self.end_headers()
            def log_message(self, *args):
                pass
        HTTPServer(('127.0.0.1', {port}), H).serve_forever()
    '''), encoding='utf-8')
    proc = subprocess.Popen(["python3", str(server)])
    for _ in range(50):
        try:
            import urllib.request
            urllib.request.urlopen(f"http://127.0.0.1:{port}/v1/models", timeout=1).read()
            return proc
        except Exception:
            time.sleep(0.1)
    proc.kill()
    raise AssertionError("local model server failed to start")


def build_expected_e2e_profile_env(soul, base_url):
    fixture = yaml.safe_load(
        (EXPECTED_DIR / "setup_e2e_custom_profile_env.yaml").read_text(encoding="utf-8")
    )
    env_map = fixture["profile_env"]
    env_map.pop("API_SERVER_KEY", None)
    env_map["SOUL_PATH"] = str(soul)
    env_map["CUSTOM_LLM_BASE_URL"] = base_url
    return env_map


def build_expected_e2e_config_head(base_url):
    fixture = yaml.safe_load(
        (EXPECTED_DIR / "setup_e2e_custom_config_head.yaml").read_text(encoding="utf-8")
    )
    cfg = fixture["config_head"]
    cfg["model"]["base_url"] = base_url
    return yaml.safe_dump(cfg, sort_keys=False)


def parse_env_text(text):
    result = {}
    for line in text.strip().splitlines():
        if not line.strip() or "=" not in line:
            continue
        key, value = line.split("=", 1)
        result[key] = value
    return result


def assert_env_matches_expected(actual_text, expected_map):
    actual = parse_env_text(actual_text)
    api_server_key = actual.pop("API_SERVER_KEY", None)
    assert api_server_key is not None
    assert len(api_server_key) == 64
    assert all(ch in "0123456789abcdef" for ch in api_server_key)
    assert actual == expected_map


@pytest.fixture
def setup_e2e_runtime(tmp_path):
    before = docker_ps_lines()
    assert any(line.startswith("hermes ") for line in before), "working hermes container must stay present"
    port = free_port()
    runtime, soul = build_setup_e2e_runtime(tmp_path, port)
    proc = start_model_server(tmp_path, port)
    try:
        yield runtime, soul, port, before
    finally:
        proc.kill()
        proc.wait(timeout=5)


def test_setup_sh_e2e_launches_isolated_container(setup_e2e_runtime):
    runtime, soul, port, _before = setup_e2e_runtime
    cleanup = ROOT / "scripts" / "cleanup-test-setup-e2e.sh"
    preclean = run(["bash", str(cleanup)], cwd=ROOT, timeout=300)
    assert preclean.returncode == 0, preclean.stderr + preclean.stdout

    env = {"COMPOSE_PROJECT_NAME": TEST_PROJECT}
    inputs = "\n".join([
        TEST_PROFILE,
        TEST_CONTAINER,
        "29",
        "ziikoo",
        TEST_BASE_URL.format(port=port),
        TEST_KEY,
        "1",
        "tester",
        str(soul),
        "n",
        "y",
        "y",
        "0.85",
        "1000000",
        "n",
        "127.0.0.1",
        "",
        "n",
    ]) + "\n"

    result = run(
        ["bash", "setup.sh"],
        cwd=runtime,
        timeout=600,
        env=env | {"PYTHONUNBUFFERED": "1"},
        input_text=inputs,
    )
    if result.returncode != 0:
        raise AssertionError(result.stdout + "\n---STDERR---\n" + result.stderr)

    wait_initialized(TEST_CONTAINER)
    after = docker_ps_lines()
    assert any(line.startswith("hermes ") for line in after)
    assert any(line.startswith(f"{TEST_CONTAINER} ") for line in after)

    inspect = run([
        "docker", "exec", TEST_CONTAINER, "sh", "-lc",
        f"sed -n '1,10p' /opt/data/profiles/{TEST_PROFILE}/config.yaml && echo ---top--- && sed -n '1,10p' /opt/data/config.yaml && echo ---env--- && sed -n '1,10p' /opt/data/profiles/{TEST_PROFILE}/.env && echo ---top-env--- && sed -n '1,10p' /opt/data/.env && echo ---rendered-exists--- && if test -f /opt/data/profiles/{TEST_PROFILE}/config.rendered.yaml; then echo yes; else echo no; fi"
    ], timeout=300)
    assert inspect.returncode == 0, inspect.stderr
    out = inspect.stdout
    active, rest = out.split('---top---', 1)
    top, rest = rest.split('---env---', 1)
    env_text, rest = rest.split('---top-env---', 1)
    top_env_text, rendered_exists = rest.split('---rendered-exists---', 1)
    expected_config_head = build_expected_e2e_config_head(TEST_BASE_URL.format(port=port))
    expected_env = build_expected_e2e_profile_env(soul, TEST_BASE_URL.format(port=port))
    assert active.strip() + "\n" == expected_config_head
    assert top.strip() + "\n" == expected_config_head
    assert_env_matches_expected(env_text, expected_env)
    assert_env_matches_expected(top_env_text, expected_env)
    assert rendered_exists.strip() == "no"
