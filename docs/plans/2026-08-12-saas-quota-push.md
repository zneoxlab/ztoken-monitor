# SaaS 配额刷新与预警推送 Implementation Plan

**Goal:** 让 SaaS 用户在移动 App 被系统回收后，仍能按账户和所选额度窗口收到一次性的“刷新到 100%”与“剩余低于阈值”系统通知。

**Architecture:** 桌面端继续把额度快照写入 SaaS Hub；Hub 在用户级 MySQL 事务中更新设备、计算聚合额度、推进持久化状态机并写入事件/Transactional Outbox。同一个 Hub 进程内的后台 Push Worker 通过 Android FCM 与 iOS APNs 投递，移动端只负责规则配置、系统授权、令牌注册与通知跳转；自建 Hub 保留本地差分提醒作为回退。

**Tech Stack:** Node.js 22、原生 `node:http`、MySQL 8、FCM HTTP v1、APNs HTTP/2、Flutter/Riverpod/Dio、Android Firebase Messaging、iOS UserNotifications/APNs。

---

## 兼容与安全边界

- 所有新 wire 字段均为可选新增，旧桌面端和旧移动端仍可读取现有统计。
- SaaS 通知规则以“剩余百分比”存储，不受 UI 的“剩余/已用”显示模式影响。
- 第一版只支持百分比额度窗口；`metric=credits` 等余额窗口不进入百分比预警。
- 首次观测只建立基线。刷新严格为 `previousRemaining < 100 && currentRemaining == 100`；预警严格为 `previousRemaining > threshold && currentRemaining <= threshold`。
- 事件在数据库内 exactly-once，外部推送按 at-least-once 处理，移动端用 `eventId` 去重。
- 推送令牌使用独立 32 字节服务端密钥 AES-256-GCM 加密，日志、SSE、统计响应均不得包含令牌。
- 当前工作区含用户未提交的移动端通知/显示模式改动；只做增量修改，不还原、不提交这些既有修改。

### Task 1: 建立版本化数据库迁移

**Files:**
- Create: `saas-hub/sql/migrations/001_quota_push.sql`
- Modify: `saas-hub/scripts/migrate.js`
- Test: `saas-hub/tests/db.test.js`

**Steps:**

1. 写失败测试，验证 migration runner 会创建并记录 `schema_migrations`，同一文件不会重复运行。
2. 创建通知规则、安装、状态、事件、投递五类表，所有表用 `user_id` 外键隔离；事件与投递建立唯一业务键。
3. 将 `migrate.js` 改为先重放基础 `schema.sql`，再按文件名顺序执行未应用迁移；SQL 注释先按行移除再分句。
4. 运行 `cd saas-hub && npm test`，预期全部通过；设置 `SAAS_HUB_DB_TEST=1` 时额外验证真实 MySQL。

### Task 2: 实现规则文档、目标解析与配额状态机

**Files:**
- Create: `saas-hub/src/notificationRules.js`
- Create: `saas-hub/src/quotaNotifications.js`
- Create: `saas-hub/tests/notificationRules.test.js`
- Create: `saas-hub/tests/quotaNotifications.test.js`

**Steps:**

1. 写首样本、`99→100`、`100→100`、阈值首次跨越、刷新后重新预警、窗口多选、规则变更重建基线、乱序快照和 credits 排除测试。
2. 规则规范形态为：

   ```json
   {
     "id": "客户端生成的稳定规则 ID",
     "targetId": "服务端下发的账户目标 ID",
     "enabled": true,
     "refreshEnabled": true,
     "warningEnabled": true,
     "thresholdPercent": 20,
     "windowIds": ["session", "weekly"]
   }
   ```

3. `buildNotificationTargets(limits)` 只暴露当前可配置的百分比窗口及稳定 ID；缺新协议字段时提供显式 `legacy` 回退。
4. `evaluateQuotaRules()` 输出新状态与候选事件，不访问数据库、网络或当前时间之外的全局状态。
5. 运行 `cd saas-hub && node --test tests/notificationRules.test.js tests/quotaNotifications.test.js`，预期全部通过。

### Task 3: 把状态机接入 Hub 的原子 ingest

**Files:**
- Modify: `saas-hub/src/db.js`
- Modify: `saas-hub/src/hub.js`
- Modify: `saas-hub/tests/hub.test.js`
- Create: `saas-hub/tests/notificationDb.test.js`

**Steps:**

