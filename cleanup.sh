#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "============================================"
echo "  Hermes Single-Agent 清理脚本"
echo "============================================"
echo ""
echo -e "${RED}${BOLD}⚠  此操作将删除以下内容：${NC}"
echo "  • Hermes 容器和镜像"
echo "  • hermes-data 数据卷（包含聊天记录、配置、skill）"
echo "  • mcp-net Docker 网络"
echo "  • SSH 密钥（id_hermes-single）和 authorized_keys 条目"
echo "  • .env 配置文件"
echo ""

read -p "确认清理? [y/N]: " confirm
case "$confirm" in
    y|Y|yes)
        ;;
    *)
        echo -e "  ${YELLOW}已取消${NC}"
        exit 0
        ;;
esac

# ── 停止并删除容器 ──
echo ""
echo -e "${BOLD}[1/6] 停止并删除容器...${NC}"
if [ -f "$SCRIPT_DIR/docker-compose.yml" ]; then
    cd "$SCRIPT_DIR" && docker compose down -v 2>/dev/null || true
    echo -e "  ${GREEN}✓ 容器已删除${NC}"
else
    echo -e "  ${YELLOW}⚠ docker-compose.yml 不存在，跳过${NC}"
fi

# ── 停止并删除 Playwright MCP 容器（如果有子模块） ──
echo ""
echo -e "${BOLD}[2/6] 停止并删除 Playwright MCP 容器...${NC}"
PLAYWRIGHT_DIR="$SCRIPT_DIR/playwright"
if [ -f "$PLAYWRIGHT_DIR/docker-compose.yml" ]; then
    cd "$PLAYWRIGHT_DIR" && docker compose down -v 2>/dev/null || true
    echo -e "  ${GREEN}✓ Playwright MCP 已删除${NC}"
else
    echo -e "  ${YELLOW}⚠ playwright 子仓库不存在或已清理，跳过${NC}"
fi

# ── 删除 mcp-net 网络 ──
echo ""
echo -e "${BOLD}[3/6] 删除 mcp-net 网络...${NC}"
if docker network inspect mcp-net >/dev/null 2>&1; then
    docker network rm mcp-net 2>/dev/null || true
    echo -e "  ${GREEN}✓ mcp-net 已删除${NC}"
else
    echo -e "  ${YELLOW}⚠ mcp-net 不存在，跳过${NC}"
fi

# ── 删除 SSH 密钥 ──
echo ""
echo -e "${BOLD}[4/6] 清理 SSH 密钥...${NC}"
SSH_KEY="$HOME/.ssh/id_hermes-single"
if [ -f "$SSH_KEY" ]; then
    # 从 authorized_keys 中移除公钥
    PUB_KEY="${SSH_KEY}.pub"
    if [ -f "$PUB_KEY" ] && [ -f "$HOME/.ssh/authorized_keys" ]; then
        grep -vFf "$PUB_KEY" "$HOME/.ssh/authorized_keys" > /tmp/authorized_keys_tmp 2>/dev/null || true
        mv /tmp/authorized_keys_tmp "$HOME/.ssh/authorized_keys" 2>/dev/null || true
        chmod 600 "$HOME/.ssh/authorized_keys" 2>/dev/null || true
        echo -e "  ${GREEN}✓ authorized_keys 条目已移除${NC}"
    fi
    rm -f "$SSH_KEY" "${SSH_KEY}.pub"
    echo -e "  ${GREEN}✓ SSH 密钥已删除${NC}"
else
    echo -e "  ${YELLOW}⚠ SSH 密钥不存在，跳过${NC}"
fi

# ── 删除 .env ──
echo ""
echo -e "${BOLD}[5/6] 删除配置文件...${NC}"
if [ -f "$ENV_FILE" ]; then
    rm -f "$ENV_FILE"
    echo -e "  ${GREEN}✓ .env 已删除${NC}"
else
    echo -e "  ${YELLOW}⚠ .env 不存在，跳过${NC}"
fi

# ── 删除 hermes-data volume ──
echo ""
echo -e "${BOLD}[6/6] 删除数据卷...${NC}"
if docker volume inspect hermes-data >/dev/null 2>&1; then
    docker volume rm hermes-data 2>/dev/null || true
    echo -e "  ${GREEN}✓ hermes-data 数据卷已删除${NC}"
else
    echo -e "  ${YELLOW}⚠ hermes-data 不存在，跳过${NC}"
fi

echo ""
echo -e "${GREEN}${BOLD}✅ 清理完成${NC}"
echo ""
echo "如需重置 git 子模块："
echo "  git submodule update --init"
echo ""
echo "重新部署："
echo "  bash setup.sh"
