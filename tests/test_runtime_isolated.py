import shutil
import subprocess
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
TEST_CONTAINER = "hermes-single-test-runtime"
TEST_PROJECT = "hermes_single_test_runtime"
TEST_PROFILE = "kaguya"
TEST_KEY = "sk-test-runtime"
TEST_BASE_URL = "https://api.gaoxin.net.cn/v1"


def run(cmd, cwd=None, timeout=300):
    return subprocess.run(
        cmd,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def docker_ps_lines():
    result = run(["docker", "ps", "--format", "{{.Names}} {{.Status}}"])
    assert result.returncode == 0, result.stderr
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def wait_initialized(timeout=120):
    start = time.time()
    while time.time() - start < timeout:
        result = run(["docker", "exec", TEST_CONTAINER, "test", "-f", "/opt/data/.initialized"], timeout=20)
        if result.returncode == 0:
            return
        time.sleep(2)
    raise AssertionError("test container did not become initialized in time")


def build_runtime_dir(tmp_path):
    runtime = tmp_path / "runtime"
    runtime.mkdir()
    for rel in ["docker-compose.yml", "custom-init.sh", "render-config.sh"]:
        shutil.copy(ROOT / rel, runtime / rel)
    shutil.copytree(ROOT / "templates", runtime / "templates")
    shutil.copytree(ROOT / "lib", runtime / "lib")

    soul = runtime / "SOUL.md"
    soul.write_text("test soul", encoding="utf-8")

    state = runtime / ".setup-state.env"
    state.write_text(
        "\n".join(
            [
                f"AGENT_NAME={TEST_PROFILE}",
                f"CONTAINER_NAME={TEST_CONTAINER}",
                "LLM_PROVIDER=custom",
                "CUSTOM_LLM_PROVIDER_NAME=ziikoo",
                "LLM_PROVIDER_API_KEY_ENV=CUSTOM_LLM_API_KEY",
                "LLM_PROVIDER_BASE_URL_ENV=CUSTOM_LLM_BASE_URL",
                "LLM_MODEL=gpt-5.4",
                f"LLM_BASE_URL={TEST_BASE_URL}",
                "MODEL_CONTEXT_LENGTH=1000000",
                "COMPRESSION_ENABLED=true",
                "COMPRESSION_THRESHOLD=0.85",
                f"SOUL_PATH={soul}",
                "TERMINAL_ENV=ssh",
                "SSH_HOST=127.0.0.1",
                "SSH_USER=tester",
                "MEMORY_TOOL_ENABLED=false",
                "DISABLED_TOOLSETS=[memory]",
                "MEMORY_NUDGE_INTERVAL=0",
                "SKILL_NUDGE_INTERVAL=0",
                "TOOL_PROGRESS=verbose",
                "SHOW_REASONING=true",
                "MCP_PLAYWRIGHT_ENABLED=false",
                "PROXY_ENABLED=false",
                "PROXY_HOST=",
                "PROXY_PORT=7890",
            ]
        )
        + "\n",
        encoding="utf-8",
    )

    env = runtime / ".env"
    env.write_text(
        "\n".join(
            [
                f"HERMES_MODEL_API_KEY={TEST_KEY}",
                "DEEPSEEK_API_KEY=",
                f"CUSTOM_LLM_API_KEY={TEST_KEY}",
                "API_SERVER_KEY=fixed-runtime-key",
                f"SOUL_PATH={soul}",
                f"CUSTOM_LLM_BASE_URL={TEST_BASE_URL}",
            ]
        )
        + "\n",
        encoding="utf-8",
    )

    override = runtime / "docker-compose.override.yml"
    override.write_text(
        "services:\n  hermes:\n    container_name: hermes-single-test-runtime\n",
        encoding="utf-8",
    )
    return runtime


@pytest.fixture
def isolated_runtime(tmp_path):
    before = docker_ps_lines()
    before_without_test = [line for line in before if not line.startswith(f"{TEST_CONTAINER} ")]
    assert any(line.startswith("hermes ") for line in before_without_test), "working hermes container must stay present"
    runtime = build_runtime_dir(tmp_path)
    yield runtime, before_without_test


def test_custom_init_creates_profile_directory(isolated_runtime):
    runtime, _before = isolated_runtime
    up = run(["docker", "compose", "-p", TEST_PROJECT, "up", "-d"], cwd=runtime, timeout=300)
    assert up.returncode == 0, up.stderr
    wait_initialized()
    result = run(
        [
            "docker",
            "exec",
            TEST_CONTAINER,
            "sh",
            "-lc",
            (
                f"test -d /opt/data/profiles/{TEST_PROFILE} "
                f"&& test -f /opt/data/profiles/{TEST_PROFILE}/.env "
                f"&& test -f /opt/data/profiles/{TEST_PROFILE}/config.yaml "
                f"&& test -f /opt/data/profiles/{TEST_PROFILE}/memories/MEMORY.md "
                f"&& test -f /opt/data/profiles/{TEST_PROFILE}/memories/USER.md"
            ),
        ]
    )
    assert result.returncode == 0, result.stderr
    after = docker_ps_lines()
    assert any(line.startswith("hermes ") for line in after)
    assert any(line.startswith(f"{TEST_CONTAINER} ") for line in after)


def test_render_config_updates_active_top_level_and_removes_rendered_file(isolated_runtime):
    runtime, _before = isolated_runtime
    cleanup = ROOT / "scripts" / "cleanup-test-runtime.sh"
    preclean = run(["bash", str(cleanup)], cwd=ROOT, timeout=300)
    assert preclean.returncode == 0, preclean.stderr + preclean.stdout

    up = run(["docker", "compose", "-p", TEST_PROJECT, "up", "-d"], cwd=runtime, timeout=300)
    assert up.returncode == 0, up.stderr
    wait_initialized()

    render = run(["bash", "./render-config.sh"], cwd=runtime, timeout=300)
    assert render.returncode == 0, render.stderr + render.stdout

    inspect = run(
        [
            "docker",
            "exec",
            TEST_CONTAINER,
            "sh",
            "-lc",
            (
                f"sed -n '1,10p' /opt/data/profiles/{TEST_PROFILE}/config.yaml "
                f"&& echo ---top--- "
                f"&& sed -n '1,10p' /opt/data/config.yaml "
                f"&& echo ---env--- "
                f"&& sed -n '1,10p' /opt/data/profiles/{TEST_PROFILE}/.env "
                f"&& echo ---rendered-exists--- "
                f"&& if test -f /opt/data/profiles/{TEST_PROFILE}/config.rendered.yaml; then echo yes; else echo no; fi"
            ),
        ]
    )
    assert inspect.returncode == 0, inspect.stderr
    out = inspect.stdout
    active, rest = out.split("---top---", 1)
    top, rest = rest.split("---env---", 1)
    env_text, rendered_exists = rest.split("---rendered-exists---", 1)

    assert "provider: custom" in active
    assert "model: gpt-5.4" in active
    assert f"base_url: {TEST_BASE_URL}" in active
    assert "provider: custom" in top
    assert "model: gpt-5.4" in top
    assert f"base_url: {TEST_BASE_URL}" in top
    assert f"HERMES_MODEL_API_KEY={TEST_KEY}" in env_text
    assert f"CUSTOM_LLM_API_KEY={TEST_KEY}" in env_text
    assert rendered_exists.strip() == "no"


def test_restart_preserves_custom_active_and_top_level_config_without_rendered_file(isolated_runtime):
    runtime, _before = isolated_runtime
    cleanup = ROOT / "scripts" / "cleanup-test-runtime.sh"
    preclean = run(["bash", str(cleanup)], cwd=ROOT, timeout=300)
    assert preclean.returncode == 0, preclean.stderr + preclean.stdout

    up = run(["docker", "compose", "-p", TEST_PROJECT, "up", "-d"], cwd=runtime, timeout=300)
    assert up.returncode == 0, up.stderr
    wait_initialized()

    render = run(["bash", "./render-config.sh"], cwd=runtime, timeout=300)
    assert render.returncode == 0, render.stderr + render.stdout

    down = run(["docker", "compose", "-p", TEST_PROJECT, "down"], cwd=runtime, timeout=300)
    assert down.returncode == 0, down.stderr
    up2 = run(["docker", "compose", "-p", TEST_PROJECT, "up", "-d"], cwd=runtime, timeout=300)
    assert up2.returncode == 0, up2.stderr
    wait_initialized()

    inspect = run(
        [
            "docker",
            "exec",
            TEST_CONTAINER,
            "sh",
            "-lc",
            (
                f"sed -n '1,10p' /opt/data/profiles/{TEST_PROFILE}/config.yaml "
                f"&& echo ---top--- "
                f"&& sed -n '1,10p' /opt/data/config.yaml "
                f"&& echo ---rendered-exists--- "
                f"&& if test -f /opt/data/profiles/{TEST_PROFILE}/config.rendered.yaml; then echo yes; else echo no; fi"
            ),
        ]
    )
    assert inspect.returncode == 0, inspect.stderr
    out = inspect.stdout
    active, rest = out.split("---top---", 1)
    top, rendered_exists = rest.split("---rendered-exists---", 1)

    assert "provider: custom" in active
    assert "model: gpt-5.4" in active
    assert f"base_url: {TEST_BASE_URL}" in active
    assert "provider: custom" in top
    assert "model: gpt-5.4" in top
    assert f"base_url: {TEST_BASE_URL}" in top
    assert rendered_exists.strip() == "no"
