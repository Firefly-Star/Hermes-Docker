import os
import shutil
import socket
import subprocess
import textwrap
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
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
        "2",
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
        f"sed -n '1,10p' /opt/data/profiles/{TEST_PROFILE}/config.yaml && echo ---top--- && sed -n '1,10p' /opt/data/config.yaml && echo ---env--- && sed -n '1,10p' /opt/data/profiles/{TEST_PROFILE}/.env && echo ---rendered-exists--- && if test -f /opt/data/profiles/{TEST_PROFILE}/config.rendered.yaml; then echo yes; else echo no; fi"
    ], timeout=300)
    assert inspect.returncode == 0, inspect.stderr
    out = inspect.stdout
    active, rest = out.split('---top---', 1)
    top, rest = rest.split('---env---', 1)
    env_text, rendered_exists = rest.split('---rendered-exists---', 1)
    assert "provider: custom" in active
    assert "model: gpt-5.4" in active
    assert f"base_url: {TEST_BASE_URL.format(port=port)}" in active
    assert "provider: custom" in top
    assert "model: gpt-5.4" in top
    assert TEST_KEY in env_text
    assert rendered_exists.strip() == "no"
