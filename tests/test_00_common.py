from tests.helpers import build_common_exports, run_bash


def test_load_env_file_reads_existing_file(temp_setup_files):
    test_file = temp_setup_files['tmp_path'] / 'vars.env'
    test_file.write_text('FOO=bar\n', encoding='utf-8')
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        load_env_file {test_file}
        printf '%s' "$FOO"
        '''
    )
    assert result.returncode == 0
    assert result.stdout.strip().endswith('bar')


def test_check_deps_passes_with_fake_docker(temp_setup_files, fake_bin):
    import os
    env = {'PATH': f"{fake_bin['path']}:{os.environ['PATH']}", 'COMMAND_LOG': str(fake_bin['log'])}
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files)}
        check_deps
        ''',
        env=env,
    )
    assert result.returncode == 0
    log = fake_bin['log'].read_text(encoding='utf-8')
    assert 'docker compose version' in log
