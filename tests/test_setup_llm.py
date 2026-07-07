import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run_bash(script: str, env=None):
    merged_env = os.environ.copy()
    merged_env.update(env or {})
    return subprocess.run(
        ["bash", "-lc", script],
        cwd=ROOT,
        env=merged_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )


def test_deepseek_llm_provider_writes_deepseek_config_to_env(tmp_path):
    env_file = tmp_path / ".env"
    soul = tmp_path / "SOUL.md"
    soul.write_text("soul", encoding="utf-8")

    result = run_bash(
        f'''
        set -e
        export HERMES_SINGLE_TEST_MODE=1
        source ./setup.sh
        ENV_FILE={env_file!s}
        AGENT_NAME=kaguya
        SOUL_PATH={soul!s}
        SSH_HOST=127.0.0.1
        SSH_USER=tester
        API_SERVER_KEY=fixed
        MEMORY_TOOL_ENABLED=true
        DISABLED_TOOLSETS='[]'
        MEMORY_NUDGE_INTERVAL=10
        SKILL_NUDGE_INTERVAL=10
        TOOL_PROGRESS=all
        SHOW_REASONING=false
        MCP_PLAYWRIGHT_ENABLED=false
        prompt_llm_provider <<'INPUT'
1
sk-deepseek
INPUT
        write_env
        ''',
    )

    assert result.returncode == 0, result.stderr + result.stdout
    content = env_file.read_text(encoding="utf-8")
    assert "LLM_PROVIDER=deepseek" in content
    assert "LLM_MODEL=deepseek-v4-flash" in content
    assert "LLM_BASE_URL=https://api.deepseek.com/v1" in content
    assert "DEEPSEEK_API_KEY=sk-deepseek" in content


def test_custom_llm_provider_fetches_models_and_writes_selection(tmp_path):
    env_file = tmp_path / ".env"
    soul = tmp_path / "SOUL.md"
    soul.write_text("soul", encoding="utf-8")

    server = tmp_path / "server.py"
    server.write_text(
        """
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/v1/models':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'data': [{'id': 'alpha'}, {'id': 'beta'}]}).encode())
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, *args):
        pass
HTTPServer(('127.0.0.1', 8765), H).serve_forever()
""".strip(),
        encoding="utf-8",
    )

    result = run_bash(
        f'''
        set -e
        python3 {server!s} &
        srv=$!
        trap 'kill $srv 2>/dev/null || true' EXIT
        for i in {{1..30}}; do
            if python3 - <<'PY'
import urllib.request
urllib.request.urlopen('http://127.0.0.1:8765/v1/models', timeout=1).read()
PY
            then break; fi
            sleep 0.1
        done
        export HERMES_SINGLE_TEST_MODE=1
        source ./setup.sh
        ENV_FILE={env_file!s}
        AGENT_NAME=kaguya
        SOUL_PATH={soul!s}
        SSH_HOST=127.0.0.1
        SSH_USER=tester
        API_SERVER_KEY=fixed
        MEMORY_TOOL_ENABLED=true
        DISABLED_TOOLSETS='[]'
        MEMORY_NUDGE_INTERVAL=10
        SKILL_NUDGE_INTERVAL=10
        TOOL_PROGRESS=all
        SHOW_REASONING=false
        MCP_PLAYWRIGHT_ENABLED=false
        prompt_llm_provider <<'INPUT'
2
my-provider
http://127.0.0.1:8765/v1
sk-custom
2
INPUT
        write_env
        ''',
    )

    assert result.returncode == 0, result.stderr + result.stdout
    content = env_file.read_text(encoding="utf-8")
    assert "LLM_PROVIDER=my-provider" in content
    assert "LLM_MODEL=beta" in content
    assert "LLM_BASE_URL=http://127.0.0.1:8765/v1" in content
    assert "CUSTOM_LLM_API_KEY=sk-custom" in content
