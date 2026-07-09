# 当前开发状态与下一步路线

本文档用于记录：
- 当前仓库已经完成到哪里
- 最近几轮修复解决了什么问题
- 目前还剩哪些明确待办
- 下一步推荐的开发顺序

适合在每次新开维护会话时先读一遍。

---

## 当前开发完成度

### A. 已完成

#### 1. setup.sh 主路径基本可用
已经具备：
- 交互输入
- 写 `.setup-state.env`
- 写 `.env`
- 起容器
- 初始化 profile

并且已经通过：
- 真 `setup.sh` E2E 测试

#### 2. active config 管理已收口
之前问题：
- `render-config.sh` 只把正确配置写到 `config.rendered.yaml`
- 真正生效的 `config.yaml` 仍然是旧的 deepseek

现在结果：
- `render-config.sh` 直接接管 active config
- 顶层 `/opt/data/config.yaml` 和 profile `config.yaml` 都由本项目管理
- 不再长期保留 `config.rendered.yaml`

#### 3. setup.sh E2E profile bootstrap 已打通
之前问题：
- `AGENT_NAME` 没正确参与 compose 环境展开
- 容器内部仍然只生成默认 profile `kaguya`
- 即使生成目标 profile，也会 clone 到 deepseek 旧配置

现在结果：
- compose 会显式读取 `.setup-state.env` / `.env`
- setup 启动后会显式 bootstrap 目标 profile
- 宿主机生成的 active config / env 会直接分发给目标 profile

#### 4. 三层测试体系已建立
- L1: setup.d 模块/函数测试
- L2: 运行时隔离容器测试
- L3: setup.sh 真 E2E

并且均已通过当前基线。

#### 5. 多 Provider Setup 主线已完成
当前结果：
- `setup.d/30-llm-provider.sh` 已接入 `data/hermes-providers.json`
- setup 向导会读取 catalog 并只展示 `setup_supported=true` 的 provider
- provider-specific API key / base URL env 名称已由 catalog 驱动
- 非 custom provider 优先使用 catalog 内置模型列表
- custom endpoint 继续走 `/models`，失败时允许手动输入模型名

已通过的相关测试：
- `tests/test_30_llm_provider.py`
- `tests/test_100_env.py`
- `tests/test_setup_e2e.py`
- `tests/test_runtime_isolated.py`

最近一次相关回归为：
- `12 passed`

---

### B. 已发现但未完成

#### README / README-CH 文档同步
之前 README 仍偏旧，尤其是：
- provider 选择能力
- 三层测试体系
- active config 管理方式
- cleanup / 回归测试入口

当前状态：
- README / README-CH 已补齐到 catalog-driven multi-provider setup
- 但后续如果 provider catalog 范围继续变化，文档仍需继续维护

#### provider catalog 维护流程文档化
虽然已有设计文档，但后续还可以补一份更开发者导向的：
- 什么时候要重新导出 `hermes-providers.json`
- 导出后如何验证差异
- 哪些 provider 应该过滤掉

---

## 最近几轮修复解决了什么

### 修复 1：config 回退与运行态配置分裂
修复文件：
- `render-config.sh`
- `custom-init.sh`
- `tests/test_runtime_isolated.py`

结果：
- active config 由项目接管
- top-level config 与 profile active config 一致
- runtime isolated 测试通过

### 修复 2：setup.sh E2E profile 名不生效
修复文件：
- `setup.d/110-container.sh`
- `tests/test_setup_e2e.py`

结果：
- `docker compose` 显式使用 `.setup-state.env` / `.env`
- 目标 profile `kaguya-e2e` 能真实创建

### 修复 3：setup.sh E2E profile 创建后仍是 deepseek 旧配置
修复文件：
- `setup.d/110-container.sh`

结果：
- 宿主机生成的 `config.active.yaml` / `.env` 会直接分发给目标 profile
- setup E2E 通过

### 修复 4：忽略 active config 运行产物
修复文件：
- `.gitignore`

结果：
- `config.active.yaml` 不会再被误追踪

### 修复 5：多 provider setup 接入 catalog
修复文件：
- `setup.d/30-llm-provider.sh`
- `tests/test_30_llm_provider.py`
- `tests/test_100_env.py`
- `tests/test_setup_e2e.py`
- `README.md`
- `README-CH.md`

结果：
- provider 选择不再是 DeepSeek / custom 两分支硬编码
- setup 可消费仓库内已提交的 provider catalog
- provider-specific env 写入受测试保护
- E2E 已按新的 catalog 顺序修正

---

## 当前最重要待办（按优先级）

### P1. provider catalog 维护流程文档化
目标：
- 让开发者知道何时需要重新导出 `hermes-providers.json`
- 让 catalog 更新后的验证流程标准化

建议顺序：
1. 补写 catalog 维护文档
2. 记录筛选 `setup_supported=true` 的准则
3. 记录更新后应跑的测试集

### P2. README / README-CH 持续同步
当前 README 已更新到当前实现，但它们以后仍然是高频过时点。
每次改动以下内容后都应同步：
- provider 选择能力
- 测试入口
- active config 管理方式
- setup 交互流程

### P3. 扩大回归测试覆盖面
当前多 provider 相关链路已验证通过，但后续还可以考虑：
- 把更多 provider 类型补进测试样例
- 为 catalog 顺序变化增加更稳健的测试辅助
- 覆盖更多 `/models` fallback 边界情况

---

## 下一步推荐开发顺序

### 路线 1（推荐）
1. 补 catalog 维护文档
2. 按需扩充 provider 测试样例
3. 继续做文档同步

### 路线 2（测试优先）
1. 先补更多 provider 回归测试
2. 再补 catalog 维护文档

不建议路线：
- 在 provider catalog 已接入后，又回退到新的硬编码 provider 分支
因为这会重新制造 catalog 和实现分叉的问题。

---

## 当前维护者应特别注意

1. setup E2E 是高价值测试
如果改了：
- `setup.sh`
- `setup.d/110-container.sh`
- `render-config.sh`
- `custom-init.sh`
一定要跑 `tests/test_setup_e2e.py`

2. provider 选择能力现在是 catalog 驱动
如果改了：
- `data/hermes-providers.json`
- `setup.d/30-llm-provider.sh`
一定要跑：
- `tests/test_30_llm_provider.py`
- `tests/test_100_env.py`
- `tests/test_setup_e2e.py`

3. 运行态 config 的所有权已经是项目级规则
不要再引入新的“rendered 备用配置长期保留”逻辑。

4. 当前主容器 `hermes` 是生产/工作态
任何真实容器测试都必须：
- 用独立容器名
- 用独立 compose project
- 提供手动 cleanup 脚本

---

## 快速判断当前仓库是不是健康

至少执行：
```bash
cd ~/task5/hermes-single
python3 -m pytest tests/test_runtime_isolated.py -q
python3 -m pytest tests/test_setup_e2e.py -q
```

如果这两层都绿，说明：
- 运行态配置链正常
- setup 主路径正常

如果要验证多 provider 主线，再执行：
```bash
python3 -m pytest \
  tests/test_30_llm_provider.py \
  tests/test_100_env.py \
  tests/test_setup_e2e.py \
  tests/test_runtime_isolated.py -q
```

如果这一组也绿，说明多 provider setup 主线基本健康。
