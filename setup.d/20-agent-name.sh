# shellcheck shell=bash
# This file is sourced by setup.sh. Do not execute setup flow at top level.

prompt_name() {
    echo ""
    echo -e "${BOLD}[1] Agent 名称${NC}"
    local cur="${AGENT_NAME:-kaguya}"
    read -p "  名称 (默认: $cur): " val
    AGENT_NAME="${val:-$cur}"
    echo -e "  ${GREEN}✓ Agent: $AGENT_NAME${NC}"
}
