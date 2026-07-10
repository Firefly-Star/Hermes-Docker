# shellcheck shell=bash
# This file is sourced by setup.sh. Do not execute setup flow at top level.

# ── 启动容器 ──
hermes_container_name() {
    printf '%s' "${CONTAINER_NAME:-hermes}"
}

compose_cmd() {
    local compose=(docker compose)
    if [ -f "$STATE_FILE" ]; then
        compose+=(--env-file "$STATE_FILE")
    fi
    if [ -f "$ENV_FILE" ]; then
        compose+=(--env-file "$ENV_FILE")
    fi
    printf '%s\n' "${compose[@]}"
}

run_compose() {
    local compose=()
    while IFS= read -r line; do
        [ -n "$line" ] && compose+=("$line")
    done < <(compose_cmd)
    "${compose[@]}" "$@"
}

# ── 启动容器 ──
start_container() {
    echo ""
    echo -e "${BOLD}[15] 启动／重启容器${NC}"
    local container
    container="$(hermes_container_name)"
    # 确保 mcp 共享网络存在
    docker network inspect mcp-net >/dev/null 2>&1 || docker network create mcp-net
    # 如果启用了 playwright，先确保它在运行
    if [ "${MCP_PLAYWRIGHT_ENABLED:-false}" = "true" ]; then
        echo "  检查 Playwright MCP 容器..."
        if [ -f "$SCRIPT_DIR/playwright/docker-compose.yml" ]; then
            if ! docker ps --format '{{.Names}}' | grep -q '^playwright-mcp$' 2>/dev/null; then
                echo "  启动 Playwright MCP..."
                # 生成 playwright 的 .env（代理配置）
                if [ "${PROXY_ENABLED:-false}" = "true" ] && [ -n "$PROXY_HOST" ]; then
                    cat > "$SCRIPT_DIR/playwright/.env" << PROXYEOF
PROXY_URL=http://${PROXY_HOST}:${PROXY_PORT:-7890}
PROXYEOF
                fi
                (cd "$SCRIPT_DIR/playwright" && docker compose up -d)
                echo -e "  ${GREEN}✓ Playwright MCP 已启动${NC}"
            else
                echo -e "  ${GREEN}✓ Playwright MCP 已在运行${NC}"
            fi
        else
            echo -e "  ${YELLOW}⚠ ./playwright 子仓库未初始化${NC}"
            echo -e "  ${DIM}  请先运行: git submodule update --init${NC}"
        fi
    fi
    read -p "  现在启动? [Y/n]: " yn
    case "$yn" in
        n|N|no)
            echo "  跳过。手动启动: cd $SCRIPT_DIR && docker compose up -d"
            return 0
            ;;
        *)
            # 检查 SSH key 是否存在（docker-compose 会 bind mount，文件不存在则启动失败）
            if [ ! -f "$HOME/.ssh/id_hermes-single" ]; then
                echo -e "  ${RED}⚠ SSH 密钥不存在: ~/.ssh/id_hermes-single${NC}"
                echo -e "  ${DIM}  请先运行 setup.sh 完成 SSH 密钥配置，或手动生成:${NC}"
                echo -e "  ${DIM}    ssh-keygen -t ed25519 -f ~/.ssh/id_hermes-single -N \"\"${NC}"
                echo -e "  ${DIM}    cat ~/.ssh/id_hermes-single.pub >> ~/.ssh/authorized_keys${NC}"
                return 1
            fi
            # 渲染配置（宿主机 env 展开）
            echo "  渲染配置..."
            bash "$SCRIPT_DIR/render-config.sh" 2>/dev/null || echo -e "  ${YELLOW}⚠ render-config.sh 未找到，跳过${NC}"
            echo "  停止旧容器..."
            run_compose down 2>/dev/null || true
            echo "  启动新容器..."
            run_compose up -d
            echo "  等待容器初始化..."
            wait_container || return 1

            # stage2 在容器启动后可能会用镜像默认配置覆盖顶层 /opt/data/config.yaml，
            # 这里无条件重新同步一次，确保 profile config / .env 始终覆盖顶层。
            docker exec "$container" sh -lc '
                set -e
                rm -f /opt/data/profiles/'"'"${AGENT_NAME}"'"'/config.rendered.yaml
                cp /opt/data/profiles/'"'"${AGENT_NAME}"'"'/config.yaml /opt/data/config.yaml
                cp /opt/data/profiles/'"'"${AGENT_NAME}"'"'/.env /opt/data/.env
                chown -R 10000:10000 /opt/data/profiles/'"'"${AGENT_NAME}"'"' /opt/data/config.yaml /opt/data/.env 2>/dev/null || true
                chmod 600 /opt/data/profiles/'"'"${AGENT_NAME}"'"'/.env /opt/data/.env 2>/dev/null || true
            ' 2>/dev/null || true

            if [ "${AGENT_NAME:-kaguya}" != "kaguya" ]; then
                echo "  引导命名 profile: ${AGENT_NAME} ..."
                docker exec "$container" sh -lc '
                    set -e
                    cd /opt/hermes
                    . .venv/bin/activate
                    if ! hermes profile show "'"${AGENT_NAME}"'" >/dev/null 2>&1; then
                        hermes profile create "'"${AGENT_NAME}"'" --clone >/dev/null
                    fi
                '
                docker cp "$SCRIPT_DIR/config.active.yaml" "$container:/opt/data/profiles/${AGENT_NAME}/config.yaml"
                docker cp "$ENV_FILE" "$container:/opt/data/profiles/${AGENT_NAME}/.env"
                docker cp "$ENV_FILE" "$container:/opt/data/.env"
                docker exec "$container" sh -lc '
                    set -e
                    rm -f /opt/data/profiles/"'"${AGENT_NAME}"'"/config.rendered.yaml
                    cp /opt/data/profiles/"'"${AGENT_NAME}"'"/config.yaml /opt/data/config.yaml
                    cp /opt/data/profiles/"'"${AGENT_NAME}"'"/.env /opt/data/.env
                    chown -R 10000:10000 /opt/data/profiles/"'"${AGENT_NAME}"'" /opt/data/config.yaml /opt/data/.env 2>/dev/null || true
                    chmod 600 /opt/data/profiles/"'"${AGENT_NAME}"'"/.env /opt/data/.env 2>/dev/null || true
                '
                echo "  ${GREEN}✓ 命名 profile 已引导完成${NC}"
            fi
            echo -e "  ${GREEN}✓ 容器已启动${NC}"
            return 0
            ;;
    esac
}

