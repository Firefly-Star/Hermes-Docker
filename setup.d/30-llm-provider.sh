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

provider_catalog_path() {
    printf '%s\n' "$SCRIPT_DIR/data/hermes-providers.json"
}

provider_field() {
    local slug="$1"
    local field="$2"
    local catalog
    catalog="$(provider_catalog_path)"
    "$PYTHON" - "$catalog" "$slug" "$field" <<'PY'
import json
import sys
from pathlib import Path

catalog, slug, field = sys.argv[1:4]
data = json.loads(Path(catalog).read_text(encoding='utf-8'))
for provider in data.get('providers', []):
    if provider.get('slug') == slug:
        value = provider.get(field, "")
        if isinstance(value, (list, dict)):
            print(json.dumps(value, ensure_ascii=False))
        elif value is None:
            print("")
        else:
            print(value)
        break
else:
    sys.exit(1)
PY
}

list_setup_supported_providers() {
    local catalog
    catalog="$(provider_catalog_path)"
    "$PYTHON" - "$catalog" <<'PY'
import json
import sys
from pathlib import Path

catalog = Path(sys.argv[1])
data = json.loads(catalog.read_text(encoding='utf-8'))
providers = [p for p in data.get('providers', []) if p.get('setup_supported')]
for provider in providers:
    print(json.dumps(provider, ensure_ascii=False))
PY
}

provider_json_field() {
    local provider_json="$1"
    local field="$2"
    local tmp
    tmp="$(mktemp)"
    printf '%s' "$provider_json" > "$tmp"
    local rc=0
    local value
    value="$($PYTHON - "$tmp" "$field" <<'PY'
import json
import sys
from pathlib import Path

path, field = sys.argv[1:3]
data = json.loads(Path(path).read_text(encoding='utf-8'))
value = data.get(field, '')
if isinstance(value, (list, dict)):
    print(json.dumps(value, ensure_ascii=False))
elif value is None:
    print('')
else:
    print(value)
PY
)" || rc=$?
    rm -f "$tmp"
    [ $rc -eq 0 ] || return $rc
    printf '%s\n' "$value"
}

select_provider_from_catalog() {
    local catalog
    catalog="$(provider_catalog_path)"
    local rows=""
    if ! rows="$($PYTHON - "$catalog" <<'PY'
import json
import sys
from pathlib import Path

catalog = Path(sys.argv[1])
data = json.loads(catalog.read_text(encoding='utf-8'))
providers = [p for p in data.get('providers', []) if p.get('setup_supported')]
for idx, provider in enumerate(providers, 1):
    print("\t".join([
        str(idx),
        provider.get('slug', ''),
        provider.get('label', ''),
        provider.get('description', ''),
        provider.get('default_base_url', ''),
    ]))
PY
)"; then
        echo -e "  ${RED}⚠ 读取 provider catalog 失败${NC}" >&2
        return 1
    fi

    local provider_lines=()
    local line
    while IFS= read -r line; do
        [ -n "$line" ] && provider_lines+=("$line")
    done <<< "$rows"

    if [ "${#provider_lines[@]}" -eq 0 ]; then
        echo -e "  ${RED}⚠ provider catalog 为空${NC}" >&2
        return 1
    fi

    local current_slug="${LLM_PROVIDER:-deepseek}"
    local cur_choice=1
    local i idx slug label desc base
    for i in "${!provider_lines[@]}"; do
        IFS=$'\t' read -r idx slug label desc base <<< "${provider_lines[$i]}"
        if [ "$slug" = "$current_slug" ]; then
            cur_choice=$idx
        fi
    done

    echo -e "${BOLD}[3] LLM 提供方${NC}" >&2
    for i in "${!provider_lines[@]}"; do
        IFS=$'\t' read -r idx slug label desc base <<< "${provider_lines[$i]}"
        echo -e "  ${DIM}${idx}) ${label} [${slug}]${NC}" >&2
        [ -n "$desc" ] && echo -e "     ${DIM}${desc}${NC}" >&2
        [ -n "$base" ] && echo -e "     ${DIM}默认 base_url: ${base}${NC}" >&2
    done

    while true; do
        read -p "  选择 provider 编号 [1-${#provider_lines[@]}] (当前: $cur_choice): " choice
        choice="${choice:-$cur_choice}"
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#provider_lines[@]}" ]; then
            IFS=$'\t' read -r idx slug label desc base <<< "${provider_lines[$((choice - 1))]}"
            printf '%s\n' "$slug"
            return 0
        fi
        echo -e "  ${RED}⚠ 请输入 1-${#provider_lines[@]} 之间的编号${NC}" >&2
    done
}

