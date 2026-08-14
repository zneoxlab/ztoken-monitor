'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { generateKeyPairSync } = require('node:crypto');
const { createFcmProvider } = require('../src/push/fcmProvider');

function jsonResponse(status, body) {
  return {
    ok: status >= 200 && status < 300,
    status,
    async json() { return body; },
    async text() { return JSON.stringify(body); }
  };
}

function serviceAccount() {
  const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  return {
    project_id: 'quota-project',
    client_email: 'push@quota-project.iam.gserviceaccount.com',
    private_key: privateKey.export({ type: 'pkcs8', format: 'pem' })
  };
}

test('FCM 使用 service account 换 token 并发送最小隐私 payload', async () => {
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push({ url: String(url), options });
    if (String(url).includes('/token')) {
      return jsonResponse(200, { access_token: 'oauth-token', expires_in: 3600 });
    }
    return jsonResponse(200, { name: 'projects/quota-project/messages/1' });
  };
  const provider = createFcmProvider({
    serviceAccount: serviceAccount(),
    fetchImpl,
    now: () => Date.parse('2026-08-12T00:00:00.000Z')
  });

  const result = await provider.send({
    token: 'device-token',
    event: {
      id: 'evt-1',
      type: 'warning',
      title: '配额预警',
      body: '每周额度剩余较低',
      targetId: 'target-1',
      windowId: 'weekly'
    }
  });

  assert.equal(result.messageId, 'projects/quota-project/messages/1');
  assert.equal(calls.length, 2);
  assert.equal(calls[1].options.headers.authorization, 'Bearer oauth-token');
  const message = JSON.parse(calls[1].options.body).message;
  assert.equal(message.token, 'device-token');
  assert.deepEqual(message.notification, { title: '配额预警', body: '每周额度剩余较低' });
  assert.deepEqual(message.data, {
    eventId: 'evt-1',
    eventType: 'warning',
    type: 'warning',
    route: '/limits',
    targetId: 'target-1',
    windowId: 'weekly'
  });
  assert.equal(message.android.notification.tag, 'evt-1');
  assert.equal(message.android.notification.channel_id, 'quota_status');
});

test('FCM 缓存 OAuth token，避免每条通知重新认证', async () => {
  let tokenCalls = 0;
  const fetchImpl = async (url) => {
    if (String(url).includes('/token')) {
      tokenCalls += 1;
      return jsonResponse(200, { access_token: 'cached', expires_in: 3600 });
    }
    return jsonResponse(200, { name: 'message' });
  };
  const provider = createFcmProvider({ serviceAccount: serviceAccount(), fetchImpl });
  const delivery = { token: 'a', event: { id: 'evt', type: 'refresh', title: '刷新', body: '已刷新' } };
  await provider.send(delivery);
  await provider.send(delivery);
  assert.equal(tokenCalls, 1);
});

test('FCM 将 UNREGISTERED 标记为无效令牌', async () => {
  const fetchImpl = async (url) => {
    if (String(url).includes('/token')) {
      return jsonResponse(200, { access_token: 'oauth', expires_in: 3600 });
    }
    return jsonResponse(404, {
      error: { details: [{ errorCode: 'UNREGISTERED' }] }
    });
  };
  const provider = createFcmProvider({ serviceAccount: serviceAccount(), fetchImpl });
  await assert.rejects(
    () => provider.send({ token: 'expired', event: { id: 'e', type: 'warning', title: 't', body: 'b' } }),
    (error) => error.code === 'invalid_push_token' && error.invalidToken === true
  );
});

test('FCM 将 429 标记为可重试错误', async () => {
  const fetchImpl = async (url) => {
    if (String(url).includes('/token')) {
      return jsonResponse(200, { access_token: 'oauth', expires_in: 3600 });
    }
    return jsonResponse(429, { error: { status: 'RESOURCE_EXHAUSTED' } });
  };
  const provider = createFcmProvider({ serviceAccount: serviceAccount(), fetchImpl });
  await assert.rejects(
    () => provider.send({ token: 'busy', event: { id: 'e', type: 'warning', title: 't', body: 'b' } }),
    (error) => error.code === 'push_rate_limited' && error.retryable === true
  );
});

test('FCM 网络异常标记为可重试，不会把一次断网当永久失败', async () => {
  const provider = createFcmProvider({
    serviceAccount: serviceAccount(),
    fetchImpl: async () => { throw new TypeError('network down'); }
  });
  await assert.rejects(
    () => provider.send({ token: 'busy', event: { id: 'e', type: 'warning' } }),
    (error) => error.code === 'push_network_error' && error.retryable === true
  );
});

test('FCM 接受 Outbox 的 notification/data 包装形态', async () => {
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push({ url: String(url), options });
    if (String(url).includes('/token')) {
      return jsonResponse(200, { access_token: 'oauth', expires_in: 3600 });
    }
    return jsonResponse(200, { name: 'message' });
  };
  const provider = createFcmProvider({ serviceAccount: serviceAccount(), fetchImpl });
  await provider.send({
    token: 'token',
    event: {
      eventId: 'evt-wrapped',
      eventType: 'quota_warning',
      targetId: 'target',
      windowId: 'weekly',
      notification: { title: '额度预警', body: '打开查看' },
      data: { eventId: 'evt-wrapped', type: 'quota_warning' }
    }
  });
  const message = JSON.parse(calls[1].options.body).message;
  assert.deepEqual(message.notification, { title: '额度预警', body: '打开查看' });
  assert.equal(message.data.eventId, 'evt-wrapped');
  assert.equal(message.data.eventType, 'quota_warning');
});
