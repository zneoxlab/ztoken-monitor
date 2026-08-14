'use strict';

// 兼容曾经试运行过早期 001 的数据库。001 现已冻结为完整新安装基线；
// 002 用 information_schema 条件式补齐后续运行时字段，避免重复 ALTER 报错。

async function columnNames(conn, tableName) {
  const [rows] = await conn.execute(
    `SELECT COLUMN_NAME AS columnName
     FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :tableName`,
    { tableName }
  );
  return new Set(rows.map((row) => row.columnName));
}

async function indexNames(conn, tableName) {
  const [rows] = await conn.execute(
    `SELECT DISTINCT INDEX_NAME AS indexName
     FROM information_schema.STATISTICS
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :tableName`,
    { tableName }
  );
  return new Set(rows.map((row) => row.indexName));
}

async function addMissingColumns(conn, tableName, definitions) {
  const existing = await columnNames(conn, tableName);
  let applied = 0;
  for (const [name, definition] of Object.entries(definitions)) {
    if (existing.has(name)) continue;
    await conn.query(`ALTER TABLE \`${tableName}\` ADD COLUMN \`${name}\` ${definition}`);
    applied += 1;
  }
  return applied;
}

async function primaryKeyColumns(conn, tableName) {
  const [rows] = await conn.execute(
    `SELECT COLUMN_NAME AS columnName
     FROM information_schema.STATISTICS
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :tableName
       AND INDEX_NAME = 'PRIMARY'
     ORDER BY SEQ_IN_INDEX`,
    { tableName }
  );
  return rows.map((row) => row.columnName);
}

async function up(conn) {
  let applied = 0;
  const legacyDeliveryColumns = await columnNames(conn, 'push_deliveries');
  applied += await addMissingColumns(conn, 'push_installations', {
    provider: "VARCHAR(16) NOT NULL DEFAULT 'fcm' AFTER platform",
    environment: "VARCHAR(16) NOT NULL DEFAULT 'production' AFTER provider",
    app_version: "VARCHAR(64) NOT NULL DEFAULT '' AFTER environment",
    // 早期 001 曾把密文列放在 delivery 表。旧安装当时无法成功注册 token，
    // 所以这里补空默认值即可；下一次 App 注册会原子写入真实密文。
    token_ciphertext: 'TEXT NULL AFTER token_hash',
    token_iv: "VARCHAR(64) NOT NULL DEFAULT '' AFTER token_ciphertext",
    token_tag: "VARCHAR(64) NOT NULL DEFAULT '' AFTER token_iv",
    key_version: 'SMALLINT UNSIGNED NOT NULL DEFAULT 1 AFTER token_tag',
    enabled: 'TINYINT(1) NOT NULL DEFAULT 1 AFTER key_version'
  });
  if (legacyDeliveryColumns.has('token_ciphertext') &&
      legacyDeliveryColumns.has('token_iv') &&
      legacyDeliveryColumns.has('token_tag')) {
    // 把早期 Outbox 中冻结的最新密文尽量迁回 installation；没有历史 delivery
    // 的旧安装会在下方禁用，待 App 再次注册后恢复，绝不尝试发送空 token。
    await conn.query(
      `UPDATE push_installations i
       JOIN push_deliveries d ON d.id = (
         SELECT MAX(latest.id)
         FROM push_deliveries latest
         WHERE latest.installation_id = i.id
       )
       SET i.token_ciphertext = d.token_ciphertext,
           i.token_iv = d.token_iv,
           i.token_tag = d.token_tag,
           i.key_version = d.key_version,
           i.provider = d.provider,
           i.environment = d.environment
       WHERE i.token_ciphertext IS NULL OR i.token_iv = '' OR i.token_tag = ''`
    );
  }
  await conn.query(
    `UPDATE push_installations
     SET enabled = 0
     WHERE token_ciphertext IS NULL OR token_ciphertext = '' OR token_iv = '' OR token_tag = ''`
  );
  await conn.query(
    "UPDATE push_installations SET token_ciphertext = '' WHERE token_ciphertext IS NULL"
  );
  await conn.query('ALTER TABLE push_installations MODIFY token_ciphertext TEXT NOT NULL');
  applied += await addMissingColumns(conn, 'quota_notification_state', {
    state_key: "CHAR(64) NULL AFTER user_id",
    cycle_generation: 'INT UNSIGNED NOT NULL DEFAULT 1 AFTER remaining_percent',
    warning_sent: 'TINYINT(1) NOT NULL DEFAULT 0 AFTER cycle_generation'
  });
  const stateColumns = await columnNames(conn, 'quota_notification_state');
  if (stateColumns.has('state_key')) {
    await conn.query(
      `UPDATE quota_notification_state
       SET state_key = SHA2(CONCAT_WS(CHAR(0), user_id, rule_id, target_id, window_id), 256)
       WHERE state_key IS NULL OR state_key = ''`
    );
    // 旧复合主键是 user_id 外键唯一可用的前缀索引。必须先补独立索引，
    // InnoDB 才允许把该主键替换为固定长度 state_key。
    const indexesBeforePrimaryChange = await indexNames(conn, 'quota_notification_state');
    if (!indexesBeforePrimaryChange.has('idx_quota_notification_state_user_rule')) {
      await conn.query(
        'ALTER TABLE quota_notification_state ADD INDEX idx_quota_notification_state_user_rule (user_id, rule_id)'
      );
      applied += 1;
    }
    const primaryColumns = await primaryKeyColumns(conn, 'quota_notification_state');
    if (primaryColumns.join(',') !== 'state_key') {
      await conn.query(
        'ALTER TABLE quota_notification_state DROP PRIMARY KEY, ADD PRIMARY KEY (state_key)'
      );
      applied += 1;
    }
    await conn.query('ALTER TABLE quota_notification_state MODIFY state_key CHAR(64) NOT NULL');
  }
  applied += await addMissingColumns(conn, 'push_deliveries', {
    provider: "VARCHAR(16) NOT NULL DEFAULT 'fcm' AFTER platform",
    environment: "VARCHAR(16) NOT NULL DEFAULT 'production' AFTER provider",
    lease_id: 'CHAR(36) NULL DEFAULT NULL AFTER lease_until'
  });
  const obsoleteDeliveryColumns = [
    'token_ciphertext', 'token_iv', 'token_tag', 'key_version'
  ].filter((name) => legacyDeliveryColumns.has(name));
  for (const name of obsoleteDeliveryColumns) {
    await conn.query(`ALTER TABLE push_deliveries DROP COLUMN \`${name}\``);
    applied += 1;
  }
  const indexes = await indexNames(conn, 'push_installations');
  if (!indexes.has('idx_push_installations_user_enabled')) {
    await conn.query(
      'ALTER TABLE push_installations ADD INDEX idx_push_installations_user_enabled (user_id, enabled)'
    );
    applied += 1;
  }
  const stateIndexes = await indexNames(conn, 'quota_notification_state');
  if (!stateIndexes.has('idx_quota_notification_state_user_rule')) {
    await conn.query(
      'ALTER TABLE quota_notification_state ADD INDEX idx_quota_notification_state_user_rule (user_id, rule_id)'
    );
    applied += 1;
  }
  return applied;
}

module.exports = {
  up,
  columnNames,
  indexNames,
  primaryKeyColumns,
  addMissingColumns
};
