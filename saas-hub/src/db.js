'use strict';

// 数据访问层：mysql2 连接池 + users/devices/subscriptions 的 CRUD
// 纯数据访问，不含业务逻辑。业务在 hub.js。
//
// 关键设计：devices.payload_json 存完整 device record（mergeDeviceRecord 的输出），
// 读出时 JSON.parse 后即得到 normalizeDeviceRecord 期望的输入形状（顶层 today/month/allTime
// + limits + history + 可选字段）。顶层列（hostname/platform/agent_version 等）只用于查询/索引，
// 读出时合并进对象但以 payload_json 为准（payload_json 是合并后的最新值）。

const mysql = require('mysql2/promise');
const crypto = require('node:crypto');
const { emptySubscriptionDocument } = require('../../src/shared/subscriptionDisplay');

// ---- 连接池 ----

function createPool(mysqlConfig) {
  // connectionUri（DSN）或分字段两种形态
  const opts = mysqlConfig.connectionUri
    ? { uri: mysqlConfig.connectionUri }
    : {
        host: mysqlConfig.host,
        port: mysqlConfig.port,
        user: mysqlConfig.user,
        password: mysqlConfig.password,
        database: mysqlConfig.database
      };
  return mysql.createPool({
    ...opts,
    connectionLimit: mysqlConfig.connectionLimit || 10,
    charset: 'utf8mb4',
    // namedPlaceholders 让我们用 :name 占位符，更安全可读
    namedPlaceholders: true
  });
}

// 把一组读写锁进同一 MySQL 事务。通知状态、事件和 Outbox 必须一起提交：
// 否则请求在中途失败时会出现“状态已越过阈值但没有可发送事件”的永久漏报。
async function withTransaction(pool, fn) {
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const result = await fn(connection);
    await connection.commit();
    return result;
  } catch (error) {
    try { await connection.rollback(); } catch (_) {}
    throw error;
  } finally {
    connection.release();
  }
}

// ---- users ----

async function createUser(pool, { email, passwordHash, passwordSalt }) {
  const [result] = await pool.execute(
    'INSERT INTO users (email, password_hash, password_salt) VALUES (:email, :hash, :salt)',
    { email, hash: passwordHash, salt: passwordSalt }
  );
  return { id: result.insertId, email };
}

async function findUserByEmail(pool, email) {
  const [rows] = await pool.execute(
    'SELECT id, email, password_hash AS passwordHash, password_salt AS passwordSalt FROM users WHERE email = :email LIMIT 1',
    { email }
  );
  return rows[0] || null;
}

async function findUserById(pool, id) {
  const [rows] = await pool.execute(
    'SELECT id, email FROM users WHERE id = :id LIMIT 1',
    { id }
  );
  return rows[0] || null;
}

// 事务中的用户级互斥锁。设备 upsert、聚合、额度状态机和 Outbox 都在取得
// 同一用户行锁后执行，避免两台设备并发 ingest 时基于不同快照重复判定。
async function lockUserForUpdate(pool, userId) {
  const [rows] = await pool.execute(
    'SELECT id FROM users WHERE id = :userId FOR UPDATE',
    { userId }
  );
  return Boolean(rows[0]);
}

// ---- devices ----

// 把 device record 拆成顶层列 + payload_json 写入。
// payload_json 存完整 record（含 today/month/allTime/limits/history 及所有可选字段），
// 顶层列只存便于查询的标量字段。
function serializeDevice(record) {
  return {
    device_id: String(record.deviceId || record.id || ''),
    hostname: String(record.hostname || ''),
    platform: String(record.platform || ''),
    agent_version: String(record.agentVersion || ''),
    agent_runtime: String(record.agentRuntime || ''),
    payload: JSON.stringify(record)
  };
}

// 读出后还原成 normalizeDeviceRecord 期望的输入形状。
// payload_json 是合并后的完整 record，直接 parse 即可；顶层列已被包含在 payload 里，无需再合并。
function deserializeDevice(row) {
  if (!row) return null;
  const record = typeof row.payload_json === 'string' ? JSON.parse(row.payload_json) : row.payload_json;
  return record;
}

// 列出某用户的所有设备（用于 aggregateDevices 聚合）
async function listDevicesByUser(pool, userId) {
  const [rows] = await pool.execute(
    'SELECT payload_json FROM devices WHERE user_id = :userId',
    { userId }
  );
  return rows.map(deserializeDevice);
}

