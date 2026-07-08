# shellcheck shell=bash
# This file is sourced by setup.sh. Do not execute setup flow at top level.

# ── 写入 .setup-state.env 与 .env ──
# .setup-state.env 保存普通、非敏感的上次选择；.env 只保存 Hermes/container
# 运行时需要的 secrets。Hermes 会在启动时加载 profile .env，并在 config.yaml
# 中展开 ${HERMES_MODEL_API_KEY} 这类引用，因此 config 不需要也不应该写明文 key。
write_env() {
    echo ""
    echo -e "${BOLD}[14] 写入配置${NC}"

    local old_state_extra=""
    if [ -f "$STATE_FILE" ]; then
        old_state_extra=$(grep -v -E "^(AGENT_NAME=|CONTAINER_NAME=|LLM_PROVIDER=|CUSTOM_LLM_PROVIDER_NAME=|LLM_PROVIDER_API_KEY_ENV=|LLM_PROVIDER_BASE_URL_ENV=|LLM_MODEL=|LLM_BASE_URL=|MODEL_CONTEXT_LENGTH=|COMPRESSION_ENABLED=|COMPRESSION_THRESHOLD=|SOUL_PATH=|TERMINAL_ENV=|SSH_HOST=|SSH_USER=|MEMORY_TOOL_ENABLED=|DISABLED_TOOLSETS=|MEMORY_NUDGE_INTERVAL=|SKILL_NUDGE_INTERVAL=|TOOL_PROGRESS=|SHOW_REASONING=|MCP_PLAYWRIGHT_ENABLED=|PROXY_ENABLED=|PROXY_HOST=|PROXY_PORT=)" "$STATE_FILE" 2>/dev/null || true)
    fi

    local old_secret_extra=""
    if [ -f "$ENV_FILE" ]; then
        old_secret_extra=$(grep -v -E "^(HERMES_MODEL_API_KEY=|CONTAINER_NAME=|LLM_PROVIDER=|CUSTOM_LLM_PROVIDER_NAME=|LLM_PROVIDER_API_KEY_ENV=|LLM_PROVIDER_BASE_URL_ENV=|LLM_MODEL=|LLM_BASE_URL=|MODEL_CONTEXT_LENGTH=|COMPRESSION_ENABLED=|COMPRESSION_THRESHOLD=|LLM_API_KEY=|DEEPSEEK_API_KEY=|CUSTOM_LLM_API_KEY=|CUSTOM_LLM_BASE_URL=|API_SERVER_KEY=|AGENT_NAME=|SOUL_PATH=|TERMINAL_ENV=|SSH_HOST=|SSH_USER=|MEMORY_TOOL_ENABLED=|DISABLED_TOOLSETS=|MEMORY_NUDGE_INTERVAL=|SKILL_NUDGE_INTERVAL=|TOOL_PROGRESS=|SHOW_REASONING=|MCP_PLAYWRIGHT_ENABLED=|PROXY_ENABLED=|PROXY_HOST=|PROXY_PORT=)" "$ENV_FILE" 2>/dev/null || true)
    fi

    local provider="${LLM_PROVIDER:-deepseek}"
    local api_key="${LLM_API_KEY:-${HERMES_MODEL_API_KEY:-}}"
    case "$provider" in
        deepseek)
            api_key="${DEEPSEEK_API_KEY:-${api_key}}"
            ;;
        custom)
            api_key="${CUSTOM_LLM_API_KEY:-${api_key}}"
            ;;
    esac

    # 自动生成 API_SERVER_KEY
    local ask="${API_SERVER_KEY:-$($PYTHON -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null)}"

    cat > "$STATE_FILE" << EOF
AGENT_NAME=${AGENT_NAME}
CONTAINER_NAME=${CONTAINER_NAME:-hermes}
LLM_PROVIDER=${provider}
CUSTOM_LLM_PROVIDER_NAME=${CUSTOM_LLM_PROVIDER_NAME:-}
LLM_PROVIDER_API_KEY_ENV=${LLM_PROVIDER_API_KEY_ENV:-}
LLM_PROVIDER_BASE_URL_ENV=${LLM_PROVIDER_BASE_URL_ENV:-}
LLM_MODEL=${LLM_MODEL:-deepseek-v4-flash}
LLM_BASE_URL=${LLM_BASE_URL:-https://api.deepseek.com/v1}
MODEL_CONTEXT_LENGTH=${MODEL_CONTEXT_LENGTH:-}
COMPRESSION_ENABLED=${COMPRESSION_ENABLED:-true}
COMPRESSION_THRESHOLD=${COMPRESSION_THRESHOLD:-0.85}
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
    if [ -n "$old_state_extra" ]; then
        echo "" >> "$STATE_FILE"
        echo "$old_state_extra" >> "$STATE_FILE"
    fi

    cat > "$SCRIPT_DIR/docker-compose.override.yml" << EOF
services:
  hermes:
    container_name: ${CONTAINER_NAME:-hermes}
EOF

    local provider_key_env="${LLM_PROVIDER_API_KEY_ENV:-}"
    local provider_base_env="${LLM_PROVIDER_BASE_URL_ENV:-}"

    cat > "$ENV_FILE" << EOF
HERMES_MODEL_API_KEY=${api_key}
DEEPSEEK_API_KEY=$([ "$provider" = deepseek ] && printf '%s' "$api_key")
CUSTOM_LLM_API_KEY=$([ "$provider" = custom ] && printf '%s' "$api_key")
API_SERVER_KEY=${ask}
SOUL_PATH=${SOUL_PATH}
EOF
    if [ -n "$provider_key_env" ] && [ "$provider_key_env" != "DEEPSEEK_API_KEY" ] && [ "$provider_key_env" != "CUSTOM_LLM_API_KEY" ]; then
        printf '%s=%s\n' "$provider_key_env" "$api_key" >> "$ENV_FILE"
    fi
    if [ -n "$provider_base_env" ]; then
        printf '%s=%s\n' "$provider_base_env" "${LLM_BASE_URL:-}" >> "$ENV_FILE"
    fi
    if [ -n "$old_secret_extra" ]; then
        echo "" >> "$ENV_FILE"
        echo "$old_secret_extra" >> "$ENV_FILE"
    fi

    chmod 600 "$ENV_FILE" 2>/dev/null || true
    echo -e "  ${GREEN}✓ $STATE_FILE 已写入普通配置${NC}"
    echo -e "  ${GREEN}✓ $SCRIPT_DIR/docker-compose.override.yml 已写入容器名称覆盖${NC}"
    echo -e "  ${GREEN}✓ $ENV_FILE 已写入 secrets${NC}"
}
