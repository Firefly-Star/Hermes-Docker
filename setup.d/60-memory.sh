# shellcheck shell=bash
# This file is sourced by setup.sh. Do not execute setup flow at top level.

prompt_memory_tool() {
    echo ""
    echo -e "${BOLD}[6] Memory 写入工具${NC}"
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
