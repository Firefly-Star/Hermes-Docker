#!/bin/bash
# 进入 hermes-single 容器，自动激活 Hermes 虚拟环境
docker exec -it hermes-single bash --rcfile /opt/data/scripts/activate.sh
