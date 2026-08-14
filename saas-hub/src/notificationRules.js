'use strict';

const crypto = require('node:crypto');

// 配额通知规则是用户级文档，不附着某台采集设备。规则引用由当前 limits 聚合
// 动态产出的 targetId/windowId，因此客户端只展示实际受当前账户支持的窗口。

function notificationTargetId(provider) {
  const providerId = String(provider?.provider || '').trim();
  const accountIdentity = String(provider?.accountIdentity || provider?.accountKey || '').trim();
  // 规则和推送负载只携带不可读目标 ID，不能把上游 accountKey/email 等值
  // 透传给 FCM/APNs。加入 provider 域隔离后取完整 SHA-256，跨实例稳定。
  const opaqueIdentity = crypto.createHash('sha256')
    .update(`quota-notification-target\0${providerId}\0${accountIdentity}`)
    .digest('hex');
  return `${providerId}:${opaqueIdentity}`;
}

function legacyNotificationTargetIds(provider) {
  const providerId = String(provider?.provider || '').trim();
  const plainIds = [provider?.accountIdentity, provider?.accountKey]
    .map((value) => String(value || '').trim())
    .filter(Boolean)
    .map((value) => `${providerId}:${encodeURIComponent(value)}`);
  const accountKey = String(provider?.accountKey || '').trim();
  const opaqueAccountKeyId = accountKey
    ? notificationTargetId({ provider: providerId, accountKey })
    : '';
  return [...new Set([...plainIds, opaqueAccountKeyId].filter(Boolean))];
}

function notificationWindowId(window) {
  const metric = String(window?.metric || 'quota').trim().toLowerCase() || 'quota';
  const kind = String(window?.kind || '').trim().toLowerCase();
  const minutes = Number.isFinite(Number(window?.windowMinutes)) ? Number(window.windowMinutes) : '';
  return `${metric}:${kind}:${minutes}`;
}

function buildNotificationTargets(limits) {
  const providers = Array.isArray(limits?.providers) ? limits.providers : [];
  return providers
    .filter((provider) => provider && provider.status !== 'notConfigured' && provider.status !== 'disabled')
    .map((provider) => {
      const windows = (Array.isArray(provider.windows) ? provider.windows : [])
        // 余额和消费不是百分比周期额度，尚无“刷新到 100%”的准确语义。
        .filter((window) => !window?.metric && Number.isFinite(Number(window?.remainingPercent)))
        .map((window) => {
          const legacyWindowId = notificationWindowId(window);
          const windowId = String(window.windowId || legacyWindowId);
          return {
          id: windowId,
          windowId,
          kind: window.kind,
          label: window.label || window.kind,
          windowMinutes: window.windowMinutes ?? null,
          remainingPercent: Number(window.remainingPercent),
          resetsAt: window.resetsAt || null,
          legacy: { windowId: legacyWindowId }
          };
        });
      const legacyTargetIds = legacyNotificationTargetIds(provider)
        .filter((id) => id !== notificationTargetId(provider));
      return {
        id: notificationTargetId(provider),
        provider: provider.provider,
        accountIdentity: provider.accountIdentity || provider.accountKey || '',
        accountKey: provider.accountKey || '',
        accountLabel: provider.accountEmail || provider.accountName || provider.accountLabel || '',
        planLabel: provider.planLabel || '',
        updatedAt: provider.updatedAt || '',
        legacy: {
          targetId: legacyTargetIds[0] || '',
          targetIds: legacyTargetIds,
          accountKey: provider.accountKey || ''
        },
        windows
      };
    })
    .filter((target) => target.windows.length > 0);
}

function badRules(message) {
  const error = new Error(message);
  error.code = 'bad_notification_rules';
  return error;
}

function containsControlCharacter(value) {
  return [...String(value)].some((character) => {
    const codePoint = character.codePointAt(0);
    return codePoint <= 31 || codePoint === 127;
  });
}

function normalizeRule(input) {
  if (!input || typeof input !== 'object') throw badRules('rule must be an object');
  const targetId = String(input.targetId || '').trim();
  const id = String(input.id || targetId).trim();
  if (!id || id.length > 128) throw badRules('rule id is required');
  if (!targetId || targetId.length > 512) throw badRules('targetId is required');
  if (containsControlCharacter(id) || containsControlCharacter(targetId)) {
    throw badRules('rule identifiers must not contain control characters');
  }
  const threshold = Number(input.thresholdPercent ?? input.remainingThreshold);
  if (!Number.isFinite(threshold) || threshold < 0 || threshold > 100) {
    throw badRules('thresholdPercent must be between 0 and 100');
  }
  if (!Array.isArray(input.windowIds) || input.windowIds.length === 0) {
    throw badRules('windowIds must be a non-empty array');
  }
  const windowIds = [...new Set(input.windowIds.map((idValue) => String(idValue || '').trim()))];
  if (windowIds.some((idValue) => !idValue || idValue.length > 128)) {
    throw badRules('windowIds contains an invalid value');
  }
  if (windowIds.some(containsControlCharacter)) {
    throw badRules('windowIds contains control characters');
  }
  return {
    id,
    targetId,
    enabled: input.enabled !== false,
    refreshEnabled: input.refreshEnabled !== false,
    warningEnabled: input.warningEnabled !== false,
    thresholdPercent: Number(threshold.toFixed(3)),
    windowIds
  };
}

function normalizeNotificationRules(rules) {
  if (!Array.isArray(rules)) throw badRules('rules must be an array');
  const normalized = rules.map(normalizeRule);
  const ids = new Set();
  for (const rule of normalized) {
    if (ids.has(rule.id)) throw badRules('rule id must be unique');
    ids.add(rule.id);
  }
  return normalized;
}

function notificationRulesDocument(rules, { previous, now = new Date() } = {}) {
  const candidateMs = now instanceof Date ? now.getTime() : Date.parse(String(now));
  const previousMs = Date.parse(String(previous?.updatedAt || ''));
  const safeCandidateMs = Number.isFinite(candidateMs) ? candidateMs : Date.now();
  // updatedAt 是乐观锁令牌。同一毫秒内连续保存也必须前进，否则旧客户端可能
  // 带着相同令牌覆盖新文档。
  const updatedAtMs = Number.isFinite(previousMs) && safeCandidateMs <= previousMs
    ? previousMs + 1
    : safeCandidateMs;
  return {
    version: Number(previous?.version || 0) + 1,
    updatedAt: new Date(updatedAtMs).toISOString(),
    rules: normalizeNotificationRules(rules)
  };
}

function isStaleNotificationRulesWrite(current, baseUpdatedAt) {
  return String(current?.updatedAt || '') !== String(baseUpdatedAt || '');
}

module.exports = {
  notificationTargetId,
  legacyNotificationTargetIds,
  notificationWindowId,
  buildNotificationTargets,
  normalizeNotificationRules,
  notificationRulesDocument,
  isStaleNotificationRulesWrite
};
