# Docker 运行 SaaS Hub

只用 `docker` 命令（不用 docker-compose）。MySQL 在容器外，通过环境变量传连接参数。端口 8787。

## 前提

- 已装 Docker
- 已有一个可访问的 MySQL 实例（容器外），并已建好库和用户：

```sql
CREATE DATABASE IF NOT EXISTS token_monitor_saas CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'tm_saas'@'%' IDENTIFIED BY '你的强密码';
GRANT ALL PRIVILEGES ON token_monitor_saas.* TO 'tm_saas'@'%';
FLUSH PRIVILEGES;
```

注意 `'tm_saas'@'%'`：因为容器是另一台机器视角连接 MySQL，不能用 `@'localhost'`。如果 MySQL 也在同一台宿主机，容器内用 `host.docker.internal` 连它（见下文 `-e SAAS_HUB_MYSQL_HOST`）。

## 1. 构建镜像

在**仓库根目录**执行（构建上下文必须在根，因为镜像要打包 `src/shared/`）：

```bash
cd /path/to/ztoken-monitor
docker build -t ztoken-monitor-saas-hub -f saas-hub/Dockerfile .
```

## 2. 一键运行

```bash
docker run -d \
  --name saas-hub \
  --restart unless-stopped \
  -p 8787:8787 \
  -e SAAS_HUB_JWT_SECRET=$(openssl rand -hex 32) \
  -e SAAS_HUB_MYSQL_HOST=host.docker.internal \
  -e SAAS_HUB_MYSQL_PORT=3306 \
  -e SAAS_HUB_MYSQL_USER=tm_saas \
  -e SAAS_HUB_MYSQL_PASSWORD=你的强密码 \
  -e SAAS_HUB_MYSQL_DATABASE=token_monitor_saas \
  ztoken-monitor-saas-hub
```

**说明**：
- `-p 8787:8787`：宿主机 8787 端口映射到容器
- `-e SAAS_HUB_MYSQL_HOST=host.docker.internal`：MySQL 在宿主机上时用这个地址（Mac/Windows Docker Desktop 自动解析；Linux 需加 `--add-host=host.docker.internal:host-gateway`）。MySQL 在远程就用远程 IP
- `--restart unless-stopped`：崩溃自动重启，手动停了不重启
- `SAAS_HUB_JWT_SECRET`：每次 run 生成新的随机密钥。**注意**：重启容器若重新生成密钥，旧 token 全部失效。要持久化就固定一个值，或用 `-e SAAS_HUB_JWT_SECRET=固定值`

## 3. 首次启动要跑迁移（建表）

镜像内不含表结构。第一次运行后，进容器执行迁移：

```bash
docker exec -it saas-hub node scripts/migrate.js
```

或者构建时就把迁移跑进镜像（一劳永逸，但每次重建镜像会重跑，幂等所以安全）——可选，在 Dockerfile 末尾加 `RUN node scripts/migrate.js || true`（需要构建时就能连到 MySQL，一般不用）。

推荐做法：启动一次后用 `docker exec` 跑迁移，只跑一次。

## 4. 测试接口

```bash
# 健康检查
curl -s http://localhost:8787/api/health

# 注册
curl -s -X POST http://localhost:8787/api/auth/register \
  -H 'content-type: application/json' \
  -d '{"email":"test@example.com","password":"password123"}'

# 登录拿 token
TOKEN=$(curl -s -X POST http://localhost:8787/api/auth/login \
  -H 'content-type: application/json' \
  -d '{"email":"test@example.com","password":"password123"}' | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")

# 上报用量
curl -s -X POST http://localhost:8787/api/ingest \
  -H "Authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' \
  -d '{"deviceId":"macbook","hostname":"mb","platform":"darwin","today":{"totalTokens":5,"costUsd":0.1}}'

# 查统计
curl -s http://localhost:8787/api/stats -H "Authorization: Bearer $TOKEN"
```

完整接口测试见 `DEPLOY.md` 第 7 节。

## 5. 常用运维命令

```bash
# 查看日志
docker logs -f saas-hub

# 查看日志（最近 100 行）
docker logs --tail 100 saas-hub

# 停止
docker stop saas-hub

# 启动（已创建的容器）
docker start saas-hub

# 重启
docker restart saas-hub

# 删除容器（代码和镜像不受影响）
docker rm -f saas-hub

# 删除镜像
docker rmi ztoken-monitor-saas-hub

# 更新代码后重建
cd /path/to/ztoken-monitor
git pull
docker build -t ztoken-monitor-saas-hub -f saas-hub/Dockerfile .
docker rm -f saas-hub
docker run -d ...  # 同第 2 步
```

## 6. 完整环境变量参考

所有 `-e` 参数（不传的用默认值）：

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `SAAS_HUB_PORT` | 8787 | 服务端口 |
| `SAAS_HUB_HOST` | 0.0.0.0 | 绑定地址 |
| `SAAS_HUB_JWT_SECRET` | 必填 | JWT 密钥（`openssl rand -hex 32`） |
| `SAAS_HUB_JWT_EXPIRES_IN` | 90d | access token 有效期（widget 静默续期，默认 90 天） |
| `SAAS_HUB_REFRESH_EXPIRES_IN` | 90d | refresh token 有效期（滚动续期，默认 90 天） |
| `SAAS_HUB_MYSQL_HOST` | 127.0.0.1 | MySQL 主机 |
| `SAAS_HUB_MYSQL_PORT` | 3306 | MySQL 端口 |
| `SAAS_HUB_MYSQL_USER` | root | MySQL 用户 |
| `SAAS_HUB_MYSQL_PASSWORD` | 空 | MySQL 密码 |
| `SAAS_HUB_MYSQL_DATABASE` | token_monitor_saas | 数据库名 |
| `SAAS_HUB_STALE_AFTER_MS` | 600000 | 设备过期阈值 |
| `SAAS_HUB_PASSWORD_MIN_LENGTH` | 8 | 密码最小长度 |
| `SAAS_HUB_CORS_ORIGIN` | * | CORS 来源 |

## 常见问题

**Q: 启动报 `ECONNREFUSED` 连不上 MySQL**
A: 容器内 `127.0.0.1` 是容器自己，不是宿主机。MySQL 在宿主机上要用 `host.docker.internal`（Linux 加 `--add-host=host.docker.internal:host-gateway`），远程 MySQL 用远程 IP。

**Q: `host.docker.internal` 解析不了（Linux）**
A: 运行时加参数：`--add-host=host.docker.internal:host-gateway`。

**Q: 启动报 `SAAS_HUB_JWT_SECRET must be set`**
A: 没传 `-e SAAS_HUB_JWT_SECRET`。

**Q: 表不存在，接口 500**
A: 没跑迁移。`docker exec -it saas-hub node scripts/migrate.js`。

**Q: 重启后所有用户要重新登录**
A: JWT 密钥变了。固定它：`-e SAAS_HUB_JWT_SECRET=固定值`，重建容器也用同一个值。
