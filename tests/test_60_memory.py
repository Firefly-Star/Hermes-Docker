from tests.helpers import build_common_exports, run_bash


def test_prompt_memory_tool_disable_sets_related_flags(temp_setup_files):
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        prompt_memory_tool <<'INPUT'
n
INPUT
        printf 'MEM=%s\nDIS=%s\nMN=%s\nSN=%s' "$MEMORY_TOOL_ENABLED" "$DISABLED_TOOLSETS" "$MEMORY_NUDGE_INTERVAL" "$SKILL_NUDGE_INTERVAL"
        '''
    )
    assert result.returncode == 0
    assert 'MEM=false' in result.stdout
    assert 'DIS=[memory]' in result.stdout
    assert 'MN=0' in result.stdout
    assert 'SN=0' in result.stdout


def test_prompt_memory_tool_enable_restores_defaults(temp_setup_files):
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        MEMORY_TOOL_ENABLED=false
        DISABLED_TOOLSETS='[memory]'
        prompt_memory_tool <<'INPUT'
y
INPUT
        printf 'MEM=%s\nDIS=%s' "$MEMORY_TOOL_ENABLED" "$DISABLED_TOOLSETS"
        '''
    )
    assert result.returncode == 0
    assert 'MEM=true' in result.stdout
    assert 'DIS=[]' in result.stdout
