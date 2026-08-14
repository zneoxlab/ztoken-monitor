'use strict';

class PushDeliveryError extends Error {
  constructor(message, { code = 'push_delivery_failed', retryable = false, invalidToken = false, status = 0 } = {}) {
    super(message);
    this.name = 'PushDeliveryError';
    this.code = code;
    this.retryable = retryable;
    this.invalidToken = invalidToken;
    this.status = status;
  }
}

function pushErrorCode(error) {
  const code = String(error?.code || '').trim();
  return /^[a-z0-9_]{1,64}$/.test(code) ? code : 'push_delivery_failed';
}

module.exports = { PushDeliveryError, pushErrorCode };
