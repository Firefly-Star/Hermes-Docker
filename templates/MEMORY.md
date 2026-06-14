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