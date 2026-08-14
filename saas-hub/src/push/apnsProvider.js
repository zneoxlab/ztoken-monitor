'use strict';

const crypto = require('node:crypto');
const http2 = require('node:http2');
const { PushDeliveryError } = require('./errors');

const APNS_TOKEN_TTL_MS = 50 * 60 * 1000;
const INVALID_TOKEN_REASONS = new Set(['BadDeviceToken', 'DeviceTokenNotForTopic', 'Unregistered']);

function base64urlJson(value) {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}

function apnsJwt({ teamId, keyId, privateKey, nowMs }) {
  const header = base64urlJson({ alg: 'ES256', kid: keyId });
  const claims = base64urlJson({ iss: teamId, iat: Math.floor(nowMs / 1000) });
  const input = `${header}.${claims}`;
  const signature = crypto.sign('sha256', Buffer.from(input), {
    key: privateKey,
    dsaEncoding: 'ieee-p1363'
  });
  return `${input}.${signature.toString('base64url')}`;
}

function defaultRequest({ origin, path, headers, body, timeoutMs = 20_000 }) {
  return new Promise((resolve, reject) => {
    const client = http2.connect(origin);
    let settled = false;
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      client.close();
      if (error) reject(error); else resolve(value);
    };
    client.once('error', (error) => finish(error));
    client.setTimeout(timeoutMs, () => finish(new Error('APNs request timed out')));
    const request = client.request({ ':method': 'POST', ':path': path, ...headers });
    let status = 0;
    let responseBody = '';
    request.setEncoding('utf8');
    request.on('response', (responseHeaders) => {
      status = Number(responseHeaders[':status'] || 0);
    });
    request.on('data', (chunk) => { responseBody += chunk; });
    request.on('end', () => finish(null, { status, body: responseBody }));
    request.on('error', (error) => finish(error));
    request.end(body);
  });
}

function apnsError(status, body) {
  let reason = '';
  try { reason = JSON.parse(body || '{}').reason || ''; } catch (_) {}
  if (status === 410 || INVALID_TOKEN_REASONS.has(reason)) {
    return new PushDeliveryError('APNs device token is no longer valid', {
      code: 'invalid_push_token', invalidToken: true, status
    });
  }
  if (status === 429 || reason === 'TooManyRequests') {
    return new PushDeliveryError('APNs rate limit exceeded', {
      code: 'push_rate_limited', retryable: true, status
    });
  }
  if (status >= 500) {
    return new PushDeliveryError('APNs service unavailable', {
      code: 'push_service_unavailable', retryable: true, status
    });
  }
  return new PushDeliveryError('APNs rejected the notification', {
    code: 'push_rejected', retryable: false, status
  });
}

function apnsPayload(event) {
  const data = event?.data && typeof event.data === 'object' ? event.data : {};
  const notification = event?.notification && typeof event.notification === 'object'
    ? event.notification
    : {};
  const eventType = String(event.eventType || event.type || data.type || '');
  return {
    aps: {
      alert: {
        title: String(notification.title || event.title || '配额状态变化'),
        body: String(notification.body || event.body || '打开 ZT助手 查看详情')
      },
      sound: 'default',
      'thread-id': 'quota-status'
    },
    eventId: String(event.eventId || event.id || data.eventId || ''),
    eventType,
    type: eventType,
    route: '/limits',
    targetId: String(event.targetId || data.targetId || ''),
    windowId: String(event.windowId || data.windowId || '')
  };
}

function createApnsProvider({
  teamId,
  keyId,
  bundleId,
  privateKey,
  requestImpl = defaultRequest,
  now = Date.now,
  timeoutMs = 20_000
} = {}) {
  if (!teamId || !keyId || !bundleId || !privateKey) {
    throw new Error('APNs requires teamId, keyId, bundleId and privateKey');
  }
  let cachedJwt = '';
  let jwtCreatedAt = 0;

  function authToken() {
    const nowMs = now();
    if (cachedJwt && nowMs - jwtCreatedAt < APNS_TOKEN_TTL_MS) return cachedJwt;
    cachedJwt = apnsJwt({ teamId, keyId, privateKey, nowMs });
    jwtCreatedAt = nowMs;
    return cachedJwt;
  }

  async function send(delivery) {
    const token = String(delivery.token || '').trim();
    if (!/^[a-fA-F0-9]{32,256}$/.test(token)) {
      throw new PushDeliveryError('Invalid APNs device token', {
        code: 'invalid_push_token', invalidToken: true
      });
    }
    const event = delivery.event || {};
    const eventId = String(event.eventId || event.id || event.data?.eventId || 'quota-event').slice(0, 64);
    const origin = delivery.environment === 'sandbox'
      ? 'https://api.sandbox.push.apple.com'
      : 'https://api.push.apple.com';
    let response;
    try {
      response = await requestImpl({
        origin,
        path: `/3/device/${token}`,
        headers: {
          authorization: `bearer ${authToken()}`,
          'apns-topic': bundleId,
          'apns-push-type': 'alert',
          'apns-priority': '10',
          'apns-collapse-id': eventId
        },
        body: JSON.stringify(apnsPayload(event)),
        timeoutMs
      });
    } catch (_) {
      throw new PushDeliveryError('Unable to reach APNs', {
        code: 'push_network_error', retryable: true
      });
    }
    if (response.status === 200) return { messageId: eventId };
    throw apnsError(response.status, response.body);
  }

  return { send };
}

module.exports = {
  createApnsProvider,
  apnsJwt,
  apnsPayload,
  defaultRequest
};
