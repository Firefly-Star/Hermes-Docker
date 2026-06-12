#!/bin/bash
set -e

source /opt/hermes/.venv/bin/activate

HERMES_HOME="${HERMES_HOME:-/opt/data}"
TEMPLATES="/opt/data/templates"
PROFILE="kaguya"
MARKER="$HERMES_HOME/.initialized"

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

# ── 写激活脚本到持久卷（/opt/data/ 一定可写） ──
mkdir -p /opt/data/scripts
cat > /opt/data/scripts/activate.sh << 'SCRIPT'
#!/bin/bash
source /opt/hermes/.venv/bin/activate
SCRIPT
chmod +x /opt/data/scripts/activate.sh

# ── 后台启动 gateway（内部使用，不暴露端口） ──
echo "=== Starting Hermes gateway (profile: $PROFILE) ==="
hermes -p "$PROFILE" gateway run > /tmp/hermes-gateway.log 2>&1 &

# ── 保持容器运行 ──
echo "=== Container ready ==="
echo "  docker exec -it hermes-single bash"
echo "  hermes -p $PROFILE chat"
tail -f /dev/null
