import json
import socket
import textwrap
from pathlib import Path

from tests.helpers import build_common_exports, run_bash


def _provider_catalog():
    return json.loads(
        Path('/home/wxz/task5/hermes-single/data/hermes-providers.json').read_text(encoding='utf-8')
    )


def test_provider_catalog_contains_setup_supported_entries():
    data = _provider_catalog()
    supported = {p['slug'] for p in data['providers'] if p.get('setup_supported')}
    assert 'openai-api' in supported
    assert 'openrouter' in supported
    assert 'deepseek' in supported
    assert 'custom' in supported
    assert 'nous' not in supported


def _free_port():
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    port = s.getsockname()[1]
    s.close()
    return port


def test_prompt_llm_provider_selects_openai_api_from_catalog(temp_setup_files):
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        prompt_llm_provider <<'INPUT'
5
sk-openai
3
INPUT
        printf 'PROVIDER=%s\nMODEL=%s\nKEYENV=%s\nBASEENV=%s\nBASE=%s' "$LLM_PROVIDER" "$LLM_MODEL" "$LLM_PROVIDER_API_KEY_ENV" "$LLM_PROVIDER_BASE_URL_ENV" "$LLM_BASE_URL"
        '''
    )
    assert result.returncode == 0
    assert 'PROVIDER=openai-api' in result.stdout
    assert 'KEYENV=OPENAI_API_KEY' in result.stdout
    assert 'BASEENV=OPENAI_BASE_URL' in result.stdout
    assert 'BASE=https://api.openai.com/v1' in result.stdout


def test_prompt_llm_provider_selects_openrouter_from_catalog(temp_setup_files):
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        prompt_llm_provider <<'INPUT'
1
sk-openrouter
2
INPUT
        printf 'PROVIDER=%s\nMODEL=%s\nKEYENV=%s\nBASEENV=%s\nBASE=%s' "$LLM_PROVIDER" "$LLM_MODEL" "$LLM_PROVIDER_API_KEY_ENV" "$LLM_PROVIDER_BASE_URL_ENV" "$LLM_BASE_URL"
        '''
    )
    assert result.returncode == 0
    assert 'PROVIDER=openrouter' in result.stdout
    assert 'KEYENV=OPENROUTER_API_KEY' in result.stdout
    assert 'BASEENV=OPENROUTER_BASE_URL' in result.stdout
    assert 'BASE=https://openrouter.ai/api/v1' in result.stdout


def test_prompt_llm_provider_selects_deepseek(temp_setup_files):
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        LLM_MODEL=deepseek-v4-flash
        prompt_llm_provider <<'INPUT'
13
sk-deepseek
2
INPUT
        printf 'PROVIDER=%s\nMODEL=%s\nKEYENV=%s\nBASEENV=%s' "$LLM_PROVIDER" "$LLM_MODEL" "$LLM_PROVIDER_API_KEY_ENV" "$LLM_PROVIDER_BASE_URL_ENV"
        '''
    )
    assert result.returncode == 0
    assert 'PROVIDER=deepseek' in result.stdout
    assert 'MODEL=deepseek-v4-flash' in result.stdout
    assert 'KEYENV=DEEPSEEK_API_KEY' in result.stdout
    assert 'BASEENV=DEEPSEEK_BASE_URL' in result.stdout


def test_prompt_llm_provider_custom_allows_manual_model_if_models_fetch_fails(temp_setup_files):
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        prompt_llm_provider <<'INPUT'
29
manual-provider
http://127.0.0.1:9/v1
sk-custom
manual-model
INPUT
        printf 'PROVIDER=%s\nNAME=%s\nMODEL=%s\nKEYENV=%s\nBASEENV=%s' "$LLM_PROVIDER" "$CUSTOM_LLM_PROVIDER_NAME" "$LLM_MODEL" "$LLM_PROVIDER_API_KEY_ENV" "$LLM_PROVIDER_BASE_URL_ENV"
        ''',
        timeout=60,
    )
    assert result.returncode == 0
    assert 'PROVIDER=custom' in result.stdout
    assert 'NAME=manual-provider' in result.stdout
    assert 'MODEL=manual-model' in result.stdout
    assert 'KEYENV=CUSTOM_LLM_API_KEY' in result.stdout
    assert 'BASEENV=CUSTOM_LLM_BASE_URL' in result.stdout


def test_prompt_llm_provider_selects_custom_and_fetches_models(temp_setup_files):
    port = _free_port()
    server = temp_setup_files['tmp_path'] / 'server.py'
    server.write_text(
        textwrap.dedent(
            f'''
            from http.server import BaseHTTPRequestHandler, HTTPServer
            import json
            class H(BaseHTTPRequestHandler):
                def do_GET(self):
                    if self.path == '/v1/models':
                        self.send_response(200)
                        self.send_header('Content-Type', 'application/json')
                        self.end_headers()
                        self.wfile.write(json.dumps({{'data':[{{'id':'alpha'}},{{'id':'beta'}}]}}).encode())
                    else:
                        self.send_response(404)
                        self.end_headers()
                def log_message(self, *args):
                    pass
            HTTPServer(('127.0.0.1', {port}), H).serve_forever()
            '''
        ),
        encoding='utf-8',
    )
    result = run_bash(
        f'''
        python3 {server} &
        srv=$!
        trap 'kill $srv 2>/dev/null || true' EXIT
        for i in {{1..30}}; do
          python3 - <<'PY' && break || true
import urllib.request
urllib.request.urlopen('http://127.0.0.1:{port}/v1/models', timeout=1).read()
PY
          sleep 0.1
        done
        {build_common_exports(**temp_setup_files)}
        prompt_llm_provider <<'INPUT'
29
my-provider
http://127.0.0.1:{port}/v1
sk-custom
2
INPUT
        printf 'PROVIDER=%s\nNAME=%s\nMODEL=%s\nKEYENV=%s\nBASEENV=%s' "$LLM_PROVIDER" "$CUSTOM_LLM_PROVIDER_NAME" "$LLM_MODEL" "$LLM_PROVIDER_API_KEY_ENV" "$LLM_PROVIDER_BASE_URL_ENV"
        ''',
        timeout=60,
    )
    assert result.returncode == 0
    assert 'PROVIDER=custom' in result.stdout
    assert 'NAME=my-provider' in result.stdout
    assert 'MODEL=beta' in result.stdout
    assert 'KEYENV=CUSTOM_LLM_API_KEY' in result.stdout
    assert 'BASEENV=CUSTOM_LLM_BASE_URL' in result.stdout
