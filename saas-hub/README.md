# ZT Monitor SaaS Hub

多租户 SaaS hub 服务：支持用户登录（邮箱+密码+JWT），多设备 token 用量同步聚合，按用户隔离数据。

整体同步合并逻辑复用主项目 `src/shared/` 的纯函数（`aggregateDevices`/`mergeDeviceRecord`/`subscriptionDocument` 等），协议与现有自托管 node hub（`src/hub/server.js`）逐字段对齐，仅鉴权头从 `Bearer <secret>` 换成 `Bearer <JWT>`。

## 与现有 hub 的关系

| hub 形态 | 位置 | 租户 | 存储 | 鉴权 |
|---|---|---|---|---|
| 自托管 Node hub | `src/hub/server.js` | 单租户 | `devices.json` | 共享 secret |
| Cloudflare Worker hub | `worker/` | 单租户 | Durable Object | 共享 secret |
| **SaaS hub（本项目）** | `saas-hub/` | **多租户** | **MySQL** | **JWT** |

## 快速开始

```bash
cd saas-hub
cp .env.example .env          # 填写 SAAS_HUB_JWT_SECRET 和 MySQL 凭据
npm install
npm run migrate               # 建库 + 建表
npm start                     # 默认监听 :17322
```

生成 JWT 密钥：`openssl rand -hex 32`

## API

### 认证（不鉴权）
- `POST /api/auth/register` — `{email, password}` → `{ok, token, refreshToken, user:{id, email}}`
- `POST /api/auth/login` — `{email, password}` → `{ok, token, refreshToken, user:{id, email}}`
- `POST /api/auth/refresh` — `{refreshToken}` → `{ok, token, refreshToken}`（滚动续期，换发新 access + 新 refresh）

### 数据接口（需 `Authorization: Bearer <JWT>`）
与现有 node hub 协议一致：
- `POST /api/ingest` — 上报用量，设备首次上报自动绑定到当前用户
- `GET /api/stats` — 聚合统计（仅当前用户的设备）
- `GET /api/stats/stream` — SSE 流，仅推送当前用户的变更
- `GET /api/devices` / `GET /api/history` — 设备列表 / 历史序列
- `GET` / `PUT /api/subscriptions` — 订阅列表读写（PUT 带 `baseUpdatedAt` 乐观并发）
- `DELETE /api/devices/:id` — 删除设备（只能删自己的）
- `GET /api/health` — 健康检查（不鉴权）

## 多租户隔离

- 每条设备记录带 `user_id`，聚合时只算该用户的设备
- 设备首次上报时，hub 从 JWT 解出 userId 自动绑定
- 若 deviceId 已绑定到其他用户，再次上报返回 403 `device_ownership_conflict`
- SSE 帧只推送给该用户自己的连接

## 测试

```bash
npm test                       # node:test
npm run verify                 # lint + test
```

`db.test.js` 和 `server.test.js` 需要可用的 MySQL 实例。可用 docker 起一个：
```bash
docker run -d --name saas-hub-mysql -e MYSQL_ROOT_PASSWORD=test -p 3306:3306 mysql:8
```

## 技术栈

- 原生 `node:http`（与现有 hub 一致，零 web 框架依赖）
- MySQL + `mysql2`（手写 SQL）
- JWT：`jsonwebtoken`
- 密码哈希：Node 内置 `crypto.scrypt`
- Redis：Phase 1 不引入（单实例内存即可），Phase 2 多实例时引入做跨实例广播

## 不在 Phase 1 范围

- widget 端 SaaS 模式接入（Phase 2）
- Redis 多实例广播 / JWT 黑名单 / 分布式锁（Phase 2）
- 登录限流 / 管理后台 UI
