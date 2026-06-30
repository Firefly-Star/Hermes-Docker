#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

confirm_step() {
    local desc="$1"
    echo ""
    echo -e "${BOLD}[?] ${desc}${NC}"
    read -p "  执行? [y/N]: " val
    case "$val" in
        y|Y|yes) return 0 ;;
        *) echo -e "  ${YELLOW}跳过${NC}"; return 1 ;;
    esac
}

echo "============================================"
echo "  Hermes Single-Agent 清理脚本"
echo "============================================"
echo ""
echo -e "${RED}${BOLD}⚠  可逐项选择需要清理的内容${NC}"
echo ""

# ── 停止并删除容器 ──
if confirm_step "停止并删除 Hermes 容器 (docker compose down -v)"; then
    if [ -f "$SCRIPT_DIR/docker-compose.yml" ]; then
        cd "$SCRIPT_DIR" && docker compose down -v 2>/dev/null || true
        echo -e "  ${GREEN}✓ 容器已删除${NC}"
    else
        echo -e "  ${YELLOW}⚠ docker-compose.yml 不存在${NC}"
    fi
fi

# ── 停止并删除 Playwright MCP 容器 ──
if confirm_step "停止并删除 Playwright MCP 容器 (如果有子模块)"; then
    PLAYWRIGHT_DIR="$SCRIPT_DIR/playwright"
    if [ -f "$PLAYWRIGHT_DIR/docker-compose.yml" ]; then
        cd "$PLAYWRIGHT_DIR" && docker compose down -v 2>/dev/null || true
        echo -e "  ${GREEN}✓ Playwright MCP 已删除${NC}"
    else
        echo -e "  ${YELLOW}⚠ playwright 子仓库不存在或已清理${NC}"
    fi
fi

# ── 删除 mcp-net 网络 ──
if confirm_step "删除 mcp-net Docker 网络"; then
    if docker network inspect mcp-net >/dev/null 2>&1; then
        docker network rm mcp-net 2>/dev/null || true
        echo -e "  ${GREEN}✓ mcp-net 已删除${NC}"
    else
        echo -e "  ${YELLOW}⚠ mcp-net 不存在${NC}"
    fi
fi

# ── 删除 SSH 密钥 ──
SSH_KEY="$HOME/.ssh/id_hermes-single"
if [ -f "$SSH_KEY" ] && confirm_step "清理 SSH 密钥 (id_hermes-single)"; then
    PUB_KEY="${SSH_KEY}.pub"
    if [ -f "$PUB_KEY" ] && [ -f "$HOME/.ssh/authorized_keys" ]; then
        local tmp
        tmp=$(mktemp) || true
        if [ -n "$tmp" ]; then
            grep -vFf "$PUB_KEY" "$HOME/.ssh/authorized_keys" > "$tmp" && mv "$tmp" "$HOME/.ssh/authorized_keys" || rm -f "$tmp"
            chmod 600 "$HOME/.ssh/authorized_keys" 2>/dev/null || true
            echo -e "  ${GREEN}✓ authorized_keys 条目已移除${NC}"
        fi
    fi
    rm -f "$SSH_KEY" "${SSH_KEY}.pub"
    echo -e "  ${GREEN}✓ SSH 密钥已删除${NC}"
fi

# ── 删除 .env ──
if [ -f "$ENV_FILE" ] && confirm_step "删除 .env 配置文件"; then
    rm -f "$ENV_FILE"
    echo -e "  ${GREEN}✓ .env 已删除${NC}"
fi

# ── 删除 hermes-data volume ──
if confirm_step "删除 hermes-data 数据卷（包含聊天记录、配置、skill）"; then
    if docker volume inspect hermes-data >/dev/null 2>&1; then
        docker volume rm hermes-data 2>/dev/null || true
        echo -e "  ${GREEN}✓ hermes-data 数据卷已删除${NC}"
    else
        echo -e "  ${YELLOW}⚠ hermes-data 不存在${NC}"
    fi
fi

echo ""
echo -e "${GREEN}${BOLD}✅ 清理完成${NC}"
echo ""
echo "如需重置 git 子模块："
echo "  git submodule update --init"
echo ""
echo "重新部署："
echo "  bash setup.sh"
