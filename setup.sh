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
    echo -e "  ${DIM}指向你的 SOUL.md 文件（Agent 人格定义）。${NC}"
    local cur="${SOUL_PATH:-./SOUL.md}"
    [ -n "$SOUL_PATH" ] && echo -e "  ${DIM}当前: $SOUL_PATH${NC}"
    while true; do
        read -p "  路径 (默认: $cur): " val
        val="${val:-$cur}"
        if [ ! -f "$val" ]; then
            echo -e "  ${RED}⚠ 文件不存在: $(realpath "$val" 2>/dev/null || echo "$val")${NC}"
        else
            SOUL_PATH="$(realpath "$val")"
            echo -e "  ${GREEN}✓ $SOUL_PATH${NC}"
            break
        fi
    done
}

prompt_memory_tool() {
    echo ""
    echo -e "${BOLD}[5] Memory 写入工具${NC}"
    echo -e "  ${DIM}禁用后 Agent 无法自动保存 memory，但能继续读取已有的 memory 和 user 数据。${NC}"
    echo -e "  ${DIM}适合不希望 memory 被覆盖的场景。${NC}"
    local cur="${MEMORY_TOOL_ENABLED:-true}"
    local label="开启"
    [ "$cur" = "false" ] && label="关闭"
    read -p "  启用? [Y/n] (当前: $label): " val
    case "$val" in
        n|N|no)
            MEMORY_TOOL_ENABLED=false
            DISABLED_TOOLSETS="[memory]"
            MEMORY_NUDGE_INTERVAL=0
            SKILL_NUDGE_INTERVAL=0
            echo -e "  ${YELLOW}⚠ 已禁用 memory 写入工具，后台 review 也已关闭${NC}"
            ;;
        y|Y|yes)
            MEMORY_TOOL_ENABLED=true
            DISABLED_TOOLSETS="[]"
            echo -e "  ${GREEN}✓ memory 工具已开启${NC}"
            ;;
        *)
            MEMORY_TOOL_ENABLED="${cur}"
            echo -e "  ${GREEN}✓ 保持当前设置${NC}"
            ;;
    esac
}

prompt_tool_progress() {
    echo ""
    echo -e "${BOLD}[6] 工具调用显示模式${NC}"
    echo -e "  ${DIM}all:     每次工具调用显示简短参数预览${NC}"
    echo -e "  ${DIM}verbose: 每次工具调用显示完整参数 JSON${NC}"
    echo -e "  ${DIM}选 y 还会开启 thinking block 显示${NC}"
    local cur="${TOOL_PROGRESS:-all}"
    local label="简短预览"
    [ "$cur" = "verbose" ] && label="完整参数 + reasoning"
    read -p "  显示完整参数并开启 reasoning? [y/N] (当前: $label): " val
    case "$val" in
        y|Y|yes)
            TOOL_PROGRESS=verbose
            SHOW_REASONING=true
            echo -e "  ${GREEN}✓ 将显示完整参数，同时开启 reasoning 显示${NC}"
            ;;
        n|N|no)
            TOOL_PROGRESS=all
            echo -e "  ${GREEN}✓ 使用简短预览${NC}"
            ;;
        *)
            TOOL_PROGRESS="${cur}"
            echo -e "  ${GREEN}✓ 保持当前设置${NC}"
            ;;
    esac
}

