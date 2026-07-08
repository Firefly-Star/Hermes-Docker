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

---

### B. 已发现但未完成

#### 多 Provider Setup
当前状态：
- provider catalog 数据已存在：`data/hermes-providers.json`
- 开发者导出脚本已存在：`scripts/export-hermes-providers.py`
- 设计文档已存在：`docs/provider-catalog-design.md`
- RED 测试已开始写

但当前实现仍然只有：
- DeepSeek
- Custom OpenAI-compatible

setup 向导尚未真正读取 `hermes-providers.json`。

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

---

## 当前最重要待办（按优先级）

### P1. 完成多 Provider Setup
目标：
- 像 Hermes 一样支持多家 provider
- 但普通用户不需要自己导出 provider catalog

建议顺序：
1. 先把 provider catalog RED 测试整理干净
2. 改 `setup.d/30-llm-provider.sh`
3. 改 `tests/test_100_env.py`
4. 重新跑：
   - `tests/test_30_llm_provider.py`
   - `tests/test_100_env.py`
   - `tests/test_setup_e2e.py`

### P2. README / README-CH 更新
目前 README 仍偏旧，尤其是：
- provider 选择能力
- 三层测试体系
- active config 管理方式
- cleanup 脚本

### P3. provider catalog 维护流程文档化
虽然已有设计文档，但后续还可以补一份更开发者导向的：
- 什么时候要重新导出 `hermes-providers.json`
- 导出后如何验证差异
- 哪些 provider 应该过滤掉

---

## 下一步推荐开发顺序

### 路线 1（推荐）
1. 完成多 provider setup
2. 测试通过
3. 更新 README
4. 提交

### 路线 2（文档优先）
1. 先更新 README / README-CH
2. 再做多 provider

不建议路线：
- 继续加新功能而不先把多 provider 做完
因为仓库里已经有半完成的 provider catalog 资产，继续拖会越来越混乱。

---

## 当前维护者应特别注意

1. setup E2E 是高价值测试
如果改了：
- `setup.sh`
- `setup.d/110-container.sh`
- `render-config.sh`
- `custom-init.sh`
一定要跑 `tests/test_setup_e2e.py`

2. 运行态 config 的所有权已经是项目级规则
不要再引入新的“rendered 备用配置长期保留”逻辑。

3. provider catalog 的维护边界已经明确
- 开发者更新 JSON
- 用户只消费 JSON

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

如果再加上 L1 全绿，说明当前仓库主线基本健康。
