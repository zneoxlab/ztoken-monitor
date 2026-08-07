'use strict';

// SaaS Hub HTTP 服务入口：路由分发 + JWT 鉴权中间件 + 错误码映射 + 启动
// 对照现有 node hub（src/hub/server.js）的结构，区别：
// 1. 鉴权从 secret 比较换成 JWT（requireAuth 中间件）
// 2. 多租户：数据接口 req.userId 已挂，hub/db 按 userId 隔离
// 3. 存储从 devices.json 换成 MySQL

const http = require('node:http');
const { URL } = require('node:url');
const { loadConfig } = require('./config');
const db = require('./db');
const { createHub } = require('./hub');
const { createSseRegistry } = require('./sse');
const { createRequireAuth } = require('./auth');
const { createAuthRoutes } = require('./routes/auth');
const { createApiRoutes } = require('./routes/api');

// 带可配置 CORS origin 的 sendJson（SaaS 场景需收紧来源）
function createSendJson(corsOrigin) {
  const accessControlOrigin = corsOrigin || '*';
  return function sendJson(res, statusCode, payload, extraHeaders = {}) {
    const body = JSON.stringify(payload);
    res.writeHead(statusCode, {
      'access-control-allow-origin': accessControlOrigin,
      'access-control-allow-methods': 'GET,POST,PUT,DELETE,OPTIONS',
      'access-control-allow-headers': 'authorization,content-type,x-token-monitor-secret',
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      ...extraHeaders
    });
    res.end(body);
    return true;
  };
}

function createServer(config) {
  const pool = db.createPool(config.mysql);
  const sseRegistry = createSseRegistry();
  const hub = createHub({ pool, db, sseRegistry, staleAfterMs: config.staleAfterMs });
  const sendJson = createSendJson(config.corsOrigin);
  const requireAuth = createRequireAuth({ secret: config.jwtSecret });

  const authRoutes = createAuthRoutes({
    pool,
    jwtSecret: config.jwtSecret,
    jwtExpiresIn: config.jwtExpiresIn,
    jwtRefreshExpiresIn: config.jwtRefreshExpiresIn,
    passwordMinLength: config.passwordMinLength,
    sendJson
  });

  const apiRoutes = createApiRoutes({
    pool,
    hub,
    db,
    sseRegistry,
    sendJson
  });

  async function handleRequest(req, res) {
    if (req.method === 'OPTIONS') {
      res.writeHead(204, {
        'access-control-allow-origin': config.corsOrigin || '*',
        'access-control-allow-methods': 'GET,POST,PUT,DELETE,OPTIONS',
        'access-control-allow-headers': 'authorization,content-type,x-token-monitor-secret'
      });
      res.end('');
      return;
    }

    const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);

    // 健康检查（不鉴权）
    if (req.method === 'GET' && url.pathname === '/api/health') {
      return apiRoutes.health(req, res);
    }

    // 认证接口（不鉴权）
    if (req.method === 'POST' && url.pathname === '/api/auth/register') {
      return authRoutes.register(req, res);
    }
    if (req.method === 'POST' && url.pathname === '/api/auth/login') {
      return authRoutes.login(req, res);
    }
    if (req.method === 'POST' && url.pathname === '/api/auth/refresh') {
      return authRoutes.refresh(req, res);
    }

    // 数据接口（全部过 requireAuth）
    // requireAuth 失败时已用 sendAuthError 写过响应（res.end）并调 next(err) reject，
    // catch 里据 res.writableEnded 跳过二次写，避免 ERR_HTTP_HEADERS_SENT 崩进程。
    try {
      await new Promise((resolve, reject) => {
        requireAuth(req, res, (err) => {
          if (err) return reject(err);
          resolve();
        });
      });
      const handled = await apiRoutes.handle(req, res, url);
      if (!handled && !res.headersSent) {
        return sendJson(res, 404, { error: 'not_found' });
      }
    } catch (error) {
      // 鉴权失败已写过 401（res.writableEnded），不在这里二次写响应
      if (res.writableEnded) return;
      console.error(error);
      sendJson(res, 500, { error: 'internal_error', message: error.message });
    }
  }

  const server = http.createServer((req, res) => {
    handleRequest(req, res).catch((error) => {
      console.error(error);
      // 兜底：若 res 还没响应才写 500，避免二次写头崩溃
      if (!res.writableEnded) {
        try { sendJson(res, 500, { error: 'internal_error', message: error.message }); } catch (_) {}
      }
    });
  });

  function start() {
    return new Promise((resolve, reject) => {
      const onError = (err) => { server.off('listening', onListening); reject(err); };
      const onListening = () => { server.off('error', onError); resolve(); };
      server.once('error', onError);
      server.once('listening', onListening);
      server.listen(config.port, config.host);
    });
  }

  function stop() {
    return new Promise((resolve) => {
      sseRegistry.closeAll();
      server.close(() => {
        pool.end().then(() => resolve()).catch(() => resolve());
      });
    });
  }

  return { start, stop, server, pool, hub, sseRegistry };
}

// 启动入口
if (require.main === module) {
  const config = loadConfig();
  if (!config.jwtSecret) {
    console.error('Error: SAAS_HUB_JWT_SECRET must be set. Generate with: openssl rand -hex 32');
    process.exit(1);
  }
  const { start } = createServer(config);
  start().then(() => {
    console.log(`SaaS Hub listening on http://${config.host}:${config.port}`);
    console.log(`MySQL database: ${config.mysql.database || config.mysql.connectionUri}`);
  }).catch((err) => {
    console.error(`Hub failed to start: ${err.message}`);
    process.exit(1);
  });
}

module.exports = { createServer, createSendJson };
