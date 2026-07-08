from tests.helpers import build_common_exports, run_bash


def test_prompt_ssh_user_uses_default_user(temp_setup_files):
    result = run_bash(
        f'''
        export USER=test-user
        {build_common_exports(**temp_setup_files)}
        unset SSH_USER
        prompt_ssh_user <<'INPUT'

INPUT
        printf '%s' "$SSH_USER"
        '''
    )
    assert result.returncode == 0
    assert result.stdout.strip().endswith('test-user')


def test_prompt_ssh_user_accepts_custom_user(temp_setup_files):
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        prompt_ssh_user <<'INPUT'
wxz
INPUT
        printf '%s' "$SSH_USER"
        '''
    )
    assert result.returncode == 0
    assert result.stdout.strip().endswith('wxz')
