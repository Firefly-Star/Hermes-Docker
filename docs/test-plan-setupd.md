# setup.d 脚本测试设计文档

目标：为 `setup.d/` 下每个脚本建立对应测试文件，在不影响当前工作中的 `hermes` 容器前提下，验证交互逻辑、状态写入逻辑、以及容器/宿主机副作用边界。

安全原则：
1. 默认所有测试都设置 `HERMES_SINGLE_TEST_MODE=1`，只 `source ./setup.sh`，不直接执行 `main`。
2. 默认所有测试都使用临时 `ENV_FILE` / `STATE_FILE` / `SOUL` / `HOME` / `PATH`。
3. 对会调用 `docker compose down/up`、`docker exec`、`docker cp`、`service/systemctl`、`ssh-keygen` 的函数，统一用 fake-bin stub 拦截，不直接命中真实系统。
4. 容器相关测试使用新的专用容器名与 compose project name，例如 `hermes-single-test-*`，且优先 stub 外部命令；只有显式的隔离集成测试才允许启动新测试容器。
5. 禁止测试中访问/修改当前正在运行的 `hermes` 容器。

测试分层：
- L1: shell 函数级测试（交互、变量赋值、文件输出）
- L2: 副作用命令测试（通过 stub 验证会调用什么命令，不真正执行）
- L3: 隔离容器集成测试（仅对必要路径，使用新容器名/新 project）

## 目录映射

每个 setup.d 脚本对应一个测试文件：
- `setup.d/00-common.sh` -> `tests/test_00_common.py`
- `setup.d/20-agent-name.sh` -> `tests/test_20_agent_name.py`
- `setup.d/25-container-name.sh` -> `tests/test_25_container_name.py`
- `setup.d/30-llm-provider.sh` -> `tests/test_30_llm_provider.py`
- `setup.d/40-ssh-user.sh` -> `tests/test_40_ssh_user.py`
- `setup.d/50-soul.sh` -> `tests/test_50_soul.py`
- `setup.d/60-memory.sh` -> `tests/test_60_memory.py`
- `setup.d/70-display.sh` -> `tests/test_70_display.py`
- `setup.d/75-compression.sh` -> `tests/test_75_compression.py`
- `setup.d/80-playwright-mcp.sh` -> `tests/test_80_playwright_mcp.py`
- `setup.d/90-ssh-server.sh` -> `tests/test_90_ssh_server.py`
- `setup.d/100-env.sh` -> `tests/test_100_env.py`
- `setup.d/110-container.sh` -> `tests/test_110_container.py`
- `setup.d/999-main.sh` -> `tests/test_999_main.py`

另加：
- `tests/conftest.py`：共用 fixture / fake-bin / helper
- `tests/helpers.py`：运行 shell 函数与读取产物的帮助函数

## 公共测试基建

### fixture 设计
1. `repo_root`
   - 指向 `/home/wxz/task5/hermes-single`
2. `tmp_env_files`
   - 创建临时 `.env`、`.setup-state.env`、`SOUL.md`
3. `fake_home`
   - 提供隔离的 `$HOME`，包含 `.ssh/authorized_keys` 等
4. `fake_bin`
   - 提供 stub 命令：`docker`、`docker-compose`、`systemctl`、`service`、`sudo`、`ssh-keygen`、`hostname`、`ip`、`realpath`
5. `bash_env`
   - 统一导出：
     - `HERMES_SINGLE_TEST_MODE=1`
     - `ENV_FILE`, `STATE_FILE`
     - `HOME=fake_home`
     - `PATH=fake_bin:$PATH`
     - `SCRIPT_DIR=repo_root`
6. `run_shell_function(name, stdin, extra_env)`
   - `source ./setup.sh` 后调用指定函数
7. `command_log`
   - fake-bin 将被调用命令写入日志，供断言使用

### 参数确定原则
- 交互输入值：取脚本中允许的边界值、默认值、非法值。
- 环境变量初值：按脚本默认值以及当前项目真实使用值构造。
- 路径参数：都落在 `tmp_path` 下，避免碰真实目录。
- 容器名/project 名：统一使用 `hermes-single-test-*`，确保不等于 `hermes`。

## 各脚本测试设计

### 00-common.sh
函数：
- `load_env_file(file)`：存在则 source，不存在则静默
- `load_env()`：读取 `STATE_FILE` 与 `ENV_FILE`
- `is_wsl()`：检查 `/proc/version`
- `check_deps()`：检查 `docker` 与 `docker compose version`

用例：
1. `load_env_file` 读取已有 env
   - 输入：临时文件 `FOO=bar`
   - 期望：shell 中 `FOO=bar`
2. `load_env_file` 对不存在文件不报错
   - 期望：返回码 0
3. `load_env` 同时加载 state/env
   - 期望：两个文件中的变量都可见
4. `check_deps` 在 fake docker 存在时通过
   - 期望：返回码 0
5. `check_deps` 缺少 docker 时失败
   - 期望：返回非 0，输出“请先安装 Docker”

容器内期望：无。
容器外期望：仅 shell 变量与输出变化。

