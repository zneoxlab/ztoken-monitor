'use strict';

const crypto = require('node:crypto');
const { buildNotificationTargets } = require('./notificationRules');

function makeDedupeKey(userId, rule, target, window, type, cycleGeneration, ruleVersion) {
  return crypto.createHash('sha256')
    .update(JSON.stringify({
      userId,
      ruleId: rule.id,
      targetId: target.id,
      windowId: window.id,
      type,
      cycleGeneration,
      // 保存规则会清空状态并重新基线；文档版本把新基线的 cycle 1 与旧配置
      // 的 cycle 1 隔离，历史事件无需删除也不会阻塞新规则的合法事件。
      ruleVersion: Number(ruleVersion) || 1
    }))
    .digest('hex');
}

function pushPayload({ eventId, type, target, window, remainingPercent, threshold }) {
  // 不把邮箱、账号标识、余额或消费明细放进锁屏可见正文。App 收到 eventId 后
  // 可跳转到已鉴权的额度页；provider/window 只保留在 data 供页面定位。
  return {
    eventId,
    eventType: type,
    type,
    route: '/limits',
    targetId: target.id,
    windowId: window.id,
    notification: {
      title: type === 'quota_refreshed' ? '额度已刷新' : '额度预警',
      body: type === 'quota_refreshed' ? '配额已恢复，打开查看详情。' : '配额已达到预警阈值，打开查看详情。'
    },
    data: {
      eventId,
      type,
      targetId: target.id,
      provider: target.provider,
      windowId: window.id,
      remainingPercent,
      thresholdPercent: threshold
    }
  };
}

// 在调用方持有的用户级事务内运行。状态键的 INSERT IGNORE + SELECT ... FOR UPDATE
// 使并发 ingest 中第一份快照仅建基线，之后同一跨越最多生成一条事件。
async function evaluateQuotaNotifications({ db, executor, userId, rulesDocument, limits, now = new Date() }) {
  const rules = Array.isArray(rulesDocument?.rules) ? rulesDocument.rules : [];
  if (rules.length === 0) return { events: [], deliveries: 0 };
  const targets = buildNotificationTargets(limits);
  const targetById = new Map();
  for (const target of targets) {
    targetById.set(target.id, target);
    const legacyTargetIds = Array.isArray(target.legacy?.targetIds)
      ? target.legacy.targetIds
      : [target.legacy?.targetId];
    for (const legacyTargetId of legacyTargetIds) {
      if (legacyTargetId) targetById.set(legacyTargetId, target);
    }
  }
  const events = [];
  let installations = null;
  let deliveries = 0;
  const fallbackObservedAt = now.toISOString();

  for (const rule of rules) {
    if (!rule.enabled) continue;
    const target = targetById.get(rule.targetId);
    if (!target) continue;
    const selectedWindowIds = new Set(rule.windowIds || []);
    const observedAt = target.updatedAt || fallbackObservedAt;
    for (const window of target.windows) {
      if (!selectedWindowIds.has(window.id) && !selectedWindowIds.has(window.legacy?.windowId)) continue;
      const remainingPercent = Number(window.remainingPercent);
      if (!Number.isFinite(remainingPercent)) continue;
      const stateKey = {
        ruleId: rule.id,
        targetId: target.id,
        windowId: window.id,
        remainingPercent,
        cycleGeneration: 1,
        warningSent: 0,
        observedAt
      };
      const inserted = await db.ensureQuotaNotificationState(executor, userId, stateKey);
      // 首次观察是基线，绝不补发当前已经低于阈值或 100% 的状态。
      if (inserted) continue;
      const previousState = await db.getQuotaNotificationStateForUpdate(executor, userId, stateKey);
      if (!previousState) continue;
      const previous = Number(previousState.remainingPercent);
      // 提供方完成时间倒退（或相同的旧快照重放）不能倒推状态，否则会制造
      // “先降后升”的虚假刷新/预警。没有来源时间时才退回本次 ingest 的当前时间。
      if (previousState.observedAt && observedAt < previousState.observedAt) continue;
      let cycleGeneration = Number(previousState.cycleGeneration) || 1;
      let warningSent = Boolean(previousState.warningSent);
      let type = '';
      // “回到 100%”既是刷新通知的触发条件，也是下一周期预警的重新布防点。
      // 即使用户关闭了刷新通知，也必须推进周期并清除 warningSent。
      if (previous < 100 && remainingPercent === 100) {
        cycleGeneration += 1;
        warningSent = false;
        if (rule.refreshEnabled) type = 'quota_refreshed';
      } else if (rule.warningEnabled && !warningSent && previous > rule.thresholdPercent && remainingPercent <= rule.thresholdPercent) {
        type = 'quota_warning';
        warningSent = true;
      }

      await db.updateQuotaNotificationState(executor, userId, {
        ...stateKey,
        cycleGeneration,
        warningSent
      });
      if (!type) continue;

      const eventId = crypto.randomUUID();
      const payload = pushPayload({
        eventId,
        type,
        target,
        window,
        remainingPercent,
        threshold: rule.thresholdPercent
      });
      const event = await db.createNotificationEvent(executor, userId, {
        eventId,
        eventType: type,
        dedupeKey: makeDedupeKey(
          userId,
          rule,
          target,
          window,
          type,
          cycleGeneration,
          rulesDocument?.version
        ),
        payload
      });
      if (!installations) installations = await db.listActivePushInstallations(executor, userId);
      await db.createPushDeliveries(executor, event.id, installations, payload);
      deliveries += installations.length;
      events.push({ eventId, type, ruleId: rule.id, targetId: target.id, windowId: window.id });
    }
  }
  return { events, deliveries };
}

module.exports = { evaluateQuotaNotifications, pushPayload, makeDedupeKey };
