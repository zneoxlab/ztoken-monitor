'use strict';

// server.test.js — 端到端 HTTP 测试。需要 MySQL（SAAS_HUB_DB_TEST=1）。
// 用真实 server（port:0 随机端口），验证完整 wire shape 与多租户隔离。
// 无 MySQL 时整体跳过。

const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const { loadConfig } = require('../src/config');
const { createServer } = require('../src/server');
const db = require('../src/db');

let pool = null;
let serverInfo = null;

test.before(async () => {
  if (process.env.SAAS_HUB_DB_TEST !== '1') return;
  const config = loadConfig();
  // 测试用独立数据库，避免污染
  config.mysql.database = (config.mysql.database || 'token_monitor_saas') + '_test';
  try {
    pool = db.createPool({ ...config.mysql, database: undefined });
    await pool.query(`CREATE DATABASE IF NOT EXISTS \`${config.mysql.database}\``);
    await pool.end();
    pool = db.createPool(config.mysql);
    // 跑 schema
    const fs = require('node:fs');
    const schema = fs.readFileSync(config.schemaPath, 'utf8');
    for (const stmt of schema.split(';').map((s) => s.trim()).filter((s) => s && !s.startsWith('--'))) {
      await pool.query(stmt);
    }
    config.jwtSecret = config.jwtSecret || 'test-secret-do-not-use-in-prod';
    serverInfo = createServer(config);
    await serverInfo.start();
  } catch (err) {
    console.warn(`MySQL unavailable, skipping server tests: ${err.message}`);
    pool = null;
  }
});

test.after(async () => {
  if (serverInfo) await serverInfo.stop();
  if (pool) {
    const config = loadConfig();
    try { await pool.query(`DROP DATABASE IF EXISTS \`${config.mysql.database}_test\``); } catch (_) {}
    await pool.end();
  }
});

function shouldSkip() { return pool === null; }