// 取某用户的某设备（用于 ingest 时 merge 的 existing；按 user_id + device_id）
async function getDevice(pool, userId, deviceId) {
  const [rows] = await pool.execute(
    'SELECT payload_json FROM devices WHERE user_id = :userId AND device_id = :deviceId LIMIT 1',
    { userId, deviceId }
  );
  return rows[0] ? deserializeDevice(rows[0]) : null;
}

// upsert：INSERT ... ON DUPLICATE KEY UPDATE（联合唯一键 user_id+device_id）
async function upsertDevice(pool, userId, record) {
  const s = serializeDevice(record);
  await pool.execute(
    `INSERT INTO devices (user_id, device_id, hostname, platform, agent_version, agent_runtime, payload_json, received_at)
     VALUES (:userId, :device_id, :hostname, :platform, :agent_version, :agent_runtime, CAST(:payload AS JSON), NOW())
     ON DUPLICATE KEY UPDATE
       hostname = VALUES(hostname),
       platform = VALUES(platform),
       agent_version = VALUES(agent_version),
       agent_runtime = VALUES(agent_runtime),
       payload_json = VALUES(payload_json),
       received_at = NOW()`,
    { userId, ...s }
  );
}

// 删除某用户的某设备（按 user_id+device_id，确保只能删自己的）
async function deleteDevice(pool, userId, deviceId) {
  const [result] = await pool.execute(
    'DELETE FROM devices WHERE user_id = :userId AND device_id = :deviceId',
    { userId, deviceId }
  );
  return result.affectedRows > 0;
}

// 统计全表设备数（用于 /api/health）
async function countAllDevices(pool) {
  const [rows] = await pool.query('SELECT COUNT(*) AS cnt FROM devices');
  return rows[0].cnt;
}

// ---- subscriptions ----

// 每用户一份订阅文档。不存在则返回空文档（emptySubscriptionDocument）。
async function getSubscriptions(pool, userId) {
  const [rows] = await pool.execute(
    'SELECT version, updated_at AS updatedAt, subscriptions_json AS subscriptionsJson FROM subscriptions WHERE user_id = :userId LIMIT 1',
    { userId }
  );
  if (!rows[0]) return emptySubscriptionDocument();
  const row = rows[0];
  return {
    version: row.version,
    updatedAt: row.updatedAt,
    subscriptions: typeof row.subscriptionsJson === 'string' ? JSON.parse(row.subscriptionsJson) : row.subscriptionsJson
  };
}

// 整份替换（INSERT ... ON DUPLICATE KEY UPDATE，主键是 user_id）
async function replaceSubscriptions(pool, userId, doc) {
  const json = JSON.stringify(doc.subscriptions);
  await pool.execute(
    `INSERT INTO subscriptions (user_id, version, updated_at, subscriptions_json)
     VALUES (:userId, :version, :updatedAt, CAST(:json AS JSON))
     ON DUPLICATE KEY UPDATE
       version = VALUES(version),
       updated_at = VALUES(updated_at),
       subscriptions_json = VALUES(subscriptions_json)`,
    { userId, version: doc.version, updatedAt: doc.updatedAt, json }
  );
}

// ---- quota notification rules ----

function emptyNotificationRulesDocument() {
  return { version: 1, updatedAt: '', rules: [] };
}

async function getNotificationRules(pool, userId) {
  const [rows] = await pool.execute(
    'SELECT version, updated_at AS updatedAt, rules_json AS rulesJson FROM notification_rules WHERE user_id = :userId LIMIT 1',
    { userId }
  );
  if (!rows[0]) return emptyNotificationRulesDocument();
  const row = rows[0];
  return {
    version: row.version,
    updatedAt: row.updatedAt,
    rules: typeof row.rulesJson === 'string' ? JSON.parse(row.rulesJson) : row.rulesJson
  };
}

async function replaceNotificationRules(pool, userId, doc) {
  const json = JSON.stringify(doc.rules);
  await pool.execute(
    `INSERT INTO notification_rules (user_id, version, updated_at, rules_json)
     VALUES (:userId, :version, :updatedAt, CAST(:json AS JSON))
     ON DUPLICATE KEY UPDATE
       version = VALUES(version),
       updated_at = VALUES(updated_at),
       rules_json = VALUES(rules_json)`,
    { userId, version: doc.version, updatedAt: doc.updatedAt, json }
  );
}

async function clearQuotaNotificationStates(pool, userId, ruleIds) {
  const ids = [...new Set((ruleIds || []).map((id) => String(id || '').trim()).filter(Boolean))];
  if (ids.length === 0) return 0;
  const values = { userId };
  const placeholders = ids.map((id, index) => {
    values[`ruleId${index}`] = id;
    return `:ruleId${index}`;
  });
  const [result] = await pool.execute(
    `DELETE FROM quota_notification_state
     WHERE user_id = :userId AND rule_id IN (${placeholders.join(', ')})`,
    values
  );
  return result.affectedRows;
}

