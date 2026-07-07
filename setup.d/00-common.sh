# shellcheck shell=bash
# This file is sourced by setup.sh. Do not execute setup flow at top level.

BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# ── 读取已有配置 ──
load_env_file() {
    local file="$1"
    if [ -f "$file" ]; then
        set -a
        # shellcheck source=/dev/null
        source "$file"
        set +a
    fi
}

load_env() {
    load_env_file "$STATE_FILE"
    load_env_file "$ENV_FILE"
}
load_env

PYTHON=$(command -v python3 || command -v python || echo "python")

# ── 系统检测 ──
is_wsl() {
    grep -qi microsoft /proc/version 2>/dev/null
}

# ── 检测 Docker ──
check_deps() {
    if ! command -v docker &>/dev/null; then
        echo -e "${RED}请先安装 Docker${NC}"
        exit 1
    fi
    if ! docker compose version &>/dev/null; then
        echo -e "${RED}请安装 docker compose 插件${NC}"
        exit 1
    fi
}

# ── 交互配置 ──
