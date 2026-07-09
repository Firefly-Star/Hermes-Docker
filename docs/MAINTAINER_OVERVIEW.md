# Hermes Single-Agent 维护者总览

这是一份给“第一次接手这个仓库的人”看的入口文档。读完它，你应该能快速知道：
- 这个项目是干什么的
- 现在已经做到哪里了
- 哪些功能已经稳定，哪些还在开发中
- 代码和文档应该先看哪些
- 日常维护时该从哪里入手

---

## 一句话概述

这是一个“单容器 Hermes Agent 部署包装器”。

它的目标不是开发 Hermes 本体，而是把：
- Hermes profile 初始化
- Docker 容器部署
- SSH 回连宿主机
- SOUL / MEMORY / USER 模板注入
- 可选 Playwright MCP 接入

这些原本需要手工完成的步骤，收敛成：
- 一个交互式 `setup.sh`
- 一套模板和启动 hook
- 一组可验证的测试

---

## 当前项目状态（2026-07 当前工作树）

### 已稳定的主线
1. `setup.sh` 基础配置链已打通
   - 能写 `.setup-state.env`
   - 能写 `.env`
   - 能起容器

2. 运行态 active config 管理已收口
   - 当前项目已经接管：
     - profile `config.yaml`
     - top-level `/opt/data/config.yaml`
   - `config.rendered.yaml` 不再作为运行态长期保留

3. 真正的 `setup.sh` E2E 测试已跑通
   - 会真实执行 `bash setup.sh`
   - 会真实起测试容器
   - 不影响当前主用 `hermes` 容器

4. 三层测试体系已建立
   - setup.d 模块/函数测试
   - 运行时隔离容器集成测试
   - setup.sh 真 E2E

5. 多 provider setup 已接入主线
   - 已有 `data/hermes-providers.json`
   - `setup.d/30-llm-provider.sh` 已真正接入 catalog
   - provider-specific env 写入已有测试覆盖
   - setup E2E 已按新的 provider 顺序适配

### 当前仍需要持续维护的部分
1. provider catalog 本身的更新流程
   - catalog 现在已接入主线
   - 但开发者仍需要维护 `data/hermes-providers.json`
   - 需要补更明确的维护文档

2. README 文档同步
   - README / README-CH 已补到当前实现
   - 但 provider list、测试入口、交互细节今后仍然容易继续过时

---

## 先看哪里

### 1. 运行入口
- `setup.sh`
- `setup.d/*.sh`

这是整个向导的主入口和模块拆分。

### 2. 运行时配置链
- `render-config.sh`
- `custom-init.sh`
- `docker-compose.yml`
- `setup.d/110-container.sh`

如果你要理解“为什么配置会进容器、谁负责 active config、profile 是怎么 bootstrap 的”，重点看这几个。

### 3. 模板
- `templates/config.yaml`
- `templates/global.env`
- `templates/profile.env`
- `templates/MEMORY.md`
- `templates/USER.md`

### 4. provider catalog 相关
- `data/hermes-providers.json`
- `scripts/export-hermes-providers.py`
- `setup.d/30-llm-provider.sh`
- `docs/provider-catalog-design.md`

### 5. 测试入口
- `docs/testing-guide.md`
- `tests/test_runtime_isolated.py`
- `tests/test_setup_e2e.py`
- `tests/test_30_llm_provider.py`
- `tests/test_100_env.py`

---

## 关键设计决定

### 1. 普通用户不运行 provider 导出脚本
- `scripts/export-hermes-providers.py` 仅供开发者使用
- 开发者从 Hermes 导出 provider 元数据后，提交 `data/hermes-providers.json`
- setup 向导只读取仓库里已提交好的 JSON

### 2. provider 选择已改为 catalog 驱动
当前原则是：
- setup 不再只支持 DeepSeek / custom 两个硬编码分支
- provider-specific API key / base URL env 由 catalog 决定
- 非 custom provider 优先使用 catalog 内置 models
- custom provider 继续用 `/models` 探测并支持手工 fallback

### 3. 运行态 config 由本项目接管
当前原则是：
- profile `config.yaml` 由本项目管理
- top-level `/opt/data/config.yaml` 也由本项目管理
- 不再把 `config.rendered.yaml` 当成运行态主文件

### 4. 测试容器默认保留，清理由脚本完成
- `scripts/cleanup-test-runtime.sh`
- `scripts/cleanup-test-setup-e2e.sh`

不在测试用例 finally 中自动删容器，是为了方便人工检查。

---

## 当前最重要的未完成事项

### provider catalog 维护流程文档化
目标：
- 让开发者明确何时重新导出 `hermes-providers.json`
- 让更新 catalog 后的验证动作标准化

下一步应做：
1. 补 catalog 维护文档
2. 记录筛选 `setup_supported=true` 的准则
3. 固化 catalog 更新后的测试命令

---

## 当前测试状态
详见：
- `docs/testing-guide.md`

截至当前工作树：
- setup.d 模块/函数测试：主线已覆盖
- 运行时隔离容器测试：3 passed
- setup.sh 真 E2E：1 passed
- 多 provider 相关回归：12 passed

多 provider 相关回归包含：
- `tests/test_30_llm_provider.py`
- `tests/test_100_env.py`
- `tests/test_setup_e2e.py`
- `tests/test_runtime_isolated.py`

---

## 日常维护建议

### 如果你改了 setup.d 小逻辑
先跑：
- L1 模块测试

### 如果你改了 config 同步/容器初始化
再跑：
- `tests/test_runtime_isolated.py`

### 如果你改了 setup.sh / start_container / profile bootstrap
必须再跑：
- `tests/test_setup_e2e.py`

### 如果你改了 provider 选择能力 / provider catalog
必须再跑：
- `tests/test_30_llm_provider.py`
- `tests/test_100_env.py`
- `tests/test_setup_e2e.py`

---

## 不要踩的坑

1. 不要在当前工作目录直接做危险的真实 `docker compose down`
   - 尤其是在调试 `setup.d/110-container.sh` 时

2. 不要把 `config.rendered.yaml` 再重新当成运行态主配置
   - 这个坑已经修过一次

3. 不要让普通用户依赖 `export-hermes-providers.py`
   - 这一步必须是开发者维护动作

4. 改 `setup.sh` 行为时，不要只跑函数测试
   - 一定要跑真 E2E

5. 不要重新引入新的硬编码 provider 分支
   - 现在 provider 选择已经是 catalog 驱动，回退会制造实现与 catalog 分叉

---

## 相关文档索引

基础说明：
- `README.md`
- `README-CH.md`

测试说明：
- `docs/testing-guide.md`
- `docs/test-plan-setupd.md`
- `docs/test-plan-runtime-isolated.md`
- `docs/test-plan-setup-e2e.md`

provider 方案：
- `docs/provider-catalog-design.md`

如果你只看一份文档开始维护，先看这份总览；
如果你准备改测试，接着看 `docs/testing-guide.md`；
如果你准备改 provider 选择或 catalog，接着看 `docs/provider-catalog-design.md`。
