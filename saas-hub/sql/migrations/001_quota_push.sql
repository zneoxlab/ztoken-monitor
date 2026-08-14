-- 配额通知、推送安装与 Transactional Outbox。所有语句保持幂等，便于从没有
-- schema_migrations 的旧版安装升级；版本记录由 migrate.js 在事务结束后写入。

CREATE TABLE IF NOT EXISTS notification_rules (
  user_id BIGINT UNSIGNED NOT NULL,
  version INT NOT NULL DEFAULT 1,
  updated_at VARCHAR(40) NOT NULL DEFAULT '',
  rules_json JSON NOT NULL,
  row_updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id),
  CONSTRAINT fk_notification_rules_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS push_installations (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  installation_id VARCHAR(128) NOT NULL,
  platform VARCHAR(32) NOT NULL,
  provider VARCHAR(16) NOT NULL,
  environment VARCHAR(16) NOT NULL DEFAULT 'production',
  app_version VARCHAR(64) NOT NULL DEFAULT '',
  token_hash CHAR(64) NOT NULL,
  token_ciphertext TEXT NOT NULL,
  token_iv VARCHAR(64) NOT NULL,
  token_tag VARCHAR(64) NOT NULL,
  key_version SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  enabled TINYINT(1) NOT NULL DEFAULT 1,
  last_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_push_installations_user_installation (user_id, installation_id),
  UNIQUE KEY uk_push_installations_token_hash (token_hash),
  KEY idx_push_installations_user_enabled (user_id, enabled),
  CONSTRAINT fk_push_installations_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS quota_notification_state (
  state_key CHAR(64) NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  rule_id VARCHAR(128) NOT NULL,
  target_id VARCHAR(512) NOT NULL,
  window_id VARCHAR(128) NOT NULL,
  remaining_percent DECIMAL(7,3) NOT NULL,
  cycle_generation INT UNSIGNED NOT NULL DEFAULT 1,
  warning_sent TINYINT(1) NOT NULL DEFAULT 0,
  observed_at VARCHAR(40) NOT NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (state_key),
  KEY idx_quota_notification_state_user_rule (user_id, rule_id),
  CONSTRAINT fk_quota_notification_state_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS notification_events (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  event_id CHAR(36) NOT NULL,
  dedupe_key CHAR(64) NOT NULL,
  event_type VARCHAR(32) NOT NULL,
  payload_json JSON NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_notification_events_event_id (event_id),
  UNIQUE KEY uk_notification_events_user_dedupe (user_id, dedupe_key),
  KEY idx_notification_events_user_created (user_id, created_at),
  CONSTRAINT fk_notification_events_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS push_deliveries (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  event_id BIGINT UNSIGNED NOT NULL,
  installation_id BIGINT UNSIGNED NOT NULL,
  platform VARCHAR(32) NOT NULL,
  provider VARCHAR(16) NOT NULL,
  environment VARCHAR(16) NOT NULL,
  payload_json JSON NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'pending',
  attempts INT UNSIGNED NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  lease_until TIMESTAMP NULL DEFAULT NULL,
  lease_id CHAR(36) NULL DEFAULT NULL,
  last_error VARCHAR(512) NOT NULL DEFAULT '',
  sent_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_push_deliveries_event_installation (event_id, installation_id),
  KEY idx_push_deliveries_ready (status, next_attempt_at),
  CONSTRAINT fk_push_deliveries_event FOREIGN KEY (event_id) REFERENCES notification_events(id) ON DELETE CASCADE,
  CONSTRAINT fk_push_deliveries_installation FOREIGN KEY (installation_id) REFERENCES push_installations(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
