'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { resolvePushConfig } = require('../src/config');

test('push config 提供安全的 worker 默认值', () => {
  assert.deepEqual(resolvePushConfig({}), {
    tokenEncryptionKey: '',
    pollIntervalMs: 5_000,
    batchSize: 50,
    leaseMs: 60_000,
    maxAttempts: 8,
    fcm: { serviceAccountFile: '' },
    apns: {
      keyFile: '',
      keyId: '',
      teamId: '',
      bundleId: 'com.zneox.ztoken.ztokenMonitor'
    }
  });
});

test('push config 限制批量、轮询和重试参数范围', () => {
  const config = resolvePushConfig({
    SAAS_HUB_PUSH_POLL_INTERVAL_MS: '1',
    SAAS_HUB_PUSH_BATCH_SIZE: '9999',
    SAAS_HUB_PUSH_LEASE_MS: '2000',
    SAAS_HUB_PUSH_MAX_ATTEMPTS: '999',
    SAAS_HUB_PUSH_TOKEN_ENCRYPTION_KEY: '  secret  ',
    SAAS_HUB_FCM_SERVICE_ACCOUNT_FILE: ' /run/secrets/fcm.json ',
    SAAS_HUB_APNS_KEY_FILE: ' /run/secrets/AuthKey.p8 ',
    SAAS_HUB_APNS_KEY_ID: ' KEY ',
    SAAS_HUB_APNS_TEAM_ID: ' TEAM ',
    SAAS_HUB_APNS_BUNDLE_ID: ' app.id '
  });
  assert.equal(config.pollIntervalMs, 250);
  assert.equal(config.batchSize, 500);
  assert.equal(config.leaseMs, 5_000);
  assert.equal(config.maxAttempts, 20);
  assert.equal(config.tokenEncryptionKey, 'secret');
  assert.equal(config.fcm.serviceAccountFile, '/run/secrets/fcm.json');
  assert.deepEqual(config.apns, {
    keyFile: '/run/secrets/AuthKey.p8',
    keyId: 'KEY',
    teamId: 'TEAM',
    bundleId: 'app.id'
  });
});
