# shellcheck shell=bash
# This file is sourced by setup.sh. Do not execute setup flow at top level.

prompt_container_name() {
    echo ""
    echo -e "${BOLD}[2] Docker 容器名称${NC}"
    echo -e "  ${DIM}用于 docker container_name 和后续 docker exec/cp 操作。${NC}"
    local cur="${CONTAINER_NAME:-hermes}"
    while true; do
        read -p "  容器名称 (默认: $cur): " val
        CONTAINER_NAME="${val:-$cur}"
        if [[ "$CONTAINER_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
            export CONTAINER_NAME
            echo -e "  ${GREEN}✓ 容器名称: $CONTAINER_NAME${NC}"
            return 0
        fi
        echo -e "  ${YELLOW}请输入合法 Docker 容器名：字母/数字开头，可包含 . _ -${NC}"
    done
}
