#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
STATE_FILE="${STATE_FILE:-$SCRIPT_DIR/.setup-state.env}"
TEMPLATE="${TEMPLATE:-$SCRIPT_DIR/templates/config.yaml}"
OUTPUT="${OUTPUT:-$SCRIPT_DIR/config.rendered.yaml}"

# ── 加载普通配置与 secrets ──
load_env_file() {
    local file="$1"
    if [ -f "$file" ]; then
        set -a
        # shellcheck source=/dev/null
        source "$file"
        set +a
    fi
}
load_env_file "$STATE_FILE"
load_env_file "$ENV_FILE"

: "${LLM_PROVIDER:=deepseek}"
: "${LLM_MODEL:=deepseek-v4-flash}"
: "${LLM_BASE_URL:=https://api.deepseek.com/v1}"
# Backward compatibility with older .env files that only had provider-specific keys.
: "${HERMES_MODEL_API_KEY:=${LLM_API_KEY:-${DEEPSEEK_API_KEY:-${CUSTOM_LLM_API_KEY:-}}}}"
export LLM_PROVIDER LLM_MODEL LLM_BASE_URL HERMES_MODEL_API_KEY

# ── 渲染 ──
echo "Rendering config from template..."
python3 - "$TEMPLATE" "$OUTPUT" <<'PY'
import os
import sys

template, output = sys.argv[1:3]
with open(template, encoding="utf-8") as f:
    text = f.read()
# Preserve the runtime secret reference so config.rendered.yaml never contains
# the plaintext API key. Hermes loads profile .env and expands this itself.
placeholder = "__HERMES_MODEL_API_KEY_REF__"
text = text.replace("${HERMES_MODEL_API_KEY}", placeholder)
text = os.path.expandvars(text)
text = text.replace(placeholder, "${HERMES_MODEL_API_KEY}")
with open(output, "w", encoding="utf-8") as f:
    f.write(text)
PY

# ── 追加 MCP 配置 ──
. "$SCRIPT_DIR/lib/append-mcp.sh" "$OUTPUT"

# ── 检查未展开变量 ──
UNSET=$(grep -oE '\$\{[A-Z_]+\}' "$OUTPUT" | sed 's/\${//;s/}//' | grep -v '^HERMES_MODEL_API_KEY$' | sort -u || true)
if [ -n "$UNSET" ]; then
    echo "⚠ WARNING: unset variables: $UNSET"
else
    echo "✓ All non-secret variables expanded"
fi

# ── cp 进容器 ──
if docker ps --format '{{.Names}}' | grep -q '^hermes-single$' 2>/dev/null; then
    PROFILE="${AGENT_NAME:-kaguya}"
    docker cp "$OUTPUT" "hermes-single:/opt/data/profiles/$PROFILE/config.rendered.yaml"
    docker cp "$ENV_FILE" "hermes-single:/opt/data/profiles/$PROFILE/.env"
    docker exec hermes-single chown "10000:10000" "/opt/data/profiles/$PROFILE/.env" "/opt/data/profiles/$PROFILE/config.rendered.yaml" 2>/dev/null || true
    docker exec hermes-single chmod 600 "/opt/data/profiles/$PROFILE/.env" 2>/dev/null || true
    echo "✓ Copied config and profile .env into container"
else
    echo "⚠ Container not running, config saved to $OUTPUT only"
    echo "  Next startup will pick it up from custom-init.sh"
fi

echo "✓ Done: $OUTPUT"