# ── 等待容器就绪 ──
wait_container() {
    echo "  等待容器就绪..."
    local container
    container="$(hermes_container_name)"
    for i in $(seq 1 30); do
        if docker exec "$container" test -f /opt/data/.initialized 2>/dev/null; then
            echo -e "  ${GREEN}✓ 容器就绪${NC}"
            return 0
        fi
        sleep 1
    done
    echo -e "  ${YELLOW}⚠ 等待超时，请稍后手动进入容器${NC}"
    return 1
}

# ── 进入容器 ──
enter_container() {
    echo ""
    echo -e "${BOLD}[16] 进入容器${NC}"
    local container
    container="$(hermes_container_name)"
    if docker ps --format '{{.Names}}' | grep -q "^${container}$" 2>/dev/null; then
        # 容器正在运行，直接问要不要进
        read -p "  现在进入容器? [Y/n]: " yn
        case "$yn" in
            n|N|no)
                echo "  跳过。手动进入: bash exec.sh"
                return 0
                ;;
            *)
                wait_container || return 0
                echo "  进入容器..."
                docker exec -it "$container" bash
                ;;
        esac
    elif docker ps -a --format '{{.Names}}' | grep -q "^${container}$" 2>/dev/null; then
        # 容器存在但未运行，问要不要启动再进
        echo -e "  ${YELLOW}⚠ 容器 $container 已存在但未运行${NC}"
        read -p "  启动并进入容器? [Y/n]: " yn
        case "$yn" in
            n|N|no)
                echo "  手动启动: cd $SCRIPT_DIR && docker compose up -d"
                echo "  手动进入: bash exec.sh"
                return 0
                ;;
            *)
                echo "  启动容器..."
                docker start "$container"
                wait_container || return 0
                echo "  进入容器..."
                docker exec -it "$container" bash
                ;;
        esac
    else
        # 容器完全不存在
        echo -e "  ${YELLOW}⚠ 容器 $container 不存在，请先运行 setup.sh 完成部署${NC}"
        echo "  部署完成后: bash exec.sh"
    fi
}