extract_catalog_models() {
    local slug="$1"
    local catalog
    catalog="$(provider_catalog_path)"
    "$PYTHON" - "$catalog" "$slug" <<'PY'
import json
import sys
from pathlib import Path

catalog, slug = sys.argv[1:3]
data = json.loads(Path(catalog).read_text(encoding='utf-8'))
for provider in data.get('providers', []):
    if provider.get('slug') != slug:
        continue
    models = provider.get('models') or []
    seen = set()
    for item in models:
        if isinstance(item, str):
            model = item
        elif isinstance(item, list) and item:
            model = item[0]
        elif isinstance(item, dict):
            model = item.get('id') or item.get('name') or item.get('model')
        else:
            model = None
        if model and model not in seen:
            seen.add(model)
            print(model)
    break
PY
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
    local default_idx="${2:-1}"
    local models=()
    local line
    while IFS= read -r line; do
        [ -n "$line" ] && models+=("$line")
    done <<< "$models_text"

    if [ "${#models[@]}" -eq 0 ]; then
        echo -e "  ${RED}⚠ 没有可选模型${NC}" >&2
        return 1
    fi

    if ! [[ "$default_idx" =~ ^[0-9]+$ ]] || [ "$default_idx" -lt 1 ] || [ "$default_idx" -gt "${#models[@]}" ]; then
        default_idx=1
    fi

    echo -e "  ${DIM}可用模型:${NC}" >&2
    local i
    for i in "${!models[@]}"; do
        echo "    $((i + 1))) ${models[$i]}" >&2
    done

    while true; do
        read -p "  选择模型编号 [${default_idx}]: " idx
        idx="${idx:-$default_idx}"
        if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le "${#models[@]}" ]; then
            echo "${models[$((idx - 1))]}"
            return 0
        fi
        echo -e "  ${RED}⚠ 请输入 1-${#models[@]} 之间的编号${NC}" >&2
    done
}

prompt_provider_api_key() {
    local label="$1"
    local env_name="$2"
    local current="${LLM_API_KEY:-}"
    if [ -z "$current" ] && [ -n "$env_name" ]; then
        current="$(eval "printf '%s' \"\${$env_name:-}\"")"
    fi
    [ -n "$current" ] && echo -e "  ${DIM}当前 API Key: $(mask_secret "$current")${NC}" >&2
    while true; do
        read -p "  ${label} API Key: " val
        if [ -n "$val" ]; then
            LLM_API_KEY="$val"
            return 0
        elif [ -n "$current" ]; then
            LLM_API_KEY="$current"
            return 0
        else
            echo -e "  ${RED}⚠ 必填${NC}" >&2
        fi
    done
}

prompt_provider_base_url() {
    local label="$1"
    local default_base_url="$2"
    local base_env="$3"
    local current="${LLM_BASE_URL:-}"
    if [ -z "$current" ] && [ -n "$base_env" ]; then
        current="$(eval "printf '%s' \"\${$base_env:-}\"")"
    fi
    current="${current:-$default_base_url}"
    while true; do
        if [ -n "$current" ]; then
            read -p "  ${label} Base URL [${current}]: " val
            val="${val:-$current}"
        else
            read -p "  ${label} Base URL: " val
        fi
        if [ -n "$val" ]; then
            local normalized
            normalized="$(normalize_base_url "$val")"
            if [[ "$normalized" =~ ^https?:// ]] || [[ "$normalized" =~ ^acp:// ]]; then
                LLM_BASE_URL="$normalized"
                return 0
            fi
            echo -e "  ${RED}⚠ Base URL 格式无效，请输入 http(s):// 或 acp:// 开头的地址${NC}" >&2
            continue
        fi
        echo -e "  ${RED}⚠ Base URL 必填${NC}" >&2
    done
}

prompt_manual_model() {
    local default_model="${1:-}"
    while true; do
        if [ -n "$default_model" ]; then
            read -p "  手动输入模型名 [${default_model}]: " val
            val="${val:-$default_model}"
        else
            read -p "  手动输入模型名: " val
        fi
        if [ -n "$val" ]; then
            printf '%s\n' "$val"
            return 0
        fi
        echo -e "  ${RED}⚠ 模型名必填${NC}" >&2
    done
}

select_model_from_catalog_or_api() {
    local slug="$1"
    local base_url="$2"
    local api_key="$3"
    local models_text=""
    local default_model="${LLM_MODEL:-}"
    local default_idx=1

    if [ "$slug" != "custom" ]; then
        models_text="$(extract_catalog_models "$slug")"
        if [ -n "$models_text" ]; then
            if [ -n "$default_model" ]; then
                local i=1
                local line
                while IFS= read -r line; do
                    if [ "$line" = "$default_model" ]; then
                        default_idx=$i
                        break
                    fi
                    i=$((i + 1))
                done <<< "$models_text"
            fi
            select_model_from_list "$models_text" "$default_idx"
            return $?
        fi
    fi

    if [ -n "$base_url" ]; then
        echo "  正在请求 ${base_url}/models ..." >&2
        if models_text="$(fetch_models "$base_url" "$api_key")"; then
            if [ -n "$models_text" ]; then
                if [ -n "$default_model" ]; then
                    local i=1
                    local line
                    while IFS= read -r line; do
                        if [ "$line" = "$default_model" ]; then
                            default_idx=$i
                            break
                        fi
                        i=$((i + 1))
                    done <<< "$models_text"
                fi
                select_model_from_list "$models_text" "$default_idx"
                return $?
            fi
        else
            echo -e "  ${YELLOW}⚠ 获取模型列表失败，将改为手动输入模型名${NC}" >&2
        fi
    fi

    prompt_manual_model "$default_model"
}

set_provider_specific_key_var() {
    local env_name="$1"
    local value="$2"
    case "$env_name" in
        DEEPSEEK_API_KEY) DEEPSEEK_API_KEY="$value" ;;
        CUSTOM_LLM_API_KEY) CUSTOM_LLM_API_KEY="$value" ;;
        OPENAI_API_KEY) OPENAI_API_KEY="$value" ;;
        OPENROUTER_API_KEY) OPENROUTER_API_KEY="$value" ;;
        ANTHROPIC_API_KEY) ANTHROPIC_API_KEY="$value" ;;
        GOOGLE_API_KEY) GOOGLE_API_KEY="$value" ;;
        GEMINI_API_KEY) GEMINI_API_KEY="$value" ;;
    esac
}