1. 写失败测试，模拟同用户并发上报，断言同一业务事件只生成一次。
2. 增加 `withTransaction`、用户行锁、规则/状态/事件/安装/投递 CRUD；所有函数同时接受 pool 或 transaction connection。
3. `ingest` 在一笔事务中锁定用户，读取并合并设备，聚合最终 stats，推进规则状态，并通过唯一 dedupe key 写事件及每安装一条 delivery。
4. 事务提交后才广播 SSE；stats 增加可选 `notificationRulesUpdatedAt`，不携带规则正文。
5. 运行 Hub 单元测试与可选 MySQL 集成测试。

### Task 4: 增加 JWT 保护的通知 API

**Files:**
- Modify: `saas-hub/src/routes/api.js`
- Modify: `saas-hub/src/hub.js`
- Create: `saas-hub/src/pushTokenCrypto.js`
- Create: `saas-hub/tests/pushInstallations.test.js`
- Modify: `saas-hub/tests/api.test.js`
- Modify: `saas-hub/tests/server.test.js`

**Steps:**

1. 实现 `GET /api/notification-targets`、`GET/PUT /api/notification-rules`、`PUT/DELETE /api/push/installations/:installationId`。
2. 规则 PUT 使用 `baseUpdatedAt` 乐观并发，冲突返回 `409 stale_write`；成功后清理旧规则状态并广播版本戳。
3. 安装注册只从 JWT 读取用户；校验 UUID、platform/provider/token；同一 token 或 installationId 再注册时原子转绑。
4. 用独立环境密钥加密 token 并存 HMAC hash；缺少密钥时注册端点返回明确的 `push_not_configured`，不保存明文。
5. 测试用户隔离、令牌轮换、账号切换、撤销、无密钥和非法输入。

### Task 5: 实现独立 Push Worker 与 provider adapters

**Files:**
- Create: `saas-hub/src/push/deliveryWorker.js`
- Create: `saas-hub/src/push/fcmProvider.js`
- Create: `saas-hub/src/push/apnsProvider.js`
- Create: `saas-hub/src/push-worker.js`
- Create: `saas-hub/tests/outboxWorker.test.js`
- Create: `saas-hub/tests/fcmProvider.test.js`
- Create: `saas-hub/tests/apnsProvider.test.js`
- Modify: `saas-hub/src/config.js`
- Modify: `saas-hub/package.json`
- Modify: `saas-hub/.env.example`

**Steps:**

1. 写 provider mock 测试和投递租赁/重试/失效令牌测试。
2. FCM adapter 用 Service Account RS256 JWT 换短期 OAuth2 token，再调用 HTTP v1；不增加 Node 依赖。
3. APNs adapter 用 ES256 `.p8` 生成短期 JWT，经 `node:http2` 投递 `alert`；区分 sandbox/production token。
4. Worker 批量租赁到期投递，成功标记 sent，可重试错误指数退避，无效 token 撤销安装；达到最大次数标记 failed。
5. `npm start` 启动 HTTP 服务时，在同一进程内启动后台 Worker；保留 `npm run push-worker` 作为需要独立扩容时的可选入口。

### Task 6: 增加稳定账户/窗口标识协议

**Files:**
- Modify: `src/shared/limits.js`
- Modify: relevant provider collectors under `src/shared/*Limits.js` and `src/shared/limitCollector.js`
- Modify: `tests/shared/limits.test.js`
- Modify: relevant provider tests under `tests/shared/`
- Modify: `docs/API.md`
- Generate: `worker/src/shared/limits.js`

**Steps:**

1. 测试 `accountIdentity/windowId/cycleId` 的规范化、跨设备聚合、旧 payload 兼容和 public stats 脱敏。
2. `accountIdentity` 仅在 provider 有跨设备主体时生成；无法可靠获得时保留旧 `accountKey` 回退，禁止凭 label 猜账户。
3. provider 显式提供稳定 `windowId`；`cycleId` 只在上游有真实周期 ID 时提供。
4. 运行 `npm run sync:worker`，再运行 shared tests，确认生成副本无漂移。

### Task 7: 实现移动端规则模型、Repository 与 SaaS/本地模式切换

**Files:**
- Create: `app/lib/core/notifications/notification_models.dart`
- Create: `app/lib/core/notifications/notification_rules_repository.dart`
- Create: `app/lib/core/notifications/push_lifecycle.dart`
- Modify: `app/lib/core/network/stats_repository.dart`
- Modify: `app/lib/core/models/stats.dart`
- Modify: `app/lib/core/notifications/quota_notification.dart`
- Modify: `app/lib/core/notifications/quota_notification_service.dart`
- Test: `app/test/core/notifications/`

