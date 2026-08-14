'use strict';

const fs = require('node:fs');
const db = require('./db');
const { loadConfig } = require('./config');
const { createPushTokenCrypto } = require('./pushTokenCrypto');
const { createDeliveryWorker } = require('./push/deliveryWorker');
const { createFcmProvider } = require('./push/fcmProvider');
const { createApnsProvider } = require('./push/apnsProvider');

function readSecretFile(fsApi, filePath, label) {
  try {
    return fsApi.readFileSync(filePath, 'utf8');
  } catch (error) {
    throw new Error(`${label} 无法读取: ${error.message}`);
  }
}

function createPushProviders(pushConfig, {
  fsApi = fs,
  fetchImpl = globalThis.fetch,
  apnsRequestImpl
} = {}) {
  const providers = {};
  const fcmFile = pushConfig?.fcm?.serviceAccountFile;
  if (fcmFile) {
    let serviceAccount;
    try {
      serviceAccount = JSON.parse(readSecretFile(fsApi, fcmFile, 'FCM Service Account'));
    } catch (error) {
      if (error instanceof SyntaxError) throw new Error(`FCM Service Account JSON 无效: ${error.message}`);
      throw error;
    }
    providers.fcm = createFcmProvider({ serviceAccount, fetchImpl });
  }

  const apns = pushConfig?.apns || {};
  const hasAnyApnsSetting = Boolean(apns.keyFile || apns.keyId || apns.teamId);
  if (hasAnyApnsSetting) {
    if (!apns.keyFile || !apns.keyId || !apns.teamId || !apns.bundleId) {
      throw new Error('APNs 配置不完整，需要 keyFile、keyId、teamId 和 bundleId');
    }
    providers.apns = createApnsProvider({
      teamId: apns.teamId,
      keyId: apns.keyId,
      bundleId: apns.bundleId,
      privateKey: readSecretFile(fsApi, apns.keyFile, 'APNs .p8'),
      ...(apnsRequestImpl ? { requestImpl: apnsRequestImpl } : {})
    });
  }
  return providers;
}

function createDbDeliveryStore(pool, dbApi = db) {
  return {
    claim: (input) => dbApi.claimPushDeliveries(pool, input),
    renewLease: (input) => dbApi.renewPushDeliveryLease(pool, input),
    markSent: (input) => dbApi.markPushDeliverySent(pool, input),
    markRetry: (input) => dbApi.markPushDeliveryRetry(pool, input),
    markFailed: (input) => dbApi.markPushDeliveryFailed(pool, input),
    markInvalid: (input) => dbApi.markPushDeliveryInvalid(pool, input)
  };
}

function createPushWorkerRuntime(config, {
  dbApi = db,
  pool = null,
  providers = null,
  fsApi = fs,
  fetchImpl = globalThis.fetch,
  apnsRequestImpl,
  logger = console
} = {}) {
  const pushConfig = config?.push || {};
  const tokenCrypto = createPushTokenCrypto(pushConfig.tokenEncryptionKey);
  if (!tokenCrypto) {
    throw new Error('SAAS_HUB_PUSH_TOKEN_ENCRYPTION_KEY 未配置，Push Worker 拒绝启动');
  }
  const activeProviders = providers || createPushProviders(pushConfig, {
    fsApi,
    fetchImpl,
    apnsRequestImpl
  });
  if (Object.keys(activeProviders).length === 0) {
    throw new Error('FCM/APNs 均未配置，Push Worker 拒绝启动');
  }
  const activePool = pool || dbApi.createPool(config.mysql);
  const ownsPool = !pool;
  const store = createDbDeliveryStore(activePool, dbApi);
  const worker = createDeliveryWorker({
    store,
    providers: activeProviders,
    decryptToken: (envelope) => tokenCrypto.decrypt(envelope),
    batchSize: pushConfig.batchSize,
    leaseMs: pushConfig.leaseMs,
    maxAttempts: pushConfig.maxAttempts,
    logger
  });
  return {
    providers: Object.keys(activeProviders),
    runBatch: worker.runBatch,
    async close() {
      // HTTP Hub 将自己的 pool 注入进来时，Worker 只是借用它；只有独立
      // `node src/push-worker.js` 启动方式才由 Worker 负责释放连接池。
      if (ownsPool && typeof activePool.end === 'function') await activePool.end();
    }
  };
}

function delay(ms, signal = null) {
  if (!signal) return new Promise((resolve) => setTimeout(resolve, ms));
  if (signal.aborted) return Promise.resolve();
  return new Promise((resolve) => {
    let settled = false;
    const finish = () => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      signal.removeEventListener('abort', finish);
      resolve();
    };
    const timer = setTimeout(finish, ms);
    timer.unref?.();
    signal.addEventListener('abort', finish, { once: true });
  });
}

async function runWorkerLoop(runtime, {
  pollIntervalMs = 5_000,
  shouldStop = () => false,
  signal = null,
  logger = console
} = {}) {
  while (!shouldStop() && !signal?.aborted) {
    let claimed = 0;
    try {
      const summary = await runtime.runBatch();
      claimed = summary.claimed;
      if (claimed > 0) {
        logger.info?.(`[push-worker] claimed=${summary.claimed} sent=${summary.sent} retried=${summary.retried} invalid=${summary.invalid} failed=${summary.failed} lease_lost=${summary.leaseLost}`);
      }
    } catch (error) {
      logger.error?.(`[push-worker] batch failed: ${error.message}`);
    }
    if (claimed === 0 && !shouldStop() && !signal?.aborted) {
      await delay(pollIntervalMs, signal);
    }
  }
}

async function main() {
  const config = loadConfig();
  const runtime = createPushWorkerRuntime(config);
  let stopping = false;
  const stop = () => { stopping = true; };
  process.once('SIGINT', stop);
  process.once('SIGTERM', stop);
  console.log(`Push Worker started (${runtime.providers.join(', ')})`);
  try {
    await runWorkerLoop(runtime, {
      pollIntervalMs: config.push.pollIntervalMs,
      shouldStop: () => stopping
    });
  } finally {
    await runtime.close();
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(`Push Worker failed: ${error.message}`);
    process.exitCode = 1;
  });
}

module.exports = {
  createPushProviders,
  createDbDeliveryStore,
  createPushWorkerRuntime,
  runWorkerLoop,
  readSecretFile,
  main
};
