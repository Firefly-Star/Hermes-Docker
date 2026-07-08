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

### 仍在开发中的功能
1. “像 Hermes 一样支持多 provider 选择”
   - 已有 `data/hermes-providers.json`
   - 已有开发者导出脚本 `scripts/export-hermes-providers.py`
   - 但 `setup.d/30-llm-provider.sh` 还没有真正接入 catalog
   - 当前用户可选项仍然基本是：
     - DeepSeek
     - Custom OpenAI-compatible

2. README 文档还没完全跟最新实现对齐
   - 尤其是 provider 选择能力、测试体系、active config 管理权等内容，需要后续同步更新

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

---

## 关键设计决定

### 1. 普通用户不运行 provider 导出脚本
- `scripts/export-hermes-providers.py` 仅供开发者使用
- 开发者从 Hermes 导出 provider 元数据后，提交 `data/hermes-providers.json`
- setup 向导只读取仓库里已提交好的 JSON

### 2. 运行态 config 由本项目接管
当前原则是：
- profile `config.yaml` 由本项目管理
- top-level `/opt/data/config.yaml` 也由本项目管理
- 不再把 `config.rendered.yaml` 当成运行态主文件

### 3. 测试容器默认保留，清理由脚本完成
- `scripts/cleanup-test-runtime.sh`
- `scripts/cleanup-test-setup-e2e.sh`

不在测试用例 finally 中自动删容器，是为了方便人工检查。

---

## 当前最重要的未完成事项

### 多 Provider Setup
目标：
- 像 Hermes 一样支持尽可能多的 provider
- 但用户不需要进入容器或自己导出 provider 列表

当前实现状态：
- `data/hermes-providers.json` 已存在
- catalog 设计文档已写：`docs/provider-catalog-design.md`
- RED 测试已经开始写，且已经暴露出当前实现仍然只有 1/2 两个 provider 选项

下一步应做：
1. 先把 provider catalog RED 测试修成“纯净 RED”
2. 改 `setup.d/30-llm-provider.sh` 读取 JSON
3. 补写 `write_env` 的 provider-specific env 测试
4. 跑绿后再更新 README

---

## 当前测试状态
详见：
- `docs/testing-guide.md`

截至目前：
- setup.d 模块/函数测试：30 passed
- 运行时隔离容器测试：3 passed
- setup.sh 真 E2E：1 passed

说明：
- 当前主路径已经有很强的测试支撑
- 但“多 provider 目录”这条新功能还没合入主线

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

### 如果你改了 provider 选择能力
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
如果你准备做多 provider，接着看 `docs/provider-catalog-design.md`。