### 20-agent-name.sh
函数：`prompt_name()`
作用：读取 agent 名称，空输入时保留默认/当前值。

用例：
1. 空输入 -> 默认 `kaguya`
2. 给定输入 `my-agent` -> 设置为 `my-agent`
3. 当前已有 `AGENT_NAME=alice` 且空输入 -> 保持 `alice`

期望：只修改 shell 变量 `AGENT_NAME`。

### 25-container-name.sh
函数：`prompt_container_name()`
作用：读取并校验 Docker 容器名。

用例：
1. 空输入 -> 默认 `hermes`
2. 合法值 `hermes-test_1`
3. 先给非法值 `-bad` 再给合法值 `ok-name`
   - 期望：提示非法后重试
4. 成功时导出 `CONTAINER_NAME`

期望：
- shell 变量 `CONTAINER_NAME`
- stdout 包含成功/错误提示

### 30-llm-provider.sh
函数：
- `mask_secret(secret)`
- `normalize_base_url(url)`
- `fetch_models(base_url, api_key)`
- `select_model_from_list(models_text)`
- `prompt_llm_provider()`

用例：
1. `normalize_base_url` 去除结尾 `/`
2. `fetch_models` 对本地假 HTTP server 返回模型列表
3. `select_model_from_list` 正确按编号选中
4. `prompt_llm_provider` 选择 DeepSeek
   - 参数：输入 1 + key
   - 期望：
     - `LLM_PROVIDER=deepseek`
     - `LLM_MODEL=deepseek-v4-flash`
     - `LLM_PROVIDER_API_KEY_ENV=DEEPSEEK_API_KEY`
     - `LLM_PROVIDER_BASE_URL_ENV=DEEPSEEK_BASE_URL`
5. `prompt_llm_provider` 选择 custom
   - 参数：输入 2 + provider 名 + base url + api key + 选中模型编号
   - 期望：
     - `LLM_PROVIDER=custom`
     - `CUSTOM_LLM_PROVIDER_NAME=...`
     - `LLM_PROVIDER_API_KEY_ENV=CUSTOM_LLM_API_KEY`
     - `LLM_PROVIDER_BASE_URL_ENV=CUSTOM_LLM_BASE_URL`
6. `/models` 失败时会重新提示

容器内期望：无。
容器外期望：shell 变量变更；本地假 server 被访问。

### 40-ssh-user.sh
函数：`prompt_ssh_user()`

用例：
1. 空输入 -> 默认 `$USER`
2. 输入 `wxz`
3. 当前已有 `SSH_USER=alice` 且空输入 -> 保持 `alice`

### 50-soul.sh
函数：`prompt_soul()`

用例：
1. 输入存在的 SOUL 路径 -> 转为绝对路径
2. 先输入不存在路径，再输入存在路径 -> 重试成功
3. 空输入使用默认 `./SOUL.md`

期望：
- `SOUL_PATH` 为 `realpath` 后绝对路径
- 非法路径会提示错误

### 60-memory.sh
函数：`prompt_memory_tool()`

用例：
1. 输入 `n` ->
   - `MEMORY_TOOL_ENABLED=false`
   - `DISABLED_TOOLSETS=[memory]`
   - `MEMORY_NUDGE_INTERVAL=0`
   - `SKILL_NUDGE_INTERVAL=0`
2. 输入 `y` ->
   - `MEMORY_TOOL_ENABLED=true`
   - `DISABLED_TOOLSETS=[]`
3. 空输入 -> 保持当前状态

### 70-display.sh
函数：`prompt_tool_progress()`

用例：
1. 输入 `y` -> `TOOL_PROGRESS=verbose`, `SHOW_REASONING=true`
2. 输入 `n` -> `TOOL_PROGRESS=all`
3. 空输入 -> 保持当前值

### 75-compression.sh
函数：
- `prompt_compression()`
- `prompt_model_context_length()`

用例：
1. 启用压缩并输入合法阈值 `0.90`
2. 输入非法阈值 `0.2` 后再输入 `0.85`
3. 禁用压缩时阈值保持原值
4. `prompt_model_context_length` 空输入 -> 不设置
5. 输入非法值 `1024` 后再输入 `131072`

期望：
- `COMPRESSION_ENABLED`
- `COMPRESSION_THRESHOLD`
- `MODEL_CONTEXT_LENGTH`

### 80-playwright-mcp.sh
函数：
- `prompt_playwright_mcp()`
- `prompt_playwright_proxy()`

用例：
1. 输入 `y` 启用，随后 `n` 不启用代理
2. 输入 `y` 启用，随后 `y` 启用代理并填写 host/port
3. 输入 `n` 禁用 playwright
4. 空输入保持当前值
5. `is_wsl()` 为真/假时自动 IP 逻辑分支

期望：
- `MCP_PLAYWRIGHT_ENABLED`
- `PROXY_ENABLED`
- `PROXY_HOST`
- `PROXY_PORT`

### 90-ssh-server.sh
函数：
- `setup_ssh_server()`
- `detect_ssh_host()`
- `setup_ssh_key()`

