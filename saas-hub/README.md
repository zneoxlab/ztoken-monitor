# ZT Monitor SaaS Hub

多租户 SaaS hub 服务：支持用户登录（邮箱+密码+JWT）、多设备 token 用量同步聚合，以及 App 退出后仍可送达的配额刷新/低额度系统通知。

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
npm start                     # 默认监听 :8787；推送 Worker 会在同一进程内后台启动
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
- `GET /api/notification-targets` — 当前账户实际支持的百分比额度窗口
- `GET` / `PUT /api/notification-rules` — 按账户配置刷新通知、剩余阈值和窗口多选
- `PUT` / `DELETE /api/push/installations/:installationId` — 注册、轮换或撤销系统推送令牌
- `DELETE /api/devices/:id` — 删除设备（只能删自己的）
- `GET /api/health` — 健康检查（不鉴权）

## 多租户隔离

- 每条设备记录带 `user_id`，聚合时只算该用户的设备
- 设备首次上报时，hub 从 JWT 解出 userId 自动绑定；同一 `deviceId` 在不同用户下各自独立（按 `user_id + device_id` 查找与更新）
- SSE 帧只推送给该用户自己的连接
- 推送令牌使用独立服务端密钥 AES-256-GCM 加密；JWT 用户身份是安装绑定的唯一来源

## 配额推送

- 首次快照只建基线；只有剩余 `<100% → 100%` 才算刷新。
- 预警只在剩余第一次从阈值上方进入阈值及以下时发送；同周期额度反弹不会重新预警，刷新后才重新启用。
- SaaS Hub 在同一 MySQL 事务写入状态、事件和 Outbox；同一个 Hub 进程内的后台 Worker 再调用 Android FCM 或 iOS APNs，HTTP ingest 不等待外部推送。
- 第一版只覆盖 iOS 与有 Google Play 服务的 Android。无 GMS Android 和 HarmonyOS 暂无远端推送，App 仍可安全使用其它功能。
- 不要把 `google-services.json`、Firebase Service Account JSON、Apple `.p8` 或任何真实令牌提交到仓库。

完整凭证和单服务部署见 `DEPLOY.md`。`npm run push-worker` 仅保留给需要单独扩容 Worker 的高级部署，不是普通部署步骤。

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

- Redis 多实例广播 / JWT 黑名单 / 分布式锁（Phase 2）
- 登录限流 / 管理后台 UI
- HarmonyOS/Huawei Push Kit 与无 GMS 厂商推送
