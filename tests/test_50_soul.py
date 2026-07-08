from pathlib import Path

from tests.helpers import build_common_exports, run_bash


def test_prompt_soul_resolves_existing_file(temp_setup_files):
    soul = temp_setup_files['soul']
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        prompt_soul <<'INPUT'
{soul}
INPUT
        printf '%s' "$SOUL_PATH"
        '''
    )
    assert result.returncode == 0
    assert result.stdout.strip().endswith(str(Path(soul).resolve()))


def test_prompt_soul_retries_for_missing_file(temp_setup_files):
    soul = temp_setup_files['soul']
    missing = soul.parent / 'missing.md'
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        prompt_soul <<'INPUT'
{missing}
{soul}
INPUT
        printf '\nRESULT=%s' "$SOUL_PATH"
        '''
    )
    assert result.returncode == 0
    assert '文件不存在' in result.stdout
    assert f'RESULT={Path(soul).resolve()}' in result.stdout
