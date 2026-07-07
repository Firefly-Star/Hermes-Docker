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


def common_exports(env_file, state_file, soul):
    return f"""
        export HERMES_SINGLE_TEST_MODE=1
        source ./setup.sh
        ENV_FILE={env_file!s}
        STATE_FILE={state_file!s}
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
        COMPRESSION_ENABLED=true
        COMPRESSION_THRESHOLD=0.85
        MODEL_CONTEXT_LENGTH=
    """


def test_deepseek_llm_provider_splits_state_and_secret_env(tmp_path):
    env_file = tmp_path / ".env"
    state_file = tmp_path / ".setup-state.env"
    soul = tmp_path / "SOUL.md"
    soul.write_text("soul", encoding="utf-8")

    result = run_bash(
        f'''
        set -e
        {common_exports(env_file, state_file, soul)}
        prompt_llm_provider <<'INPUT'
1
sk-deepseek
INPUT
        write_env
        ''',
    )

    assert result.returncode == 0, result.stderr + result.stdout
    secrets = env_file.read_text(encoding="utf-8")
    state = state_file.read_text(encoding="utf-8")

    assert "HERMES_MODEL_API_KEY=sk-deepseek" in secrets
    assert "DEEPSEEK_API_KEY=sk-deepseek" in secrets
    assert "API_SERVER_KEY=fixed" in secrets
    assert "LLM_PROVIDER=" not in secrets
    assert "LLM_MODEL=" not in secrets
    assert "LLM_BASE_URL=" not in secrets

    assert "LLM_PROVIDER=deepseek" in state
    assert "LLM_MODEL=deepseek-v4-flash" in state
    assert "LLM_BASE_URL=https://api.deepseek.com/v1" in state
    assert "COMPRESSION_ENABLED=true" in state
    assert "COMPRESSION_THRESHOLD=0.85" in state
    assert "MODEL_CONTEXT_LENGTH=" in state
    assert "DEEPSEEK_API_KEY=" not in state
    assert "HERMES_MODEL_API_KEY=" not in state


def test_custom_llm_provider_fetches_models_and_splits_state_and_secret_env(tmp_path):
    env_file = tmp_path / ".env"
    state_file = tmp_path / ".setup-state.env"
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
        {common_exports(env_file, state_file, soul)}
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
    secrets = env_file.read_text(encoding="utf-8")
    state = state_file.read_text(encoding="utf-8")

    assert "HERMES_MODEL_API_KEY=sk-custom" in secrets
    assert "CUSTOM_LLM_API_KEY=sk-custom" in secrets
    assert "LLM_PROVIDER=" not in secrets
    assert "LLM_MODEL=" not in secrets
    assert "LLM_BASE_URL=" not in secrets

    assert "LLM_PROVIDER=custom" in state
    assert "CUSTOM_LLM_PROVIDER_NAME=my-provider" in state
    assert "LLM_MODEL=beta" in state
    assert "LLM_BASE_URL=http://127.0.0.1:8765/v1" in state
    assert "CUSTOM_LLM_API_KEY=" not in state
    assert "HERMES_MODEL_API_KEY=" not in state


def test_prompt_compression_and_context_length_write_state(tmp_path):
    env_file = tmp_path / ".env"
    state_file = tmp_path / ".setup-state.env"
    soul = tmp_path / "SOUL.md"
    soul.write_text("soul", encoding="utf-8")

    result = run_bash(
        f'''
        set -e
        {common_exports(env_file, state_file, soul)}
        HERMES_MODEL_API_KEY=sk-test
        prompt_compression <<'INPUT'
y
0.90
INPUT
        prompt_model_context_length <<'INPUT'
131072
INPUT
        write_env
        ''',
    )

    assert result.returncode == 0, result.stderr + result.stdout
    state = state_file.read_text(encoding="utf-8")
    secrets = env_file.read_text(encoding="utf-8")
    assert "COMPRESSION_ENABLED=true" in state
    assert "COMPRESSION_THRESHOLD=0.90" in state
    assert "MODEL_CONTEXT_LENGTH=131072" in state
    assert "COMPRESSION_THRESHOLD=" not in secrets
    assert "MODEL_CONTEXT_LENGTH=" not in secrets


def test_rendered_config_keeps_api_key_as_env_reference_and_context_length_optional(tmp_path):
    env_file = tmp_path / ".env"
    state_file = tmp_path / ".setup-state.env"
    output = tmp_path / "config.rendered.yaml"
    env_file.write_text("HERMES_MODEL_API_KEY=sk-secret\nDEEPSEEK_API_KEY=sk-secret\nAPI_SERVER_KEY=fixed\n", encoding="utf-8")
    base_state = (
        "AGENT_NAME=kaguya\n"
        "LLM_PROVIDER=deepseek\n"
        "LLM_MODEL=deepseek-v4-flash\n"
        "LLM_BASE_URL=https://api.deepseek.com/v1\n"
        "COMPRESSION_ENABLED=true\n"
        "COMPRESSION_THRESHOLD=0.85\n"
        "TERMINAL_ENV=ssh\n"
        "SSH_HOST=127.0.0.1\n"
        "SSH_USER=tester\n"
        "DISABLED_TOOLSETS=[]\n"
        "MEMORY_NUDGE_INTERVAL=10\n"
        "SKILL_NUDGE_INTERVAL=10\n"
        "SHOW_REASONING=false\n"
    )
    state_file.write_text(base_state + "MODEL_CONTEXT_LENGTH=\n", encoding="utf-8")

    result = run_bash(f"ENV_FILE={env_file!s} STATE_FILE={state_file!s} OUTPUT={output!s} ./render-config.sh")
    assert result.returncode == 0, result.stderr + result.stdout
    rendered = output.read_text(encoding="utf-8")
    assert "provider: deepseek" in rendered
    assert "default: deepseek-v4-flash" in rendered
    assert "base_url: https://api.deepseek.com/v1" in rendered
    assert "api_key: ${HERMES_MODEL_API_KEY}" in rendered
    assert "threshold: 0.85" in rendered
    assert "context_length:" not in rendered
    assert "sk-secret" not in rendered

    state_file.write_text(base_state + "MODEL_CONTEXT_LENGTH=131072\n", encoding="utf-8")
    result = run_bash(f"ENV_FILE={env_file!s} STATE_FILE={state_file!s} OUTPUT={output!s} ./render-config.sh")
    assert result.returncode == 0, result.stderr + result.stdout
    rendered = output.read_text(encoding="utf-8")
    assert "  context_length: 131072" in rendered
    assert "api_key: ${HERMES_MODEL_API_KEY}" in rendered
    assert "sk-secret" not in rendered
