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
