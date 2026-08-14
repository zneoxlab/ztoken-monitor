'use strict';

// 数据接口路由：/api/ingest、/api/stats、/api/stats/stream、/api/devices、
// /api/history、/api/subscriptions、/api/devices/:id、/api/health
// 协议与现有 node hub（src/hub/server.js）逐字段对齐，仅鉴权换 JWT。
// 所有数据接口（除 health）在 server.js 已过 requireAuth，req.userId 已挂。

const { readJsonBody } = require('../../../src/shared/http');

function createApiRoutes({ pool, hub, db, sseRegistry, sendJson, pushTokenCrypto = null }) {
  // GET /api/health（不鉴权，server.js 直接调）
  async function health(req, res) {
    const deviceCount = await db.countAllDevices(pool);
    return sendJson(res, 200, {
      ok: true,
      role: 'hub',
      version: 1,
      deviceCount,
      secretRequired: true,
      now: new Date().toISOString()
    });
  }

  // GET /api/stats
  async function getStats(req, res) {
    const stats = await hub.getStats(req.userId);
    return sendJson(res, 200, stats);
  }

  // GET /api/devices
  async function getDevices(req, res) {
    const { devices } = await hub.getDevices(req.userId);
    return sendJson(res, 200, { devices });
  }

  // GET /api/history
  async function getHistory(req, res) {
    const history = await hub.getHistory(req.userId);
    return sendJson(res, 200, history);
  }

  // GET /api/stats/stream（SSE，per-user 隔离）
  async function statsStream(req, res) {
    res.writeHead(200, {
      'content-type': 'text/event-stream',
      'cache-control': 'no-cache, no-transform',
      connection: 'keep-alive',
      'x-accel-buffering': 'no'
    });
    const stats = await hub.getStats(req.userId);
    sseRegistry.sendSnapshot(res, stats);
    const unregister = sseRegistry.add(req.userId, res);
    let cleaned = false;
    const cleanup = () => {
      if (cleaned) return;
      cleaned = true;
      unregister();
    };
    req.on('close', cleanup);
    req.on('error', cleanup);
    res.on('close', cleanup);
    return true;
  }

  // POST /api/ingest
  async function ingest(req, res) {
    let payload;
    try {
      payload = await readJsonBody(req);
    } catch (error) {
      if (error.code === 'payload_too_large') {
        res.shouldKeepAlive = false;
        return sendJson(res, 413, { error: 'payload_too_large', message: error.message }, { connection: 'close' });
      }
      return sendJson(res, 400, { error: 'bad_request', message: error.message });
    }
    try {
      const result = await hub.ingest(req.userId, payload);
      return sendJson(res, 200, { ok: true, deviceId: result.record.deviceId, stats: result.stats });
    } catch (error) {
      if (error.code === 'deviceId_required') {
        return sendJson(res, 400, { error: 'deviceId_required' });
      }
      throw error;
    }
  }

  // GET /api/subscriptions
  async function getSubscriptions(req, res) {
    const doc = await hub.getSubscriptions(req.userId);
    return sendJson(res, 200, { ok: true, ...doc });
  }

  // PUT /api/subscriptions
  async function putSubscriptions(req, res) {
    let body;
    try {
      body = await readJsonBody(req);
    } catch (error) {
      if (error.code === 'payload_too_large') {
        res.shouldKeepAlive = false;
        return sendJson(res, 413, { error: 'payload_too_large', message: error.message }, { connection: 'close' });
      }
      return sendJson(res, 400, { error: 'bad_request', message: error.message });
    }
    try {
      const stored = await hub.setSubscriptions(req.userId, body?.subscriptions, body?.baseUpdatedAt);
      return sendJson(res, 200, { ok: true, ...stored });
    } catch (error) {
      if (error.code === 'stale_write') {
        return sendJson(res, 409, { error: 'stale_write', ...error.current });
      }
      if (error.code === 'bad_subscriptions') {
        return sendJson(res, 400, { error: 'bad_request', message: error.message });
      }
      throw error;
    }
  }

  // GET /api/notification-targets：只返回当前实际可观测到的百分比额度窗口。
  async function getNotificationTargets(req, res) {
    const result = await hub.getNotificationTargets(req.userId);
    return sendJson(res, 200, { ok: true, ...result });
  }

  // GET /api/notification-rules
  async function getNotificationRules(req, res) {
    const doc = await hub.getNotificationRules(req.userId);
    return sendJson(res, 200, { ok: true, ...doc });
  }

  // PUT /api/notification-rules
  async function putNotificationRules(req, res) {
    let body;
    try {
      body = await readJsonBody(req);
    } catch (error) {
      if (error.code === 'payload_too_large') {
        res.shouldKeepAlive = false;
        return sendJson(res, 413, { error: 'payload_too_large', message: error.message }, { connection: 'close' });
      }
      return sendJson(res, 400, { error: 'bad_request', message: error.message });
    }
    try {
      const stored = await hub.setNotificationRules(req.userId, body?.rules, body?.baseUpdatedAt);
      return sendJson(res, 200, { ok: true, ...stored });
    } catch (error) {
      if (error.code === 'stale_write') {
        return sendJson(res, 409, { error: 'stale_write', ...error.current });
      }
      if (error.code === 'bad_notification_rules') {
        return sendJson(res, 400, { error: 'bad_request', message: error.message });
      }
      throw error;
    }
  }

  // PUT /api/push/installations/:installationId。installationId 以 path 为准，
  // 绝不从 body 接收 userId；JWT 是唯一的账号绑定来源。
  async function putPushInstallation(req, res, url) {
    let body;
    try {
      body = await readJsonBody(req);
    } catch (error) {
      if (error.code === 'payload_too_large') {
        res.shouldKeepAlive = false;
        return sendJson(res, 413, { error: 'payload_too_large', message: error.message }, { connection: 'close' });
      }
      return sendJson(res, 400, { error: 'bad_request', message: error.message });
    }
    try {
      const installationId = decodeURIComponent(url.pathname.slice('/api/push/installations/'.length));
      const installation = await hub.registerPushInstallation(req.userId, {
        installationId,
        platform: body?.platform,
        provider: body?.provider,
        environment: body?.environment,
        appVersion: body?.appVersion,
        token: body?.token
      }, pushTokenCrypto);
      return sendJson(res, 200, { ok: true, installation });
    } catch (error) {
      if (error.code === 'push_not_configured') return sendJson(res, 503, { error: 'push_not_configured' });
      if (error.code === 'bad_push_installation') {
        return sendJson(res, 400, { error: 'bad_request', message: error.message });
      }
      throw error;
    }
  }

  async function deletePushInstallation(req, res, url) {
    const installationId = decodeURIComponent(url.pathname.slice('/api/push/installations/'.length));
    try {
      const removed = await hub.removePushInstallation(req.userId, installationId);
      return sendJson(res, 200, { ok: true, installationId, removed });
    } catch (error) {
      if (error.code === 'bad_push_installation') {
        return sendJson(res, 400, { error: 'bad_request', message: error.message });
      }
      throw error;
    }
  }

  // DELETE /api/devices/:id
  async function deleteDevice(req, res, url) {
    const deviceId = decodeURIComponent(url.pathname.slice('/api/devices/'.length));
    await hub.deleteDevice(req.userId, deviceId);
    return sendJson(res, 200, { ok: true, deviceId });
  }

  // 路由分发：返回 true 表示已处理，false 表示未匹配
  async function handle(req, res, url) {
    const { method, pathname } = { method: req.method, pathname: url.pathname };

    if (method === 'GET' && pathname === '/api/health') return health(req, res);
    if (method === 'GET' && pathname === '/api/stats') return getStats(req, res);
    if (method === 'GET' && pathname === '/api/devices') return getDevices(req, res);
    if (method === 'GET' && pathname === '/api/history') return getHistory(req, res);
    if (method === 'GET' && pathname === '/api/stats/stream') return statsStream(req, res);
    if (method === 'POST' && pathname === '/api/ingest') return ingest(req, res);
    if (method === 'GET' && pathname === '/api/subscriptions') return getSubscriptions(req, res);
    if (method === 'PUT' && pathname === '/api/subscriptions') return putSubscriptions(req, res);
    if (method === 'GET' && pathname === '/api/notification-targets') return getNotificationTargets(req, res);
    if (method === 'GET' && pathname === '/api/notification-rules') return getNotificationRules(req, res);
    if (method === 'PUT' && pathname === '/api/notification-rules') return putNotificationRules(req, res);
    if (method === 'PUT' && pathname.startsWith('/api/push/installations/')) return putPushInstallation(req, res, url);
    if (method === 'DELETE' && pathname.startsWith('/api/push/installations/')) return deletePushInstallation(req, res, url);
    if (method === 'DELETE' && pathname.startsWith('/api/devices/')) return deleteDevice(req, res, url);

    return false;
  }

  return { handle, health };
}

module.exports = { createApiRoutes };
