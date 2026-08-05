# SaaS Hub 部署指南

本指南覆盖：在 Linux 服务器上从零部署 SaaS Hub + MySQL，并完成全部接口测试。

## 前置要求

- Linux 服务器（已确认 Node 22.13+）
- 一个 MySQL 8.x 实例（可以是服务器本地装的，也可以是远程的）
- 代码已推到 git / 或直接 scp 上去

## 1. 拉代码

```bash
git clone <你的仓库地址> /opt/ztoken-monitor
cd /opt/ztoken-monitor/saas-hub
```

如果是 scp 上传：

```bash
# 本地执行
cd /Users/xiaozhou/hub/vibecoding/ztoken-monitor
rsync -av --exclude node_modules --exclude .git saas-hub/ user@your-server:/opt/ztoken-monitor/saas-hub/
```

注意：saas-hub 依赖主项目的 `src/shared/`，所以**必须带着上一层 `src/shared/` 一起部署**。整个 `ztoken-monitor` 仓库一起拉最省事。

## 2. 装 Node 22.13+

```bash
node -v   # 确认 >= 22.13
# 没有就用 nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
nvm install 22 && nvm use 22
```

## 3. 装 MySQL（如服务器还没有）

```bash
# Debian/Ubuntu
sudo apt update && sudo apt install -y mysql-server
sudo systemctl start mysql
sudo mysql_secure_installation

# 或 CentOS/RHEL
sudo yum install -y mysql-server
sudo systemctl start mysqld
```

建专用数据库和用户：

```bash
sudo mysql <<'SQL'
CREATE DATABASE IF NOT EXISTS token_monitor_saas CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'tm_saas'@'localhost' IDENTIFIED BY '改成一个强密码';
GRANT ALL PRIVILEGES ON token_monitor_saas.* TO 'tm_saas'@'localhost';
FLUSH PRIVILEGES;
SQL
```

## 4. 配置 .env

```bash
cd /opt/ztoken-monitor/saas-hub
cp .env.example .env
# 生成 JWT 密钥
openssl rand -hex 32
```

编辑 `.env`：

```bash
nano .env
```

填入（按你上一步的实际值替换）：

```ini
SAAS_HUB_PORT=17322
SAAS_HUB_HOST=0.0.0.0
SAAS_HUB_CORS_ORIGIN=*

# 粘贴上面 openssl 生成的密钥
SAAS_HUB_JWT_SECRET=粘贴这里
SAAS_HUB_JWT_EXPIRES_IN=90d
SAAS_HUB_REFRESH_EXPIRES_IN=90d

# MySQL（如果 MySQL 在本机，用 localhost）
SAAS_HUB_MYSQL_HOST=127.0.0.1
SAAS_HUB_MYSQL_PORT=3306
SAAS_HUB_MYSQL_USER=tm_saas
SAAS_HUB_MYSQL_PASSWORD=你刚才设的强密码
SAAS_HUB_MYSQL_DATABASE=token_monitor_saas
SAAS_HUB_MYSQL_CONNECTION_LIMIT=10

SAAS_HUB_STALE_AFTER_MS=600000
SAAS_HUB_PASSWORD_MIN_LENGTH=8
```

确认 `.env` 权限：

```bash
chmod 600 .env
```

## 5. 装依赖 + 跑迁移

```bash
cd /opt/ztoken-monitor/saas-hub
npm install
npm run migrate
```

迁移成功应看到：

```
Database 'token_monitor_saas' ensured.
Schema applied from schema.sql.
```

## 6. 启动服务（前台，先验证）

```bash
npm start
```

应看到：

```
SaaS Hub listening on http://0.0.0.0:17322
MySQL database: token_monitor_saas
```

保持这个终端开着，另开一个终端跑下面的接口测试。Ctrl+C 可停止。

## 7. 接口测试

### 7.1 健康检查（不鉴权）

```bash
curl -s http://localhost:17322/api/health | python3 -m json.tool
```

期望：

```json
{"ok": true, "role": "hub", "version": 1, "deviceCount": 0, "secretRequired": true, "now": "..."}
```

### 7.2 注册用户

```bash
curl -s -X POST http://localhost:17322/api/auth/register \
  -H 'content-type: application/json' \
  -d '{"email":"test@example.com","password":"password123"}' | python3 -m json.tool
```

期望返回 `token` 和 `user`。把 token 存起来：

```bash
TOKEN=$(curl -s -X POST http://localhost:17322/api/auth/login \
  -H 'content-type: application/json' \
  -d '{"email":"test@example.com","password":"password123"}' | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")
echo "TOKEN=$TOKEN"
```

### 7.3 无 token 访问应 401

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:17322/api/stats
# 期望: 401
```

### 7.4 上报设备用量

```bash
curl -s -X POST http://localhost:17322/api/ingest \
  -H "Authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' \
  -d '{"deviceId":"macbook","hostname":"mb","platform":"darwin-arm64","agentVersion":"0.1.0","today":{"totalTokens":5,"costUsd":0.1},"month":{"totalTokens":100,"costUsd":2.5}}' | python3 -m json.tool
