'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { createHub } = require('../src/hub');

// mock db：用内存 Map 模拟，验证 hub 业务逻辑（不打真实 MySQL）
function createMockDb() {
  const users = new Map();      // userId -> {id, email}
  const devices = new Map();    // `${userId}:${deviceId}` -> record
  const subs = new Map();       // userId -> doc

  return {
    async createUser(_, { email }) {
      const id = users.size + 1;
      users.set(id, { id, email });
      return { id, email };
    },
    async listDevicesByUser(_, userId) {
      const out = [];
      for (const [key, record] of devices) {
        if (key.startsWith(`${userId}:`)) out.push(record);
      }
      return out;
    },
    async getDevice(_, userId, deviceId) {
      return devices.get(`${userId}:${deviceId}`) || null;
    },
    async getDeviceOwner(_, deviceId) {
      for (const [key] of devices) {
        if (key.endsWith(`:${deviceId}`)) {
          return Number(key.split(':')[0]);
        }
      }
      return null;
    },
    async upsertDevice(_, userId, record) {
      devices.set(`${userId}:${record.deviceId}`, record);
    },
    async deleteDevice(_, userId, deviceId) {
      return devices.delete(`${userId}:${deviceId}`);
    },
    async countAllDevices() {
      return devices.size;
    },
    async getSubscriptions(_, userId) {
      return subs.get(userId) || { version: 1, updatedAt: '', subscriptions: [] };
    },
    async replaceSubscriptions(_, userId, doc) {
      subs.set(userId, doc);
    }
  };
}

function createMockSse() {
  const broadcasts = [];
  return {
    add: () => () => {},
    remove: () => {},
    sendSnapshot: () => {},
    broadcastStats: (userId, stats, reason) => broadcasts.push({ userId, stats, reason }),
    size: () => 0,
    closeAll: () => {},
    broadcasts
  };
}

function setup() {
  const db = createMockDb();
  const sse = createMockSse();
  const hub = createHub({ pool: null, db, sseRegistry: sse, staleAfterMs: 600000 });
  return { db, sse, hub };
}

// ---- ingest ----

test('ingest 首次上报绑定 userId', async () => {
  const { hub, db } = setup();
  const { record } = await hub.ingest(1, { deviceId: 'dev-a', today: { totalTokens: 5, costUsd: 0.1 } });
  assert.equal(record.deviceId, 'dev-a');
  // 设备已归属 user 1
  const owner = await db.getDeviceOwner(null, 'dev-a');
  assert.equal(owner, 1);
});

test('ingest 同用户再次上报正常合并', async () => {
  const { hub } = setup();
  await hub.ingest(1, { deviceId: 'dev-a', today: { totalTokens: 5 } });
  const { record } = await hub.ingest(1, { deviceId: 'dev-a', today: { totalTokens: 8 } });
  // mergeDeviceRecord 经 normalizeDeviceRecord 后 period 数据在 record.periods.today
  assert.equal(record.periods.today.totalTokens, 8);
});

test('ingest 缺 deviceId 抛错', async () => {
  const { hub } = setup();
  await assert.rejects(() => hub.ingest(1, { today: { totalTokens: 1 } }), /deviceId_required/);
});

test('ingest 设备归属他人时返回 403', async () => {
  const { hub } = setup();
  await hub.ingest(1, { deviceId: 'shared-dev', today: { totalTokens: 1 } });
  // user 2 尝试上报同一 deviceId
  await assert.rejects(
    () => hub.ingest(2, { deviceId: 'shared-dev', today: { totalTokens: 1 } }),
    (err) => err.code === 'device_ownership_conflict'
  );
});

test('ingest 缺 limits 时沿用旧值（mergeDeviceRecord 复用）', async () => {
  const { hub, db } = setup();
  // 首次带 limits
  await hub.ingest(1, {
    deviceId: 'dev-a',
    today: { totalTokens: 5 },
    limits: { providers: [{ provider: 'claude', remaining: 1000 }] }
  });
  // 再次不带 limits
  await hub.ingest(1, { deviceId: 'dev-a', today: { totalTokens: 8 } });
  const stored = await db.getDevice(null, 1, 'dev-a');
  // limits 应沿用
  assert.ok(stored.limits);
  assert.ok(stored.limits.providers.some((p) => p.provider === 'claude'));
});

test('ingest 触发 SSE 广播给当前用户', async () => {
  const { hub, sse } = setup();
  await hub.ingest(1, { deviceId: 'dev-a', today: { totalTokens: 5 } });
  assert.equal(sse.broadcasts.length, 1);
  assert.equal(sse.broadcasts[0].userId, 1);
  assert.equal(sse.broadcasts[0].reason, 'ingest');
});

// ---- getStats / getDevices / getHistory ----

test('getStats 只聚合当前用户的设备', async () => {
  const { hub } = setup();
  await hub.ingest(1, { deviceId: 'dev-a', today: { totalTokens: 5 } });
  await hub.ingest(2, { deviceId: 'dev-b', today: { totalTokens: 99 } });

  const stats1 = await hub.getStats(1);
  const stats2 = await hub.getStats(2);
  // user 1 只看到 dev-a
  assert.equal(stats1.devices.length, 1);
  assert.equal(stats1.devices[0].deviceId, 'dev-a');
  // user 2 只看到 dev-b
  assert.equal(stats2.devices.length, 1);
  assert.equal(stats2.devices[0].deviceId, 'dev-b');
});

