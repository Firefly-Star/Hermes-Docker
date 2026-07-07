# shellcheck shell=bash
# This file is sourced by setup.sh. Do not execute setup flow at top level.

mask_secret() {
    local secret="$1"
    if [ -n "$secret" ]; then
        echo "${secret:0:8}..."
    fi
}

normalize_base_url() {
    local url="$1"
    # 去掉末尾斜杠，避免拼接 /models 时变成 //models
    while [ "${url%/}" != "$url" ]; do
        url="${url%/}"
    done
    echo "$url"
}

fetch_models() {
    local base_url
    base_url="$(normalize_base_url "$1")"
    local api_key="${2:-}"
    "$PYTHON" - "$base_url" "$api_key" <<'PY'
import json
import sys
import urllib.error
import urllib.request

base_url = sys.argv[1].rstrip("/")
api_key = sys.argv[2]
url = f"{base_url}/models"
headers = {"Accept": "application/json"}
if api_key:
    headers["Authorization"] = f"Bearer {api_key}"

try:
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=20) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
except urllib.error.HTTPError as exc:
    body = exc.read().decode("utf-8", "replace")[:500]
    print(f"ERROR: GET {url} returned HTTP {exc.code}: {body}", file=sys.stderr)
    sys.exit(1)
except Exception as exc:
    print(f"ERROR: failed to fetch models from {url}: {exc}", file=sys.stderr)
    sys.exit(1)

data = payload.get("data", payload)
models = []
if isinstance(data, list):
    for item in data:
        if isinstance(item, str):
            models.append(item)
        elif isinstance(item, dict):
            model_id = item.get("id") or item.get("name") or item.get("model")
            if model_id:
                models.append(str(model_id))

# 去重并保持顺序
seen = set()
for model in models:
    if model not in seen:
        seen.add(model)
        print(model)
PY
}

select_model_from_list() {
    local models_text="$1"
    local models=()
    local line
    while IFS= read -r line; do
        [ -n "$line" ] && models+=("$line")
    done <<< "$models_text"

    if [ "${#models[@]}" -eq 0 ]; then
        echo -e "  ${RED}⚠ 没有从 /models 响应中解析到模型 id/name${NC}" >&2
        return 1
    fi

    echo -e "  ${DIM}可用模型:${NC}" >&2
    local i
    for i in "${!models[@]}"; do
        echo "    $((i + 1))) ${models[$i]}" >&2
    done

    while true; do
        read -p "  选择模型编号: " idx
        if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le "${#models[@]}" ]; then
            echo "${models[$((idx - 1))]}"
            return 0
        fi
        echo -e "  ${RED}⚠ 请输入 1-${#models[@]} 之间的编号${NC}" >&2
    done
}

prompt_llm_provider() {
    echo ""
    echo -e "${BOLD}[2] LLM 提供方${NC}"
    echo -e "  ${DIM}1) DeepSeek（默认 base_url: https://api.deepseek.com/v1，模型: deepseek-v4-flash）${NC}"
    echo -e "  ${DIM}2) 自定义 OpenAI-compatible LLM（填写 provider 名称、base url，并从 /models 选择模型）${NC}"

    local cur_provider="${LLM_PROVIDER:-deepseek}"
    local cur_choice=1
    [ "$cur_provider" != "deepseek" ] && cur_choice=2

    while true; do
        read -p "  选择 [1/2] (当前: $cur_choice): " choice
        choice="${choice:-$cur_choice}"
        case "$choice" in
            1)
                LLM_PROVIDER=deepseek
                CUSTOM_LLM_PROVIDER_NAME=""
                LLM_MODEL="deepseek-v4-flash"
                LLM_BASE_URL="https://api.deepseek.com/v1"
                while true; do
                    local cur="${LLM_API_KEY:-${DEEPSEEK_API_KEY:-}}"
                    [ -n "$cur" ] && echo -e "  ${DIM}当前 API Key: $(mask_secret "$cur")${NC}"
                    read -p "  DeepSeek API Key: " val
                    if [ -n "$val" ]; then
                        LLM_API_KEY="$val"
                        DEEPSEEK_API_KEY="$val"
                        break
                    elif [ -n "$cur" ]; then
                        LLM_API_KEY="$cur"
                        DEEPSEEK_API_KEY="$cur"
                        break
                    else
                        echo -e "  ${RED}⚠ 必填${NC}"
                    fi
                done
                echo -e "  ${GREEN}✓ DeepSeek: $LLM_MODEL${NC}"
                break
                ;;
            2)
                while true; do
                    read -p "  提供方名称 (例如: openai-compatible): " val
                    val="${val:-${CUSTOM_LLM_PROVIDER_NAME:-}}"
                    if [ -n "$val" ] && [[ "$val" =~ ^[A-Za-z0-9_.-]+$ ]]; then
                        CUSTOM_LLM_PROVIDER_NAME="$val"
                        LLM_PROVIDER=custom
                        break
                    fi
                    echo -e "  ${RED}⚠ 名称必填，只能包含字母、数字、_、-、.${NC}"
                done
                while true; do
                    read -p "  Base URL (例如: http://127.0.0.1:8000/v1): " val
                    val="${val:-${LLM_BASE_URL:-}}"
                    if [ -n "$val" ]; then
                        LLM_BASE_URL="$(normalize_base_url "$val")"
                        break
                    fi
                    echo -e "  ${RED}⚠ Base URL 必填${NC}"
                done
                local cur_key="${LLM_API_KEY:-${CUSTOM_LLM_API_KEY:-}}"
                [ -n "$cur_key" ] && echo -e "  ${DIM}当前 API Key: $(mask_secret "$cur_key")${NC}"
                read -p "  API Key (如果服务不需要鉴权可留空): " val
                LLM_API_KEY="${val:-$cur_key}"
                CUSTOM_LLM_API_KEY="$LLM_API_KEY"

                echo "  正在请求 ${LLM_BASE_URL}/models ..."
                local models_text
                if ! models_text="$(fetch_models "$LLM_BASE_URL" "$LLM_API_KEY")"; then
                    echo -e "  ${RED}⚠ 获取模型列表失败，请检查 Base URL / API Key${NC}"
                    continue
                fi
                if ! LLM_MODEL="$(select_model_from_list "$models_text")"; then
                    continue
                fi
                echo -e "  ${GREEN}✓ ${CUSTOM_LLM_PROVIDER_NAME} (custom): $LLM_MODEL${NC}"
                break
                ;;
            *)
                echo -e "  ${RED}⚠ 请输入 1 或 2${NC}"
                ;;
        esac
    done
}
