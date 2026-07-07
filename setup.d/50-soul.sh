# shellcheck shell=bash
# This file is sourced by setup.sh. Do not execute setup flow at top level.

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
