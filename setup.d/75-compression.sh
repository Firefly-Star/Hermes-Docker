# shellcheck shell=bash
# This file is sourced by setup.sh. Do not execute setup flow at top level.

prompt_compression() {
    echo ""
    echo -e "${BOLD}[8] 自动上下文压缩${NC}"
    echo -e "  ${DIM}Hermes 的 compression.threshold 是上下文使用比例。${NC}"
    echo -e "  ${DIM}默认 0.85 表示约 85% 时压缩；128k 上下文约 109k token。${NC}"

    local cur_enabled="${COMPRESSION_ENABLED:-true}"
    local cur_threshold="${COMPRESSION_THRESHOLD:-0.85}"
    local enabled_label="启用"
    [ "$cur_enabled" = "false" ] && enabled_label="禁用"

    read -p "  启用自动压缩? [Y/n] (当前: $enabled_label): " val
    case "$val" in
        n|N|no|NO)
            COMPRESSION_ENABLED=false
            echo -e "  ${GREEN}✓ 将禁用自动压缩${NC}"
            ;;
        y|Y|yes|YES|"")
            COMPRESSION_ENABLED=true
            ;;
        *)
            COMPRESSION_ENABLED="$cur_enabled"
            ;;
    esac

    if [ "$COMPRESSION_ENABLED" = "true" ]; then
        while true; do
            read -p "  压缩阈值比例 [0.50-0.95] (当前/默认: $cur_threshold): " threshold
            threshold="${threshold:-$cur_threshold}"
            if "$PYTHON" - "$threshold" <<'PY' >/dev/null 2>&1
import sys
try:
    value = float(sys.argv[1])
except Exception:
    raise SystemExit(1)
raise SystemExit(0 if 0.50 <= value <= 0.95 else 1)
PY
            then
                COMPRESSION_THRESHOLD="$threshold"
                echo -e "  ${GREEN}✓ 自动压缩阈值: $COMPRESSION_THRESHOLD${NC}"
                break
            fi
            echo -e "  ${YELLOW}请输入 0.50 到 0.95 之间的小数，例如 0.85${NC}"
        done
    else
        COMPRESSION_THRESHOLD="${cur_threshold}"
    fi
}

prompt_model_context_length() {
    echo ""
    echo -e "${BOLD}[9] 模型 context length 覆盖${NC}"
    echo -e "  ${DIM}留空则 config.yaml 不写 model.context_length，让 Hermes 自己探测/判断。${NC}"
    local cur="${MODEL_CONTEXT_LENGTH:-}"
    local cur_label="未设置"
    [ -n "$cur" ] && cur_label="$cur"

    while true; do
        read -p "  硬编码模型 context length? 留空=不设置 (当前: $cur_label): " ctx
        if [ -z "$ctx" ]; then
            MODEL_CONTEXT_LENGTH=""
            echo -e "  ${GREEN}✓ 不写 model.context_length，交给 Hermes 自动判断${NC}"
            return
        fi
        if "$PYTHON" - "$ctx" <<'PY' >/dev/null 2>&1
import sys
try:
    value = int(sys.argv[1])
except Exception:
    raise SystemExit(1)
raise SystemExit(0 if value >= 64000 else 1)
PY
        then
            MODEL_CONTEXT_LENGTH="$ctx"
            echo -e "  ${GREEN}✓ 将写入 model.context_length: $MODEL_CONTEXT_LENGTH${NC}"
            return
        fi
        echo -e "  ${YELLOW}请输入不小于 64000 的整数 token 数，或直接回车不设置${NC}"
    done
}
