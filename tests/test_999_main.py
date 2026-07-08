from tests.helpers import build_common_exports, run_bash


def test_main_calls_steps_in_order(temp_setup_files):
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        check_deps() {{ echo check_deps; }}
        prompt_name() {{ echo prompt_name; }}
        prompt_container_name() {{ echo prompt_container_name; }}
        prompt_llm_provider() {{ echo prompt_llm_provider; }}
        prompt_ssh_user() {{ echo prompt_ssh_user; }}
        prompt_soul() {{ echo prompt_soul; }}
        prompt_memory_tool() {{ echo prompt_memory_tool; }}
        prompt_tool_progress() {{ echo prompt_tool_progress; }}
        prompt_compression() {{ echo prompt_compression; }}
        prompt_model_context_length() {{ echo prompt_model_context_length; }}
        prompt_playwright_mcp() {{ echo prompt_playwright_mcp; }}
        setup_ssh_server() {{ echo setup_ssh_server; }}
        detect_ssh_host() {{ echo detect_ssh_host; }}
        setup_ssh_key() {{ echo setup_ssh_key; }}
        write_env() {{ echo write_env; }}
        start_container() {{ echo start_container; }}
        enter_container() {{ echo enter_container; }}
        main
        ''',
    )
    assert result.returncode == 0
    expected = [
        'check_deps', 'prompt_name', 'prompt_container_name', 'prompt_llm_provider',
        'prompt_ssh_user', 'prompt_soul', 'prompt_memory_tool', 'prompt_tool_progress',
        'prompt_compression', 'prompt_model_context_length', 'prompt_playwright_mcp',
        'setup_ssh_server', 'detect_ssh_host', 'setup_ssh_key', 'write_env',
        'start_container', 'enter_container'
    ]
    out = result.stdout
    cursor = -1
    for item in expected:
        pos = out.find(item)
        assert pos > cursor, f'{item} not found in order'
        cursor = pos
