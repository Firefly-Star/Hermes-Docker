#!/bin/bash
set -e

HERMES_HOME="${HERMES_HOME:-/opt/data}"
TEMPLATES="${HERMES_HOME}/templates"
PROFILE="${AGENT_NAME:-kaguya}"

# ── 权限修复 ──
chown -R 10000:10000 /opt/data/ 2>/dev/null || true
grep -q "source /opt/hermes/.venv/bin/activate" /root/.bashrc 2>/dev/null ||
  echo "source /opt/hermes/.venv/bin/activate" >> /root/.bashrc

# ── 渲染 profile config ──
render() {
    python3 -c "
import os, sys
with open('${1}') as f:
    sys.stdout.write(os.path.expandvars(f.read()))
"
}

if [ -f "$TEMPLATES/config.yaml" ]; then
    render "$TEMPLATES/config.yaml" > "$HERMES_HOME/profiles/$PROFILE/config.yaml"
fi

# ── 按条件追加 MCP 配置（playwright） ──
if [ "${MCP_PLAYWRIGHT_ENABLED:-false}" = "true" ]; then
    cat >> "$HERMES_HOME/profiles/$PROFILE/config.yaml" << 'MCPEOF'
mcp_servers:
  playwright:
    url: "http://playwright-mcp:8931/mcp"
    timeout: 120
MCPEOF
fi
