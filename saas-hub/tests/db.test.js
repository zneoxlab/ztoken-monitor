'use strict';

// db.test.js — 需要 MySQL。无 MySQL 时跳过（环境变量 SAAS_HUB_MYSQL_HOST 未配置或连不上）。
// 用户有现成 MySQL 时设置 .env 后这些测试会自动覆盖真实 CRUD + JSON 列往返。

const test = require('node:test');
const assert = require('node:assert');
const { createPool } = require('../src/db');
const db = require('../src/db');
const { loadConfig } = require('../src/config');

// 检测 MySQL 是否可用：要求显式设置 SAAS_HUB_DB_TEST=1 且能连上
async function tryGetPool() {
  if (process.env.SAAS_HUB_DB_TEST !== '1') return null;
  const config = loadConfig();
  try {
    const pool = createPool(config.mysql);
    await pool.query('SELECT 1');
    return pool;
  } catch (err) {
    console.warn(`MySQL not available, skipping db tests: ${err.message}`);
    return null;
  }
}

test('MySQL CRUD 往返：upsert + get + list + delete', { todo: false }, async (t) => {
  const pool = await tryGetPool();
  if (!pool) { t.skip('MySQL unavailable (set SAAS_HUB_DB_TEST=1 to enable)'); return; }

  // 建测试用 user（用唯一邮箱避免冲突）
  const email = `dbtest_${Date.now()}@example.com`;
  // 用正式 hashPassword 保证 hash/salt 配对
  const auth = require('../src/auth');
  const cred = await auth.hashPassword('password123');
  const user = await db.createUser(pool, { email, passwordHash: cred.hash, passwordSalt: cred.salt });
  const userId = user.id;
  t.after(async () => {
    // 清理：删 user 会级联删 devices/subscriptions（FK ON DELETE CASCADE）
    await pool.execute('DELETE FROM users WHERE id = :id', { id: userId });
  });

  const record = {
    deviceId: `dev-test-${Date.now()}`,
    hostname: 'mb',
    platform: 'darwin-arm64',
    agentVersion: '0.1.0',
    today: { totalTokens: 5, costUsd: 0.1 },
    month: { totalTokens: 100, costUsd: 2.5 },
    allTime: { totalTokens: 1000, costUsd: 25 }
  };

  // upsert（首次）
  await db.upsertDevice(pool, userId, record);
  const got = await db.getDevice(pool, userId, record.deviceId);
  assert.equal(got.deviceId, record.deviceId);
  assert.equal(got.hostname, 'mb');
  assert.equal(got.today.totalTokens, 5);

  // list
  const all = await db.listDevicesByUser(pool, userId);
  assert.ok(all.some((d) => d.deviceId === record.deviceId));

  // delete
  await db.deleteDevice(pool, userId, record.deviceId);
  const afterDelete = await db.getDevice(pool, userId, record.deviceId);
  assert.equal(afterDelete, null);

  await pool.end();
});

test('mergeDeviceRecord 在 DB 场景的 limits 沿用（golden 往返）', async (t) => {
  const pool = await tryGetPool();
  if (!pool) { t.skip('MySQL unavailable'); return; }

  const auth = require('../src/auth');
  const cred = await auth.hashPassword('password123');
  const email = `dbtest2_${Date.now()}@example.com`;
  const user = await db.createUser(pool, { email, passwordHash: cred.hash, passwordSalt: cred.salt });
  const userId = user.id;
  t.after(async () => { await pool.execute('DELETE FROM users WHERE id = :id', { id: userId }); });

  const deviceId = `dev-golden-${Date.now()}`;
  // 第一次带 limits
  await db.upsertDevice(pool, userId, {
    deviceId,
    today: { totalTokens: 5 },
    limits: { providers: [{ provider: 'claude', remaining: 1000 }] }
  });
  // 第二次不带 limits（模拟 limitsOnly 之外的普通 tick）
  await db.upsertDevice(pool, userId, {
    deviceId,
    today: { totalTokens: 8 }
  });
  const stored = await db.getDevice(pool, userId, deviceId);
  // 关键回归：limits 不应丢失（payload_json 存的是最后一次 upsert 的完整 record，
  // 而 hub.ingest 用 mergeDeviceRecord 合并后才存——这里直接测 db 层，需 hub 层合并。
  // 所以这个测试验证的是：db 能完整存取 record，limits 字段在 JSON 列里不丢。）
  assert.ok(stored.limits, 'limits 应在 payload_json 中保留');
  assert.ok(stored.limits.providers.some((p) => p.provider === 'claude'));

  await pool.end();
});