// ---- push installations ----

async function registerPushInstallation(pool, userId, installation) {
  // 一个设备令牌只能属于一个登录用户。先删去旧绑定，再写当前绑定，令牌轮换和
  // 账号切换均为幂等；调用方在事务中使用时可与相关写入共同提交。
  const [existingRows] = await pool.execute(
    `SELECT id FROM push_installations
     WHERE user_id = :userId AND installation_id = :installationId
     LIMIT 1 FOR UPDATE`,
    { userId, installationId: installation.installationId }
  );
  await pool.execute(
    `DELETE FROM push_installations
     WHERE token_hash = :tokenHash
       AND (user_id <> :userId OR installation_id <> :installationId)`,
    { userId, installationId: installation.installationId, tokenHash: installation.tokenHash }
  );
  await pool.execute(
    `INSERT INTO push_installations
       (user_id, installation_id, platform, provider, environment, app_version, token_hash, token_ciphertext, token_iv, token_tag, key_version, enabled, last_seen_at)
     VALUES
       (:userId, :installationId, :platform, :provider, :environment, :appVersion, :tokenHash, :tokenCiphertext, :tokenIv, :tokenTag, :keyVersion, 1, NOW())
     ON DUPLICATE KEY UPDATE
       platform = VALUES(platform),
       provider = VALUES(provider),
       environment = VALUES(environment),
       app_version = VALUES(app_version),
       token_hash = VALUES(token_hash),
       token_ciphertext = VALUES(token_ciphertext),
       token_iv = VALUES(token_iv),
       token_tag = VALUES(token_tag),
       key_version = VALUES(key_version),
       enabled = 1,
       last_seen_at = NOW()`,
    { userId, ...installation }
  );
  // 令牌或账号重新绑定时，旧 token 可能已经被 provider 判为无效。清除同安装
  // 未发送任务，避免历史事件在新 token 注册后突然补发；后续变化会创建新事件。
  if (existingRows[0]) {
    await pool.execute(
      `DELETE FROM push_deliveries
       WHERE installation_id = :installationId AND status IN ('pending', 'leased', 'invalid')`,
      { installationId: existingRows[0].id }
    );
  }
  const [rows] = await pool.execute(
    `SELECT id, installation_id AS installationId, platform, provider, environment, app_version AS appVersion, enabled
     FROM push_installations WHERE user_id = :userId AND installation_id = :installationId LIMIT 1`,
    { userId, installationId: installation.installationId }
  );
  return rows[0] || null;
}

async function removePushInstallation(pool, userId, installationId) {
  const [result] = await pool.execute(
    'DELETE FROM push_installations WHERE user_id = :userId AND installation_id = :installationId',
    { userId, installationId }
  );
  return result.affectedRows > 0;
}

async function listActivePushInstallations(pool, userId) {
  const [rows] = await pool.execute(
    `SELECT id, installation_id AS installationId, platform, provider, environment,
            token_ciphertext AS tokenCiphertext, token_iv AS tokenIv, token_tag AS tokenTag,
            key_version AS keyVersion
     FROM push_installations WHERE user_id = :userId AND enabled = 1`,
    { userId }
  );
  return rows;
}

// ---- quota state, business events and transactional outbox ----

function quotaNotificationStateKey(userId, state) {
  return crypto.createHash('sha256')
    // 与 002 升级迁移的 SQL 回填算法保持一致。各 ID 的规范化拒绝控制字符，
    // 因此 NUL 分隔不会产生字段边界碰撞。
    .update([
      String(userId), String(state.ruleId || ''), String(state.targetId || ''),
      String(state.windowId || '')
    ].join('\0'))
    .digest('hex');
}

async function ensureQuotaNotificationState(pool, userId, state) {
  const stateKey = quotaNotificationStateKey(userId, state);
  const [result] = await pool.execute(
    `INSERT IGNORE INTO quota_notification_state
       (state_key, user_id, rule_id, target_id, window_id, remaining_percent, cycle_generation, warning_sent, observed_at)
     VALUES (:stateKey, :userId, :ruleId, :targetId, :windowId, :remainingPercent, :cycleGeneration, :warningSent, :observedAt)`,
    { stateKey, userId, ...state }
  );
  return result.affectedRows === 1;
}

