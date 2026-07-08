# Hermes Single-Agent — 单容器 Hermes 代理

## 维护者入口 / 文档索引

如果你是第一次接手这个仓库，建议按这个顺序阅读：

1. `docs/MAINTAINER_OVERVIEW.md`
   - 项目总览：这个项目是做什么的、已经做到哪里、先看哪些文件
2. `docs/CURRENT_STATUS_AND_ROADMAP.md`
   - 当前开发状态：最近修复了什么、还剩哪些明确待办、下一步推荐做什么
3. `docs/MAINTENANCE_RUNBOOK.md`
   - 日常维护手册：常用命令、如何跑测试、改哪类文件时该跑哪层测试
4. `docs/testing-guide.md`
   - 三层测试体系说明：setup.d 模块测试、运行时隔离容器测试、setup.sh 真 E2E
5. `docs/provider-catalog-design.md`
   - 多 provider setup 设计：后续如何把 provider 选择能力做成像 Hermes 一样的 catalog 驱动

如果你只是普通使用者，可以直接继续看下方“快速开始”。

一个极简的 Docker 方案，运行单个 [Hermes agent](https://github.com/NousResearch/hermes-agent)。setup 向导可配置 **DeepSeek V4 Flash** 或自定义 OpenAI-compatible LLM endpoint。

## 快速开始

```bash
# 1. 编辑 SOUL.md 定义你代理的人格

# 2. 运行 setup 向导：填写 API Key、代理名称、SOUL 路径，
#    脚本会自动启动容器并 exec 进去
bash setup.sh
```

进入容器后虚拟环境已自动激活，直接使用：

```
hermes -p <agent_name> chat       # 聊天
hermes -p <agent_name> shell      # 交互式 shell（带工具）
hermes -p <agent_name> run <指令>   # 单条指令
```

## 前提条件

- **一台 Linux 服务器**（或虚拟机），通过 SSH 连接操作 — 所有命令在服务器上执行
- **Docker**（含 `docker compose` 插件）已安装在服务器上
- **OpenSSH 服务端** — 用于 Agent 通过 SSH 回连宿主机执行命令
  ```bash
  sudo apt update && sudo apt install -y openssh-server
  ```
- **LLM API Key** — DeepSeek API Key（[platform.deepseek.com](https://platform.deepseek.com)）或自定义 OpenAI-compatible endpoint 的凭据

## 配置

`setup.sh` 会拆分生成两个 gitignored 文件：

- `.setup-state.env`：普通、非敏感的上次选择，例如 provider、模型名、base URL、SSH 用户、SOUL 路径。
- `.env`：Hermes/container 运行时需要的 secrets，例如 `HERMES_MODEL_API_KEY`、`DEEPSEEK_API_KEY`、`CUSTOM_LLM_API_KEY`、`API_SERVER_KEY`。

Hermes 会在 profile 启动时加载 `/opt/data/profiles/<agent>/.env`。`config.yaml` 中只保留 `api_key: ${HERMES_MODEL_API_KEY}` 引用，由 Hermes 自己在运行时展开，避免把明文 API key 写入 config。

普通配置：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `LLM_PROVIDER` | `deepseek` | Hermes model provider 名称；自定义 endpoint 固定为 `custom` |
| `CUSTOM_LLM_PROVIDER_NAME` | — | 自定义 endpoint 输入的显示名称；不作为 Hermes provider |
| `LLM_MODEL` | `deepseek-v4-flash` | 选择的模型名 |
| `LLM_BASE_URL` | `https://api.deepseek.com/v1` | OpenAI-compatible API base URL |
| `MODEL_CONTEXT_LENGTH` | — | 可选的 `model.context_length` 覆盖；留空则不写入 config，让 Hermes 自动判断 |
| `COMPRESSION_ENABLED` | `true` | 是否启用 Hermes 自动上下文压缩 |
| `COMPRESSION_THRESHOLD` | `0.85` | 自动压缩触发比例；128k 上下文约 109k token 时触发 |
| `AGENT_NAME` | `kaguya` | Hermes profile / 代理名称 |
| `CONTAINER_NAME` | `hermes` | Docker 容器名称；setup 会同步生成 `docker-compose.override.yml` 固定该名称 |
| `SOUL_PATH` | — | SOUL.md 文件路径 |

Secrets：

| 变量 | 说明 |
|---|---|
| `HERMES_MODEL_API_KEY` | `config.yaml` 引用的模型 API key |
| `DEEPSEEK_API_KEY` | DeepSeek API key 副本，兼容 Hermes/provider 检测 |
| `CUSTOM_LLM_API_KEY` | 自定义 endpoint API key 副本 |
| `API_SERVER_KEY` | 内部 API 网关密钥 |

### 上下文压缩与 context length

Hermes 支持通过 `compression.enabled` 开关自动上下文压缩，并通过 `compression.threshold` 设置触发比例。setup 默认启用自动压缩，并把阈值设为 `0.85`，避免 128k 上下文在约 64k token 时过早压缩。

如果你的模型 context length 无法被 Hermes 正确识别，可以在 setup 中填写硬编码值，例如 `131072`。留空时不会写入 `model.context_length`，Hermes 会继续使用自己的探测/判断逻辑。

### 修改代理名称

代理名称同时也是 Hermes 的 **profile 名称**。在 `.setup-state.env` 中修改：

```
AGENT_NAME=my-agent
```

然后重启容器：`docker compose up -d`

### 自定义人格（SOUL.md）

`SOUL.md` 定义代理的人格（系统提示词）。在运行 `setup.sh` 前编辑它，或之后修改后重启：

```
docker compose restart
```

如果想用不同的 SOUL.md 文件，更新 `.setup-state.env` 中的 `SOUL_PATH` 然后重启。

你也可以修改 `templates/MEMORY.md` 和 `templates/USER.md`，让 Agent 在首次启动时自动加载更适合你的记忆和用户画像。

## 文件结构

```
.
├── setup.sh              # 交互式配置向导入口（运行这个）
├── setup.d/              # setup.sh source 的配置模块
│   ├── 00-common.sh      # 公共变量 / helper
│   ├── 30-llm-provider.sh # LLM provider / model 选择
│   └── ...               # 每个设置项独立一个文件
├── custom-init.sh         # 容器启动 hook（cont-init.d，优先于系统 init 执行）
├── docker-compose.yml    # 服务定义
├── .setup-state.env      # 普通非敏感设置（自动生成，已 gitignore）
├── .env                  # Secrets（自动生成，已 gitignore）
├── SOUL.md               # 代理人格定义（编辑这个）
├── templates/
│   ├── config.yaml       # Hermes 配置模板（DeepSeek V4 Flash 预设）
│   ├── global.env        # 全局环境变量模板
│   └── profile.env       # Profile 环境变量模板
├── README.md             # English documentation
├── README-CH.md          # 本文档
└── .gitignore
```

## 工作原理

1. `setup.sh` 收集配置，把普通选项写入 `.setup-state.env`，把 secrets 写入 `.env`，然后 `docker compose up -d` 启动容器
2. 容器启动时运行 `custom-init.sh`（作为 cont-init.d hook）：渲染配置模板、创建 Hermes profile、按需配置 MCP
3. 配置完成后自动 `exec` 进入容器，Hermes 虚拟环境已预先激活
4. 在容器内使用 `hermes -p <agent_name> ...` 命令

## 疑难解答

### SSH 宿主机 IP 检测

`setup.sh` 会自动检测宿主机 IP 并写入 `SSH_HOST`，供容器内 Agent 通过 SSH 回连宿主机执行命令。

检测方式：
- **原生 Linux**：使用 `ip route get 1` 获取默认路由的源 IP
- **WSL**：使用 `hostname -I` 取第一个非环回 IP

**常见问题：**

**WSL 下检测到的 IP 连不上** — WSL `hostname -I` 拿到的是 WSL 虚拟网卡的地址（`172.x.x.x`），不是 Windows 宿主机的地址（`192.168.x.x`）。如果 SSH 连接失败，可以手动修改 `.setup-state.env` 中的 `SSH_HOST` 为 Windows 宿主机的实际 IP。

修改后重启容器：
```bash
docker compose up -d
```

**更换网络环境后 IP 变了** — 例如从办公室 WiFi 切换到家里网络。重新运行 `setup.sh` 会重新检测并更新 `SSH_HOST`；或手动编辑 `.setup-state.env` 后重启容器即可。

## 协议

本项目为配置封装。底层 Hermes agent 由 Nous Research 许可。
