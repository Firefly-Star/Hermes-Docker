from pathlib import Path

from tests.helpers import build_common_exports, read_text, run_bash


def test_write_env_writes_custom_provider_files(temp_setup_files):
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        LLM_PROVIDER=custom
        CUSTOM_LLM_PROVIDER_NAME=my-provider
        LLM_PROVIDER_API_KEY_ENV=CUSTOM_LLM_API_KEY
        LLM_PROVIDER_BASE_URL_ENV=CUSTOM_LLM_BASE_URL
        LLM_MODEL=gpt-5.4
        LLM_BASE_URL=https://api.gaoxin.net.cn/v1
        CUSTOM_LLM_API_KEY=sk-custom
        write_env
        '''
    )
    assert result.returncode == 0
    env_text = read_text(temp_setup_files['env_file'])
    state_text = read_text(temp_setup_files['state_file'])
    override_text = read_text(Path(temp_setup_files['tmp_path']).parent / 'docker-compose.override.yml') if False else read_text(Path('/home/wxz/task5/hermes-single/docker-compose.override.yml'))
    assert 'HERMES_MODEL_API_KEY=sk-custom' in env_text
    assert 'CUSTOM_LLM_API_KEY=sk-custom' in env_text
    assert 'CUSTOM_LLM_BASE_URL=https://api.gaoxin.net.cn/v1' in env_text
    assert 'LLM_PROVIDER=custom' in state_text
    assert 'LLM_MODEL=gpt-5.4' in state_text
    assert 'LLM_BASE_URL=https://api.gaoxin.net.cn/v1' in state_text
    assert 'container_name: hermes-test' in override_text


def test_write_env_preserves_extra_lines(temp_setup_files):
    temp_setup_files['env_file'].write_text('EXTRA_SECRET=keepme\n', encoding='utf-8')
    temp_setup_files['state_file'].write_text('EXTRA_STATE=keep\n', encoding='utf-8')
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        DEEPSEEK_API_KEY=sk-deepseek
        write_env
        ''',
    )
    assert result.returncode == 0
    env_text = read_text(temp_setup_files['env_file'])
    state_text = read_text(temp_setup_files['state_file'])
    assert 'EXTRA_SECRET=keepme' in env_text
    assert 'EXTRA_STATE=keep' in state_text
