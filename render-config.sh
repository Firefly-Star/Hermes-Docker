#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
STATE_FILE="${STATE_FILE:-$SCRIPT_DIR/.setup-state.env}"
TEMPLATE="${TEMPLATE:-$SCRIPT_DIR/templates/config.yaml}"
OUTPUT="${OUTPUT:-$SCRIPT_DIR/config.rendered.yaml}"
ACTIVE_OUTPUT="${ACTIVE_OUTPUT:-$SCRIPT_DIR/config.active.yaml}"

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
: "${MODEL_CONTEXT_LENGTH:=}"
: "${COMPRESSION_ENABLED:=true}"
: "${COMPRESSION_THRESHOLD:=0.85}"
if [ -n "$MODEL_CONTEXT_LENGTH" ]; then
    MODEL_CONTEXT_LENGTH_LINE="  context_length: $MODEL_CONTEXT_LENGTH"
else
    MODEL_CONTEXT_LENGTH_LINE=""
fi
: "${CONTAINER_NAME:=hermes}"
# Backward compatibility with older .env files that only had provider-specific keys.
: "${HERMES_MODEL_API_KEY:=${LLM_API_KEY:-${DEEPSEEK_API_KEY:-${CUSTOM_LLM_API_KEY:-}}}}"
export CONTAINER_NAME LLM_PROVIDER LLM_MODEL LLM_BASE_URL MODEL_CONTEXT_LENGTH MODEL_CONTEXT_LENGTH_LINE COMPRESSION_ENABLED COMPRESSION_THRESHOLD HERMES_MODEL_API_KEY

# ── 渲染 ──
echo "Rendering config from template..."
python3 - "$TEMPLATE" "$OUTPUT" "$ACTIVE_OUTPUT" <<'PY'
import os
import sys

template, output = sys.argv[1:3]
with open(template, encoding="utf-8") as f:
    text = f.read()
# Preserve the runtime secret reference so active config never contains
# the plaintext API key. Hermes loads profile .env and expands this itself.
secret_placeholder = "__HERMES_MODEL_API_KEY_REF__"
text = text.replace("${HERMES_MODEL_API_KEY}", secret_placeholder)
# MODEL_CONTEXT_LENGTH_LINE is optional. Keep the template valid YAML by storing
# it as a comment, then replace the whole comment with either the real key or an
# empty line before generic env expansion.
text = text.replace("# ${MODEL_CONTEXT_LENGTH_LINE}", os.environ.get("MODEL_CONTEXT_LENGTH_LINE", ""))
text = os.path.expandvars(text)
text = text.replace(secret_placeholder, "${HERMES_MODEL_API_KEY}")
with open(output, "w", encoding="utf-8") as f:
    f.write(text)
with open(sys.argv[3], "w", encoding="utf-8") as f:
    f.write(text)
PY

# ── 追加 MCP 配置 ──
. "$SCRIPT_DIR/lib/append-mcp.sh" "$OUTPUT"
. "$SCRIPT_DIR/lib/append-mcp.sh" "$ACTIVE_OUTPUT"

# ── 检查未展开变量 ──
UNSET=$(grep -oE '\$\{[A-Z_]+\}' "$OUTPUT" | sed 's/\${//;s/}//' | grep -v '^HERMES_MODEL_API_KEY$' | sort -u || true)
if [ -n "$UNSET" ]; then
    echo "⚠ WARNING: unset variables: $UNSET"
else
    echo "✓ All non-secret variables expanded"
fi

# ── cp 进容器 ──
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" 2>/dev/null; then
    PROFILE="${AGENT_NAME:-kaguya}"
    docker cp "$ACTIVE_OUTPUT" "${CONTAINER_NAME}:/opt/data/profiles/$PROFILE/config.yaml"
    docker cp "$ACTIVE_OUTPUT" "${CONTAINER_NAME}:/opt/data/config.yaml"
    docker exec "$CONTAINER_NAME" rm -f "/opt/data/profiles/$PROFILE/config.rendered.yaml" 2>/dev/null || true
    docker cp "$ENV_FILE" "${CONTAINER_NAME}:/opt/data/profiles/$PROFILE/.env"
    docker cp "$ENV_FILE" "${CONTAINER_NAME}:/opt/data/.env"
    docker exec "$CONTAINER_NAME" chown "10000:10000" "/opt/data/profiles/$PROFILE/.env" "/opt/data/profiles/$PROFILE/config.yaml" "/opt/data/config.yaml" "/opt/data/.env" 2>/dev/null || true
    docker exec "$CONTAINER_NAME" chmod 600 "/opt/data/profiles/$PROFILE/.env" "/opt/data/.env" 2>/dev/null || true
    echo "✓ Copied active config and both top-level/profile .env into container"
else
    echo "⚠ Container not running, config saved to $ACTIVE_OUTPUT only"
    echo "  Next startup will pick it up from custom-init.sh"
fi

echo "✓ Done: $ACTIVE_OUTPUT"
