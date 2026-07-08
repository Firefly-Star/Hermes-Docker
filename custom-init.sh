#!/bin/bash
set -e

HERMES_HOME="${HERMES_HOME:-/opt/data}"
TEMPLATES="${HERMES_HOME}/templates"
PROFILE="${AGENT_NAME:-kaguya}"
PROFILE_DIR="$HERMES_HOME/profiles/$PROFILE"

# ── 权限修复 ──
chown -R 10000:10000 /opt/data/ 2>/dev/null || true
grep -q "source /opt/hermes/.venv/bin/activate" /root/.bashrc 2>/dev/null ||
  echo "source /opt/hermes/.venv/bin/activate" >> /root/.bashrc

# 容器镜像内的 stage2 hook 会在 custom-init 之后运行，并在首次启动时用
# /opt/data/config.yaml 作为 profile 默认配置来源。这里同步一份顶层 config，
# 避免 stage2 在我们已经写好 profile/config.rendered.yaml 后，又把 profile
# config.yaml 用镜像默认 deepseek 配置覆盖回去。
TOP_LEVEL_CONFIG="$HERMES_HOME/config.yaml"

# ── 确保 profile 目录存在 ──
mkdir -p "$PROFILE_DIR"

: "${LLM_PROVIDER:=deepseek}"
: "${LLM_MODEL:=deepseek-v4-flash}"
: "${LLM_BASE_URL:=https://api.deepseek.com/v1}"
: "${HERMES_MODEL_API_KEY:=${LLM_API_KEY:-${DEEPSEEK_API_KEY:-${CUSTOM_LLM_API_KEY:-}}}}"
: "${MODEL_CONTEXT_LENGTH:=}"
: "${COMPRESSION_ENABLED:=true}"
: "${COMPRESSION_THRESHOLD:=0.85}"
if [ -n "$MODEL_CONTEXT_LENGTH" ]; then
    MODEL_CONTEXT_LENGTH_LINE="  context_length: $MODEL_CONTEXT_LENGTH"
else
    MODEL_CONTEXT_LENGTH_LINE=""
fi
export LLM_PROVIDER LLM_MODEL LLM_BASE_URL MODEL_CONTEXT_LENGTH MODEL_CONTEXT_LENGTH_LINE COMPRESSION_ENABLED COMPRESSION_THRESHOLD HERMES_MODEL_API_KEY

# ── 确保 profile .env 存在，Hermes 启动时会自动加载它 ──
if [ ! -f "$PROFILE_DIR/.env" ]; then
    cat > "$PROFILE_DIR/.env" << EOF
HERMES_MODEL_API_KEY=${HERMES_MODEL_API_KEY}
DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY:-}
CUSTOM_LLM_API_KEY=${CUSTOM_LLM_API_KEY:-}
API_SERVER_KEY=${API_SERVER_KEY:-}
EOF
    chown 10000:10000 "$PROFILE_DIR/.env" 2>/dev/null || true
    chmod 600 "$PROFILE_DIR/.env" 2>/dev/null || true
fi

# ── 渲染 profile config ──
if [ -f "$PROFILE_DIR/config.yaml" ]; then
    cp "$PROFILE_DIR/config.yaml" "$TOP_LEVEL_CONFIG"
    echo "init: using project-managed active config"
elif [ -f "$TEMPLATES/config.yaml" ]; then
    # fallback: 容器内渲染。保留 ${HERMES_MODEL_API_KEY}，避免 config.yaml 落明文 key。
    python3 - "$TEMPLATES/config.yaml" "$PROFILE_DIR/config.yaml" <<'PY'
import os
import sys

template, output = sys.argv[1:3]
with open(template, encoding="utf-8") as f:
    text = f.read()
placeholder = "__HERMES_MODEL_API_KEY_REF__"
text = text.replace("${HERMES_MODEL_API_KEY}", placeholder)
text = text.replace("# ${MODEL_CONTEXT_LENGTH_LINE}", os.environ.get("MODEL_CONTEXT_LENGTH_LINE", ""))
text = os.path.expandvars(text)
text = text.replace(placeholder, "${HERMES_MODEL_API_KEY}")
with open(output, "w", encoding="utf-8") as f:
    f.write(text)
PY
    echo "init: rendered config from template"
    cp "$PROFILE_DIR/config.yaml" "$TOP_LEVEL_CONFIG"
    # ── 追加 MCP 配置 ──
    . "$HERMES_HOME/lib/append-mcp.sh" "$PROFILE_DIR/config.yaml"
    . "$HERMES_HOME/lib/append-mcp.sh" "$TOP_LEVEL_CONFIG"
fi
rm -f "$PROFILE_DIR/config.rendered.yaml" 2>/dev/null || true
chown 10000:10000 "$PROFILE_DIR/config.yaml" 2>/dev/null || true
chown 10000:10000 "$TOP_LEVEL_CONFIG" 2>/dev/null || true

# ── 复制 MEMORY.md / USER.md 模板到 profile memories ──
MEMORIES_DIR="$PROFILE_DIR/memories"
mkdir -p "$MEMORIES_DIR"
for f in MEMORY.md USER.md; do
    if [ -f "$TEMPLATES/$f" ]; then
        # cp -u: 源比目标新时才复制（首次初始化 / 模板更新时自动同步）
        cp -u "$TEMPLATES/$f" "$MEMORIES_DIR/$f"
        echo "init: synced $f from template"
    fi
done

# ── 初始化标记 ──
touch "$HERMES_HOME/.initialized" 2>/dev/null || true
