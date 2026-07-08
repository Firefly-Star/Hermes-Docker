import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run_bash(script: str, env=None, timeout=30):
    merged_env = os.environ.copy()
    merged_env.update(env or {})
    return subprocess.run(
        ["bash", "-lc", script],
        cwd=ROOT,
        env=merged_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def build_common_exports(env_file, state_file, soul=None, soul_file=None, home_dir=None, extra_exports=None, **_ignored):
    soul_path = soul_file if soul_file is not None else soul
    exports = [
        "export HERMES_SINGLE_TEST_MODE=1",
        "source ./setup.sh",
        f"ENV_FILE={env_file!s}",
        f"STATE_FILE={state_file!s}",
        f"SOUL_PATH={soul_path!s}",
        "AGENT_NAME=kaguya",
        "CONTAINER_NAME=hermes-test",
        "SSH_HOST=127.0.0.1",
        "SSH_USER=tester",
        "API_SERVER_KEY=fixed",
        "MEMORY_TOOL_ENABLED=true",
        "DISABLED_TOOLSETS='[]'",
        "MEMORY_NUDGE_INTERVAL=10",
        "SKILL_NUDGE_INTERVAL=10",
        "TOOL_PROGRESS=all",
        "SHOW_REASONING=false",
        "MCP_PLAYWRIGHT_ENABLED=false",
        "COMPRESSION_ENABLED=true",
        "COMPRESSION_THRESHOLD=0.85",
        "MODEL_CONTEXT_LENGTH=",
        "PROXY_ENABLED=false",
        "PROXY_HOST=",
        "PROXY_PORT=7890",
    ]
    if home_dir is not None:
        exports.append(f"HOME={home_dir!s}")
    for k, v in (extra_exports or {}).items():
        exports.append(f"{k}={v}")
    return "\n".join(exports)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")
