# 追加 Playwright MCP 配置到指定 YAML 文件
# 用法: source lib/append-mcp.sh <config_file_path>
# 依赖环境变量: MCP_PLAYWRIGHT_ENABLED

_append_mcp_file="$1"
if [ "${MCP_PLAYWRIGHT_ENABLED:-false}" = "true" ]; then
    if ! grep -q "playwright-mcp" "$_append_mcp_file" 2>/dev/null; then
        cat >> "$_append_mcp_file" << 'MCPEOF'
mcp_servers:
  playwright:
    url: "http://playwright-mcp:8931/mcp"
    timeout: 120
MCPEOF
    fi
fi
unset _append_mcp_file