**Steps:**

1. 写 API JSON、规则冲突、本地正确边界和 SaaS 禁止本地双通知测试。
2. SaaS 模式从服务端读取/保存规则；self-hosted 模式保留本地差分，修正为严格刷新/阈值语义。
3. 权限只在用户首次成功保存启用规则后申请；拒绝不阻断规则保存，并允许以后重新检查。
4. installationId 存安全存储；登录/启动/token refresh 幂等注册，登出前尽力撤销。

### Task 8: 在配额页增加按账户通知设置

**Files:**
- Create: `app/lib/features/limits/widgets/quota_notification_settings.dart`
- Modify: `app/lib/features/limits/limits_page.dart`
- Modify: `app/lib/features/limits/widgets/limits_provider_card.dart`
- Modify: `app/lib/features/me/me_page.dart`
- Test: `app/test/core/notifications/quota_notification_settings_test.dart`

**Steps:**

1. 每个账户卡增加“通知设置”；只列出该账户当前支持的百分比窗口，可多选。
2. 提供总开关、刷新通知开关、额度预警开关和剩余阈值；阈值文案始终明确为“剩余”。
3. 保存中禁用重复提交；`409` 时提示重新加载，不静默覆盖别的设备修改。
4. 删除“我的”页面旧全局通知配置，保留显示模式配置。
5. 覆盖小屏、放大字体、无可配置窗口、权限拒绝和离线错误测试。

### Task 9: 接入 Android FCM 与 iOS APNs

**Files:**
- Modify: `app/android/app/build.gradle.kts`
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Modify: `app/android/app/src/main/kotlin/com/zneox/ztoken/ztoken_monitor/MainActivity.kt`
- Create: `app/android/app/src/main/kotlin/com/zneox/ztoken/ztoken_monitor/QuotaFirebaseMessagingService.kt`
- Modify: `app/ios/Runner/AppDelegate.swift`
- Create: `app/ios/Runner/Runner.entitlements`
- Modify: `app/ios/Runner.xcodeproj/project.pbxproj`
- Modify: `app/lib/core/router.dart`

**Steps:**

1. Android 使用原生 Firebase Messaging SDK；Firebase 配置由未提交的本机/CI 配置注入，缺配置时 App 可构建但注册返回 unavailable。
2. iOS 请求权限后调用 `registerForRemoteNotifications()`，把 APNs token、sandbox/production 环境传给 Flutter。
3. 两端 MethodChannel 统一提供权限、token、初始通知事件和运行中点击事件；数据仅含 `eventId/targetId/windowId/route`。
4. 通知点击进入 `/limits`；重复 `eventId` 不重复处理。
5. Android/Harmony 无对应原生能力时安全降级，不让启动白屏。

### Task 10: 运维、文档与全量验证

**Files:**
- Modify: `saas-hub/README.md`
- Modify: `saas-hub/DEPLOY.md`
- Modify: `saas-hub/DOCKER.md`
- Modify: relevant privacy/help copy in `app/`

**Steps:**

1. 记录 Firebase/APNs 凭证、加密密钥、单服务部署、最小出网、轮换与回滚步骤；不提交真实凭证。
2. 记录第一版 FCM 不覆盖无 GMS/HarmonyOS 设备的限制。
3. 运行：

   ```bash
   cd saas-hub && npm run verify
   cd .. && npm run sync:worker && npm run verify
   cd app && flutter analyze && flutter test
   ```

4. 构建 Android debug 与 iOS simulator（无签名）验证；无真实 FCM/APNs 凭证时只声明本地构建与 mock provider 通过，不宣称真机推送成功。
5. 检查 `git diff`，确认没有真实 token、Service Account、`.p8`、`google-services.json` 或用户无关改动。

## 完成标准

- App 退出后，已注册设备能由 FCM/APNs 收到服务端生成的配额通知。
- 每个额度账户可独立开启通知、设置剩余阈值并多选其支持窗口。
- 首样本不通知，`<100→100` 刷新一次，`>阈值→<=阈值` 预警一次，重复快照不重复。
- Hub 重启或 App 重启不破坏一次性语义；同一用户并发 ingest 不重复创建事件。
- SaaS 与本地 fallback 不对同一变化双重通知。
- 所有自动化检查通过；真实端到端推送需在凭证和签名配置完成后用真机验收。
