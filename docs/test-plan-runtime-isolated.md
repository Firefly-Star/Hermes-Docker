# 独立测试容器集成测试设计

目标：补充一层真实容器集成测试，验证以下链路：
- 宿主机 `render-config.sh` -> `docker cp`
- 容器启动时 `custom-init.sh`
- profile 目录生成
- 容器内 `config.yaml` / `.env` / `memories/*` 的实际状态

## 安全隔离要求

1. 绝不使用当前仓库根目录直接运行 `docker compose down/up`，因为默认 compose 项目可能影响当前工作容器。
2. 所有真实容器集成测试都在临时目录中进行：
   - 复制 `docker-compose.yml`
   - 复制 `custom-init.sh`
   - 复制 `templates/`
   - 复制 `lib/`
3. 测试容器固定使用：
   - 容器名：`hermes-single-test-runtime`
   - compose project：`hermes_single_test_runtime`
   - volume 名依赖 compose project 自动带前缀，不复用现有 `hermes-data`
4. Playwright/MCP 不参与本轮真实容器测试，避免碰共享 `playwright-mcp` 容器。
5. 测试运行默认保留 `hermes-single-test-runtime` 与其 project 资源，供人工检查；清理通过单独脚本 `scripts/cleanup-test-runtime.sh` 完成。
6. 每次运行前后都断言当前 `hermes` 容器仍然存在且状态不变。

## 真实集成测试用例

### 用例 1：custom-init 首次启动生成 profile 目录
输入：
- AGENT_NAME=testkaguya
- CONTAINER_NAME=hermes-single-test-runtime
- custom provider 环境变量
- 临时 SOUL.md

执行：
- 在临时 workdir 中 `docker compose -p hermes_single_test_runtime up -d`
- 等待 `/opt/data/.initialized`

预期容器内：
- `/opt/data/profiles/testkaguya/` 存在
- `/opt/data/profiles/testkaguya/.env` 存在
- `/opt/data/profiles/testkaguya/config.yaml` 存在
- `/opt/data/profiles/testkaguya/memories/MEMORY.md` 存在
- `/opt/data/profiles/testkaguya/memories/USER.md` 存在

预期容器外：
- 不影响现有 `hermes` 容器

### 用例 2：render-config.sh 将宿主机配置复制进测试容器 profile
输入：
- 临时 `.env`
- 临时 `.setup-state.env`
- custom provider 配置

执行：
- 在临时 workdir 中运行 `./render-config.sh`

预期容器内：
- `config.rendered.yaml` 被复制到 `/opt/data/profiles/testkaguya/config.rendered.yaml`
- `.env` 被复制到 `/opt/data/profiles/testkaguya/.env`
- 复制后的 `config.rendered.yaml` 中：
  - `provider: custom`
  - `model: gpt-5.4`
  - `api_key: ${HERMES_MODEL_API_KEY}`
  - `base_url: https://api.gaoxin.net.cn/v1`
- `.env` 中：
  - `HERMES_MODEL_API_KEY=...`
  - `CUSTOM_LLM_API_KEY=...`
  - `CUSTOM_LLM_BASE_URL=...`

### 用例 3：custom-init 优先采用预渲染 config.rendered.yaml
执行：
- 先 `render-config.sh`
- 再重建测试容器

预期容器内：
- `config.yaml` 内容与 `config.rendered.yaml` 一致（至少头部关键字段一致）

## 实现策略

新增：
- `tests/test_runtime_isolated.py`

测试方法：
1. Python 测试中创建 `tmp_path/runtime/`
2. 复制所需文件到该目录
3. 写入临时 `.env` / `.setup-state.env` / `SOUL.md`
4. 用 `docker compose -p hermes_single_test_runtime ...` 启动
5. 用 `docker exec hermes-single-test-runtime ...` 验证
6. 测试默认不在 finally 中清理；由 `scripts/cleanup-test-runtime.sh` 统一执行 `down -v`、兜底删容器、兜底删项目卷/网络。

额外保护：
- 每个测试前后记录 `docker ps --format '{{.Names}} {{.Status}}'`
- 断言 `hermes` 在测试前后都存在
- 断言测试容器名不是 `hermes`
