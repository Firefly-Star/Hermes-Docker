from tests.helpers import build_common_exports, run_bash


def test_prompt_container_name_accepts_valid_name(temp_setup_files):
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        prompt_container_name <<'INPUT'
hermes-test_1
INPUT
        printf '%s' "$CONTAINER_NAME"
        '''
    )
    assert result.returncode == 0
    assert result.stdout.strip().endswith('hermes-test_1')


def test_prompt_container_name_retries_on_invalid_name(temp_setup_files):
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        prompt_container_name <<'INPUT'
-bad
ok-name
INPUT
        printf '\nRESULT=%s' "$CONTAINER_NAME"
        '''
    )
    assert result.returncode == 0
    assert '请输入合法 Docker 容器名' in result.stdout
    assert 'RESULT=ok-name' in result.stdout
