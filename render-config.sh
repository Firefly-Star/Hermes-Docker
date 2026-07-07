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

: "${LLM_PROVIDER:=deepseek}"
: "${LLM_MODEL:=deepseek-v4-flash}"
: "${LLM_BASE_URL:=https://api.deepseek.com/v1}"
: "${LLM_API_KEY:=${DEEPSEEK_API_KEY:-${CUSTOM_LLM_API_KEY:-}}}"

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
. "$SCRIPT_DIR/lib/append-mcp.sh" "$OUTPUT"

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
else
    echo "⚠ Container not running, config saved to $OUTPUT only"
    echo "  Next startup will pick it up from custom-init.sh"
fi

echo "✓ Done: $OUTPUT"
