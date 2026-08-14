'use strict';

const crypto = require('node:crypto');
const { PushDeliveryError } = require('./errors');

const TOKEN_AUDIENCE = 'https://oauth2.googleapis.com/token';
const MESSAGING_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const TOKEN_REFRESH_SKEW_MS = 5 * 60 * 1000;

function base64urlJson(value) {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}

function serviceAccountAssertion(serviceAccount, nowMs) {
  const issuedAt = Math.floor(nowMs / 1000);
  const header = base64urlJson({ alg: 'RS256', typ: 'JWT' });
  const claims = base64urlJson({
    iss: serviceAccount.client_email,
    scope: MESSAGING_SCOPE,
    aud: TOKEN_AUDIENCE,
    iat: issuedAt,
    exp: issuedAt + 3600
  });
  const signingInput = `${header}.${claims}`;
  const signature = crypto.sign('RSA-SHA256', Buffer.from(signingInput), serviceAccount.private_key);
  return `${signingInput}.${signature.toString('base64url')}`;
}

async function responseJson(response) {
  try {
    return await response.json();
  } catch (_) {
    return {};
  }
}

function fcmError(body, status) {
  const details = Array.isArray(body?.error?.details) ? body.error.details : [];
  const fcmCode = details.map((entry) => entry?.errorCode).find(Boolean) || body?.error?.status || '';
  if (fcmCode === 'UNREGISTERED') {
    return new PushDeliveryError('FCM registration token is no longer valid', {
      code: 'invalid_push_token', invalidToken: true, status
    });
  }
  if (status === 429 || fcmCode === 'QUOTA_EXCEEDED' || fcmCode === 'RESOURCE_EXHAUSTED') {
    return new PushDeliveryError('FCM rate limit exceeded', {
      code: 'push_rate_limited', retryable: true, status
    });
  }
  if (status >= 500 || fcmCode === 'UNAVAILABLE' || fcmCode === 'INTERNAL') {
    return new PushDeliveryError('FCM service unavailable', {
      code: 'push_service_unavailable', retryable: true, status
    });
  }
  return new PushDeliveryError('FCM rejected the message', {
    code: 'push_rejected', retryable: false, status
  });
}

async function fetchFcm(fetchImpl, url, options, timeoutMs = 20_000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  timer.unref?.();
  try {
    return await fetchImpl(url, { ...options, signal: controller.signal });
  } catch (_) {
    throw new PushDeliveryError('Unable to reach FCM', {
      code: 'push_network_error', retryable: true
    });
  } finally {
    clearTimeout(timer);
  }
}

function notificationData(event) {
  const data = event?.data && typeof event.data === 'object' ? event.data : {};
  const eventType = String(event.eventType || event.type || data.type || '');
  return {
    eventId: String(event.eventId || event.id || data.eventId || ''),
    eventType,
    type: eventType,
    route: '/limits',
    targetId: String(event.targetId || data.targetId || ''),
    windowId: String(event.windowId || data.windowId || '')
  };
}

function notificationText(event) {
  const notification = event?.notification && typeof event.notification === 'object'
    ? event.notification
    : {};
  return {
    title: String(notification.title || event?.title || '配额状态变化'),
    body: String(notification.body || event?.body || '打开 ZT助手 查看详情')
  };
}

function createFcmProvider({
  serviceAccount,
  fetchImpl = globalThis.fetch,
  now = Date.now,
  timeoutMs = 20_000
} = {}) {
  if (!serviceAccount?.project_id || !serviceAccount?.client_email || !serviceAccount?.private_key) {
    throw new Error('FCM service account requires project_id, client_email and private_key');
  }
  if (typeof fetchImpl !== 'function') throw new Error('FCM fetch implementation is unavailable');

  let cachedAccessToken = '';
  let accessTokenExpiresAt = 0;

  async function accessToken({ force = false } = {}) {
    const nowMs = now();
    if (!force && cachedAccessToken && nowMs + TOKEN_REFRESH_SKEW_MS < accessTokenExpiresAt) {
      return cachedAccessToken;
    }
    const assertion = serviceAccountAssertion(serviceAccount, nowMs);
    const response = await fetchFcm(fetchImpl, TOKEN_AUDIENCE, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion
      }).toString()
    }, timeoutMs);
    const body = await responseJson(response);
    if (!response.ok || !body.access_token) {
      throw new PushDeliveryError('Unable to authenticate with FCM', {
        code: 'push_auth_failed', retryable: response.status >= 500, status: response.status
      });
    }
    cachedAccessToken = String(body.access_token);
    const expiresIn = Math.max(60, Number(body.expires_in) || 3600);
    accessTokenExpiresAt = nowMs + expiresIn * 1000;
    return cachedAccessToken;
  }

  async function requestSend(delivery, { retryAuth = true } = {}) {
    const oauthToken = await accessToken();
    const event = delivery.event || {};
    const data = notificationData(event);
    const eventId = data.eventId || 'quota-event';
    const notification = notificationText(event);
    const response = await fetchFcm(
      fetchImpl,
      `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(serviceAccount.project_id)}/messages:send`,
      {
        method: 'POST',
        headers: {
          authorization: `Bearer ${oauthToken}`,
          'content-type': 'application/json; charset=utf-8'
        },
        body: JSON.stringify({
          message: {
            token: delivery.token,
            notification,
            data,
            android: {
              priority: 'high',
              notification: { tag: eventId, channel_id: 'quota_status' }
            }
          }
        })
      },
      timeoutMs
    );
    const body = await responseJson(response);
    if (response.ok) return { messageId: String(body.name || '') };
    if (response.status === 401 && retryAuth) {
      cachedAccessToken = '';
      accessTokenExpiresAt = 0;
      await accessToken({ force: true });
      return requestSend(delivery, { retryAuth: false });
    }
    throw fcmError(body, response.status);
  }

  return { send: requestSend };
}

module.exports = {
  createFcmProvider,
  serviceAccountAssertion,
  notificationData,
  notificationText,
  fetchFcm,
  MESSAGING_SCOPE,
  TOKEN_AUDIENCE
};