```

期望 `{ok: true, deviceId: "macbook", stats: {...}}`。

### 7.5 拉取聚合统计

```bash
curl -s http://localhost:17322/api/stats -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
```

期望 `devices` 数组里有刚上报的 macbook，`periods.today.totalTokens` 是 5。

### 7.6 设备列表 / 历史

```bash
curl -s http://localhost:17322/api/devices -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
curl -s http://localhost:17322/api/history -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
```

### 7.7 订阅列表（乐观并发）

首次写入：

```bash
curl -s -X PUT http://localhost:17322/api/subscriptions \
  -H "Authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' \
  -d '{"subscriptions":[{"id":"sub_1","provider":"claude","planName":"Pro","amountMinor":2000,"currency":"USD","startDate":"2026-05-31"}],"baseUpdatedAt":""}' | python3 -m json.tool
```

记下返回的 `updatedAt`，用错误 base 再写应得 409：

```bash
curl -s -o /dev/null -w "%{http_code}\n" -X PUT http://localhost:17322/api/subscriptions \
  -H "Authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' \
  -d '{"subscriptions":[],"baseUpdatedAt":"wrong"}'
# 期望: 409
```

### 7.8 SSE 流

```bash
curl -N http://localhost:17322/api/stats/stream -H "Authorization: Bearer $TOKEN"
```

应立即收到 `event: snapshot` 帧。保持挂着，另开终端再 ingest 一次，会看到 `event: stats` 实时推送。Ctrl+C 退出。

### 7.9 多租户隔离（可选，验证关键安全点）

注册第二个用户，用它的 token 上报同一个 deviceId，应得 403：

```bash
TOKEN2=$(curl -s -X POST http://localhost:17322/api/auth/register \
  -H 'content-type: application/json' \
  -d '{"email":"test2@example.com","password":"password123"}' | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")

curl -s -o /dev/null -w "%{http_code}\n" -X POST http://localhost:17322/api/ingest \
  -H "Authorization: Bearer $TOKEN2" \
  -H 'content-type: application/json' \
  -d '{"deviceId":"macbook","today":{"totalTokens":1}}'
# 期望: 403（device_ownership_conflict）
```

第二个用户看不到第一个用户的设备：

```bash
curl -s http://localhost:17322/api/stats -H "Authorization: Bearer $TOKEN2" | python3 -c "import sys,json;d=json.load(sys.stdin);print('devices:',len(d['devices']))"
# 期望: devices: 0
```

### 7.10 删除设备

```bash
curl -s -X DELETE http://localhost:17322/api/devices/macbook -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
```

### 7.11 跑测试套件（含真实 MySQL 的端到端）

```bash
cd /opt/ztoken-monitor/saas-hub
SAAS_HUB_DB_TEST=1 npm test
```

应全部通过（不再有 skip）。这一步会建一个 `token_monitor_saas_test` 临时库，测完自动清理。

## 8. 后台常驻（用 systemd）

验证通过后，配置开机自启和崩溃重启：

```bash
sudo tee /etc/systemd/system/saas-hub.service > /dev/null <<EOF
[Unit]
Description=ZT Monitor SaaS Hub
After=network.target mysql.service

[Service]
Type=simple
User=部署用户名
WorkingDirectory=/opt/ztoken-monitor/saas-hub
ExecStart=$(which node) src/server.js
Restart=on-failure
RestartSec=5
EnvironmentFile=/opt/ztoken-monitor/saas-hub/.env

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable saas-hub
sudo systemctl start saas-hub
sudo systemctl status saas-hub
```

查日志：

```bash
sudo journalctl -u saas-hub -f
```

## 9. 反向代理（可选，生产用 HTTPS）

```nginx
server {
    listen 443 ssl http2;
    server_name saas.your-domain.com;
    # ssl_certificate ...

    location / {
        proxy_pass http://127.0.0.1:17322;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        # SSE 关键：禁用缓冲，允许长连接
        proxy_buffering off;
        proxy_read_timeout 86400s;
    }
}
```

## 10. 防火墙

```bash
# 只放行需要的端口
sudo ufw allow 17322/tcp   # 或只放 nginx 的 443
```

---

## 常见问题

**Q: migrate 报 `Access denied`**
A: 检查 `.env` 里的 MySQL 用户密码，以及用户是否有 CREATE 权限。

**Q: 启动报 `SAAS_HUB_JWT_SECRET must be set`**
A: `.env` 没填 JWT 密钥，或 `.env` 不在 `saas-hub/` 目录下。

**Q: 接口测试报 `ECONNREFUSED`**
A: 服务没起来，或端口被占。`systemctl status saas-hub` 看日志。

**Q: SSE 收不到实时推送**
A: 如果走 nginx，确认 `proxy_buffering off` 和 `proxy_read_timeout` 足够长。

**Q: 想重置数据**
A: `npm run migrate` 是幂等的（CREATE IF NOT EXISTS）。要清空就 `DROP DATABASE token_monitor_saas` 后重跑 migrate。
