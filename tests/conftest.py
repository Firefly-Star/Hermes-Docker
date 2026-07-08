from pathlib import Path

import pytest


@pytest.fixture
def repo_root():
    return Path(__file__).resolve().parents[1]


@pytest.fixture
def temp_setup_files(tmp_path):
    env_file = tmp_path / ".env"
    state_file = tmp_path / ".setup-state.env"
    soul = tmp_path / "SOUL.md"
    soul.write_text("soul", encoding="utf-8")
    return {
        "tmp_path": tmp_path,
        "env_file": env_file,
        "state_file": state_file,
        "soul": soul,
    }


@pytest.fixture
def fake_home(tmp_path):
    home = tmp_path / "home"
    ssh_dir = home / ".ssh"
    ssh_dir.mkdir(parents=True, exist_ok=True)
    (ssh_dir / "authorized_keys").write_text("", encoding="utf-8")
    return home


@pytest.fixture
def fake_bin(tmp_path):
    bindir = tmp_path / "fake-bin"
    bindir.mkdir()
    log = tmp_path / "command.log"

    scripts = {
        "docker": "#!/bin/sh\necho docker \"$@\" >> \"$COMMAND_LOG\"\nif [ \"$1\" = \"compose\" ] && [ \"$2\" = \"version\" ]; then exit 0; fi\nif [ \"$1\" = \"network\" ] && [ \"$2\" = \"inspect\" ]; then exit 1; fi\nif [ \"$1\" = \"ps\" ] && [ \"$2\" = \"--format\" ]; then exit 0; fi\nexit 0\n",
        "systemctl": "#!/bin/sh\necho systemctl \"$@\" >> \"$COMMAND_LOG\"\nif [ \"$1\" = \"is-active\" ]; then exit 1; fi\nif [ \"$1\" = \"is-enabled\" ]; then exit 1; fi\nif [ \"$1\" = \"list-unit-files\" ]; then echo ssh.service; exit 0; fi\nexit 0\n",
        "service": "#!/bin/sh\necho service \"$@\" >> \"$COMMAND_LOG\"\nif [ \"$1\" = \"ssh\" ] && [ \"$2\" = \"status\" ]; then exit 1; fi\nexit 0\n",
        "sudo": "#!/bin/sh\necho sudo \"$@\" >> \"$COMMAND_LOG\"\n\"$@\"\n",
        "sshd": "#!/bin/sh\nexit 0\n",
        "ssh-keygen": "#!/bin/sh\necho ssh-keygen \"$@\" >> \"$COMMAND_LOG\"\nif [ \"$1\" = \"-t\" ]; then\n  keyfile=\"$4\"\n  printf private > \"$keyfile\"\n  printf public > \"$keyfile.pub\"\nfi\nexit 0\n",
        "hostname": "#!/bin/sh\nif [ \"$1\" = \"-I\" ]; then\n  echo 172.24.29.222\n  exit 0\nfi\n/usr/bin/hostname \"$@\"\n",
        "ip": "#!/bin/sh\nif [ \"$1\" = \"route\" ] && [ \"$2\" = \"get\" ] && [ \"$3\" = \"1\" ]; then\n  echo '1.0.0.0 via 192.168.1.1 dev eth0 src 10.0.0.8 uid 1000'\n  exit 0\nfi\nexit 1\n",
        "realpath": "#!/bin/sh\npython3 - <<'PY' \"$1\"\nimport os,sys\nprint(os.path.realpath(sys.argv[1]))\nPY\n",
    }

    for name, content in scripts.items():
        path = bindir / name
        path.write_text(content, encoding="utf-8")
        path.chmod(0o755)

    return {"path": bindir, "log": log}
