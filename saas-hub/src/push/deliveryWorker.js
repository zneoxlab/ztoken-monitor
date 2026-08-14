'use strict';

const crypto = require('node:crypto');
const { pushErrorCode } = require('./errors');

const MAX_RETRY_DELAY_MS = 60 * 60 * 1000;

function retryDelayMs(attempts) {
  const exponent = Math.max(0, Math.floor(Number(attempts) || 1) - 1);
  return Math.min(MAX_RETRY_DELAY_MS, 30_000 * (2 ** exponent));
}

function createDeliveryWorker({
  store,
  providers,
  decryptToken,
  batchSize = 50,
  leaseMs = 60_000,
  maxAttempts = 8,
  now = Date.now,
  randomId = () => crypto.randomUUID(),
  logger = console
} = {}) {
  if (!store || typeof store.claim !== 'function') throw new Error('delivery store is required');
  if (!providers || typeof providers !== 'object') throw new Error('push providers are required');
  if (typeof decryptToken !== 'function') throw new Error('decryptToken is required');

  async function transition(method, command, summary, key) {
    const applied = await store[method](command);
    if (applied !== false) {
      summary[key] += 1;
      return true;
    }
    summary.leaseLost += 1;
    logger.warn?.(`[push-worker] delivery ${command.deliveryId} lost lease before ${method}`);
    return false;
  }

  function startLeaseHeartbeat(row, leaseId) {
    if (typeof store.renewLease !== 'function') return () => {};
    const intervalMs = Math.max(1_000, Math.floor(leaseMs / 3));
    let timer = null;
    let inFlight = Promise.resolve();
    const renew = () => {
      inFlight = store.renewLease({
        deliveryId: row.id,
        leaseId,
        leaseUntil: new Date(now() + leaseMs).toISOString()
      }).then((renewed) => {
        if (renewed === false) {
          logger.warn?.(`[push-worker] delivery ${row.id} lease renewal was rejected`);
        }
      }).catch((error) => {
        logger.warn?.(`[push-worker] delivery ${row.id} lease renewal failed: ${error.message}`);
      });
    };
    timer = setInterval(renew, intervalMs);
    timer.unref?.();
    return async () => {
      clearInterval(timer);
      await inFlight;
    };
  }

  async function ensureFreshLease(row, leaseId) {
    if (typeof store.renewLease !== 'function') return true;
    try {
      return await store.renewLease({
        deliveryId: row.id,
        leaseId,
        leaseUntil: new Date(now() + leaseMs).toISOString()
      });
    } catch (error) {
      logger.warn?.(`[push-worker] delivery ${row.id} initial lease renewal failed: ${error.message}`);
      return false;
    }
  }

  async function deliver(row, summary, leaseId) {
    if (!await ensureFreshLease(row, leaseId)) {
      summary.leaseLost += 1;
      return;
    }
    const provider = providers[row.provider];
    if (!provider || typeof provider.send !== 'function') {
      // 凭证可能在部署后补齐；配置缺失不是消息本身的永久错误，保留在 Outbox。
      await transition('markRetry', {
        deliveryId: row.id,
        leaseId,
        nextAttemptAt: new Date(now() + MAX_RETRY_DELAY_MS).toISOString(),
        lastError: 'push_provider_unconfigured'
      }, summary, 'retried');
      return;
    }
    let token;
    try {
      token = decryptToken({
        tokenCiphertext: row.tokenCiphertext,
        tokenIv: row.tokenIv,
        tokenTag: row.tokenTag,
        keyVersion: row.keyVersion
      });
    } catch (_) {
      await transition('markFailed', {
        deliveryId: row.id, leaseId, lastError: 'push_token_decrypt_failed'
      }, summary, 'failed');
      return;
    }

    const stopHeartbeat = startLeaseHeartbeat(row, leaseId);
    try {
      const result = await provider.send({
        token,
        environment: row.environment,
        event: row.event || row.payload || {}
      });
      await transition('markSent', {
        deliveryId: row.id, leaseId, result: result || {}
      }, summary, 'sent');
    } catch (error) {
      const reason = pushErrorCode(error);
      if (error?.invalidToken) {
        await transition('markInvalid', {
          deliveryId: row.id,
          installationId: row.installationId,
          leaseId,
          lastError: reason
        }, summary, 'invalid');
        return;
      }
      const attempts = Math.max(1, Number(row.attempts) || 1);
      if (error?.retryable && attempts < maxAttempts) {
        const nextAttemptAt = new Date(now() + retryDelayMs(attempts)).toISOString();
        await transition('markRetry', {
          deliveryId: row.id,
          leaseId,
          nextAttemptAt,
          lastError: reason
        }, summary, 'retried');
        return;
      }
      await transition('markFailed', {
        deliveryId: row.id, leaseId, lastError: reason
      }, summary, 'failed');
      logger.warn?.(`[push-worker] delivery ${row.id} failed: ${reason}`);
    } finally {
      await stopHeartbeat();
    }
  }

  async function runBatch() {
    const leaseId = randomId();
    const leaseUntil = new Date(now() + leaseMs).toISOString();
    const rows = await store.claim({ batchSize, leaseId, leaseUntil });
    const summary = {
      claimed: rows.length, sent: 0, retried: 0, invalid: 0, failed: 0, leaseLost: 0
    };
    for (const row of rows) await deliver(row, summary, leaseId);
    return summary;
  }

  return { runBatch };
}

module.exports = { createDeliveryWorker, retryDelayMs };
