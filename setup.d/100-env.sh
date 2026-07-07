# shellcheck shell=bash
# This file is sourced by setup.sh. Do not execute setup flow at top level.

# ── 写入 .env ──
write_env() {
    echo ""
    echo -e "${BOLD}[11] 写入配置${NC}"
    local old_extra=""
    if [ -f "$ENV_FILE" ]; then
        old_extra=$(grep -v -E "^(AGENT_NAME=|LLM_PROVIDER=|LLM_MODEL=|LLM_BASE_URL=|LLM_API_KEY=|DEEPSEEK_API_KEY=|CUSTOM_LLM_API_KEY=|API_SERVER_KEY=|SOUL_PATH=|TERMINAL_ENV=|SSH_HOST=|SSH_USER=|MEMORY_TOOL_ENABLED=|DISABLED_TOOLSETS=|MEMORY_NUDGE_INTERVAL=|SKILL_NUDGE_INTERVAL=|TOOL_PROGRESS=|SHOW_REASONING=|MCP_PLAYWRIGHT_ENABLED=|PROXY_ENABLED=|PROXY_HOST=|PROXY_PORT=)" "$ENV_FILE" 2>/dev/null || true)
    fi

    # 自动生成 API_SERVER_KEY
    local ask="${API_SERVER_KEY:-$($PYTHON -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null)}"

    cat > "$ENV_FILE" << EOF
AGENT_NAME=${AGENT_NAME}
LLM_PROVIDER=${LLM_PROVIDER:-deepseek}
LLM_MODEL=${LLM_MODEL:-deepseek-v4-flash}
LLM_BASE_URL=${LLM_BASE_URL:-https://api.deepseek.com/v1}
LLM_API_KEY=${LLM_API_KEY:-${DEEPSEEK_API_KEY:-}}
DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY:-${LLM_API_KEY:-}}
CUSTOM_LLM_API_KEY=${CUSTOM_LLM_API_KEY:-}
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