// HTTP 调用工具
function call(baseUrl, method, path, { body, token } = {}) {
  return new Promise((resolve, reject) => {
    const headers = { 'content-type': 'application/json' };
    if (token) headers.authorization = `Bearer ${token}`;
    const data = body ? JSON.stringify(body) : null;
    const req = http.request(`${baseUrl}${path}`, { method, headers }, (res) => {
      let chunks = '';
      res.on('data', (c) => { chunks += c; });
      res.on('end', () => {
        let json = null;
        try { json = chunks ? JSON.parse(chunks) : null; } catch (_) {}
        resolve({ status: res.statusCode, json, raw: chunks });
      });
    });
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

let baseUrl = '';
test('setup baseUrl', () => {
  if (!serverInfo) { test.skip('MySQL unavailable'); return; }
  const { port } = serverInfo.server.address();
  baseUrl = `http://127.0.0.1:${port}`;
});

test('GET /api/health 返回 ok', async () => {
  if (shouldSkip()) return;
  const { status, json } = await call(baseUrl, 'GET', '/api/health');
  assert.equal(status, 200);
  assert.equal(json.ok, true);
  assert.equal(json.role, 'hub');
});

test('注册 + 登录流程', async () => {
  if (shouldSkip()) return;
  const email = `srv_${Date.now()}@example.com`;
  const reg = await call(baseUrl, 'POST', '/api/auth/register', { body: { email, password: 'password123' } });
  assert.equal(reg.status, 200);
  assert.ok(reg.json.token);
  assert.ok(reg.json.refreshToken, 'register 应返回 refreshToken');
  assert.equal(reg.json.user.email, email);

  const login = await call(baseUrl, 'POST', '/api/auth/login', { body: { email, password: 'password123' } });
  assert.equal(login.status, 200);
  assert.ok(login.json.token);
  assert.ok(login.json.refreshToken, 'login 应返回 refreshToken');
});

test('重复注册返回 409', async () => {
  if (shouldSkip()) return;
  const email = `srv2_${Date.now()}@example.com`;
  await call(baseUrl, 'POST', '/api/auth/register', { body: { email, password: 'password123' } });
  const dup = await call(baseUrl, 'POST', '/api/auth/register', { body: { email, password: 'password123' } });
  assert.equal(dup.status, 409);
  assert.equal(dup.json.error, 'email_taken');
});

test('错误密码登录返回 401', async () => {
  if (shouldSkip()) return;
  const email = `srv3_${Date.now()}@example.com`;
  await call(baseUrl, 'POST', '/api/auth/register', { body: { email, password: 'password123' } });
  const bad = await call(baseUrl, 'POST', '/api/auth/login', { body: { email, password: 'wrongpassword' } });
  assert.equal(bad.status, 401);
  assert.equal(bad.json.error, 'invalid_credentials');
});

test('无 token 访问 /api/stats 返回 401', async () => {
  if (shouldSkip()) return;
  const { status, json } = await call(baseUrl, 'GET', '/api/stats');
  assert.equal(status, 401);
  assert.equal(json.error, 'unauthorized');
});

test('ingest + stats + devices 端到端', async () => {
  if (shouldSkip()) return;
  const email = `srv4_${Date.now()}@example.com`;
  const reg = await call(baseUrl, 'POST', '/api/auth/register', { body: { email, password: 'password123' } });
  const token = reg.json.token;

  const ingest = await call(baseUrl, 'POST', '/api/ingest', {
    token,
    body: { deviceId: 'dev-e2e', hostname: 'mb', platform: 'darwin', today: { totalTokens: 5, costUsd: 0.1 } }
  });
  assert.equal(ingest.status, 200);
  assert.equal(ingest.json.ok, true);
  assert.equal(ingest.json.deviceId, 'dev-e2e');
  assert.ok(ingest.json.stats);

  const stats = await call(baseUrl, 'GET', '/api/stats', { token });
  assert.equal(stats.status, 200);
  assert.equal(stats.json.devices.length, 1);
  assert.equal(stats.json.devices[0].deviceId, 'dev-e2e');
  // wire shape 关键字段
  assert.ok(stats.json.periods.today, 'periods.today 存在');
  assert.ok('subscriptionsUpdatedAt' in stats.json);

  const devices = await call(baseUrl, 'GET', '/api/devices', { token });
  assert.equal(devices.status, 200);
  assert.equal(devices.json.devices.length, 1);
});

test('多租户隔离：两用户互不可见', async () => {
  if (shouldSkip()) return;
  const regA = await call(baseUrl, 'POST', '/api/auth/register', { body: { email: `a_${Date.now()}@e.com`, password: 'password123' } });
  const regB = await call(baseUrl, 'POST', '/api/auth/register', { body: { email: `b_${Date.now()}@e.com`, password: 'password123' } });
  const tokA = regA.json.token;
  const tokB = regB.json.token;

  await call(baseUrl, 'POST', '/api/ingest', { token: tokA, body: { deviceId: 'dev-a', today: { totalTokens: 1 } } });
  await call(baseUrl, 'POST', '/api/ingest', { token: tokB, body: { deviceId: 'dev-b', today: { totalTokens: 2 } } });

  const statsA = await call(baseUrl, 'GET', '/api/stats', { token: tokA });
  const statsB = await call(baseUrl, 'GET', '/api/stats', { token: tokB });
  assert.equal(statsA.json.devices.length, 1);
  assert.equal(statsA.json.devices[0].deviceId, 'dev-a');
  assert.equal(statsB.json.devices.length, 1);
  assert.equal(statsB.json.devices[0].deviceId, 'dev-b');
});

test('设备所有权冲突返回 403', async () => {
  if (shouldSkip()) return;
  const regA = await call(baseUrl, 'POST', '/api/auth/register', { body: { email: `own_a_${Date.now()}@e.com`, password: 'password123' } });
  const regB = await call(baseUrl, 'POST', '/api/auth/register', { body: { email: `own_b_${Date.now()}@e.com`, password: 'password123' } });
  const sharedDevice = `shared-${Date.now()}`;
  await call(baseUrl, 'POST', '/api/ingest', { token: regA.json.token, body: { deviceId: sharedDevice, today: { totalTokens: 1 } } });
  const conflict = await call(baseUrl, 'POST', '/api/ingest', { token: regB.json.token, body: { deviceId: sharedDevice, today: { totalTokens: 2 } } });
  assert.equal(conflict.status, 403);
  assert.equal(conflict.json.error, 'device_ownership_conflict');
});

test('subscriptions PUT 乐观并发：stale_write 返回 409', async () => {
  if (shouldSkip()) return;
  const reg = await call(baseUrl, 'POST', '/api/auth/register', { body: { email: `sub_${Date.now()}@e.com`, password: 'password123' } });
  const token = reg.json.token;
  const sub = { id: 'sub_1', provider: 'claude', planName: 'Plus', amountMinor: 9000, currency: 'USD', startDate: '2026-05-31' };

  const first = await call(baseUrl, 'PUT', '/api/subscriptions', { token, body: { subscriptions: [sub], baseUpdatedAt: '' } });
  assert.equal(first.status, 200);
  assert.ok(first.json.updatedAt);

  // 用错误 base → 409
  const stale = await call(baseUrl, 'PUT', '/api/subscriptions', { token, body: { subscriptions: [sub], baseUpdatedAt: 'wrong' } });
  assert.equal(stale.status, 409);
  assert.equal(stale.json.error, 'stale_write');
  assert.ok(stale.json.updatedAt, '409 响应带当前文档');
});

test('DELETE /api/devices/:id 只删自己的设备', async () => {
  if (shouldSkip()) return;
  const regA = await call(baseUrl, 'POST', '/api/auth/register', { body: { email: `del_a_${Date.now()}@e.com`, password: 'password123' } });
  const regB = await call(baseUrl, 'POST', '/api/auth/register', { body: { email: `del_b_${Date.now()}@e.com`, password: 'password123' } });
  const dev = `del-${Date.now()}`;
  await call(baseUrl, 'POST', '/api/ingest', { token: regA.json.token, body: { deviceId: dev, today: { totalTokens: 1 } } });
  // B 尝试删 A 的设备
  const delB = await call(baseUrl, 'DELETE', `/api/devices/${dev}`, { token: regB.json.token });
  assert.equal(delB.status, 200); // deleteDevice 按 user_id+device_id，B 删不到但不报错
  // A 的设备还在
  const statsA = await call(baseUrl, 'GET', '/api/stats', { token: regA.json.token });
  assert.equal(statsA.json.devices.length, 1);
  // A 自己删
  await call(baseUrl, 'DELETE', `/api/devices/${dev}`, { token: regA.json.token });
  const statsA2 = await call(baseUrl, 'GET', '/api/stats', { token: regA.json.token });
  assert.equal(statsA2.json.devices.length, 0);
});

test('refresh 换发新 token，refresh 不能当 Bearer', async () => {
  if (shouldSkip()) return;
  const email = `rf_${Date.now()}@example.com`;
  const reg = await call(baseUrl, 'POST', '/api/auth/register', { body: { email, password: 'password123' } });
  const oldToken = reg.json.token;
  const refreshToken = reg.json.refreshToken;
  assert.ok(refreshToken, 'register 应返回 refreshToken');

  // 用 refresh token 换发新 token
  const refreshed = await call(baseUrl, 'POST', '/api/auth/refresh', { body: { refreshToken } });
  assert.equal(refreshed.status, 200);
  assert.ok(refreshed.json.token);
  assert.ok(refreshed.json.refreshToken);
  assert.notEqual(refreshed.json.token, oldToken, '新 access token 应与旧的不同');

  // 新 token 可访问数据接口
  const stats = await call(baseUrl, 'GET', '/api/stats', { token: refreshed.json.token });
  assert.equal(stats.status, 200);

  // refresh token 不能当 Bearer 访问数据接口
  const asBearer = await call(baseUrl, 'GET', '/api/stats', { token: refreshToken });
  assert.equal(asBearer.status, 401);
  assert.equal(asBearer.json.error, 'invalid_token');
});

test('非法 refresh token 返回 401', async () => {
  if (shouldSkip()) return;
  const bad = await call(baseUrl, 'POST', '/api/auth/refresh', { body: { refreshToken: 'not-a-token' } });
  assert.equal(bad.status, 401);
  assert.equal(bad.json.error, 'invalid_token');
});
