#!/bin/bash
set -e

HERMES_HOME="${HERMES_HOME:-/opt/data}"
TEMPLATES="${HERMES_HOME}/templates"
PROFILE="${AGENT_NAME:-kaguya}"

# ── 权限修复 ──
chown -R 10000:10000 /opt/data/ 2>/dev/null || true
grep -q "source /opt/hermes/.venv/bin/activate" /root/.bashrc 2>/dev/null ||
  echo "source /opt/hermes/.venv/bin/activate" >> /root/.bashrc

# ── 确保 profile 目录存在 ──
mkdir -p "$HERMES_HOME/profiles/$PROFILE"

# ── 渲染 profile config ──
if [ -f "$HERMES_HOME/profiles/$PROFILE/config.rendered.yaml" ]; then
    # 宿主机预渲染版本优先
    cp "$HERMES_HOME/profiles/$PROFILE/config.rendered.yaml" "$HERMES_HOME/profiles/$PROFILE/config.yaml"
    echo "init: using pre-rendered config"
elif [ -f "$TEMPLATES/config.yaml" ]; then
    # fallback: 容器内渲染
    python3 -c "
import os, sys
with open('$TEMPLATES/config.yaml') as f:
    sys.stdout.write(os.path.expandvars(f.read()))
" > "$HERMES_HOME/profiles/$PROFILE/config.yaml"
    echo "init: rendered config from template"
    # ── 按条件追加 MCP 配置（playwright） ──
    if [ "${MCP_PLAYWRIGHT_ENABLED:-false}" = "true" ]; then
        if ! grep -q "playwright-mcp" "$HERMES_HOME/profiles/$PROFILE/config.yaml" 2>/dev/null; then
            cat >> "$HERMES_HOME/profiles/$PROFILE/config.yaml" << 'MCPEOF'
mcp_servers:
  playwright:
    url: "http://playwright-mcp:8931/mcp"
    timeout: 120
MCPEOF
        fi
    fi
fi

# ── 复制 MEMORY.md / USER.md 模板到 profile memories ──
MEMORIES_DIR="$HERMES_HOME/profiles/$PROFILE/memories"
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