async function getQuotaNotificationStateForUpdate(pool, userId, state) {
  const stateKey = quotaNotificationStateKey(userId, state);
  const [rows] = await pool.execute(
    `SELECT remaining_percent AS remainingPercent, cycle_generation AS cycleGeneration,
            warning_sent AS warningSent, observed_at AS observedAt
     FROM quota_notification_state
     WHERE state_key = :stateKey AND user_id = :userId
     FOR UPDATE`,
    { stateKey, userId }
  );
  return rows[0] || null;
}

async function updateQuotaNotificationState(pool, userId, state) {
  const stateKey = quotaNotificationStateKey(userId, state);
  await pool.execute(
    `UPDATE quota_notification_state
     SET remaining_percent = :remainingPercent, cycle_generation = :cycleGeneration,
         warning_sent = :warningSent, observed_at = :observedAt
     WHERE state_key = :stateKey AND user_id = :userId`,
    { stateKey, userId, ...state }
  );
}

async function createNotificationEvent(pool, userId, event) {
  const [result] = await pool.execute(
    `INSERT INTO notification_events (user_id, event_id, dedupe_key, event_type, payload_json)
     VALUES (:userId, :eventId, :dedupeKey, :eventType, CAST(:payload AS JSON))`,
    { userId, ...event, payload: JSON.stringify(event.payload) }
  );
  return { id: result.insertId, eventId: event.eventId };
}

async function createPushDeliveries(pool, eventId, installations, payload) {
  for (const installation of installations) {
    await pool.execute(
      `INSERT IGNORE INTO push_deliveries
         (event_id, installation_id, platform, provider, environment, payload_json)
       VALUES (:eventId, :installationId, :platform, :provider, :environment, CAST(:payload AS JSON))`,
      { eventId, ...installation, payload: JSON.stringify(payload) }
    );
  }
}

// ---- push worker outbox leasing ----

function parseJsonColumn(value) {
  return typeof value === 'string' ? JSON.parse(value) : value;
}

function deliveryCommandId(input) {
  return Number(input?.deliveryId ?? input?.id);
}

function mysqlTimestamp(value, name) {
  const date = value instanceof Date ? value : new Date(value);
  if (!Number.isFinite(date.getTime())) throw new Error(`${name} must be a valid timestamp`);
  // 交给 mysql2 以 Date 参数编码，避免把带 T/Z 的 ISO 字符串直接写入
  // TIMESTAMP 时受 MySQL SQL mode / 版本差异影响。
  return date;
}

async function claimPushDeliveries(pool, { batchSize, leaseId, leaseUntil }) {
  const size = Math.max(1, Math.min(100, Number(batchSize) || 20));
  if (!leaseId) throw new Error('leaseId is required');
  return withTransaction(pool, async (connection) => {
    // SKIP LOCKED 让多个 worker 只各自领取一批；已过期的 leased 记录可以被新
    // worker 重领。最终状态更新都要求相同 lease_id，旧 worker 无法覆盖新租约。
    const [candidates] = await connection.execute(
      `SELECT d.id FROM push_deliveries d
       JOIN push_installations i ON i.id = d.installation_id AND i.enabled = 1
       WHERE (
         (d.status = 'pending' AND (d.next_attempt_at IS NULL OR d.next_attempt_at <= NOW()))
         OR (d.status = 'leased' AND d.lease_until < NOW())
       )
       ORDER BY d.id ASC
       LIMIT :size
       FOR UPDATE SKIP LOCKED`,
      { size }
    );
    const claimed = [];
    for (const candidate of candidates) {
      await connection.execute(
        `UPDATE push_deliveries
         SET status = 'leased', attempts = attempts + 1, lease_id = :leaseId, lease_until = :leaseUntil
         WHERE id = :id`,
        { id: candidate.id, leaseId, leaseUntil: mysqlTimestamp(leaseUntil, 'leaseUntil') }
      );
      const [rows] = await connection.execute(
        `SELECT d.id, d.installation_id AS installationId, d.platform, d.provider, d.environment,
                d.attempts, d.payload_json AS payloadJson,
                i.token_ciphertext AS tokenCiphertext, i.token_iv AS tokenIv, i.token_tag AS tokenTag,
                i.key_version AS keyVersion, e.event_id AS eventId
         FROM push_deliveries d
         JOIN notification_events e ON e.id = d.event_id
         JOIN push_installations i ON i.id = d.installation_id AND i.enabled = 1
         WHERE d.id = :id AND d.lease_id = :leaseId LIMIT 1`,
        { id: candidate.id, leaseId }
      );
      if (rows[0]) claimed.push({ ...rows[0], payload: parseJsonColumn(rows[0].payloadJson) });
    }
    return claimed;
  });
}

