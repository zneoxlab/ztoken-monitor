'use strict';

const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { Readable } = require('node:stream');
const test = require('node:test');
const { createApiRoutes } = require('../src/routes/api');

function mockResponse() {
  const res = new EventEmitter();
  res.writeHead = () => {};
  res.write = () => {};
  res.end = () => {};
  res.headersSent = false;
  Object.defineProperty(res, 'headersSent', {
    get() { return this._headersSent || false; },
    set(v) { this._headersSent = v; }
  });
  const originalWriteHead = res.writeHead;
  res.writeHead = (...args) => {
    res._headersSent = true;
    return originalWriteHead(...args);
  };
  return res;
}

test('GET /api/stats/stream returns true after opening SSE', async () => {
  const sent = [];
  const sseRegistry = {
    sendSnapshot(res, stats) { sent.push({ res, stats }); },
    add(userId, res) {
      sent.push({ userId, res });
      return () => {};
    }
  };
  const hub = {
    async getStats(userId) {
      return { devices: [], userId };
    }
  };
  const api = createApiRoutes({
    pool: {},
    hub,
    db: {},
    sseRegistry,
    sendJson: () => true
  });

  const req = new EventEmitter();
  req.method = 'GET';
  req.userId = 42;
  const res = mockResponse();
  const url = new URL('http://localhost/api/stats/stream');

  const handled = await api.handle(req, res, url);
  assert.equal(handled, true);
  assert.equal(res.headersSent, true);
  assert.equal(sent.length, 2);
});

function jsonRequest(method, userId, body) {
  const req = Readable.from([JSON.stringify(body)]);
  req.method = method;
  req.userId = userId;
  req.headers = { 'content-type': 'application/json' };
  return req;
}

test('PUT push installation 在未注入密钥时返回 push_not_configured', async () => {
  const responses = [];
  const api = createApiRoutes({
    pool: {},
    db: {},
    sseRegistry: {},
    sendJson: (_res, status, payload) => { responses.push({ status, payload }); return true; },
    hub: {
      async registerPushInstallation() {
        const error = new Error('push_not_configured');
        error.code = 'push_not_configured';
        throw error;
      }
    }
  });
  const req = jsonRequest('PUT', 7, { platform: 'ios', token: 'token' });
  const handled = await api.handle(req, mockResponse(), new URL('http://localhost/api/push/installations/phone-1'));
  assert.equal(handled, true);
  assert.deepEqual(responses[0], { status: 503, payload: { error: 'push_not_configured' } });
});

test('PUT notification rules 将 stale_write 映射为 409 并携带当前文档', async () => {
  const responses = [];
  const current = { version: 2, updatedAt: '2026-08-12T00:00:00.000Z', rules: [] };
  const api = createApiRoutes({
    pool: {},
    db: {},
    sseRegistry: {},
    sendJson: (_res, status, payload) => { responses.push({ status, payload }); return true; },
    hub: {
      async setNotificationRules() {
        const error = new Error('stale_write');
        error.code = 'stale_write';
        error.current = current;
        throw error;
      }
    }
  });
  const req = jsonRequest('PUT', 7, { rules: [], baseUpdatedAt: '' });
  await api.handle(req, mockResponse(), new URL('http://localhost/api/notification-rules'));
  assert.deepEqual(responses[0], { status: 409, payload: { error: 'stale_write', ...current } });
});
