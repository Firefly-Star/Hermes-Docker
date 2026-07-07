# shellcheck shell=bash
# This file is sourced by setup.sh. Do not execute setup flow at top level.

prompt_ssh_user() {
    echo ""
    echo -e "${BOLD}[3] 宿主机 SSH 用户${NC}"
    echo -e "  ${DIM}Agent 将通过 SSH 连接到宿主机执行命令。${NC}"
    local cur="${SSH_USER:-$USER}"
    read -p "  用户名 (默认: $cur): " val
    SSH_USER="${val:-$cur}"
    echo -e "  ${GREEN}✓ SSH 用户: $SSH_USER${NC}"
}
