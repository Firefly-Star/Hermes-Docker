# shellcheck shell=bash
# This file is sourced by setup.sh. Do not execute setup flow at top level.

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