async function renewPushDeliveryLease(pool, input) {
  const [result] = await pool.execute(
    `UPDATE push_deliveries
     SET lease_until = :leaseUntil
     WHERE id = :id AND status = 'leased' AND lease_id = :leaseId`,
    {
      id: deliveryCommandId(input),
      leaseId: input?.leaseId,
      leaseUntil: mysqlTimestamp(input?.leaseUntil, 'leaseUntil')
    }
  );
  return result.affectedRows > 0;
}

async function markPushDeliverySent(pool, input) {
  const [result] = await pool.execute(
    `UPDATE push_deliveries
     SET status = 'sent', sent_at = NOW(), lease_id = NULL, lease_until = NULL, last_error = ''
     WHERE id = :id AND status = 'leased' AND lease_id = :leaseId`,
    { id: deliveryCommandId(input), leaseId: input?.leaseId }
  );
  return result.affectedRows > 0;
}

async function markPushDeliveryRetry(pool, input) {
  const [result] = await pool.execute(
    `UPDATE push_deliveries
     SET status = 'pending', next_attempt_at = :nextAttemptAt, lease_id = NULL, lease_until = NULL,
         last_error = :lastError
     WHERE id = :id AND status = 'leased' AND lease_id = :leaseId`,
    {
      id: deliveryCommandId(input), leaseId: input?.leaseId,
      nextAttemptAt: mysqlTimestamp(input?.nextAttemptAt, 'nextAttemptAt'),
      lastError: String(input?.lastError || '').slice(0, 512)
    }
  );
  return result.affectedRows > 0;
}

async function markPushDeliveryFailed(pool, input) {
  const [result] = await pool.execute(
    `UPDATE push_deliveries
     SET status = 'failed', lease_id = NULL, lease_until = NULL, last_error = :lastError
     WHERE id = :id AND status = 'leased' AND lease_id = :leaseId`,
    {
      id: deliveryCommandId(input), leaseId: input?.leaseId,
      lastError: String(input?.lastError || '').slice(0, 512)
    }
  );
  return result.affectedRows > 0;
}

async function markPushDeliveryInvalid(pool, input) {
  return withTransaction(pool, async (connection) => {
    const [rows] = await connection.execute(
      `SELECT installation_id AS installationId FROM push_deliveries
       WHERE id = :id AND status = 'leased' AND lease_id = :leaseId FOR UPDATE`,
      { id: deliveryCommandId(input), leaseId: input?.leaseId }
    );
    if (!rows[0]) return false;
    await connection.execute(
      `UPDATE push_deliveries
       SET status = 'invalid', lease_id = NULL, lease_until = NULL, last_error = :lastError
       WHERE id = :id AND lease_id = :leaseId`,
      {
        id: deliveryCommandId(input), leaseId: input?.leaseId,
        lastError: String(input?.lastError || 'invalid_push_token').slice(0, 512)
      }
    );
    await connection.execute(
      'UPDATE push_installations SET enabled = 0 WHERE id = :installationId',
      { installationId: rows[0].installationId }
    );
    await connection.execute(
      `UPDATE push_deliveries
       SET status = 'invalid', lease_id = NULL, lease_until = NULL, last_error = :lastError
       WHERE installation_id = :installationId AND status IN ('pending', 'leased')`,
      {
        installationId: rows[0].installationId,
        lastError: String(input?.lastError || 'invalid_push_token').slice(0, 512)
      }
    );
    return true;
  });
}

module.exports = {
  createPool,
  withTransaction,
  createUser,
  findUserByEmail,
  findUserById,
  lockUserForUpdate,
  listDevicesByUser,
  getDevice,
  upsertDevice,
  deleteDevice,
  countAllDevices,
  getSubscriptions,
  replaceSubscriptions,
  emptyNotificationRulesDocument,
  getNotificationRules,
  replaceNotificationRules,
  clearQuotaNotificationStates,
  quotaNotificationStateKey,
  registerPushInstallation,
  removePushInstallation,
  listActivePushInstallations,
  ensureQuotaNotificationState,
  getQuotaNotificationStateForUpdate,
  updateQuotaNotificationState,
  createNotificationEvent,
  createPushDeliveries,
  claimPushDeliveries,
  renewPushDeliveryLease,
  markPushDeliverySent,
  markPushDeliveryRetry,
  markPushDeliveryFailed,
  markPushDeliveryInvalid,
  serializeDevice,
  deserializeDevice
};
