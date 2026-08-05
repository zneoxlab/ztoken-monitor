'use strict';

// 数据访问层：mysql2 连接池 + users/devices/subscriptions 的 CRUD
// 纯数据访问，不含业务逻辑。业务在 hub.js。
//
// 关键设计：devices.payload_json 存完整 device record（mergeDeviceRecord 的输出），
// 读出时 JSON.parse 后即得到 normalizeDeviceRecord 期望的输入形状（顶层 today/month/allTime
// + limits + history + 可选字段）。顶层列（hostname/platform/agent_version 等）只用于查询/索引，
// 读出时合并进对象但以 payload_json 为准（payload_json 是合并后的最新值）。

const mysql = require('mysql2/promise');
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

// 取某用户的某设备（用于 ingest 时 merge 的 existing）
async function getDevice(pool, userId, deviceId) {
  const [rows] = await pool.execute(
    'SELECT payload_json FROM devices WHERE user_id = :userId AND device_id = :deviceId LIMIT 1',
    { userId, deviceId }
  );
  return rows[0] ? deserializeDevice(rows[0]) : null;
}

// 查 device_id 的归属用户（不带 user_id 过滤，用于所有权检查）
// 返回 userId 或 null（无主）
async function getDeviceOwner(pool, deviceId) {
  const [rows] = await pool.execute(
    'SELECT user_id AS userId FROM devices WHERE device_id = :deviceId LIMIT 1',
    { deviceId }
  );
  return rows[0] ? rows[0].userId : null;
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

module.exports = {
  createPool,
  createUser,
  findUserByEmail,
  findUserById,
  listDevicesByUser,
  getDevice,
  getDeviceOwner,
  upsertDevice,
  deleteDevice,
  countAllDevices,
  getSubscriptions,
  replaceSubscriptions,
  serializeDevice,
  deserializeDevice
};