副作用高，全部使用 fake-bin stub。

用例：
1. `setup_ssh_server` 在 `sshd` 缺失时失败并提示安装
2. `setup_ssh_server` 在 WSL + service 未运行时会调用 `sudo service ssh start`
3. `setup_ssh_server` 在 Linux + systemctl 未运行时会调用 `systemctl enable/start`
4. `detect_ssh_host` 在 WSL 使用 `hostname -I`
5. `detect_ssh_host` 在 Linux 使用 `ip route get 1`
6. `setup_ssh_key` 首次生成 key 并追加 authorized_keys
7. 已有 key 时不会重复追加

容器内期望：无。
容器外期望：
- fake home 下 `.ssh/authorized_keys` 内容变化
- command_log 记录调用的 sudo/service/systemctl/ssh-keygen

### 100-env.sh
函数：`write_env()`

用例：
1. deepseek 模式写出 `.setup-state.env`、`.env`、`docker-compose.override.yml`
2. custom 模式写出 `CUSTOM_LLM_API_KEY` 与 `CUSTOM_LLM_BASE_URL`
3. 保留旧文件中的 extra 字段
4. `API_SERVER_KEY` 缺失时自动生成 64 hex
5. `SOUL_PATH` 写入 `.env`
6. `.env` 权限为 600

容器内期望：无（函数本身只写宿主机文件）。
容器外期望：
- state/env/override 产物完全匹配预期内容结构

### 110-container.sh
函数：
- `hermes_container_name()`
- `start_container()`
- `wait_container()`
- `enter_container()`

风险最高。默认全部 stub docker，不碰真实 `hermes`。

用例：
1. `hermes_container_name` 返回当前容器名
2. `start_container` 选择 `n` 时不执行 docker compose down/up
3. `start_container` 缺失 SSH key 时失败
4. `start_container` 启用 playwright 且 MCP 容器不存在时，会写 `playwright/.env` 并调用 `docker compose up -d`
5. `start_container` 正常路径会调用：
   - `docker network inspect/create`
   - `bash render-config.sh`
   - `docker compose down`
   - `docker compose up -d`
6. `wait_container` 在第 N 次 `docker exec test -f /opt/data/.initialized` 成功时返回 0
7. `enter_container` 容器运行中、未运行、完全不存在三条分支

容器内期望：默认无真实容器副作用。
容器外期望：command_log 精确记录命令序列。

### 999-main.sh
函数：`main()`

测试策略：不让它调用真实外部命令，使用函数 monkeypatch / 预先定义同名 shell 函数覆盖。

用例：
1. `main` 按顺序调用各步骤：
   - `check_deps`
   - `prompt_name`
   - `prompt_container_name`
   - `prompt_llm_provider`
   - `prompt_ssh_user`
   - `prompt_soul`
   - `prompt_memory_tool`
   - `prompt_tool_progress`
   - `prompt_compression`
   - `prompt_model_context_length`
   - `prompt_playwright_mcp`
   - `setup_ssh_server`
   - `detect_ssh_host`
   - `setup_ssh_key`
   - `write_env`
   - `start_container`
   - `enter_container`
2. 某一步失败时，后续步骤不继续

期望：
- 调用顺序日志与设计一致
- 不触碰真实容器

## 隔离容器测试策略

只有在需要验证 `render-config.sh -> docker cp -> profile 文件` 这条链时，才增加单独集成测试：
- 容器名固定为 `hermes-single-test-runtime`
- compose project name 固定为 `hermes_single_test_runtime`
- 单独工作目录/override 文件
- 测试前断言现有 `hermes` 容器名字不等于测试容器名
- 测试结束只删除测试容器，不使用当前仓库默认 `docker compose down`

本轮优先先做 shell 函数级与副作用命令测试，容器级集成测试只在必要时补充。

## 预期结果

1. 每个 `setup.d/*.sh` 都有独立测试文件。
2. 所有高风险副作用路径都有 stub 覆盖，不影响当前 `hermes` 容器。
3. 现有 `tests/test_setup_llm.py` 中与当前交互逻辑不一致的测试会被保留或重构到对应模块文件中，并显式记录当前失败原因或修正后预期。
4. 测试运行输出要能区分：
   - 设计预期通过
   - 当前实现缺陷导致失败
   - 设计上暂未覆盖的集成路径

## 当前已知风险/差异（测试前确认）

1. `tests/test_setup_llm.py` 当前有 2 个失败，因 `prompt_llm_provider()` 交互已经变成 `[1/2]`，旧测试仍喂 `18/37`。
2. `setup.d/110-container.sh` 真实执行会包含 `docker compose down`，绝不能直接在当前仓库目录对真实 docker 命令放行。
3. `render-config.sh` 会 `docker cp` 到当前 `CONTAINER_NAME`；测试必须通过 stub 或新容器名隔离。
4. 当前工作区已有未提交修复（如 `setup.d/30-llm-provider.sh`, `setup.d/100-env.sh`），测试应基于当前工作树而不是历史 commit。
