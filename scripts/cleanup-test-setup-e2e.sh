#!/bin/bash
set -euo pipefail

TEST_PROJECT="hermes_single_setup_e2e"
TEST_CONTAINER="hermes-single-setup-e2e"

echo "[cleanup-test-setup-e2e] project=$TEST_PROJECT container=$TEST_CONTAINER"

echo "[1/4] 检查当前主容器"
if ! docker ps --format '{{.Names}}' | grep -q '^hermes$'; then
  echo "警告：当前主 hermes 容器未在运行列表中。"
fi

echo "[2/4] 删除测试 compose 项目资源 (down -v)"
docker compose -p "$TEST_PROJECT" down -v --remove-orphans 2>/dev/null || true

echo "[3/4] 兜底删除测试容器"
if docker ps -a --format '{{.Names}}' | grep -q "^${TEST_CONTAINER}$"; then
  docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1 || true
fi

echo "[4/4] 兜底删除测试项目卷/网络"
for net in $(docker network ls --format '{{.Name}}' | grep "^${TEST_PROJECT}_" || true); do
  docker network rm "$net" >/dev/null 2>&1 || true
done
for vol in $(docker volume ls --format '{{.Name}}' | grep "^${TEST_PROJECT}_" || true); do
  docker volume rm "$vol" >/dev/null 2>&1 || true
done

echo "[done] setup.sh E2E 测试资源已清理"
docker ps --format 'table {{.Names}}\t{{.Status}}'
