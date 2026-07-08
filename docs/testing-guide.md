# Hermes-Docker 测试说明

本文档整理当前仓库的三层测试体系：
1. setup.d 模块/函数测试
2. 运行时隔离容器集成测试
3. setup.sh 真正 E2E 测试

目标：让你快速知道每层测试在验证什么、如何运行、会不会影响当前工作的 `hermes` 容器，以及跑完后怎么清理。

---

## 总览

| 层级 | 入口 | 主要验证对象 | 是否真实起容器 | 是否会碰当前 `hermes` |
|---|---|---|---|---|
| L1 模块/函数测试 | `tests/test_00_common.py` ... `tests/test_999_main.py` | `setup.d/*.sh` 的交互、变量、文件写入、副作用命令序列 | 否（默认 stub） | 否 |
| L2 运行时隔离容器集成测试 | `tests/test_runtime_isolated.py` | `render-config.sh`、`custom-init.sh`、profile/top-level config 运行态 | 是 | 否 |
| L3 `setup.sh` 真 E2E | `tests/test_setup_e2e.py` | 真正 `bash setup.sh`、交互输入、容器启动、profile bootstrap | 是 | 否 |

---

## L1：setup.d 模块/函数测试

### 覆盖范围
这些测试按脚本拆分，对应：
- `tests/test_00_common.py`
- `tests/test_20_agent_name.py`
- `tests/test_25_container_name.py`
- `tests/test_30_llm_provider.py`
- `tests/test_40_ssh_user.py`
- `tests/test_50_soul.py`
- `tests/test_60_memory.py`
- `tests/test_70_display.py`
- `tests/test_75_compression.py`
- `tests/test_80_playwright_mcp.py`
- `tests/test_90_ssh_server.py`
- `tests/test_100_env.py`
- `tests/test_110_container.py`
- `tests/test_999_main.py`

### 它验证什么
- `prompt_*` 交互函数
- shell 变量是否正确赋值
- `.env/.setup-state.env/docker-compose.override.yml` 是否正确生成
- 高风险系统命令（docker/systemctl/service/ssh-keygen）是否按预期被调用
- `main()` 调用顺序

### 隔离方式
- `HERMES_SINGLE_TEST_MODE=1`
- 临时 `.env/.setup-state.env/SOUL.md`
- fake HOME
- fake-bin stub 外部命令
- 默认不碰真实 docker 容器

### 运行命令
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

### 当前结果
- `30 passed`

### 清理
- 不需要额外清理（只使用临时目录和 stub）

---

## L2：运行时隔离容器集成测试

### 入口
- `tests/test_runtime_isolated.py`

### 它验证什么
- `custom-init.sh` 首次启动后能生成 profile 目录
- `render-config.sh` 能把项目管理的 active config / env 正确推到测试容器
- 顶层 `/opt/data/config.yaml` 与 profile `config.yaml` 在运行态保持一致
- 不再依赖/保留 `config.rendered.yaml`
- 重启后配置仍稳定

### 隔离方式
- 在 pytest `tmp_path` 下复制最小运行目录
- 固定测试容器名：`hermes-single-test-runtime`
- 固定 compose project：`hermes_single_test_runtime`
- 当前主容器 `hermes` 在测试前后都会被断言必须存在

### 运行命令
```bash
cd ~/task5/hermes-single
python3 -m pytest tests/test_runtime_isolated.py -q
```

### 当前结果
- `3 passed`

### 是否保留测试容器
- 默认会保留 `hermes-single-test-runtime`，方便人工检查

### 检查完后的清理命令
```bash
cd ~/task5/hermes-single
bash scripts/cleanup-test-runtime.sh
```

### 清理脚本会做什么
- `down -v` 删除 `hermes_single_test_runtime` project 资源
- 兜底删测试容器 `hermes-single-test-runtime`
- 兜底删测试 project 对应卷/网络
- 不会碰当前工作的 `hermes`

---

## L3：`setup.sh` 真正 E2E 测试

### 入口
- `tests/test_setup_e2e.py`

### 它验证什么
这层测试是真正的：
- `bash setup.sh`
- 真实走 `main()`
- 真实喂交互输入
- 真实执行 `write_env -> start_container -> enter_container`
- 真实启动新的测试容器
- 真实检查容器内目标 profile、active config、top-level config、.env

它覆盖的是“setup 向导整条链是否真的可用”。

### 隔离方式
- 在 pytest 临时目录复制一份隔离副本目录
- 固定测试容器名：`hermes-single-setup-e2e`
- 固定测试 compose project：`hermes_single_setup_e2e`
- 固定测试 profile：`kaguya-e2e`
- 本地临时 `/models` 假服务供 `prompt_llm_provider()` 选择模型
- 当前主容器 `hermes` 在测试前后都会被断言必须存在

### 运行命令
```bash
cd ~/task5/hermes-single
python3 -m pytest tests/test_setup_e2e.py -q
```

### 当前结果
- `1 passed`

### 是否保留测试容器
- 默认会保留 `hermes-single-setup-e2e`，方便人工检查

### 检查完后的清理命令
```bash
cd ~/task5/hermes-single
bash scripts/cleanup-test-setup-e2e.sh
```

### 清理脚本会做什么
- `down -v` 删除 `hermes_single_setup_e2e` project 资源
- 兜底删测试容器 `hermes-single-setup-e2e`
- 兜底删测试 project 对应卷/网络
- 不会碰当前工作的 `hermes`

---

## 推荐执行顺序

如果你只是想验证代码逻辑：
1. 先跑 L1
2. 需要验证容器运行态再跑 L2
3. 需要验证真实 setup 向导再跑 L3

推荐顺序：
```bash
cd ~/task5/hermes-single

# 1) 模块/函数层
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

# 2) 运行时容器层
python3 -m pytest tests/test_runtime_isolated.py -q

# 3) 真 setup.sh E2E
python3 -m pytest tests/test_setup_e2e.py -q
```

---

## 一次性全跑
如果你想一次性把三层都跑完：
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

## 跑完后的清理建议
如果你跑了 L2 / L3，建议最后手动清理：
```bash
cd ~/task5/hermes-single
bash scripts/cleanup-test-runtime.sh
bash scripts/cleanup-test-setup-e2e.sh
```

如果只跑 L1，不需要清理。

---

## 当前已知测试结论

截至当前仓库状态：
- setup.d 模块/函数测试：`30 passed`
- 运行时隔离容器测试：`3 passed`
- setup.sh 真 E2E：`1 passed`

说明：
1. `setup.d` 脚本级逻辑已被覆盖
2. 运行态 config/.env 管理逻辑已被验证
3. `setup.sh` 从交互到容器启动再到 profile bootstrap 的真实链路已跑通

---

## 什么时候用哪一层

- 改 prompt / env / 小逻辑：跑 L1
- 改 `custom-init.sh` / `render-config.sh` / 顶层 config 管理：跑 L2
- 改 `setup.sh` / `start_container()` / profile bootstrap：跑 L3
- 改动较大：三层都跑
