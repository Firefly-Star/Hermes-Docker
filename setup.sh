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

prompt_ssh_user() {
    echo ""
    echo -e "${BOLD}[3] 宿主机 SSH 用户${NC}"
    echo -e "  ${DIM}Agent 将通过 SSH 连接到宿主机执行命令。${NC}"
    local cur="${SSH_USER:-$USER}"
    read -p "  用户名 (默认: $cur): " val
    SSH_USER="${val:-$cur}"
    echo -e "  ${GREEN}✓ SSH 用户: $SSH_USER${NC}"
}

prompt_soul() {
    echo ""
    echo -e "${BOLD}[4] SOUL.md 路径${NC}"
    echo -e "  ${DIM}指向你的 SOUL.md 文件（Agent 人格定义）。留空将使用 ./SOUL.md${NC}"
    local default="./SOUL.md"
    local cur="${SOUL_PATH:-$default}"
    [ -n "$SOUL_PATH" ] && echo -e "  ${DIM}当前: $SOUL_PATH${NC}"
    while true; do
        read -p "  路径 (默认: ./SOUL.md): " val
        val="${val:-$default}"
        if [ ! -f "$val" ]; then
            echo -e "  ${RED}⚠ 文件不存在: $(realpath "$val" 2>/dev/null || echo "$val")${NC}"
        else
            SOUL_PATH="$(realpath "$val")"
            echo -e "  ${GREEN}✓ $SOUL_PATH${NC}"
            break
        fi
    done
}

# ── SSH 服务安装与启动（兼容 WSL / 原生 Linux） ──
setup_ssh_server() {
    echo ""
    echo -e "${BOLD}[5] SSH 服务配置${NC}"

    if is_wsl; then
        echo -e "  ${DIM}检测到 WSL 环境${NC}"
    fi

    # 检查 openssh-server 是否已安装
    if ! command -v sshd &>/dev/null; then
        echo -e "  ${RED}⚠ openssh-server 未安装，请先手动安装：${NC}"
        echo ""
        echo -e "  ${YELLOW}  sudo apt update && sudo apt install -y openssh-server${NC}"
        echo ""
        echo -e "  ${DIM}  安装后重新运行此脚本${NC}"
        return 1
    fi
    echo -e "  ${GREEN}✓ openssh-server 已存在${NC}"

    # 生成 SSH host keys（首次安装后可能需要）
    if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
        echo -e "  生成 SSH host keys..."
        sudo ssh-keygen -A 2>/dev/null || true
    fi

    # 确保 ~/.ssh 目录权限正确
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    # 启动 SSH 服务
    if is_wsl; then
        # WSL: 兼容 systemd 和 sysvinit 两种模式
        # 如果启用了 systemd 且 ssh 被 mask，先 unmask
        if command -v systemctl &>/dev/null; then
            if systemctl is-enabled ssh 2>/dev/null | grep -q 'masked'; then
                echo -e "  ${YELLOW}⚠ ssh 服务被 mask，正在 unmask...${NC}"
                sudo systemctl unmask ssh
            fi
        fi
        if service ssh status &>/dev/null 2>&1; then
            echo -e "  ${GREEN}✓ SSH 服务运行中${NC}"
        else
            echo -e "  启动 SSH 服务..."
            sudo service ssh start
            echo -e "  ${GREEN}✓ SSH 服务已启动${NC}"
        fi
    else
        # 原生 Linux: 使用 systemctl，兼容 sshd / ssh 两种服务名
        local svc="sshd"
        if ! systemctl list-unit-files 2>/dev/null | grep -q sshd; then
            svc="ssh"
        fi
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo -e "  ${GREEN}✓ SSH 服务运行中${NC}"
        else
            echo -e "  启动 SSH 服务..."
            sudo systemctl enable "$svc" 2>/dev/null || true
            sudo systemctl start "$svc" 2>/dev/null || true
            echo -e "  ${GREEN}✓ SSH 服务已启动${NC}"
        fi
    fi
}

# ── 检测宿主机 IP ──
detect_ssh_host() {
    echo ""
    echo -e "${BOLD}[6] 宿主机 IP 地址${NC}"
    echo -e "  ${DIM}Agent 通过此地址 SSH 连接回宿主机执行命令。${NC}"

    local auto_ip=""
    if is_wsl; then
        # WSL: 取第一个非环回 IP（Docker 容器通过它访问 WSL）
        auto_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    else
        # 原生 Linux: 优先 ip route，回退 hostname -I
        auto_ip=$(ip route get 1 2>/dev/null | grep -oP 'src \K\S+')
        [ -z "$auto_ip" ] && auto_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi

    local cur="${SSH_HOST:-${auto_ip:-}}"
    if [ -z "$cur" ]; then
        echo -e "  ${YELLOW}⚠ 未能自动检测 IP，请手动输入${NC}"
        while true; do
            read -p "  宿主机 IP 地址: " val
            if [ -n "$val" ]; then
                SSH_HOST="$val"; break
            fi
        done
    else
        read -p "  宿主机 IP 地址 (检测到: $cur): " val
        SSH_HOST="${val:-$cur}"
    fi
    echo -e "  ${GREEN}✓ SSH 宿主机: $SSH_HOST${NC}"
}

