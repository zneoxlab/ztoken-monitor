'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { createHub } = require('../src/hub');
const { createPushTokenCrypto } = require('../src/pushTokenCrypto');

// mock db：用内存 Map 模拟，验证 hub 业务逻辑（不打真实 MySQL）
function createMockDb() {
  const users = new Map();      // userId -> {id, email}
  const devices = new Map();    // `${userId}:${deviceId}` -> record
  const subs = new Map();       // userId -> doc
  const rules = new Map();      // userId -> doc
  const states = new Map();     // `${userId}:${rule}:${target}:${window}` -> state
  const clearedRuleBatches = [];
  const installations = new Map();
  const events = [];
  const deliveries = [];

  const stateKey = (userId, state) => `${userId}:${state.ruleId}:${state.targetId}:${state.windowId}`;

  return {
    async withTransaction(_, fn) { return fn(null); },
    async lockUserForUpdate() { return true; },
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
    },
    async getNotificationRules(_, userId) {
      return rules.get(userId) || { version: 1, updatedAt: '', rules: [] };
    },
    async replaceNotificationRules(_, userId, doc) {
      rules.set(userId, doc);
    },
    async clearQuotaNotificationStates(_, userId, ruleIds) {
      const changed = new Set(ruleIds || []);
      clearedRuleBatches.push({ userId, ruleIds: [...changed] });
      let cleared = 0;
      for (const key of [...states.keys()]) {
        if (!key.startsWith(`${userId}:`)) continue;
        const ruleId = key.slice(`${userId}:`.length).split(':')[0];
        if (!changed.has(ruleId)) continue;
        states.delete(key);
        cleared += 1;
      }
      return cleared;
    },
    async registerPushInstallation(_, userId, installation) {
      const list = installations.get(userId) || [];
      const existing = list.find((entry) => entry.installationId === installation.installationId);
      const row = { ...installation, id: existing?.id || list.length + 1, enabled: true };
      if (existing) Object.assign(existing, row); else list.push(row);
      installations.set(userId, list);
      return row;
    },
    async removePushInstallation(_, userId, installationId) {
      const list = installations.get(userId) || [];
      const index = list.findIndex((entry) => entry.installationId === installationId);
      if (index < 0) return false;
      list.splice(index, 1);
      return true;
    },
    async listActivePushInstallations(_, userId) {
      return (installations.get(userId) || []).filter((entry) => entry.enabled);
    },
    async ensureQuotaNotificationState(_, userId, state) {
      const key = stateKey(userId, state);
      if (states.has(key)) return false;
      states.set(key, {
        remainingPercent: state.remainingPercent, cycleGeneration: state.cycleGeneration,
        warningSent: state.warningSent, observedAt: state.observedAt
      });
      return true;
    },
    async getQuotaNotificationStateForUpdate(_, userId, state) {
      return states.get(stateKey(userId, state)) || null;
    },
    async updateQuotaNotificationState(_, userId, state) {
      states.set(stateKey(userId, state), {
        remainingPercent: state.remainingPercent, cycleGeneration: state.cycleGeneration,
        warningSent: state.warningSent, observedAt: state.observedAt
      });
    },
    async createNotificationEvent(_, userId, event) {
      const row = { id: events.length + 1, userId, ...event };
      events.push(row);
      return { id: row.id, eventId: row.eventId };
    },
    async createPushDeliveries(_, eventId, activeInstallations, payload) {
      for (const installation of activeInstallations) deliveries.push({ eventId, installation, payload });
    },
    events,
    deliveries,
    installations,
    clearedRuleBatches
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

function setup({ pushTokenCrypto = null } = {}) {
  const db = createMockDb();
  const sse = createMockSse();
  const hub = createHub({ pool: null, db, sseRegistry: sse, staleAfterMs: 600000, pushTokenCrypto });
  return { db, sse, hub };
}

// ---- ingest ----

test('ingest 首次上报绑定 userId', async () => {
  const { hub, db } = setup();
  const { record } = await hub.ingest(1, { deviceId: 'dev-a', today: { totalTokens: 5, costUsd: 0.1 } });
  assert.equal(record.deviceId, 'dev-a');
  const stored = await db.getDevice(null, 1, 'dev-a');
  assert.ok(stored);
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

test('ingest 不同用户同 deviceId 各自独立', async () => {
  const { hub, db } = setup();
  await hub.ingest(1, { deviceId: 'shared-dev', today: { totalTokens: 1 } });
  const { record } = await hub.ingest(2, { deviceId: 'shared-dev', today: { totalTokens: 9 } });
  assert.equal(record.periods.today.totalTokens, 9);
  const user1 = await db.getDevice(null, 1, 'shared-dev');
  const user2 = await db.getDevice(null, 2, 'shared-dev');
  assert.equal(user1.periods.today.totalTokens, 1);
  assert.equal(user2.periods.today.totalTokens, 9);
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

test('ingest 不存储或广播 session 明细', async () => {
  const { hub, db, sse } = setup();
  const { record, stats } = await hub.ingest(1, {
    deviceId: 'dev-a',
    today: { totalTokens: 5, sessions: { 'claude:s1': { totalTokens: 5 } } },
    month: { totalTokens: 8, sessions: { 'claude:s2': { totalTokens: 8 } } },
    allTime: { totalTokens: 10, sessions: { 'claude:s3': { totalTokens: 10 } } },
    sessionDetailsOmitted: { month: 3 }
  });

  const stored = await db.getDevice(null, 1, 'dev-a');
  assert.equal(Object.hasOwn(record.periods.today, 'sessions'), false);
  assert.equal(Object.hasOwn(record.periods.month, 'sessions'), false);
  assert.equal(Object.hasOwn(record.periods.allTime, 'sessions'), false);
  assert.equal(Object.hasOwn(stored.periods.today, 'sessions'), false);
  assert.equal(stored.periods.today.totalTokens, 5);
  assert.equal(
    Object.hasOwn(stats.devices[0].periods.today, 'sessions'),
    false
  );
  assert.equal(
    Object.hasOwn(sse.broadcasts[0].stats.devices[0].periods.today, 'sessions'),
    false
  );
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

// ---- quota notification rules / transactional outbox ----

function quotaPayload(remainingPercent, updatedAt = null) {
  return {
    deviceId: 'dev-quota',
    limits: {
      providers: [{
        provider: 'codex',
        accountKey: 'account-1',
        accountIdentity: 'identity-1',
        status: 'ok',
        ...(updatedAt ? { updatedAt } : {}),
        windows: [{ windowId: 'session-5h', kind: 'session', label: '5 小时额度', windowMinutes: 300, usedPercent: 100 - remainingPercent }]
      }]
    }
  };
}

function quotaRule() {
  return {
    id: 'codex-identity-1',
    targetId: require('../src/notificationRules').notificationTargetId({
      provider: 'codex', accountIdentity: 'identity-1'
    }),
    enabled: true,
    refreshEnabled: true,
    warningEnabled: true,
    thresholdPercent: 20,
    windowIds: ['session-5h']
  };
}

test('配额规则首快照建基线，刷新和阈值跨越各只创建一次事件', async () => {
  const crypto = createPushTokenCrypto('test-push-key');
  const { hub, db } = setup({ pushTokenCrypto: crypto });
  await hub.setNotificationRules(1, [quotaRule()], '');
  await hub.registerPushInstallation(1, {
    installationId: 'phone-1', platform: 'ios', provider: 'apns', environment: 'sandbox', appVersion: '1.0.0', token: 'apns-token'
  });

  await hub.ingest(1, quotaPayload(99)); // 首次基线
  await hub.ingest(1, quotaPayload(100)); // <100 -> 100，刷新
  await hub.ingest(1, quotaPayload(100)); // 持续 100，不重复
  await hub.ingest(1, quotaPayload(20)); // >20 -> <=20，预警
  await hub.ingest(1, quotaPayload(90)); // 反弹不代表周期刷新
  await hub.ingest(1, quotaPayload(10)); // 同一周期再次降阈值，不重复
  await hub.ingest(1, quotaPayload(100)); // 严格刷新，进入新周期
  await hub.ingest(1, quotaPayload(20)); // 新周期可再次预警

  assert.deepEqual(db.events.map((event) => event.eventType), [
    'quota_refreshed', 'quota_warning', 'quota_refreshed', 'quota_warning'
  ]);
  assert.equal(db.deliveries.length, 4, '每个业务事件为启用安装建立一条 Outbox delivery');
  assert.ok(db.deliveries[0].payload.eventId);
});

test('提供方时间戳倒退的快照不会重置周期或产生事件', async () => {
  const { hub, db } = setup();
  await hub.setNotificationRules(1, [quotaRule()], '');
  await hub.ingest(1, quotaPayload(90, '2026-08-12T10:00:00.000Z'));
  await hub.ingest(1, quotaPayload(10, '2026-08-12T10:01:00.000Z'));
  await hub.ingest(1, quotaPayload(100, '2026-08-12T09:59:00.000Z'));
  assert.deepEqual(db.events.map((event) => event.eventType), ['quota_warning']);
});

test('关闭刷新通知仍以回到 100% 重新布防下一周期预警', async () => {
  const { hub, db } = setup();
  await hub.setNotificationRules(1, [{ ...quotaRule(), refreshEnabled: false }], '');
  await hub.ingest(1, quotaPayload(90));
  await hub.ingest(1, quotaPayload(20));
  await hub.ingest(1, quotaPayload(100));
  await hub.ingest(1, quotaPayload(20));
  assert.deepEqual(db.events.map((event) => event.eventType), [
    'quota_warning', 'quota_warning'
  ]);
});

test('修改规则会清除旧周期状态，下一份快照仅重新建基线', async () => {
  const { hub, db } = setup();
  const first = await hub.setNotificationRules(1, [quotaRule()], '');
  await hub.ingest(1, quotaPayload(90));
  await hub.ingest(1, quotaPayload(20));
  assert.deepEqual(db.events.map((event) => event.eventType), ['quota_warning']);

  await hub.setNotificationRules(1, [{ ...quotaRule(), thresholdPercent: 30 }], first.updatedAt);
  await hub.ingest(1, quotaPayload(10));
  assert.deepEqual(
    db.events.map((event) => event.eventType),
    ['quota_warning'],
    '规则保存后当前低额度只应成为新基线，不能补发'
  );
});

test('保存未变化规则不会重置其它配额的状态基线', async () => {
  const { hub, db } = setup();
  const first = await hub.setNotificationRules(1, [quotaRule()], '');
  await hub.setNotificationRules(1, [quotaRule()], first.updatedAt);
  assert.deepEqual(db.clearedRuleBatches.map((batch) => batch.ruleIds), [
    ['codex-identity-1'],
    []
  ]);
});

test('notification rules 使用乐观并发且 targets 只返回百分比额度窗口', async () => {
  const { hub } = setup();
  await hub.ingest(1, quotaPayload(70));
  const targets = await hub.getNotificationTargets(1);
  assert.equal(targets.targets.length, 1);
  assert.equal(targets.targets[0].accountIdentity, 'identity-1');
  assert.equal(targets.targets[0].id.includes('identity-1'), false);
  assert.equal(targets.targets[0].legacy.targetId, 'codex:identity-1');
  assert.deepEqual(targets.targets[0].legacy.targetIds.slice(0, 2), [
    'codex:identity-1', 'codex:account-1'
  ]);
  assert.equal(
    targets.targets[0].legacy.targetIds.some((id) => /^codex:[a-f0-9]{64}$/.test(id)),
    true
  );
  assert.deepEqual(targets.targets[0].windows.map((window) => window.windowId), ['session-5h']);
  assert.equal(targets.targets[0].windows[0].legacy.windowId, 'quota:session:300');

  const first = await hub.setNotificationRules(1, [quotaRule()], '');
  await assert.rejects(
    () => hub.setNotificationRules(1, [quotaRule()], ''),
    (error) => error.code === 'stale_write' && error.current.updatedAt === first.updatedAt
  );
});

test('匿名目标升级后仍评估 identity/key/旧 opaque 三种 targetId', async () => {
  const notificationRules = require('../src/notificationRules');
  const legacyIds = [
    'codex:identity-1',
    'codex:account-1',
    notificationRules.notificationTargetId({ provider: 'codex', accountKey: 'account-1' })
  ];
  for (const targetId of legacyIds) {
    const { hub, db } = setup();
    await hub.setNotificationRules(1, [{ ...quotaRule(), id: targetId, targetId }], '');
    await hub.ingest(1, quotaPayload(90));
    await hub.ingest(1, quotaPayload(20));
    assert.deepEqual(db.events.map((event) => event.eventType), ['quota_warning']);
  }
});

test('未注入推送密钥时拒绝安装注册，不会保存明文 token', async () => {
  const { hub } = setup();
  await assert.rejects(
    () => hub.registerPushInstallation(1, { installationId: 'phone-1', platform: 'android', provider: 'fcm', token: 'fcm-token' }),
    (error) => error.code === 'push_not_configured'
  );
});
