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
const {
  buildNotificationTargets,
  notificationRulesDocument,
  isStaleNotificationRulesWrite
} = require('./notificationRules');
const { evaluateQuotaNotifications } = require('./quotaNotifications');

function createHub({ pool, db, sseRegistry, staleAfterMs, pushTokenCrypto = null }) {
  // 实际传入 db 模块（已注入 pool 的函数集），或用 pool + 默认 db
  const dbApi = db || require('./db');

  async function loadDevices(userId, executor = pool) {
    const devices = await dbApi.listDevicesByUser(executor, userId);
    return devices.map(stripSessionDetailFromRecord);
  }

  // ---- 聚合（复用 aggregateDevices）----
  async function getStatsWithExecutor(userId, executor = pool) {
    const devices = await loadDevices(userId, executor);
    const stats = aggregateDevices(devices, staleAfterMs);
    stats.staleAfterMs = staleAfterMs;
    const history = aggregateHistory(devices);
    stats.historyPreview = historyPreview(history);
    stats.historyRevision = historyRevision(history);
    // 订阅版本戳（只给版本，不给列表本身——同现有 hub，避免每帧都带钱数据）
    const subs = await dbApi.getSubscriptions(executor, userId);
    stats.subscriptionsUpdatedAt = subs?.updatedAt || '';
    const rules = await dbApi.getNotificationRules(executor, userId);
    stats.notificationRulesUpdatedAt = rules?.updatedAt || '';
    return stripSessionsFromStats(stats);
  }

  async function getStats(userId) {
    return getStatsWithExecutor(userId, pool);
  }

  async function getHistory(userId) {
    const devices = await loadDevices(userId, pool);
    return aggregateHistory(devices);
  }

  async function getDevices(userId) {
    const devices = await loadDevices(userId, pool);
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

    const transaction = dbApi.withTransaction
      ? (fn) => dbApi.withTransaction(pool, fn)
      : async (fn) => fn(pool);
    const result = await transaction(async (executor) => {
      if (typeof dbApi.lockUserForUpdate === 'function') {
        await dbApi.lockUserForUpdate(executor, userId);
      }
      // 合并：incoming 缺 limits/history 时沿用旧值（mergeDeviceRecord 已处理）
      const existing = await dbApi.getDevice(executor, userId, deviceId);
      const record = stripSessionDetailFromRecord(
        mergeDeviceRecord(existing, { ...payload, receivedAt: new Date().toISOString() })
      );
      await dbApi.upsertDevice(executor, userId, record);
      const stats = await getStatsWithExecutor(userId, executor);
      const rules = await dbApi.getNotificationRules(executor, userId);
      const notifications = await evaluateQuotaNotifications({
        db: dbApi,
        executor,
        userId,
        rulesDocument: rules,
        limits: stats.limits
      });
      return { record, stats, notifications };
    });

    // 广播给该用户的所有 SSE 连接（不同用户互不可见）
    sseRegistry.broadcastStats(userId, result.stats, 'ingest');

    return result;
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

  // ---- notification rules：同 subscriptions 的乐观并发语义 ----

  const notificationRuleQueues = new Map();

  function runNotificationRuleOp(userId, fn) {
    const prev = notificationRuleQueues.get(userId) || Promise.resolve();
    const next = prev.then(fn, () => fn());
    notificationRuleQueues.set(userId, next.catch(() => {}));
    return next;
  }

  async function getNotificationRules(userId) {
    return dbApi.getNotificationRules(pool, userId);
  }

  function changedNotificationRuleIds(currentRules, nextRules) {
    const currentById = new Map((currentRules || []).map((rule) => [rule.id, rule]));
    const nextById = new Map((nextRules || []).map((rule) => [rule.id, rule]));
    const ids = new Set([...currentById.keys(), ...nextById.keys()]);
    return [...ids].filter((id) => (
      JSON.stringify(currentById.get(id) || null) !== JSON.stringify(nextById.get(id) || null)
    ));
  }

  async function setNotificationRules(userId, rules, baseUpdatedAt) {
    return runNotificationRuleOp(userId, async () => {
      const transaction = dbApi.withTransaction
        ? (fn) => dbApi.withTransaction(pool, fn)
        : async (fn) => fn(pool);
      const next = await transaction(async (executor) => {
        if (typeof dbApi.lockUserForUpdate === 'function') {
          await dbApi.lockUserForUpdate(executor, userId);
        }
        const current = await dbApi.getNotificationRules(executor, userId);
        if (isStaleNotificationRulesWrite(current, baseUpdatedAt)) {
          const error = new Error('stale_write');
          error.code = 'stale_write';
          error.current = current;
          throw error;
        }
        const document = notificationRulesDocument(rules, { previous: current });
        await dbApi.replaceNotificationRules(executor, userId, document);
        // 阈值、范围或开关变化后，旧周期状态不再适用于新规则。清空后由
        // 下一份真实额度快照只建基线，避免保存配置当下补发历史告警。
        if (typeof dbApi.clearQuotaNotificationStates === 'function') {
          const changedRuleIds = changedNotificationRuleIds(current?.rules, document.rules);
          await dbApi.clearQuotaNotificationStates(executor, userId, changedRuleIds);
        }
        return document;
      });
      const stats = await getStats(userId);
      sseRegistry.broadcastStats(userId, stats, 'notification_rules');
      return next;
    });
  }

  async function getNotificationTargets(userId) {
    const stats = await getStats(userId);
    return { updatedAt: stats?.limits?.updatedAt || '', targets: buildNotificationTargets(stats?.limits) };
  }

  function assertPushConfigured(tokenCrypto) {
    if (!tokenCrypto || typeof tokenCrypto.encrypt !== 'function') {
      const error = new Error('push_not_configured');
      error.code = 'push_not_configured';
      throw error;
    }
  }

  async function registerPushInstallation(userId, input, tokenCrypto = pushTokenCrypto) {
    assertPushConfigured(tokenCrypto);
    const installationId = String(input?.installationId || '').trim();
    const platform = String(input?.platform || '').trim().toLowerCase();
    const provider = String(input?.provider || '').trim().toLowerCase();
    const environment = String(input?.environment || 'production').trim().toLowerCase();
    const appVersion = String(input?.appVersion || '').trim();
    const supported = (platform === 'android' && provider === 'fcm' && environment === 'production')
      || (platform === 'ios' && provider === 'apns' && ['sandbox', 'production'].includes(environment));
    if (!installationId || installationId.length > 128 || !supported || appVersion.length > 64) {
      const error = new Error('invalid push installation');
      error.code = 'bad_push_installation';
      throw error;
    }
    const encrypted = tokenCrypto.encrypt(input?.token);
    const transaction = dbApi.withTransaction
      ? (fn) => dbApi.withTransaction(pool, fn)
      : async (fn) => fn(pool);
    return transaction((executor) => dbApi.registerPushInstallation(executor, userId, {
      installationId,
      platform,
      provider,
      environment,
      appVersion,
      ...encrypted
    }));
  }

  async function removePushInstallation(userId, installationId) {
    const id = String(installationId || '').trim();
    if (!id || id.length > 128) {
      const error = new Error('invalid push installation');
      error.code = 'bad_push_installation';
      throw error;
    }
    return dbApi.removePushInstallation(pool, userId, id);
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
    setSubscriptions,
    getNotificationRules,
    setNotificationRules,
    getNotificationTargets,
    registerPushInstallation,
    removePushInstallation
  };
}

module.exports = { createHub };