test('getStats 包含 subscriptionsUpdatedAt', async () => {
  const { hub } = setup();
  const stats = await hub.getStats(1);
  assert.equal(typeof stats.subscriptionsUpdatedAt, 'string');
  assert.equal(stats.subscriptionsUpdatedAt, ''); // 空文档
});

test('getDevices 返回当前用户设备列表', async () => {
  const { hub } = setup();
  await hub.ingest(1, { deviceId: 'dev-a', today: { totalTokens: 5 } });
  await hub.ingest(1, { deviceId: 'dev-b', today: { totalTokens: 3 } });
  const { devices } = await hub.getDevices(1);
  assert.equal(devices.length, 2);
});

test('deleteDevice 只删自己的设备', async () => {
  const { hub, db } = setup();
  await hub.ingest(1, { deviceId: 'dev-a', today: { totalTokens: 5 } });
  // user 2 删 user 1 的设备（按 user_id+device_id，删不到）
  await hub.deleteDevice(2, 'dev-a');
  const stillThere = await db.getDevice(null, 1, 'dev-a');
  assert.ok(stillThere, 'user 2 不能删 user 1 的设备');
  // user 1 自己删
  await hub.deleteDevice(1, 'dev-a');
  const gone = await db.getDevice(null, 1, 'dev-a');
  assert.equal(gone, null);
});

// ---- subscriptions 乐观并发 ----

// subscription fixture：用真实形状（provider/planName/amountMinor/currency/startDate）
function sampleSubscription(overrides = {}) {
  return {
    id: 'sub_1',
    provider: 'codex',
    planName: 'Plus',
    amountMinor: 9000,
    currency: 'HKD',
    startDate: '2026-05-31',
    ...overrides
  };
}

test('setSubscriptions 首次写入成功', async () => {
  const { hub } = setup();
  const doc = await hub.setSubscriptions(1, [sampleSubscription()], '');
  assert.ok(doc.updatedAt);
  assert.equal(doc.subscriptions.length, 1);
});

test('setSubscriptions 用正确 baseUpdatedAt 成功', async () => {
  const { hub } = setup();
  const first = await hub.setSubscriptions(1, [sampleSubscription()], '');
  const second = await hub.setSubscriptions(1, [sampleSubscription({ planName: 'Pro' })], first.updatedAt);
  assert.equal(second.subscriptions[0].planName, 'Pro');
});

test('setSubscriptions 用过期 baseUpdatedAt 返回 stale_write', async () => {
  const { hub } = setup();
  await hub.setSubscriptions(1, [sampleSubscription()], '');
  // 用错误的 base
  await assert.rejects(
    () => hub.setSubscriptions(1, [sampleSubscription({ planName: 'Pro' })], 'wrong-base'),
    (err) => err.code === 'stale_write' && err.current !== undefined
  );
});

test('setSubscriptions 非 array 拒绝', async () => {
  const { hub } = setup();
  await assert.rejects(
    () => hub.setSubscriptions(1, 'not-array', ''),
    (err) => err.code === 'bad_subscriptions'
  );
});

test('setSubscriptions 不支持的币种拒绝', async () => {
  const { hub } = setup();
  await assert.rejects(
    () => hub.setSubscriptions(1, [sampleSubscription({ currency: 'WTF' })], ''),
    (err) => err.code === 'bad_subscriptions'
  );
});

test('订阅 per-user 隔离：两用户的订阅列表各自独立', async () => {
  const { hub } = setup();
  await hub.setSubscriptions(1, [sampleSubscription({ provider: 'claude' })], '');
  await hub.setSubscriptions(2, [sampleSubscription({ provider: 'codex' })], '');
  const subs1 = await hub.getSubscriptions(1);
  const subs2 = await hub.getSubscriptions(2);
  // 两用户的订阅内容互不影响（updatedAt 可能相同——独立时间戳合法）
  assert.equal(subs1.subscriptions[0].provider, 'claude');
  assert.equal(subs2.subscriptions[0].provider, 'codex');
  // user 1 再写不影响 user 2
  const first = subs1.updatedAt;
  await hub.setSubscriptions(1, [sampleSubscription({ provider: 'claude', planName: 'Pro' })], first);
  const subs2After = await hub.getSubscriptions(2);
  assert.equal(subs2After.subscriptions[0].provider, 'codex', 'user 2 的订阅不被 user 1 的写入影响');
});

test('setSubscriptions 触发 SSE 广播', async () => {
  const { hub, sse } = setup();
  await hub.setSubscriptions(1, [sampleSubscription()], '');
  assert.equal(sse.broadcasts.length, 1);
  assert.equal(sse.broadcasts[0].reason, 'subscriptions');
});

test('setSubscriptions 并发串行：同用户第二次读到第一次写完后的版本', async () => {
  const { hub } = setup();
  // 两个并发写，都用空 base（第一次会成功，第二次应 stale_write）
  const p1 = hub.setSubscriptions(1, [sampleSubscription({ provider: 'first' })], '');
  const p2 = hub.setSubscriptions(1, [sampleSubscription({ provider: 'second' })], '');
  const results = await Promise.allSettled([p1, p2]);
  // 一个成功一个 stale_write
  const fulfilled = results.filter((r) => r.status === 'fulfilled');
  const rejected = results.filter((r) => r.status === 'rejected' && r.reason.code === 'stale_write');
  assert.equal(fulfilled.length, 1);
  assert.equal(rejected.length, 1);
});
