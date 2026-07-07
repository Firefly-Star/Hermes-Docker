# shellcheck shell=bash
# This file is sourced by setup.sh. Do not execute setup flow at top level.

prompt_tool_progress() {
    echo ""
    echo -e "${BOLD}[7] 工具调用显示模式${NC}"
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
