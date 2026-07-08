#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_PROJECT="hermes_single_test_runtime"
TEST_CONTAINER="hermes-single-test-runtime"

echo "[cleanup-test-runtime] project=$TEST_PROJECT container=$TEST_CONTAINER"

echo "[1/4] 当前运行中的主容器检查"
if ! docker ps --format '{{.Names}}' | grep -q '^hermes$'; then
  echo "警告：当前工作中的 hermes 容器不在运行列表里。继续清理测试资源，但请自行确认现场。"
fi

echo "[2/4] 删除测试 compose 项目资源 (down -v)"
# 不依赖临时 runtime 目录存在，直接按 project label 清理。
docker compose -p "$TEST_PROJECT" -f "$REPO_ROOT/docker-compose.yml" down -v --remove-orphans 2>/dev/null || true

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

echo "[done] 测试容器资源已清理（仅 ${TEST_PROJECT} / ${TEST_CONTAINER}）"
docker ps --format 'table {{.Names}}\t{{.Status}}'