# ── 设置 SSH 密钥（id_hermes-single + authorized_keys） ──
setup_ssh_key() {
    echo ""
    echo -e "${BOLD}[7] SSH 密钥配置${NC}"
    local key="$HOME/.ssh/id_hermes-single"
    mkdir -p "$HOME/.ssh"
    if [ ! -f "$key" ]; then
        echo -e "  生成 SSH key..."
        ssh-keygen -t ed25519 -f "$key" -N "" -q
        local pub
        pub=$(cat "${key}.pub")
        if ! grep -qF "$pub" "$HOME/.ssh/authorized_keys" 2>/dev/null; then
            echo "$pub" >> "$HOME/.ssh/authorized_keys"
        fi
        chmod 600 "$HOME/.ssh/authorized_keys" 2>/dev/null || true
        echo -e "  ${GREEN}✓ SSH key 已生成并注册到 authorized_keys${NC}"
    else
        local pub
        pub=$(cat "${key}.pub")
        if ! grep -qF "$pub" "$HOME/.ssh/authorized_keys" 2>/dev/null; then
            echo "$pub" >> "$HOME/.ssh/authorized_keys"
            chmod 600 "$HOME/.ssh/authorized_keys" 2>/dev/null || true
            echo -e "  ${GREEN}✓ 已有 key，已补充注册到 authorized_keys${NC}"
        else
            echo -e "  ${GREEN}✓ SSH key 已存在且已注册${NC}"
        fi
    fi
}

# ── 写入 .env ──
write_env() {
    echo ""
    echo -e "${BOLD}[8] 写入配置${NC}"
    local old_extra=""
    if [ -f "$ENV_FILE" ]; then
        old_extra=$(grep -v -E "^(AGENT_NAME=|DEEPSEEK_API_KEY=|API_SERVER_KEY=|SOUL_PATH=|TERMINAL_ENV=|SSH_HOST=|SSH_USER=)" "$ENV_FILE" 2>/dev/null || true)
    fi

    # 自动生成 API_SERVER_KEY
    local ask="${API_SERVER_KEY:-$($PYTHON -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null)}"

    cat > "$ENV_FILE" << EOF
AGENT_NAME=${AGENT_NAME}
DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY}
API_SERVER_KEY=${ask}
SOUL_PATH=${SOUL_PATH}
TERMINAL_ENV=ssh
SSH_HOST=${SSH_HOST}
SSH_USER=${SSH_USER}
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
    echo -e "${BOLD}[9] 启动／重启容器${NC}"
    read -p "  现在启动? [Y/n]: " yn
    case "$yn" in
        n|N|no)
            echo "  跳过。手动启动: cd $SCRIPT_DIR && docker compose up -d"
            return 0
            ;;
        *)
            echo "  停止旧容器..."
            docker compose down 2>/dev/null || true
            echo "  启动新容器..."
            docker compose up -d
            echo -e "  ${GREEN}✓ 容器已启动${NC}"
            return 0
            ;;
    esac
}

# ── 等待容器就绪 ──
wait_container() {
    echo "  等待容器就绪..."
    for i in $(seq 1 30); do
        if docker exec hermes-single test -f /opt/data/scripts/activate.sh 2>/dev/null; then
            echo -e "  ${GREEN}✓ 容器就绪${NC}"
            return 0
        fi
        sleep 1
    done
    echo -e "  ${YELLOW}⚠ 等待超时，请稍后手动进入容器${NC}"
    return 1
}

# ── 进入容器 ──
enter_container() {
    echo ""
    echo -e "${BOLD}[10] 进入容器${NC}"
    if docker ps --format '{{.Names}}' | grep -q '^hermes-single$' 2>/dev/null; then
        # 容器正在运行，直接问要不要进
        read -p "  现在进入容器? [Y/n]: " yn
        case "$yn" in
            n|N|no)
                echo "  跳过。手动进入: bash exec.sh"
                return 0
                ;;
            *)
                wait_container || return 0
                echo "  进入容器..."
                docker exec -it hermes-single bash --rcfile /opt/data/scripts/activate.sh
                ;;
        esac
    elif docker ps -a --format '{{.Names}}' | grep -q '^hermes-single$' 2>/dev/null; then
        # 容器存在但未运行，问要不要启动再进
        echo -e "  ${YELLOW}⚠ 容器 hermes-single 已存在但未运行${NC}"
        read -p "  启动并进入容器? [Y/n]: " yn
        case "$yn" in
            n|N|no)
                echo "  手动启动: cd $SCRIPT_DIR && docker compose up -d"
                echo "  手动进入: bash exec.sh"
                return 0
                ;;
            *)
                echo "  启动容器..."
                docker start hermes-single
                wait_container || return 0
                echo "  进入容器..."
                docker exec -it hermes-single bash --rcfile /opt/data/scripts/activate.sh
                ;;
        esac
    else
        # 容器完全不存在
        echo -e "  ${YELLOW}⚠ 容器 hermes-single 不存在，请先运行 setup.sh 完成部署${NC}"
        echo "  部署完成后: bash exec.sh"
    fi
}

# ========== 主流程 ==========
echo "============================================"
echo "  Hermes Single-Agent 配置向导"
echo "============================================"
echo "  一个容器，一个 profile，你的 SOUL.md"
echo "  无需端口映射，exec 进入容器使用 CLI"
echo ""

check_deps

# 预先缓存 sudo 凭证，避免后续安装 SSH 时中断流程
echo -e "${DIM}检查 sudo 权限...${NC}"
sudo -v
# 后台续期（脚本退出时自动结束）
(while true; do sudo -n true; sleep 60; done) 2>/dev/null &

prompt_name
prompt_dk
prompt_ssh_user
prompt_soul
setup_ssh_server
detect_ssh_host
setup_ssh_key
write_env
start_container
enter_container

echo ""
echo -e "${GREEN}完成。${NC}"
echo "  下次启动: cd $SCRIPT_DIR && docker compose up -d"
