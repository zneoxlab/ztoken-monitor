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
const { createPushTokenCrypto } = require('./pushTokenCrypto');
const { createPushWorkerRuntime, runWorkerLoop } = require('./push-worker');

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

function createServer(config, { logger = console } = {}) {
  const pool = db.createPool(config.mysql);
  const sseRegistry = createSseRegistry();
  // 空密钥允许测试和“暂未配置推送”的部署继续运行；注册接口会明确返回
  // push_not_configured，绝不会降级为保存明文 token。
  const pushTokenCrypto = createPushTokenCrypto(config.push?.tokenEncryptionKey);
  const hub = createHub({ pool, db, sseRegistry, staleAfterMs: config.staleAfterMs, pushTokenCrypto });
  const sendJson = createSendJson(config.corsOrigin);
  const requireAuth = createRequireAuth({ secret: config.jwtSecret });
  const pushWorkerState = {
    status: 'disabled',
    providers: [],
    runtime: null,
    controller: null,
    loopPromise: null
  };

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
    sendJson,
    pushTokenCrypto
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

  function hasPushProviderConfig() {
    const pushConfig = config.push || {};
    const apns = pushConfig.apns || {};
    return Boolean(
      pushConfig.fcm?.serviceAccountFile
      || apns.keyFile
      || apns.keyId
      || apns.teamId
    );
  }

  async function startPushWorker() {
    const pushConfig = config.push || {};
    // 未配置推送凭证时保持现有 Hub 行为，不让配额推送成为 HTTP 服务的启动门槛。
    if (!pushConfig.tokenEncryptionKey && !hasPushProviderConfig()) return;
    if (!pushConfig.tokenEncryptionKey || !hasPushProviderConfig()) {
      pushWorkerState.status = 'misconfigured';
      logger.warn?.('[push-worker] 配置不完整，已跳过启动；HTTP Hub 仍正常提供服务');
      return;
    }
    try {
      const runtime = createPushWorkerRuntime(config, {
        pool,
        logger
      });
      const controller = new AbortController();
      pushWorkerState.status = 'running';
      pushWorkerState.providers = runtime.providers;
      pushWorkerState.runtime = runtime;
      pushWorkerState.controller = controller;
      // Worker 与 HTTP 共用此进程和连接池；这里只启动后台循环，不阻塞
      // server.listen() 返回，也不需要额外的 systemd/docker service。
      pushWorkerState.loopPromise = runWorkerLoop(runtime, {
        pollIntervalMs: pushConfig.pollIntervalMs,
        signal: controller.signal,
        logger
      }).catch((error) => {
        pushWorkerState.status = 'error';
        logger.error?.(`[push-worker] 后台循环退出: ${error.message}`);
      });
      logger.info?.(`[push-worker] 已随 Hub 启动 (${runtime.providers.join(', ')})`);
    } catch (error) {
      pushWorkerState.status = 'error';
      logger.error?.(`[push-worker] 启动失败，HTTP Hub 继续运行: ${error.message}`);
    }
  }

  async function stopPushWorker() {
    pushWorkerState.controller?.abort();
    if (pushWorkerState.loopPromise) await pushWorkerState.loopPromise;
    if (pushWorkerState.runtime) await pushWorkerState.runtime.close();
    pushWorkerState.controller = null;
    pushWorkerState.loopPromise = null;
    pushWorkerState.runtime = null;
    if (pushWorkerState.status === 'running') pushWorkerState.status = 'stopped';
  }

  function start() {
    return new Promise((resolve, reject) => {
      const onError = (err) => { server.off('listening', onListening); reject(err); };
      const onListening = () => {
        server.off('error', onError);
        startPushWorker().then(resolve, reject);
      };
      server.once('error', onError);
      server.once('listening', onListening);
      server.listen(config.port, config.host);
    });
  }

  async function stop() {
    sseRegistry.closeAll();
    await stopPushWorker();
    await new Promise((resolve) => {
      if (!server.listening) return resolve();
      server.close(() => resolve());
    });
    await pool.end().catch(() => {});
  }

  return { start, stop, server, pool, hub, sseRegistry, pushWorker: pushWorkerState };
}

// 启动入口
if (require.main === module) {
  const config = loadConfig();
  if (!config.jwtSecret) {
    console.error('Error: SAAS_HUB_JWT_SECRET must be set. Generate with: openssl rand -hex 32');
    process.exit(1);
  }
  const serverInfo = createServer(config);
  let stopping = false;
  const shutdown = async (signal) => {
    if (stopping) return;
    stopping = true;
    console.log(`SaaS Hub stopping (${signal})`);
    await serverInfo.stop();
  };
  process.once('SIGINT', () => { shutdown('SIGINT').catch((error) => console.error(error)); });
  process.once('SIGTERM', () => { shutdown('SIGTERM').catch((error) => console.error(error)); });
  serverInfo.start().then(() => {
    console.log(`SaaS Hub listening on http://${config.host}:${config.port}`);
    console.log(`MySQL database: ${config.mysql.database || config.mysql.connectionUri}`);
  }).catch((err) => {
    console.error(`Hub failed to start: ${err.message}`);
    process.exit(1);
  });
}

module.exports = { createServer, createSendJson };
