# setup.sh 真正 E2E 测试设计

目标：在不影响当前工作中的 `hermes` 容器前提下，运行与 `setup.sh` 完全相同的真实交互流程，并启动新的测试容器，验证 setup 向导、配置写入、容器启动、profile 初始化三条链同时成立。

## 定义：什么叫“与 setup.sh 完全相同”

这里指：
- 真正执行 `bash setup.sh`
- 真正走 `main()`
- 真正通过 stdin 喂交互输入
- 真正执行 `check_deps -> prompt_* -> write_env -> start_container -> enter_container`
- 真正执行 `docker compose up -d`
- 真正生成 `.env/.setup-state.env/docker-compose.override.yml`
- 真正起一个测试容器

不同点仅有：
- 执行目录是临时隔离副本目录，不污染当前仓库
- 容器名 / project 名 / profile 名全部是测试专用
- 测试结束默认保留测试容器，清理由单独脚本执行

## 安全隔离原则

1. 绝不在当前工作目录直接执行 `setup.sh`。
2. 每次测试在 `tmp_path/setup-e2e-runtime/` 复制一份仓库最小副本后执行。
3. 固定测试容器名：`hermes-single-setup-e2e`
4. 固定测试 profile：`kaguya-e2e`
5. 固定测试 compose project：`hermes_single_setup_e2e`
6. 测试中 `start_container()` 允许真实执行，但只作用于测试副本目录和测试容器名。
7. `enter_container()` 交互输入固定为 `n`，避免测试卡在交互 shell。
8. 测试前后必须断言当前 `hermes` 容器始终存在。
9. 测试默认保留测试容器，手动清理通过 `scripts/cleanup-test-setup-e2e.sh`。

## 用例设计

### 用例 1：完整 setup.sh E2E 启动测试容器

执行：
- 在临时副本目录中运行 `bash setup.sh`
- 通过 here-doc 输入全部交互答案

建议输入序列：
1. Agent 名称：`kaguya-e2e`
2. 容器名称：`hermes-single-setup-e2e`
3. Provider 选择：`2` (custom)
4. Provider 名：`ziikoo`
5. Base URL：`https://api.gaoxin.net.cn/v1`
6. API key：测试 key
7. 模型编号：`1`（若 mock /models 只返回一个模型，则必为 1）
8. SSH 用户：`tester`
9. SOUL 路径：临时副本内 `SOUL.md`
10. memory：`n`
11. tool progress：`y`
12. compression：`y`
13. threshold：`0.85`
14. context length：`1000000`
15. playwright：`n`
16. SSH host：`127.0.0.1`
17. 启动容器：空/yes
18. 进入容器：`n`

预期：
- setup.sh 退出码 0
- 临时副本内 `.env/.setup-state.env/docker-compose.override.yml` 正确生成
- 测试容器 `hermes-single-setup-e2e` 运行中
- 当前工作容器 `hermes` 仍在
- 容器内 `/opt/data/profiles/kaguya-e2e/.env` 存在
- 容器内 `/opt/data/profiles/kaguya-e2e/config.yaml` 为 custom
- 容器内 `/opt/data/config.yaml` 也为 custom

### 用例 2：setup.sh E2E 后重启测试容器仍保持 custom active config

执行：
- 复用已成功 setup 的测试副本目录
- 执行 `docker compose -p hermes_single_setup_e2e down`
- 再执行 `docker compose -p hermes_single_setup_e2e up -d`

预期：
- `/opt/data/profiles/kaguya-e2e/config.yaml` 仍为 custom
- `/opt/data/config.yaml` 仍为 custom
- 不存在 `config.rendered.yaml`

## 额外实现需求

1. 因为 `prompt_llm_provider()` 在 custom 模式下会请求 `/models`，E2E 测试必须提供一个临时本地模型列表服务。
2. 因为 `setup_ssh_server()` / `detect_ssh_host()` / `setup_ssh_key()` 会碰宿主机，E2E 测试要么：
   - 使用当前机器已有 sshd / ~/.ssh/id_hermes-single
   - 要么在隔离副本目录 PATH 前放置最小 fake-bin，仅替换高风险系统命令，但不替换 docker/compose
3. cleanup 脚本必须只清理：
   - `hermes-single-setup-e2e`
   - `hermes_single_setup_e2e` project 的卷/网络

## 新增文件
- `tests/test_setup_e2e.py`
- `scripts/cleanup-test-setup-e2e.sh`

## 成功标准
1. 真正 `bash setup.sh` 运行成功。
2. 新测试容器成功启动。
3. 当前 `hermes` 容器完全不受影响。
4. 容器内 active profile config 与 top-level config 都是 custom。
5. cleanup 脚本经验证只删除测试容器与测试 project 资源。
