from tests.helpers import build_common_exports, run_bash


def test_prompt_name_uses_default_on_empty_input(temp_setup_files):
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        prompt_name <<'INPUT'

INPUT
        printf '%s' "$AGENT_NAME"
        '''
    )
    assert result.returncode == 0
    assert result.stdout.strip().endswith('kaguya')


def test_prompt_name_accepts_custom_value(temp_setup_files):
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        prompt_name <<'INPUT'
my-agent
INPUT
        printf '%s' "$AGENT_NAME"
        '''
    )
    assert result.returncode == 0
    assert result.stdout.strip().endswith('my-agent')
