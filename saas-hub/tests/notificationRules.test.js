'use strict';

const test = require('node:test');
const assert = require('node:assert');
const {
  notificationRulesDocument,
  notificationTargetId,
  legacyNotificationTargetIds
} = require('../src/notificationRules');
const { quotaNotificationStateKey } = require('../src/db');
const { makeDedupeKey } = require('../src/quotaNotifications');

const sampleRule = {
  id: 'codex-main',
  targetId: 'codex:main',
  enabled: true,
  refreshEnabled: true,
  warningEnabled: true,
  thresholdPercent: 20,
  windowIds: ['session-5h']
};

test('规则乐观锁令牌在同一毫秒连续保存时仍严格递增', () => {
  const now = new Date('2026-08-12T00:00:00.000Z');
  const first = notificationRulesDocument([sampleRule], { now });
  const second = notificationRulesDocument([sampleRule], { previous: first, now });
  assert.equal(first.updatedAt, '2026-08-12T00:00:00.000Z');
  assert.equal(second.updatedAt, '2026-08-12T00:00:00.001Z');
  assert.equal(second.version, first.version + 1);
});

test('规则重新基线后相同周期序号不会与旧事件去重键冲突', () => {
  const target = { id: 'codex:main' };
  const window = { id: 'session-5h' };
  const first = makeDedupeKey(1, sampleRule, target, window, 'quota_warning', 1, 2);
  const second = makeDedupeKey(1, sampleRule, target, window, 'quota_warning', 1, 3);
  assert.notEqual(first, second);
});

test('通知目标 ID 不暴露账户身份原值且保持确定性', () => {
  const provider = { provider: 'codex', accountIdentity: 'person@example.com' };
  const first = notificationTargetId(provider);
  assert.equal(first, notificationTargetId(provider));
  assert.equal(first.startsWith('codex:'), true);
  assert.equal(first.includes('person@example.com'), false);
  assert.match(first, /^codex:[a-f0-9]{64}$/);
});

test('状态主键使用固定长度哈希且保留字段边界', () => {
  const base = { ruleId: 'ab', targetId: 'c', windowId: 'd' };
  const other = { ruleId: 'a', targetId: 'bc', windowId: 'd' };
  assert.match(quotaNotificationStateKey(1, base), /^[a-f0-9]{64}$/);
  assert.notEqual(quotaNotificationStateKey(1, base), quotaNotificationStateKey(1, other));
});

test('目标升级兼容 identity/key 明文 ID 和 accountKey 旧匿名 ID', () => {
  const provider = {
    provider: 'codex', accountIdentity: 'identity-1', accountKey: 'account-1'
  };
  assert.deepEqual(legacyNotificationTargetIds(provider), [
    'codex:identity-1',
    'codex:account-1',
    notificationTargetId({ provider: 'codex', accountKey: 'account-1' })
  ]);
});

test('规则 ID 拒绝控制字符，状态哈希分隔无歧义', () => {
  assert.throws(
    () => notificationRulesDocument([{ ...sampleRule, targetId: 'codex:\0other' }]),
    /control characters/
  );
});
