# shellcheck shell=bash
# This file is sourced by setup.sh. Do not execute setup flow at top level.

prompt_playwright_mcp() {
    echo ""
    echo -e "${BOLD}[9] 容器化 Playwright MCP 服务器${NC}"
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
    echo -e "  ${BOLD}[9a] VPN 代理${NC}"
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
