from tests.helpers import build_common_exports, run_bash


def test_prompt_tool_progress_enable_verbose_and_reasoning(temp_setup_files):
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        prompt_tool_progress <<'INPUT'
y
INPUT
        printf 'TP=%s\nSR=%s' "$TOOL_PROGRESS" "$SHOW_REASONING"
        '''
    )
    assert result.returncode == 0
    assert 'TP=verbose' in result.stdout
    assert 'SR=true' in result.stdout


def test_prompt_tool_progress_no_sets_all(temp_setup_files):
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        TOOL_PROGRESS=verbose
        SHOW_REASONING=true
        prompt_tool_progress <<'INPUT'
n
INPUT
        printf 'TP=%s\nSR=%s' "$TOOL_PROGRESS" "$SHOW_REASONING"
        '''
    )
    assert result.returncode == 0
    assert 'TP=all' in result.stdout
