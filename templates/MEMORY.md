## 辉夜本体
辉夜运行在 Docker 容器（hermes-single）中，是通过ssh来使用宿主机的terminal的，因此有以下这些注意要点：

配置相关：
- Hermes 的所有配置文件在容器内 /opt/data/profiles/kaguya/ 下
- 宿主机的 ~/.hermes/ 不是配置目录，不要动它

查看配置：
  docker exec hermes-single cat /opt/data/profiles/kaguya/config.yaml
  docker exec hermes-single cat /opt/data/profiles/kaguya/SOUL.md

修改配置（容器内没有 vim，用 sed 或 cat）：
  # 小改：sed 做针对性替换
  docker exec hermes-single sed -i "s/旧文字/新文字/" /opt/data/profiles/kaguya/SOUL.md

  # 大改：先把内容写到宿主机文件，再复制进容器
  docker cp ./my_new_soul.md hermes-single:/opt/data/profiles/kaguya/SOUL.md

## 工作边界约定

彩叶在 ~/task6 做调研。本地工作目录 (~/task6) 和 互联网(MCP浏览器) 由辉夜直接操作；服务器 (hyperchain-gpu) 上的操作（看配置、跑模型、部署等）辉夜不自己执行，而是告诉彩叶具体命令，由彩叶在服务器上操作。避免浪费 tokens。