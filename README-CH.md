# Hermes Single-Agent — 单容器 Hermes 代理

一个极简的 Docker 方案，运行单个 [Hermes agent](https://github.com/NousResearch/hermes-agent)，后端使用 **DeepSeek V4 Flash**。只需 Docker 环境和 DeepSeek API Key。

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
- **DeepSeek API Key** — 从 [platform.deepseek.com](https://platform.deepseek.com) 获取

## 配置

所有配置保存在 `.env` 中（`setup.sh` 自动生成）：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `DEEPSEEK_API_KEY` | — | DeepSeek API 密钥（必填） |
| `AGENT_NAME` | `kaguya` | Hermes profile / 代理名称 |
| `SOUL_PATH` | — | SOUL.md 文件路径 |
| `API_SERVER_KEY` | 自动生成 | 内部 API 网关密钥 |
| `PORT` | `8642` | API 服务端口 |

### 修改代理名称

代理名称同时也是 Hermes 的 **profile 名称**。在 `.env` 中修改：

```
AGENT_NAME=my-agent
```

然后重启容器：`docker compose up -d`

### 自定义人格（SOUL.md）

`SOUL.md` 定义代理的人格（系统提示词）。在运行 `setup.sh` 前编辑它，或之后修改后重启：

```
docker compose restart
```

如果想用不同的 SOUL.md 文件，更新 `.env` 中的 `SOUL_PATH` 然后重启。

## 文件结构

```
.
├── setup.sh              # 交互式配置向导（运行这个）
├── custom-init.sh         # 容器启动 hook（cont-init.d，优先于系统 init 执行）
├── docker-compose.yml    # 服务定义
├── .env                  # 配置（自动生成，已 gitignore）
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

1. `setup.sh` 收集配置，写入 `.env`，然后 `docker compose up -d` 启动容器
2. 容器启动时运行 `custom-init.sh`（作为 cont-init.d hook）：渲染配置模板、创建 Hermes profile、按需配置 MCP
3. 配置完成后自动 `exec` 进入容器，Hermes 虚拟环境已预先激活
4. 在容器内使用 `hermes -p <agent_name> ...` 命令

## 协议

本项目为配置封装。底层 Hermes agent 由 Nous Research 许可。
