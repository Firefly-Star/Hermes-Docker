# 多 Provider Setup 设计说明

目标：让 `setup.sh` 的 LLM provider 选择能力尽量贴近 Hermes 本体，但不要求用户自己进入容器或运行导出脚本。用户只使用仓库内已经提交好的 `data/hermes-providers.json`。

## 约束与原则

1. `scripts/export-hermes-providers.py` 只作为开发者维护工具。
   - 由开发者在更新 Hermes 版本或 provider catalog 时运行。
   - 产物 `data/hermes-providers.json` 提交到 git。
   - 普通用户不需要运行这个脚本，也不需要进入容器导数据。

2. setup 向导只读取仓库里的 `data/hermes-providers.json`。
   - 不动态 import Hermes Python 源码。
   - 不要求本地已有运行中的 Hermes 容器。

3. 只展示 `setup_supported=true` 的 provider。
   - 过滤掉 OAuth / external_process / ACP 等不适合当前 setup 向导的 provider。

4. provider 选择后，模型展示优先使用 JSON 中已记录的模型清单。
   - 若 provider 的 `models` 非空，则优先本地展示模型列表。
   - 若 provider 的 `models` 为空，且用户提供了 base URL，则回退为请求 `/models`。
   - `custom` 特殊：继续使用 `/models` 请求，因为它本质是未知 OpenAI-compatible endpoint。

5. API key / base URL 写入逻辑由 provider 元数据驱动。
   - `api_key_env_vars[0]` 作为当前 provider 的主 key env
   - `base_url_env_var` 作为当前 provider 的 base URL env
   - 同时仍然统一写 `HERMES_MODEL_API_KEY`

## 目标用户体验

### 第一步：显示可选 provider 列表
从 `data/hermes-providers.json` 中筛出：
- `setup_supported=true`

显示格式建议：
- 序号
- label
- slug
- description
- 默认 base URL（如有）

例如：
1) DeepSeek [deepseek]
2) OpenRouter [openrouter]
3) OpenAI API [openai-api]
4) Anthropic [anthropic]
5) Google AI Studio [gemini]
...
N) Custom endpoint [custom]

### 第二步：根据 provider 决定需要输入什么

#### A. 普通 API provider（如 deepseek/openai-api/openrouter/huggingface 等）
需要：
- API key（必填，取 provider JSON 的 `api_key_env_vars[0]`）
- base URL（默认用 `default_base_url`，允许回车接受默认）
- 模型选择

模型选择策略：
1. 如果 JSON 里 `models` 非空：
   - 直接显示模型列表让用户选
   - 不强制请求网络
2. 如果 JSON 里 `models` 为空：
   - 若 base URL 已知，则尝试请求 `/models`
   - 请求失败则允许用户手动输入模型名

#### B. custom provider
需要：
- provider 显示名称
- base URL（必填）
- API key（可空）
- `/models` 请求返回模型列表后选择
- 若 `/models` 失败，则允许用户手动输入模型名

## 配置写入目标

### .setup-state.env（普通配置）
应写：
- `LLM_PROVIDER=<slug>`（custom 仍写 `custom`）
- `CUSTOM_LLM_PROVIDER_NAME=<用户输入，仅 custom 用>`
- `LLM_PROVIDER_API_KEY_ENV=<provider 主 key env>`
- `LLM_PROVIDER_BASE_URL_ENV=<provider base url env>`
- `LLM_MODEL=<选中的模型>`
- `LLM_BASE_URL=<选定 base url>`

### .env（敏感配置）
统一写：
- `HERMES_MODEL_API_KEY=<实际 key>`
- provider-specific key env（例如 `OPENAI_API_KEY=...` / `OPENROUTER_API_KEY=...`）
- provider-specific base url env（例如 `OPENAI_BASE_URL=...` / `OPENROUTER_BASE_URL=...`，若有）
- 仍保留现有通用字段：`API_SERVER_KEY` / `SOUL_PATH` 等

## 代码改动建议

主要修改：
- `setup.d/30-llm-provider.sh`
- `tests/test_30_llm_provider.py`
- `tests/test_100_env.py`
- 可选补充：`README.md` / `README-CH.md`

### setup.d/30-llm-provider.sh 里建议新增/重构的函数
1. `load_provider_catalog()`
   - 读取 `data/hermes-providers.json`
   - 输出可用于 shell 消费的精简 JSON

2. `list_setup_supported_providers()`
   - 返回 provider 列表（序号、slug、label）

3. `select_provider_from_catalog()`
   - 让用户选择 provider

4. `prompt_provider_base_url()`
   - 默认值来自 `default_base_url`

5. `prompt_provider_api_key()`
   - 使用 provider 的主 `api_key_env_var`

6. `select_model_from_catalog_or_api()`
   - 优先本地 models
   - 否则请求 `/models`
   - 再否则手输

7. `prompt_llm_provider()`
   - 作为统一入口，组合上述流程

## 测试策略

### RED 需要新增/调整的测试
1. provider catalog 加载成功
2. 只列出 `setup_supported=true` 的 provider
3. 选择 `openai-api` 时：
   - provider/base_url/model/api_key 写对
   - env var 名写成 `OPENAI_API_KEY` / `OPENAI_BASE_URL`
4. 选择 `openrouter` 时：
   - base_url 默认值正确
   - 模型从 JSON 本地列表中选择
5. `custom` 仍走 `/models` 请求路径
6. `/models` 失败时允许手输模型名

### GREEN 成功标准
- 现有 deepseek/custom 测试保留通过
- 新增 openai/openrouter/catlog 测试通过
- `tests/test_setup_e2e.py` 不被回归破坏

## 用户层最终效果
普通用户使用时只需要：
- 运行 `bash setup.sh`
- 从已有 provider 列表里选
- 选模型
- 填 key

他们不需要：
- 进入容器
- 运行 `export-hermes-providers.py`
- 理解 Hermes 内部 provider registry

这部分工作由开发者通过更新 `data/hermes-providers.json` 来维护。
