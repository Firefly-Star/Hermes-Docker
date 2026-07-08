from tests.helpers import build_common_exports, run_bash


def test_prompt_compression_accepts_valid_threshold(temp_setup_files):
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        prompt_compression <<'INPUT'
y
0.90
INPUT
        printf 'CE=%s\nCT=%s' "$COMPRESSION_ENABLED" "$COMPRESSION_THRESHOLD"
        '''
    )
    assert result.returncode == 0
    assert 'CE=true' in result.stdout
    assert 'CT=0.90' in result.stdout


def test_prompt_compression_retries_invalid_threshold(temp_setup_files):
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        prompt_compression <<'INPUT'
y
0.2
0.85
INPUT
        printf 'CT=%s' "$COMPRESSION_THRESHOLD"
        '''
    )
    assert result.returncode == 0
    assert '请输入 0.50 到 0.95 之间的小数' in result.stdout
    assert 'CT=0.85' in result.stdout


def test_prompt_model_context_length_accepts_empty_and_valid_integer(temp_setup_files):
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        prompt_model_context_length <<'INPUT'

INPUT
        printf 'CTX=%s\n' "$MODEL_CONTEXT_LENGTH"
        prompt_model_context_length <<'INPUT'
1024
131072
INPUT
        printf 'CTX2=%s' "$MODEL_CONTEXT_LENGTH"
        '''
    )
    assert result.returncode == 0
    assert 'CTX=' in result.stdout
    assert '请输入不小于 64000 的整数 token 数' in result.stdout
    assert 'CTX2=131072' in result.stdout
