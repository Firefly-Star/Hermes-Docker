#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# ── 读取已有配置 ──
load_env() {
    if [ -f "$ENV_FILE" ]; then
        set -a
        source "$ENV_FILE"
        set +a
    fi
}
load_env

PYTHON=$(command -v python3 || command -v python || echo "python")

# ── 检测 Docker ──
check_deps() {
    if ! command -v docker &>/dev/null; then
        echo -e "${RED}请先安装 Docker${NC}"
        exit 1
    fi
}

# ── 交互配置 ──

prompt_name() {
    echo ""
    echo -e "${BOLD}[1] Agent 名称${NC}"
    local cur="${AGENT_NAME:-kaguya}"
    read -p "  名称 (默认: $cur): " val
    AGENT_NAME="${val:-$cur}"
    echo -e "  ${GREEN}✓ Agent: $AGENT_NAME${NC}"
}

prompt_dk() {
    echo ""
    echo -e "${BOLD}[2] DeepSeek API Key${NC}"
    while true; do
        local cur="${DEEPSEEK_API_KEY:-}"
        [ -n "$cur" ] && echo -e "  ${DIM}当前: ${cur:0:8}...${NC}"
        read -p "  API Key: " val
        if [ -n "$val" ]; then
            DEEPSEEK_API_KEY="$val"; break
        elif [ -n "$cur" ]; then
            break
        else
            echo -e "  ${RED}⚠ 必填${NC}"
        fi
    done
}

prompt_soul() {
    echo ""
    echo -e "${BOLD}[3] SOUL.md 路径${NC}"
    echo -e "  ${DIM}指向你的 SOUL.md 文件（容器内唯一的 Agent 人格定义）。必填。${NC}"
    while true; do
        local cur="${SOUL_PATH:-}"
        [ -n "$cur" ] && echo -e "  ${DIM}当前: $cur${NC}"
        read -p "  路径: " val
        val="${val:-$cur}"
        if [ -z "$val" ]; then
            echo -e "  ${RED}⚠ 必填${NC}"
        elif [ ! -f "$val" ]; then
            echo -e "  ${RED}⚠ 文件不存在: $val${NC}"
        else
            SOUL_PATH="$(realpath "$val")"
            echo -e "  ${GREEN}✓ $SOUL_PATH${NC}"
            break
        fi
    done
}

# ── 写入 .env ──
write_env() {
    echo ""
    echo -e "${BOLD}[4] 写入配置${NC}"
    local old_extra=""
    if [ -f "$ENV_FILE" ]; then
        old_extra=$(grep -v -E "^(DEEPSEEK_API_KEY=|API_SERVER_KEY=|SOUL_PATH=)" "$ENV_FILE" 2>/dev/null || true)
    fi

    # 自动生成 API_SERVER_KEY
    local ask="${API_SERVER_KEY:-$($PYTHON -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null)}"

    cat > "$ENV_FILE" << EOF
AGENT_NAME=${AGENT_NAME}
DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY}
API_SERVER_KEY=${ask}
SOUL_PATH=${SOUL_PATH}
EOF
    if [ -n "$old_extra" ]; then
        echo "" >> "$ENV_FILE"
        echo "$old_extra" >> "$ENV_FILE"
    fi
    echo -e "  ${GREEN}✓ .env 已写入${NC}"
}

# ── 启动容器 ──
start_container() {
    echo ""
    echo -e "${BOLD}[5] 启动容器${NC}"
    read -p "  现在启动? [Y/n]: " yn
    case "$yn" in
        n|N|no)
            echo "  跳过。手动启动: cd $SCRIPT_DIR && docker compose up -d"
            ;;
        *)
            echo "  停止旧容器..."
            docker compose down 2>/dev/null || true
            echo "  启动新容器..."
            docker compose up -d
            echo -e "  ${GREEN}✓ 容器已启动${NC}"
            echo ""
            echo "  done."
            ;;
    esac
}

# ========== 主流程 ==========
echo "============================================"
echo "  Hermes Single-Agent 配置向导"
echo "============================================"
echo "  一个容器，一个 profile，你的 SOUL.md"
echo "  无需端口映射，exec 进入容器使用 CLI"

check_deps
prompt_name
prompt_dk
prompt_soul
write_env
start_container

echo ""
echo -e "${GREEN}完成。${NC}"
echo "  下次启动: cd $SCRIPT_DIR && docker compose up -d"

docker exec -it hermes-single bash --rcfile /opt/data/scripts/activate.sh
