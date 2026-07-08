import os
from pathlib import Path

from tests.helpers import build_common_exports, run_bash


def test_start_container_skip_does_not_run_docker_compose(temp_setup_files, fake_home, fake_bin):
    env = {'PATH': f"{fake_bin['path']}:{os.environ['PATH']}", 'COMMAND_LOG': str(fake_bin['log'])}
    key = Path(fake_home) / '.ssh' / 'id_hermes-single'
    key.write_text('private', encoding='utf-8')
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files, home_dir=fake_home)}
        start_container <<'INPUT'
n
INPUT
        ''',
        env=env,
    )
    assert result.returncode == 0
    log = fake_bin['log'].read_text(encoding='utf-8') if fake_bin['log'].exists() else ''
    assert 'docker compose down' not in log
    assert 'docker compose up -d' not in log


def test_start_container_calls_render_and_compose_when_confirmed(temp_setup_files, fake_home, fake_bin):
    env = {'PATH': f"{fake_bin['path']}:{os.environ['PATH']}", 'COMMAND_LOG': str(fake_bin['log'])}
    key = Path(fake_home) / '.ssh' / 'id_hermes-single'
    key.write_text('private', encoding='utf-8')
    result = run_bash(
        f'''
        {build_common_exports(**temp_setup_files, home_dir=fake_home)}
        start_container <<'INPUT'

INPUT
        ''',
        env=env,
    )
    assert result.returncode == 0
    log = fake_bin['log'].read_text(encoding='utf-8')
    assert 'docker network inspect mcp-net' in log
    assert 'docker network create mcp-net' in log
    assert 'docker compose down' in log
    assert 'docker compose up -d' in log
