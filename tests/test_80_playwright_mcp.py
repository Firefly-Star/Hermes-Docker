from tests.helpers import build_common_exports, run_bash


def test_prompt_playwright_mcp_enable_without_proxy(temp_setup_files):
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        prompt_playwright_mcp <<'INPUT'
y
n
INPUT
        printf 'MCP=%s\nPROXY=%s' "$MCP_PLAYWRIGHT_ENABLED" "$PROXY_ENABLED"
        '''
    )
    assert result.returncode == 0
    assert 'MCP=true' in result.stdout
    assert 'PROXY=false' in result.stdout


def test_prompt_playwright_mcp_enable_with_proxy(temp_setup_files):
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        prompt_playwright_mcp <<'INPUT'
y
y
10.0.0.1
8888
INPUT
        printf 'MCP=%s\nPROXY=%s\nHOST=%s\nPORT=%s' "$MCP_PLAYWRIGHT_ENABLED" "$PROXY_ENABLED" "$PROXY_HOST" "$PROXY_PORT"
        '''
    )
    assert result.returncode == 0
    assert 'MCP=true' in result.stdout
    assert 'PROXY=true' in result.stdout
    assert 'HOST=10.0.0.1' in result.stdout
    assert 'PORT=8888' in result.stdout
