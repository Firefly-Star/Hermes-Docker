from pathlib import Path

from tests.helpers import build_common_exports, run_bash


def test_setup_ssh_server_wsl_path_invokes_service_start(temp_setup_files, fake_home, fake_bin):
    env = {'PATH': f"{fake_bin['path']}:{__import__('os').environ['PATH']}", 'COMMAND_LOG': str(fake_bin['log'])}
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files, home_dir=fake_home)}
        setup_ssh_server
        ''',
        env=env,
    )
    assert result.returncode == 0
    log = fake_bin['log'].read_text(encoding='utf-8')
    assert 'service ssh start' in log


def test_detect_ssh_host_uses_detected_wsl_ip(temp_setup_files, fake_home, fake_bin):
    env = {'PATH': f"{fake_bin['path']}:{__import__('os').environ['PATH']}", 'COMMAND_LOG': str(fake_bin['log'])}
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files, home_dir=fake_home)}
        unset SSH_HOST
        detect_ssh_host <<'INPUT'

INPUT
        printf '%s' "$SSH_HOST"
        ''',
        env=env,
    )
    assert result.returncode == 0
    assert result.stdout.strip().endswith('172.24.29.222')


def test_setup_ssh_key_creates_key_and_authorized_keys(temp_setup_files, fake_home, fake_bin):
    env = {'PATH': f"{fake_bin['path']}:{__import__('os').environ['PATH']}", 'COMMAND_LOG': str(fake_bin['log'])}
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files, home_dir=fake_home)}
        setup_ssh_key
        ''',
        env=env,
    )
    assert result.returncode == 0
    assert (Path(fake_home) / '.ssh' / 'id_hermes-single').exists()
    auth = (Path(fake_home) / '.ssh' / 'authorized_keys').read_text(encoding='utf-8')
    assert 'public' in auth
