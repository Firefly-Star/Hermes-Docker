#!/bin/bash
chown -R 10000:10000 /opt/data/ 2>/dev/null || true
grep -q "source /opt/hermes/.venv/bin/activate" /root/.bashrc 2>/dev/null ||
  echo "source /opt/hermes/.venv/bin/activate" >> /root/.bashrc
