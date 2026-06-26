#!/bin/bash
set -e

source /opt/hermes/.venv/bin/activate

HERMES_HOME="${HERMES_HOME:-/opt/data}"
TEMPLATES="/opt/data/templates"
PROFILE="${AGENT_NAME:-kaguya}"
MARKER="$HERMES_HOME/.initialized"

# ── 确保模板渲染需要的变量都有值 ──
# SSH_HOST 由 setup.sh 自动检测并写入 .env
# 未运行 setup.sh 时默认使用 host.docker.internal（原生 Linux 有效）
TERMINAL_ENV="${TERMINAL_ENV:-ssh}"
SSH_HOST="${SSH_HOST:-host.docker.internal}"
SSH_USER="${SSH_USER:-hermes}"
export TERMINAL_ENV SSH_HOST SSH_USER

render() {
    python3 -c "
import os, sys
with open('${1}') as f:
    sys.stdout.write(os.path.expandvars(f.read()))
"
}

# ── 首次：生成全局配置 ──
if [ ! -f "$MARKER" ]; then
    echo "=== Initializing Hermes config ==="
    render "$TEMPLATES/config.yaml" > "$HERMES_HOME/config.yaml"
    render "$TEMPLATES/global.env" > "$HERMES_HOME/.env"
    touch "$MARKER"
    echo "=== Global config initialized ==="
fi

# ── 创建 profile ──
if [ ! -d "$HERMES_HOME/profiles/$PROFILE" ]; then
    echo "Creating profile: $PROFILE"
    hermes profile create "$PROFILE"
fi

render "$TEMPLATES/profile.env" > "$HERMES_HOME/profiles/$PROFILE/.env"
if [ -n "$API_SERVER_KEY" ]; then
    sed -i "s|^API_SERVER_KEY=.*|API_SERVER_KEY=$API_SERVER_KEY|" "$HERMES_HOME/profiles/$PROFILE/.env"
fi
render "$TEMPLATES/config.yaml" > "$HERMES_HOME/profiles/$PROFILE/config.yaml"

# ── 复制用户 SOUL.md ──
if [ -f "$HERMES_HOME/custom_SOUL.md" ]; then
    cp "$HERMES_HOME/custom_SOUL.md" "$HERMES_HOME/profiles/$PROFILE/SOUL.md"
    echo "=== SOUL.md loaded ==="
else
    echo "=== WARNING: custom_SOUL.md not found ==="
fi

# ── 首次启动：预填部署上下文到 Agent 记忆 ──
MEMORY_DIR="$HERMES_HOME/profiles/$PROFILE/memories"
MEMORY_MARKER="$HERMES_HOME/.memory_seeded"
if [ ! -f "$MEMORY_MARKER" ]; then
    mkdir -p "$MEMORY_DIR"
    cp "$TEMPLATES/MEMORY.md" "$MEMORY_DIR/MEMORY.md"
    cp "$TEMPLATES/USER.md" "$MEMORY_DIR/USER.md"
    touch "$MEMORY_MARKER"
    echo "=== Memory seeded with deployment context ==="
fi

# ── 写激活脚本到持久卷（/opt/data/ 一定可写） ──
mkdir -p /opt/data/scripts
cat > /opt/data/scripts/activate.sh << SCRIPT
#!/bin/bash
source /opt/hermes/.venv/bin/activate
[ -f /home/hermes/.bashrc ] && source /home/hermes/.bashrc

# 快捷命令：${PROFILE} chat  =  hermes -p ${PROFILE} chat
${PROFILE}() {
    hermes -p ${PROFILE} "\$@"
}
SCRIPT
chmod +x /opt/data/scripts/activate.sh

# 同时也写到 .bashrc，保证 docker exec -it hermes-single bash 也能用
echo "" >> /home/hermes/.bashrc
echo "# Hermes profile shortcut" >> /home/hermes/.bashrc
echo "${PROFILE}() { hermes -p ${PROFILE} \"\$@\"; }" >> /home/hermes/.bashrc

# ── 后台启动 gateway（内部使用，不暴露端口） ──
echo "=== Starting Hermes gateway (profile: $PROFILE) ==="
hermes -p "$PROFILE" gateway run > /tmp/hermes-gateway.log 2>&1 &

# ── 保持容器运行 ──
echo "=== Container ready ==="
echo "  docker exec -it hermes-single bash"
echo "  hermes -p $PROFILE chat"
tail -f /dev/null
