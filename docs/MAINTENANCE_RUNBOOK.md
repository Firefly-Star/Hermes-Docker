# 日常维护与操作手册

本文档给维护者提供“日常该怎么做”的操作手册，偏实践，不讲大背景。

如果你第一次接手仓库：
1. 先看 `docs/MAINTAINER_OVERVIEW.md`
2. 再看 `docs/CURRENT_STATUS_AND_ROADMAP.md`
3. 然后用本文档执行具体操作

---

## 1. 常用命令速查

### 查看当前 git 状态
```bash
cd ~/task5/hermes-single
git status
```

### 查看当前容器
```bash
docker ps --format 'table {{.Names}}\t{{.Status}}'
```

### 看 setup.d 主路径相关文件
```bash
sed -n '1,220p' setup.sh
sed -n '1,220p' setup.d/110-container.sh
sed -n '1,220p' render-config.sh
sed -n '1,220p' custom-init.sh
```

---

## 2. 三层测试怎么跑

### L1 模块/函数测试
```bash
cd ~/task5/hermes-single
python3 -m pytest \
  tests/test_00_common.py \
  tests/test_20_agent_name.py \
  tests/test_25_container_name.py \
  tests/test_30_llm_provider.py \
  tests/test_40_ssh_user.py \
  tests/test_50_soul.py \
  tests/test_60_memory.py \
  tests/test_70_display.py \
  tests/test_75_compression.py \
  tests/test_80_playwright_mcp.py \
  tests/test_90_ssh_server.py \
  tests/test_100_env.py \
  tests/test_110_container.py \
  tests/test_999_main.py -q
```

用途：
- 改 shell 函数
- 改交互
- 改 env/state 写入逻辑

### L2 运行时隔离容器测试
```bash
cd ~/task5/hermes-single
python3 -m pytest tests/test_runtime_isolated.py -q
```

用途：
- 改 `render-config.sh`
- 改 `custom-init.sh`
- 改 active config 管理

跑完后如需清理：
```bash
bash scripts/cleanup-test-runtime.sh
```

### L3 setup.sh 真 E2E
```bash
cd ~/task5/hermes-single
python3 -m pytest tests/test_setup_e2e.py -q
```

用途：
- 改 `setup.sh`
- 改 `setup.d/110-container.sh`
- 改 profile bootstrap
- 改真实 setup 交互流程

跑完后如需清理：
```bash
bash scripts/cleanup-test-setup-e2e.sh
```

### 全量跑法
```bash
cd ~/task5/hermes-single
python3 -m pytest \
  tests/test_00_common.py \
  tests/test_20_agent_name.py \
  tests/test_25_container_name.py \
  tests/test_30_llm_provider.py \
  tests/test_40_ssh_user.py \
  tests/test_50_soul.py \
  tests/test_60_memory.py \
  tests/test_70_display.py \
  tests/test_75_compression.py \
  tests/test_80_playwright_mcp.py \
  tests/test_90_ssh_server.py \
  tests/test_100_env.py \
  tests/test_110_container.py \
  tests/test_999_main.py \
  tests/test_runtime_isolated.py \
  tests/test_setup_e2e.py -q
```

---

## 3. 什么时候跑哪层测试

### 改 `setup.d/30-llm-provider.sh`
至少跑：
- `tests/test_30_llm_provider.py`
- `tests/test_100_env.py`
- `tests/test_setup_e2e.py`

### 改 `render-config.sh`
至少跑：
- `tests/test_runtime_isolated.py`
- `tests/test_setup_e2e.py`

### 改 `custom-init.sh`
至少跑：
- `tests/test_runtime_isolated.py`
- `tests/test_setup_e2e.py`

### 改 `setup.d/110-container.sh`
至少跑：
- `tests/test_110_container.py`
- `tests/test_setup_e2e.py`

### 改 README / 文档
- 一般不需要跑代码测试
- 但如果文档声明了命令或结果，最好顺手验证一次

---

## 4. 开发 provider catalog 功能时该怎么做

### provider catalog 的来源
开发者维护：
- `scripts/export-hermes-providers.py`
- `data/hermes-providers.json`

普通用户不运行导出脚本。

### 更新 provider catalog（开发者操作）
当 Hermes 上游 provider registry 变化时：
1. 在 Hermes 可用环境里运行导出脚本
2. 更新 `data/hermes-providers.json`
3. 提交到仓库

### 开发时应该改哪些文件
- `setup.d/30-llm-provider.sh`
- `tests/test_30_llm_provider.py`
- `tests/test_100_env.py`
- 需要时更新：
  - `README.md`
  - `README-CH.md`
  - `docs/provider-catalog-design.md`

### 开发时推荐顺序
1. 先写 RED 测试
2. 再改 shell 逻辑
3. 跑测试到 GREEN
4. 更新文档
5. 提交

---

## 5. 提交前检查

推荐最小检查：
```bash
cd ~/task5/hermes-single
git status
python3 -m pytest tests/test_runtime_isolated.py -q
python3 -m pytest tests/test_setup_e2e.py -q
```

如果改动的是 setup.d 主逻辑，再补：
```bash
python3 -m pytest \
  tests/test_00_common.py \
  tests/test_20_agent_name.py \
  tests/test_25_container_name.py \
  tests/test_30_llm_provider.py \
  tests/test_40_ssh_user.py \
  tests/test_50_soul.py \
  tests/test_60_memory.py \
  tests/test_70_display.py \
  tests/test_75_compression.py \
  tests/test_80_playwright_mcp.py \
  tests/test_90_ssh_server.py \
  tests/test_100_env.py \
  tests/test_110_container.py \
  tests/test_999_main.py -q
```

---

## 6. 当前主容器安全规则

### 不要做的事
- 不要在当前仓库目录直接随手跑 `docker compose down`
- 不要在没确认容器名/project name 的情况下启动/删除测试容器
- 不要把运行态 `config.active.yaml` 重新追踪进 git

### 要做的事
- 真实容器测试后用 cleanup 脚本清理
- 跑 E2E 前后看一眼：
```bash
docker ps --format 'table {{.Names}}\t{{.Status}}'
```

---

## 7. 当前仓库中最关键的维护文件

如果你只想快速 debug 主链路，优先看：
- `setup.sh`
- `setup.d/30-llm-provider.sh`
- `setup.d/100-env.sh`
- `setup.d/110-container.sh`
- `render-config.sh`
- `custom-init.sh`

如果你只想快速跑测试，优先看：
- `docs/testing-guide.md`
- `tests/test_runtime_isolated.py`
- `tests/test_setup_e2e.py`

如果你只想了解当前开发重点，优先看：
- `docs/CURRENT_STATUS_AND_ROADMAP.md`
- `docs/provider-catalog-design.md`

---

## 8. 当前已知下一步

当前最重要的开发任务是：
- 完成多 provider setup

即：
- `setup.d/30-llm-provider.sh` 真正读取 `data/hermes-providers.json`
- 不再只支持 DeepSeek / Custom 两项

在动手之前，建议先读：
- `docs/provider-catalog-design.md`
