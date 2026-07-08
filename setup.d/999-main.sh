# shellcheck shell=bash
# This file is sourced by setup.sh. Do not execute setup flow at top level.

main() {
    echo "============================================"
    echo "  Hermes Single-Agent 配置向导"
    echo "============================================"
    echo "  一个容器，一个 profile，你的 SOUL.md"
    echo "  无需端口映射，exec 进入容器使用 CLI"
    echo ""

    check_deps

    # 预先缓存 sudo 凭证，避免后续安装 SSH 时中断流程
    # 注释掉以避免交互阻塞，SSH 已配好不需要
    # echo -e "${DIM}检查 sudo 权限...${NC}"
    # sudo -v
    # 后台续期（脚本退出时自动结束）
    # (while true; do sudo -n true; sleep 60; done) 2>/dev/null &
    # SUDO_PID=$!
    # trap 'kill $SUDO_PID 2>/dev/null; wait $SUDO_PID 2>/dev/null' EXIT INT TERM

    prompt_name
    prompt_container_name
    prompt_llm_provider
    prompt_ssh_user
    prompt_soul
    prompt_memory_tool
    prompt_tool_progress
    prompt_compression
    prompt_model_context_length
    prompt_playwright_mcp
    setup_ssh_server
    detect_ssh_host
    setup_ssh_key
    write_env
    start_container
    enter_container

    echo ""
    echo -e "${GREEN}完成。${NC}"
    echo "  下次启动: cd $SCRIPT_DIR && docker compose up -d"
}