prompt_playwright_mcp() {
    echo ""
    echo -e "${BOLD}[7] 容器化 Playwright MCP 服务器${NC}"
    echo -e "  ${DIM}通过 Docker 部署 Playwright MCP 浏览器，让 Agent 能打开网页、截图、交互。${NC}"
    echo -e "  ${DIM}子仓库已在 ./playwright/ 目录下${NC}"
    echo -e "  ${DIM}克隆时需加 --recurse-submodules，或之后运行 git submodule update --init${NC}"
    local cur="${MCP_PLAYWRIGHT_ENABLED:-false}"
    local label="不启用"
    [ "$cur" = "true" ] && label="启用"
    read -p "  启用? [y/N] (当前: $label): " val
    case "$val" in
        y|Y|yes)
            MCP_PLAYWRIGHT_ENABLED=true
            echo -e "  ${GREEN}✓ 将自动部署 Playwright MCP${NC}"
            # ── VPN 代理配置 ──
            prompt_playwright_proxy
            ;;
        n|N|no)
            MCP_PLAYWRIGHT_ENABLED=false
            echo -e "  ${YELLOW}⚠ 跳过 Playwright MCP${NC}"
            echo -e "  ${DIM}  需要时可根据子仓库 README 自行配置，或重新运行 setup 选择启用${NC}"
            ;;
        *)
            MCP_PLAYWRIGHT_ENABLED="${cur}"
            echo -e "  ${GREEN}✓ 保持当前设置${NC}"
            ;;
    esac
}

prompt_playwright_proxy() {
    echo ""
    echo -e "  ${BOLD}[7a] VPN 代理${NC}"
    echo -e "  ${DIM}代理让 Chrome 能访问被墙的网站（如 Google）。${NC}"
    local cur_proxy="${PROXY_ENABLED:-false}"
    local label="不使用"
    [ "$cur_proxy" = "true" ] && label="使用"
    read -p "  使用代理? [y/N] (当前: $label): " sub_val
    case "$sub_val" in
        y|Y|yes)
            PROXY_ENABLED=true
            # 检测宿主机 IP
            local auto_ip=""
            if is_wsl; then
                auto_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
                echo -e "    ${DIM}检测到 WSL 环境${NC}"
            else
                auto_ip=$(ip route get 1 2>/dev/null | grep -oP 'src \K\S+')
                [ -z "$auto_ip" ] && auto_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
            fi
            local cur_ip="${PROXY_HOST:-$auto_ip}"
            read -p "  宿主机 IP (检测到: $cur_ip): " ip_val
            PROXY_HOST="${ip_val:-$cur_ip}"
            local cur_port="${PROXY_PORT:-7890}"
            read -p "  端口 (默认: $cur_port): " port_val
            PROXY_PORT="${port_val:-$cur_port}"
            echo -e "  ${GREEN}✓ 代理: http://${PROXY_HOST}:${PROXY_PORT}${NC}"
            ;;
        *)
            PROXY_ENABLED=false
            echo -e "  ${YELLOW}跳过代理${NC}"
            ;;
    esac
}

