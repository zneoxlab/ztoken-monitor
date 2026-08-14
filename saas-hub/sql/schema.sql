-- SaaS Hub 数据库表结构
-- 多租户：所有数据按 user_id 隔离。设备首次上报自动绑定到 JWT 里的 userId。

-- 用户表：邮箱+密码登录
CREATE TABLE IF NOT EXISTS users (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  email           VARCHAR(255) NOT NULL,
  password_hash   VARBINARY(255) NOT NULL,        -- scrypt 输出，64 字节
  password_salt   VARBINARY(32) NOT NULL,          -- scrypt salt，16 字节
  created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_users_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 设备记录表：每条记录属于一个用户
-- device_id 由 widget 端生成，跨用户可能相同；联合唯一键 (user_id, device_id) 定位记录
-- payload_json 存完整 device record（today/month/allTime/limits/history + 可选字段）
-- 读出时合并顶层列 + payload_json 全部键，确保 mergeDeviceRecord 读到的 existing 不丢字段
CREATE TABLE IF NOT EXISTS devices (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id         BIGINT UNSIGNED NOT NULL,
  device_id       VARCHAR(128) NOT NULL,
  hostname        VARCHAR(255) NOT NULL DEFAULT '',
  platform        VARCHAR(64)  NOT NULL DEFAULT '',
  agent_version   VARCHAR(64)  NOT NULL DEFAULT '',
  agent_runtime   VARCHAR(64)  NOT NULL DEFAULT '',
  payload_json    JSON NOT NULL,
  updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  received_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_devices_user_device (user_id, device_id),
  KEY idx_devices_device_id (device_id),
  CONSTRAINT fk_devices_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 订阅文档表：每用户一份（订阅描述账号而非机器，全 hub 共享一份）
-- updated_at 是乐观并发令牌：必须 VARCHAR 存原 ISO 字符串，不能用 TIMESTAMP
-- （isStaleSubscriptionWrite 做严格字符串相等，时区转换会破坏相等性；空串代表"首次写入"）
CREATE TABLE IF NOT EXISTS subscriptions (
  user_id           BIGINT UNSIGNED NOT NULL,
  version           INT NOT NULL DEFAULT 1,
  updated_at        VARCHAR(40) NOT NULL DEFAULT '',
  subscriptions_json JSON NOT NULL,
  row_updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id),
  CONSTRAINT fk_subs_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 已应用的增量迁移。schema.sql 是新安装的完整基线；migrate.js 仍会按此表
-- 给旧安装补齐每个版本的变更，避免把生产升级依赖在手工执行上。
CREATE TABLE IF NOT EXISTS schema_migrations (
  version           VARCHAR(128) NOT NULL,
  applied_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 每用户一份配额通知规则文档。updated_at 是严格比较的 ISO 字符串，语义与
-- subscriptions.updated_at 相同，避免数据库时区/精度改变乐观并发令牌。
CREATE TABLE IF NOT EXISTS notification_rules (
  user_id           BIGINT UNSIGNED NOT NULL,
  version           INT NOT NULL DEFAULT 1,
  updated_at        VARCHAR(40) NOT NULL DEFAULT '',
  rules_json        JSON NOT NULL,
  row_updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id),
  CONSTRAINT fk_notification_rules_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 一个 App 安装对应一条可轮换的系统推送令牌。明文 token 永不落库；
-- token_hash 用于幂等更新和将同一安装令牌从旧账号原子转移到新账号。
CREATE TABLE IF NOT EXISTS push_installations (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id           BIGINT UNSIGNED NOT NULL,
  installation_id   VARCHAR(128) NOT NULL,
  platform          VARCHAR(32) NOT NULL,
  provider          VARCHAR(16) NOT NULL,
  environment       VARCHAR(16) NOT NULL DEFAULT 'production',
  app_version       VARCHAR(64) NOT NULL DEFAULT '',
  token_hash        CHAR(64) NOT NULL,
  token_ciphertext  TEXT NOT NULL,
  token_iv          VARCHAR(64) NOT NULL,
  token_tag         VARCHAR(64) NOT NULL,
  key_version       SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  enabled           TINYINT(1) NOT NULL DEFAULT 1,
  last_seen_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_push_installations_user_installation (user_id, installation_id),
  UNIQUE KEY uk_push_installations_token_hash (token_hash),
  KEY idx_push_installations_user_enabled (user_id, enabled),
  CONSTRAINT fk_push_installations_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 每条规则/目标窗口的上次观测。首次观测仅建基线；随后由这个持久状态保证
-- 刷新和预警在重启、并发 ingest 后都只创建一次业务事件。
CREATE TABLE IF NOT EXISTS quota_notification_state (
  state_key         CHAR(64) NOT NULL,
  user_id           BIGINT UNSIGNED NOT NULL,
  rule_id           VARCHAR(128) NOT NULL,
  target_id         VARCHAR(512) NOT NULL,
  window_id         VARCHAR(128) NOT NULL,
  remaining_percent DECIMAL(7,3) NOT NULL,
  cycle_generation  INT UNSIGNED NOT NULL DEFAULT 1,
  warning_sent      TINYINT(1) NOT NULL DEFAULT 0,
  observed_at       VARCHAR(40) NOT NULL,
  updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (state_key),
  KEY idx_quota_notification_state_user_rule (user_id, rule_id),
  CONSTRAINT fk_quota_notification_state_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 业务事件先落库，再由独立推送 worker 发送。dedupe_key 仅保证同一用户下的
-- 同一次阈值跨越不会重复入队；外部推送仍是至少一次，客户端以 eventId 去重。
CREATE TABLE IF NOT EXISTS notification_events (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id           BIGINT UNSIGNED NOT NULL,
  event_id          CHAR(36) NOT NULL,
  dedupe_key        CHAR(64) NOT NULL,
  event_type        VARCHAR(32) NOT NULL,
  payload_json      JSON NOT NULL,
  created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_notification_events_event_id (event_id),
  UNIQUE KEY uk_notification_events_user_dedupe (user_id, dedupe_key),
  KEY idx_notification_events_user_created (user_id, created_at),
  CONSTRAINT fk_notification_events_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Outbox 对每个启用安装冻结可发送 payload，并通过 installation_id 回查当前
-- 加密 token。这样令牌轮换不会让旧任务继续发送到失效 token，注销会级联取消。
CREATE TABLE IF NOT EXISTS push_deliveries (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  event_id          BIGINT UNSIGNED NOT NULL,
  installation_id   BIGINT UNSIGNED NOT NULL,
  platform          VARCHAR(32) NOT NULL,
  provider          VARCHAR(16) NOT NULL,
  environment       VARCHAR(16) NOT NULL,
  payload_json      JSON NOT NULL,
  status            VARCHAR(16) NOT NULL DEFAULT 'pending',
  attempts          INT UNSIGNED NOT NULL DEFAULT 0,
  next_attempt_at   TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  lease_until       TIMESTAMP NULL DEFAULT NULL,
  lease_id          CHAR(36) NULL DEFAULT NULL,
  last_error        VARCHAR(512) NOT NULL DEFAULT '',
  sent_at           TIMESTAMP NULL DEFAULT NULL,
  created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_push_deliveries_event_installation (event_id, installation_id),
  KEY idx_push_deliveries_ready (status, next_attempt_at),
  CONSTRAINT fk_push_deliveries_event FOREIGN KEY (event_id) REFERENCES notification_events(id) ON DELETE CASCADE,
  CONSTRAINT fk_push_deliveries_installation FOREIGN KEY (installation_id) REFERENCES push_installations(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