prompt_llm_provider() {
    echo ""

    local provider_slug
    if ! provider_slug="$(select_provider_from_catalog)"; then
        return 1
    fi

    if [ "$provider_slug" = "custom" ]; then
        while true; do
            read -p "  提供方名称 (例如: openai-compatible): " val
            val="${val:-${CUSTOM_LLM_PROVIDER_NAME:-}}"
            if [ -n "$val" ] && [[ "$val" =~ ^[A-Za-z0-9_.-]+$ ]]; then
                CUSTOM_LLM_PROVIDER_NAME="$val"
                break
            fi
            echo -e "  ${RED}⚠ 名称必填，只能包含字母、数字、_、-、.${NC}"
        done
        LLM_PROVIDER=custom
        LLM_PROVIDER_API_KEY_ENV="CUSTOM_LLM_API_KEY"
        LLM_PROVIDER_BASE_URL_ENV="CUSTOM_LLM_BASE_URL"
        LLM_BASE_URL=""
        prompt_provider_base_url "Custom" "" "$LLM_PROVIDER_BASE_URL_ENV" || return 1
        local cur_key="${LLM_API_KEY:-${CUSTOM_LLM_API_KEY:-}}"
        [ -n "$cur_key" ] && echo -e "  ${DIM}当前 API Key: $(mask_secret "$cur_key")${NC}" >&2
        read -p "  API Key (如果服务不需要鉴权可留空): " val
        LLM_API_KEY="${val:-$cur_key}"
        CUSTOM_LLM_API_KEY="$LLM_API_KEY"
        if ! LLM_MODEL="$(select_model_from_catalog_or_api "$LLM_PROVIDER" "$LLM_BASE_URL" "$LLM_API_KEY")"; then
            return 1
        fi
        echo -e "  ${GREEN}✓ ${CUSTOM_LLM_PROVIDER_NAME} (custom): $LLM_MODEL${NC}"
        return 0
    fi

    local provider_label provider_base provider_key_env provider_base_env provider_key_json
    provider_label="$(provider_field "$provider_slug" label)"
    provider_base="$(provider_field "$provider_slug" default_base_url)"
    provider_key_json="$(provider_field "$provider_slug" api_key_env_vars)"
    provider_key_env="$(printf '%s' "$provider_key_json" | "$PYTHON" -c 'import json,sys; vals=json.load(sys.stdin); print(vals[0] if vals else "")')"
    provider_base_env="$(provider_field "$provider_slug" base_url_env_var)"

    LLM_PROVIDER="$provider_slug"
    CUSTOM_LLM_PROVIDER_NAME=""
    LLM_PROVIDER_API_KEY_ENV="$provider_key_env"
    LLM_PROVIDER_BASE_URL_ENV="$provider_base_env"
    LLM_BASE_URL="${provider_base}"

    prompt_provider_api_key "$provider_label" "$provider_key_env" || return 1
    prompt_provider_base_url "$provider_label" "$provider_base" "$provider_base_env" || return 1
    set_provider_specific_key_var "$provider_key_env" "$LLM_API_KEY"

    if ! LLM_MODEL="$(select_model_from_catalog_or_api "$provider_slug" "$LLM_BASE_URL" "$LLM_API_KEY")"; then
        return 1
    fi
    echo -e "  ${GREEN}✓ ${provider_label}: $LLM_MODEL${NC}"
}
