'use strict';

const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
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