test('subscriptions CRUD 往返', async (t) => {
  const pool = await tryGetPool();
  if (!pool) { t.skip('MySQL unavailable'); return; }

  const auth = require('../src/auth');
  const cred = await auth.hashPassword('password123');
  const email = `dbtest3_${Date.now()}@example.com`;
  const user = await db.createUser(pool, { email, passwordHash: cred.hash, passwordSalt: cred.salt });
  const userId = user.id;
  t.after(async () => { await pool.execute('DELETE FROM users WHERE id = :id', { id: userId }); });

  // 空文档
  const empty = await db.getSubscriptions(pool, userId);
  assert.equal(empty.updatedAt, '');
  assert.equal(empty.subscriptions.length, 0);

  // 写入
  const doc = { version: 1, updatedAt: '2026-01-01T00:00:00.000Z', subscriptions: [{ id: 's1', provider: 'claude' }] };
  await db.replaceSubscriptions(pool, userId, doc);
  const got = await db.getSubscriptions(pool, userId);
  assert.equal(got.updatedAt, '2026-01-01T00:00:00.000Z');
  assert.equal(got.subscriptions.length, 1);
  assert.equal(got.subscriptions[0].provider, 'claude');

  // 覆盖
  const doc2 = { version: 1, updatedAt: '2026-02-01T00:00:00.000Z', subscriptions: [] };
  await db.replaceSubscriptions(pool, userId, doc2);
  const got2 = await db.getSubscriptions(pool, userId);
  assert.equal(got2.updatedAt, '2026-02-01T00:00:00.000Z');
  assert.equal(got2.subscriptions.length, 0);

  await pool.end();
});

test('多租户隔离：两用户同 deviceId 不冲突', async (t) => {
  const pool = await tryGetPool();
  if (!pool) { t.skip('MySQL unavailable'); return; }

  const auth = require('../src/auth');
  const cred = await auth.hashPassword('password123');
  const email1 = `dbtest4a_${Date.now()}@example.com`;
  const email2 = `dbtest4b_${Date.now()}@example.com`;
  const u1 = await db.createUser(pool, { email: email1, passwordHash: cred.hash, passwordSalt: cred.salt });
  const u2 = await db.createUser(pool, { email: email2, passwordHash: cred.hash, passwordSalt: cred.salt });
  t.after(async () => {
    await pool.execute('DELETE FROM users WHERE id IN (:a, :b)', { a: u1.id, b: u2.id });
    await pool.end();
  });

  const sharedDeviceId = `shared-${Date.now()}`;
  // 两用户各自 upsert 同一 deviceId（联合唯一 user_id+device_id，应都成功）
  await db.upsertDevice(pool, u1.id, { deviceId: sharedDeviceId, today: { totalTokens: 1 } });
  await db.upsertDevice(pool, u2.id, { deviceId: sharedDeviceId, today: { totalTokens: 2 } });

  const d1 = await db.getDevice(pool, u1.id, sharedDeviceId);
  const d2 = await db.getDevice(pool, u2.id, sharedDeviceId);
  assert.equal(d1.today.totalTokens, 1);
  assert.equal(d2.today.totalTokens, 2);
  const rows = await pool.execute('SELECT user_id FROM devices WHERE device_id = :id', { id: sharedDeviceId });
  assert.equal(rows[0].length, 2, '两用户各一条记录');
});
