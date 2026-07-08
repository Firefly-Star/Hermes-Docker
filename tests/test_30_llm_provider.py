import os
import socket
import textwrap
from pathlib import Path

from tests.helpers import build_common_exports, run_bash


def _free_port():
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    port = s.getsockname()[1]
    s.close()
    return port


def test_normalize_base_url_strips_trailing_slashes(temp_setup_files):
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        printf '%s' "$(normalize_base_url https://example.com/v1///)"
        '''
    )
    assert result.returncode == 0
    assert result.stdout.strip().endswith('https://example.com/v1')


def test_prompt_llm_provider_selects_deepseek(temp_setup_files):
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        prompt_llm_provider <<'INPUT'
1
sk-deepseek
INPUT
        printf 'PROVIDER=%s\nMODEL=%s\nKEYENV=%s\nBASEENV=%s' "$LLM_PROVIDER" "$LLM_MODEL" "$LLM_PROVIDER_API_KEY_ENV" "$LLM_PROVIDER_BASE_URL_ENV"
        '''
    )
    assert result.returncode == 0
    assert 'PROVIDER=deepseek' in result.stdout
    assert 'MODEL=deepseek-v4-flash' in result.stdout
    assert 'KEYENV=DEEPSEEK_API_KEY' in result.stdout
    assert 'BASEENV=DEEPSEEK_BASE_URL' in result.stdout


def test_prompt_llm_provider_selects_custom_and_fetches_models(temp_setup_files):
    port = _free_port()
    server = temp_setup_files['tmp_path'] / 'server.py'
    server.write_text(textwrap.dedent(f'''
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
    '''), encoding='utf-8')
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
2
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
