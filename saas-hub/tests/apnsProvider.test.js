'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { generateKeyPairSync } = require('node:crypto');
const { createApnsProvider } = require('../src/push/apnsProvider');

function apnsConfig() {
  const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  return {
    teamId: 'TEAM123456',
    keyId: 'KEY1234567',
    bundleId: 'com.zneox.ztoken.ztokenMonitor',
    privateKey: privateKey.export({ type: 'pkcs8', format: 'pem' })
  };
}

test('APNs 按 token 环境选择 host 并发送 alert payload', async () => {
  const calls = [];
  const provider = createApnsProvider({
    ...apnsConfig(),
    requestImpl: async (request) => {
      calls.push(request);
      return { status: 200, body: '' };
    },
    now: () => Date.parse('2026-08-12T00:00:00.000Z')
  });

  await provider.send({
    token: 'a'.repeat(64),
    environment: 'sandbox',
    event: {
      id: 'evt-ios',
      type: 'refresh',
      title: '配额已刷新',
      body: '每周额度已恢复',
      targetId: 'target-ios',
      windowId: 'weekly'
    }
  });

  assert.equal(calls[0].origin, 'https://api.sandbox.push.apple.com');
  assert.equal(calls[0].headers['apns-topic'], 'com.zneox.ztoken.ztokenMonitor');
  assert.equal(calls[0].headers['apns-push-type'], 'alert');
  assert.match(calls[0].headers.authorization, /^bearer [^.]+\.[^.]+\.[^.]+$/);
  const payload = JSON.parse(calls[0].body);
  assert.deepEqual(payload.aps.alert, { title: '配额已刷新', body: '每周额度已恢复' });
  assert.equal(payload.eventId, 'evt-ios');
  assert.equal(payload.eventType, 'refresh');
  assert.equal(payload.type, 'refresh');
  assert.equal(payload.route, '/limits');
  assert.equal(payload.targetId, 'target-ios');
});

test('APNs 将 Unregistered 标记为无效令牌', async () => {
  const provider = createApnsProvider({
    ...apnsConfig(),
    requestImpl: async () => ({ status: 410, body: JSON.stringify({ reason: 'Unregistered' }) })
  });
  await assert.rejects(
    () => provider.send({ token: 'b'.repeat(64), event: { id: 'e', type: 'warning', title: 't', body: 'b' } }),
    (error) => error.code === 'invalid_push_token' && error.invalidToken === true
  );
});

test('APNs 将 503 标记为可重试错误', async () => {
  const provider = createApnsProvider({
    ...apnsConfig(),
    requestImpl: async () => ({ status: 503, body: JSON.stringify({ reason: 'ServiceUnavailable' }) })
  });
  await assert.rejects(
    () => provider.send({ token: 'c'.repeat(64), event: { id: 'e', type: 'warning', title: 't', body: 'b' } }),
    (error) => error.code === 'push_service_unavailable' && error.retryable === true
  );
});

test('APNs 拒绝非法 device token，且不发网络请求', async () => {
  let called = false;
  const provider = createApnsProvider({
    ...apnsConfig(),
    requestImpl: async () => { called = true; return { status: 200, body: '' }; }
  });
  await assert.rejects(
    () => provider.send({ token: '../bad', event: { id: 'e', type: 'warning', title: 't', body: 'b' } }),
    (error) => error.code === 'invalid_push_token'
  );
  assert.equal(called, false);
});

test('APNs 接受 Outbox 的 notification/data 包装形态', async () => {
  let sent = null;
  const provider = createApnsProvider({
    ...apnsConfig(),
    requestImpl: async (request) => { sent = request; return { status: 200, body: '' }; }
  });
  await provider.send({
    token: 'd'.repeat(64),
    event: {
      eventId: 'evt-wrapped',
      eventType: 'quota_refreshed',
      targetId: 'target',
      windowId: 'weekly',
      notification: { title: '额度已刷新', body: '打开查看' },
      data: { eventId: 'evt-wrapped', type: 'quota_refreshed' }
    }
  });
  const payload = JSON.parse(sent.body);
  assert.deepEqual(payload.aps.alert, { title: '额度已刷新', body: '打开查看' });
  assert.equal(payload.eventId, 'evt-wrapped');
  assert.equal(payload.eventType, 'quota_refreshed');
  assert.equal(payload.type, 'quota_refreshed');
});
