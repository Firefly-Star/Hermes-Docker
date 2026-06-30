#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
TEMPLATE="$SCRIPT_DIR/templates/config.yaml"
OUTPUT="$SCRIPT_DIR/config.rendered.yaml"

# ── 加载 .env ──
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

# ── 渲染 ──
echo "Rendering config from template..."
python3 -c "
import os, sys
with open('$TEMPLATE') as f:
    expanded = os.path.expandvars(f.read())
with open('$OUTPUT', 'w') as f:
    f.write(expanded)
"

# ── 追加 MCP 配置 ──
if [ "${MCP_PLAYWRIGHT_ENABLED:-false}" = "true" ]; then
    if ! grep -q "playwright-mcp" "$OUTPUT" 2>/dev/null; then
        echo "Appending Playwright MCP config..."
        cat >> "$OUTPUT" << 'MCPEOF'
mcp_servers:
  playwright:
    url: "http://playwright-mcp:8931/mcp"
    timeout: 120
MCPEOF
    fi
fi

# ── 检查未展开变量 ──
UNSET=$(grep -oE '\$\{[A-Z_]+\}' "$OUTPUT" | sed 's/\${//;s/}//' | sort -u)
if [ -n "$UNSET" ]; then
    echo "⚠ WARNING: unset variables: $UNSET"
else
    echo "✓ All variables expanded"
fi

# ── cp 进容器 ──
if docker ps --format '{{.Names}}' | grep -q '^hermes-single$' 2>/dev/null; then
    PROFILE="${AGENT_NAME:-kaguya}"
    docker cp "$OUTPUT" "hermes-single:/opt/data/profiles/$PROFILE/config.rendered.yaml"
    echo "✓ Copied into container"
fi

echo "✓ Done: $OUTPUT"