# ── SSH 服务安装与启动（兼容 WSL / 原生 Linux） ──
setup_ssh_server() {
    echo ""
    echo -e "${BOLD}[8] SSH 服务配置${NC}"

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
    echo -e "${BOLD}[9] 宿主机 IP 地址${NC}"
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
    echo -e "${BOLD}[10] SSH 密钥配置${NC}"
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
    echo -e "${BOLD}[11] 写入配置${NC}"
    local old_extra=""
    if [ -f "$ENV_FILE" ]; then
        old_extra=$(grep -v -E "^(AGENT_NAME=|DEEPSEEK_API_KEY=|API_SERVER_KEY=|SOUL_PATH=|TERMINAL_ENV=|SSH_HOST=|SSH_USER=|MEMORY_TOOL_ENABLED=|DISABLED_TOOLSETS=|MEMORY_NUDGE_INTERVAL=|SKILL_NUDGE_INTERVAL=|TOOL_PROGRESS=|SHOW_REASONING=|MCP_PLAYWRIGHT_ENABLED=|PROXY_ENABLED=|PROXY_HOST=|PROXY_PORT=)" "$ENV_FILE" 2>/dev/null || true)
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
MEMORY_TOOL_ENABLED=${MEMORY_TOOL_ENABLED:-true}
DISABLED_TOOLSETS=${DISABLED_TOOLSETS:-[]}
MEMORY_NUDGE_INTERVAL=${MEMORY_NUDGE_INTERVAL:-10}
SKILL_NUDGE_INTERVAL=${SKILL_NUDGE_INTERVAL:-10}
TOOL_PROGRESS=${TOOL_PROGRESS:-all}
SHOW_REASONING=${SHOW_REASONING:-false}
MCP_PLAYWRIGHT_ENABLED=${MCP_PLAYWRIGHT_ENABLED:-false}
PROXY_ENABLED=${PROXY_ENABLED:-false}
PROXY_HOST=${PROXY_HOST:-}
PROXY_PORT=${PROXY_PORT:-7890}
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
    echo -e "${BOLD}[12] 启动／重启容器${NC}"
    # 确保 mcp 共享网络存在
    docker network inspect mcp-net >/dev/null 2>&1 || docker network create mcp-net
    # 如果启用了 playwright，先确保它在运行
    if [ "${MCP_PLAYWRIGHT_ENABLED:-false}" = "true" ]; then
        echo "  检查 Playwright MCP 容器..."
        if [ -f "$SCRIPT_DIR/playwright/docker-compose.yml" ]; then
            if ! docker ps --format '{{.Names}}' | grep -q '^playwright-mcp$' 2>/dev/null; then
                echo "  启动 Playwright MCP..."
                # 生成 playwright 的 .env（代理配置）
                if [ "${PROXY_ENABLED:-false}" = "true" ] && [ -n "$PROXY_HOST" ]; then
                    cat > "$SCRIPT_DIR/playwright/.env" << PROXYEOF
PROXY_URL=http://${PROXY_HOST}:${PROXY_PORT:-7890}
PROXYEOF
                fi
                (cd "$SCRIPT_DIR/playwright" && docker compose up -d)
                echo -e "  ${GREEN}✓ Playwright MCP 已启动${NC}"
            else
                echo -e "  ${GREEN}✓ Playwright MCP 已在运行${NC}"
            fi
        else
            echo -e "  ${YELLOW}⚠ ./playwright 子仓库未初始化${NC}"
            echo -e "  ${DIM}  请先运行: git submodule update --init${NC}"
        fi
    fi
    read -p "  现在启动? [Y/n]: " yn
    case "$yn" in
        n|N|no)
            echo "  跳过。手动启动: cd $SCRIPT_DIR && docker compose up -d"
            return 0
            ;;
        *)
            # 检查 SSH key 是否存在（docker-compose 会 bind mount，文件不存在则启动失败）
            if [ ! -f "$HOME/.ssh/id_hermes-single" ]; then
                echo -e "  ${RED}⚠ SSH 密钥不存在: ~/.ssh/id_hermes-single${NC}"
                echo -e "  ${DIM}  请先运行 setup.sh 完成 SSH 密钥配置，或手动生成:${NC}"
                echo -e "  ${DIM}    ssh-keygen -t ed25519 -f ~/.ssh/id_hermes-single -N \"\"${NC}"
                echo -e "  ${DIM}    cat ~/.ssh/id_hermes-single.pub >> ~/.ssh/authorized_keys${NC}"
                return 1
            fi
            # 渲染配置（宿主机 env 展开）
            echo "  渲染配置..."
            bash "$SCRIPT_DIR/render-config.sh" 2>/dev/null || echo -e "  ${YELLOW}⚠ render-config.sh 未找到，跳过${NC}"
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
        if docker exec hermes-single test -f /opt/data/.initialized 2>/dev/null; then
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
    echo -e "${BOLD}[13] 进入容器${NC}"
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
                docker exec -it hermes-single bash
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
                docker exec -it hermes-single bash
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
SUDO_PID=$!
trap 'kill $SUDO_PID 2>/dev/null; wait $SUDO_PID 2>/dev/null' EXIT INT TERM

prompt_name
prompt_dk
prompt_ssh_user
prompt_soul
prompt_memory_tool
prompt_tool_progress
prompt_playwright_mcp
setup_ssh_server
detect_ssh_host
setup_ssh_key
write_env
start_container
enter_container

echo ""
echo -e "${GREEN}完成。${NC}"
echo "  下次启动: cd $SCRIPT_DIR && docker compose up -d"
