'use strict';

const test = require('node:test');
const assert = require('node:assert');
const {
  createPushProviders,
  createDbDeliveryStore,
  createPushWorkerRuntime,
  runWorkerLoop
} = require('../src/push-worker');

test('createPushProviders 只启用已配置的 provider', () => {
  const files = new Map([
    ['/secrets/fcm.json', JSON.stringify({
      project_id: 'project',
      client_email: 'push@example.invalid',
      private_key: 'private-key'
    })]
  ]);
  const providers = createPushProviders({
    fcm: { serviceAccountFile: '/secrets/fcm.json' },
    apns: { keyFile: '', keyId: '', teamId: '', bundleId: 'app.id' }
  }, {
    fsApi: { readFileSync: (path) => files.get(path) }
  });
  assert.deepEqual(Object.keys(providers), ['fcm']);
});

test('APNs 任一凭证存在时要求配置完整', () => {
  assert.throws(
    () => createPushProviders({
      fcm: { serviceAccountFile: '' },
      apns: { keyFile: '/key.p8', keyId: '', teamId: '', bundleId: 'app.id' }
    }),
    /APNs 配置不完整/
  );
});

test('DB store 将命令原样传给租赁安全的数据访问函数', async () => {
  const calls = [];
  const dbApi = {
    claimPushDeliveries: async (pool, input) => { calls.push(['claim', pool, input]); return []; },
    renewPushDeliveryLease: async (pool, input) => calls.push(['renew', pool, input]),
    markPushDeliverySent: async (pool, input) => calls.push(['sent', pool, input]),
    markPushDeliveryRetry: async (pool, input) => calls.push(['retry', pool, input]),
    markPushDeliveryFailed: async (pool, input) => calls.push(['failed', pool, input]),
    markPushDeliveryInvalid: async (pool, input) => calls.push(['invalid', pool, input])
  };
  const pool = {};
  const store = createDbDeliveryStore(pool, dbApi);
  await store.claim({ leaseId: 'lease' });
  await store.renewLease({ deliveryId: 1, leaseId: 'lease' });
  await store.markSent({ deliveryId: 1, leaseId: 'lease' });
  assert.deepEqual(calls, [
    ['claim', pool, { leaseId: 'lease' }],
    ['renew', pool, { deliveryId: 1, leaseId: 'lease' }],
    ['sent', pool, { deliveryId: 1, leaseId: 'lease' }]
  ]);
});

test('runtime 缺少加密密钥或发送 provider 时拒绝启动', () => {
  const base = {
    mysql: {},
    push: {
      tokenEncryptionKey: '',
      batchSize: 1,
      leaseMs: 5_000,
      maxAttempts: 2,
      fcm: { serviceAccountFile: '' },
      apns: { keyFile: '', keyId: '', teamId: '', bundleId: 'app.id' }
    }
  };
  assert.throws(() => createPushWorkerRuntime(base, { pool: {} }), /ENCRYPTION_KEY/);
  assert.throws(
    () => createPushWorkerRuntime({
      ...base,
      push: { ...base.push, tokenEncryptionKey: 'test-key' }
    }, { pool: {} }),
    /均未配置/
  );
});

test('同进程 Hub 停止时可以用 AbortSignal 唤醒空闲轮询', async () => {
  const controller = new AbortController();
  const runtime = { runBatch: async () => ({ claimed: 0 }) };
  const startedAt = Date.now();
  setTimeout(() => controller.abort(), 10);
  await runWorkerLoop(runtime, {
    pollIntervalMs: 60_000,
    signal: controller.signal,
    logger: { error() {} }
  });
  assert.ok(Date.now() - startedAt < 2_000, '停止信号不应等待完整轮询周期');
});
