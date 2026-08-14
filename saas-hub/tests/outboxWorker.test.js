'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { createDeliveryWorker, retryDelayMs } = require('../src/push/deliveryWorker');

function row(overrides = {}) {
  return {
    id: 1,
    installationId: 'install-1',
    provider: 'fcm',
    tokenCiphertext: 'encrypted',
    environment: '',
    attempts: 1,
    event: { id: 'evt-1', type: 'warning', title: '配额预警', body: '剩余较低' },
    ...overrides
  };
}

test('worker 成功投递后标记 sent', async () => {
  const calls = [];
  const store = {
    claim: async () => [row()],
    renewLease: async () => true,
    markSent: async (command) => calls.push(['sent', command]),
    markRetry: async () => assert.fail('不应重试'),
    markFailed: async () => assert.fail('不应失败'),
    markInvalid: async () => assert.fail('不应失效')
  };
  const worker = createDeliveryWorker({
    store,
    providers: { fcm: { send: async ({ token }) => ({ messageId: `m:${token}` }) } },
    decryptToken: () => 'plain-token',
    now: () => Date.parse('2026-08-12T00:00:00.000Z'),
    randomId: () => 'lease-1'
  });
  const result = await worker.runBatch();
  assert.deepEqual(result, {
    claimed: 1, sent: 1, retried: 0, invalid: 0, failed: 0, leaseLost: 0
  });
  assert.deepEqual(calls, [[
    'sent',
    { deliveryId: 1, leaseId: 'lease-1', result: { messageId: 'm:plain-token' } }
  ]]);
});

test('worker 对可重试错误安排指数退避', async () => {
  const retries = [];
  const store = {
    claim: async () => [row({ attempts: 3 })],
    renewLease: async () => true,
    markSent: async () => assert.fail('不应成功'),
    markRetry: async (command) => retries.push(command),
    markFailed: async () => assert.fail('不应永久失败'),
    markInvalid: async () => assert.fail('不应失效')
  };
  const error = Object.assign(new Error('busy'), { retryable: true, code: 'push_rate_limited' });
  const now = Date.parse('2026-08-12T00:00:00.000Z');
  const worker = createDeliveryWorker({
    store,
    providers: { fcm: { send: async () => { throw error; } } },
    decryptToken: () => 'plain',
    now: () => now,
    randomId: () => 'lease'
  });
  const result = await worker.runBatch();
  assert.equal(result.retried, 1);
  assert.equal(retries[0].deliveryId, 1);
  assert.equal(retries[0].leaseId, 'lease');
  assert.equal(new Date(retries[0].nextAttemptAt).getTime(), now + retryDelayMs(3));
  assert.equal(retries[0].lastError, 'push_rate_limited');
});

test('worker 对无效令牌撤销 installation', async () => {
  let invalid = null;
  const store = {
    claim: async () => [row()],
    renewLease: async () => true,
    markSent: async () => assert.fail('不应成功'),
    markRetry: async () => assert.fail('不应重试'),
    markFailed: async () => assert.fail('不应永久失败'),
    markInvalid: async (command) => { invalid = command; }
  };
  const error = Object.assign(new Error('gone'), { invalidToken: true, code: 'invalid_push_token' });
  const worker = createDeliveryWorker({
    store,
    providers: { fcm: { send: async () => { throw error; } } },
    decryptToken: () => 'plain',
    randomId: () => 'lease'
  });
  const result = await worker.runBatch();
  assert.equal(result.invalid, 1);
  assert.deepEqual(invalid, {
    deliveryId: 1,
    installationId: 'install-1',
    leaseId: 'lease',
    lastError: 'invalid_push_token'
  });
});

test('worker 达到最大次数后标记 failed，不无限重试', async () => {
  let failed = null;
  const store = {
    claim: async () => [row({ attempts: 8 })],
    renewLease: async () => true,
    markSent: async () => assert.fail('不应成功'),
    markRetry: async () => assert.fail('不应重试'),
    markFailed: async (command) => { failed = command; },
    markInvalid: async () => assert.fail('不应失效')
  };
  const worker = createDeliveryWorker({
    store,
    providers: { fcm: { send: async () => { throw new Error('network'); } } },
    decryptToken: () => 'plain',
    maxAttempts: 8
  });
  const result = await worker.runBatch();
  assert.equal(result.failed, 1);
  assert.equal(failed.deliveryId, 1);
  assert.equal(failed.lastError, 'push_delivery_failed');
});

test('retryDelayMs 有上限且按尝试次数增长', () => {
  assert.equal(retryDelayMs(1), 30_000);
  assert.equal(retryDelayMs(2), 60_000);
  assert.equal(retryDelayMs(30), 3_600_000);
});

test('未配置的 provider 保留在 Outbox，等待部署补齐凭证', async () => {
  let retry = null;
  const now = Date.parse('2026-08-12T00:00:00.000Z');
  const worker = createDeliveryWorker({
    store: {
      claim: async () => [row({ provider: 'apns' })],
      renewLease: async () => true,
      markSent: async () => assert.fail('不应成功'),
      markRetry: async (command) => { retry = command; },
      markFailed: async () => assert.fail('不应永久失败'),
      markInvalid: async () => assert.fail('不应失效')
    },
    providers: {},
    decryptToken: () => 'plain',
    now: () => now,
    randomId: () => 'lease'
  });
  const result = await worker.runBatch();
  assert.equal(result.retried, 1);
  assert.equal(retry.lastError, 'push_provider_unconfigured');
  assert.equal(new Date(retry.nextAttemptAt).getTime(), now + 3_600_000);
});

test('租约状态写入被拒绝时不谎报成功', async () => {
  const worker = createDeliveryWorker({
    store: {
      claim: async () => [row()],
      renewLease: async () => true,
      markSent: async () => false,
      markRetry: async () => false,
      markFailed: async () => false,
      markInvalid: async () => false
    },
    providers: { fcm: { send: async () => ({ messageId: 'sent-outside-db' }) } },
    decryptToken: () => 'plain',
    logger: { warn() {} }
  });
  const result = await worker.runBatch();
  assert.equal(result.sent, 0);
  assert.equal(result.leaseLost, 1);
});

test('排队期间租约已丢失时不会调用外部推送服务', async () => {
  let sent = 0;
  const worker = createDeliveryWorker({
    store: {
      claim: async () => [row()],
      renewLease: async () => false,
      markSent: async () => assert.fail('不应落 sent'),
      markRetry: async () => assert.fail('不应重试'),
      markFailed: async () => assert.fail('不应失败'),
      markInvalid: async () => assert.fail('不应失效')
    },
    providers: { fcm: { send: async () => { sent += 1; } } },
    decryptToken: () => 'plain'
  });
  const result = await worker.runBatch();
  assert.equal(sent, 0);
  assert.equal(result.leaseLost, 1);
});
