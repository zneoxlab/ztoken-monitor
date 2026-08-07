'use strict';

// 业务核心（transport-agnostic）：与现有 node hub（src/hub/server.js）的
// ingest/deleteDevice/getStats/getHistory/getSubscriptions/setSubscriptions 对应。
//
// 区别：每个函数首参加 userId（多租户隔离），store 换成 db 调用，broadcastStats 按 userId 广播。
// 合并/聚合/订阅逻辑全部复用 src/shared 的纯函数，零改动。
//
// 这样 hub.js 可被 server.js（HTTP）和未来 RPC/测试直接调用，与现有 node hub 的设计一致
// （现有 server.js 注释明确 ingest 是 transport-agnostic core）。

const {
  aggregateDevices,
  aggregateHistory,
  mergeDeviceRecord
} = require('../../src/shared/usage');
const { historyPreview, historyRevision } = require('../../src/shared/history');
const {
  isStaleSubscriptionWrite,
  subscriptionDocument
} = require('../../src/shared/subscriptionDisplay');
const { CURRENCY_CODES, normalizeCurrency } = require('../../src/shared/currency');
const { stripSessionDetailFromRecord, stripSessionsFromStats } = require('./deviceRecord');

function createHub({ pool, db, sseRegistry, staleAfterMs }) {
  // 实际传入 db 模块（已注入 pool 的函数集），或用 pool + 默认 db
  const dbApi = db || require('./db');

  async function loadDevices(userId) {
    const devices = await dbApi.listDevicesByUser(pool, userId);
    return devices.map(stripSessionDetailFromRecord);
  }

  // ---- 聚合（复用 aggregateDevices）----
  async function getStats(userId) {
    const devices = await loadDevices(userId);
    const stats = aggregateDevices(devices, staleAfterMs);
    stats.staleAfterMs = staleAfterMs;
    const history = aggregateHistory(devices);
    stats.historyPreview = historyPreview(history);
    stats.historyRevision = historyRevision(history);
    // 订阅版本戳（只给版本，不给列表本身——同现有 hub，避免每帧都带钱数据）
    const subs = await dbApi.getSubscriptions(pool, userId);
    stats.subscriptionsUpdatedAt = subs?.updatedAt || '';
    return stripSessionsFromStats(stats);
  }

  async function getHistory(userId) {
    const devices = await loadDevices(userId);
    return aggregateHistory(devices);
  }

  async function getDevices(userId) {
    const devices = await loadDevices(userId);
    return { devices };
  }

  // ---- ingest：userId 绑定 + 所有权检查 + 合并 ----
  async function ingest(userId, payload) {
    if (!payload || (!payload.deviceId && !payload.id)) {
      const error = new Error('deviceId_required');
      error.code = 'deviceId_required';
      throw error;
    }
    const deviceId = String(payload.deviceId || payload.id);

    // 所有权检查：deviceId 一旦绑定到某用户，其它用户无法绑定（403）
    const ownerUserId = await dbApi.getDeviceOwner(pool, deviceId);
    if (ownerUserId !== null && ownerUserId !== userId) {
      const error = new Error('device belongs to another user');
      error.code = 'device_ownership_conflict';
      throw error;
    }

    // 合并：incoming 缺 limits/history 时沿用旧值（mergeDeviceRecord 已处理）
    const existing = await dbApi.getDevice(pool, userId, deviceId);
    const record = stripSessionDetailFromRecord(
      mergeDeviceRecord(existing, { ...payload, receivedAt: new Date().toISOString() })
    );

    await dbApi.upsertDevice(pool, userId, record);

    // 广播给该用户的所有 SSE 连接（不同用户互不可见）
    const stats = await getStats(userId);
    sseRegistry.broadcastStats(userId, stats, 'ingest');

    return { record, stats };
  }

  async function deleteDevice(userId, deviceId) {
    await dbApi.deleteDevice(pool, userId, deviceId);
    const stats = await getStats(userId);
    sseRegistry.broadcastStats(userId, stats, 'delete');
  }

  // ---- 订阅：乐观并发 + per-user 串行 lane ----

  async function getSubscriptions(userId) {
    return dbApi.getSubscriptions(pool, userId);
  }

  // per-user 串行队列：Map<userId, Promise>，同用户并发 PUT 串行执行。
  // 对齐 AGENTS.md 的"Hub reads and writes run in a per-hub lane"。
  // 第二个写读到的 current 必是第一个写完后的，stale_write 由 isStaleSubscriptionWrite 兜底。
  // Phase 2 多实例时换 Redis 分布式锁。
  const subscriptionQueues = new Map();

  function runSubscriptionOp(userId, fn) {
    const prev = subscriptionQueues.get(userId) || Promise.resolve();
    // 链下去，错误也吞掉（不阻断后续），返回本次结果
    const next = prev.then(fn, () => fn());
    subscriptionQueues.set(userId, next.catch(() => {}));
    return next;
  }

  async function setSubscriptions(userId, subscriptions, baseUpdatedAt) {
    return runSubscriptionOp(userId, async () => {
      // 非 array 直接拒绝（而非规整成空数组——空数组会被当成合法清空，抹掉别处不存在的记录）
      if (!Array.isArray(subscriptions)) {
        const error = new Error('subscriptions must be an array');
        error.code = 'bad_subscriptions';
        throw error;
      }

      const current = await dbApi.getSubscriptions(pool, userId);

      // 乐观并发：baseUpdatedAt 必须等于当前 updatedAt
      if (isStaleSubscriptionWrite(current, baseUpdatedAt)) {
        const error = new Error('stale_write');
        error.code = 'stale_write';
        error.current = current;
        throw error;
      }

      // 币种校验：不支持的币种直接拒绝（而非静默改 USD——会改写用户输入的金额）
      const unsupported = subscriptions.find(
        (entry) => entry?.currency && !CURRENCY_CODES.includes(String(entry.currency).trim().toUpperCase())
      );
      if (unsupported) {
        const error = new Error(`unsupported currency: ${String(unsupported.currency).trim().toUpperCase()}`);
        error.code = 'bad_subscriptions';
        throw error;
      }

      // 生成新文档（updatedAt 生成 + bump 逻辑都在 subscriptionDocument 内）
      const next = subscriptionDocument(subscriptions, {
        previousUpdatedAt: current?.updatedAt,
        currencyApi: { normalizeCurrency }
      });

      await dbApi.replaceSubscriptions(pool, userId, next);

      // 广播（其它设备持有的副本刚被超越，不广播要等下次轮询才知道）
      const stats = await getStats(userId);
      sseRegistry.broadcastStats(userId, stats, 'subscriptions');

      return next;
    });
  }

  return {
    ingest,
    deleteDevice,
    getStats,
    getHistory,
    getDevices,
    getSubscriptions,
    setSubscriptions
  };
}

module.exports = { createHub };
