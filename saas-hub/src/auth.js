'use strict';

// 认证模块：scrypt 密码哈希 + JWT 签发/校验 + requireAuth 中间件
//
// 密码哈希用 Node 内置 crypto.scrypt（零额外依赖），salt 用 crypto.randomBytes(16)。
// JWT 用 jsonwebtoken。Phase 1 不做黑名单，token 过期靠 exp；verifyToken 内预留 isRevoked 钩子。

const crypto = require('node:crypto');
const jwt = require('jsonwebtoken');

// scrypt 参数：N=16384 是 Node 默认，单次约 100ms，注册/登录可接受
const SCRYPT_KEYLEN = 64;

// ---- 密码哈希 ----

function generateSalt(bytes = 16) {
  return crypto.randomBytes(bytes);
}

// scrypt 是异步的（CPU 密集），用 Promise 包装避免阻塞事件循环
function hashPassword(password, salt = generateSalt()) {
  return new Promise((resolve, reject) => {
    crypto.scrypt(password, salt, SCRYPT_KEYLEN, (err, hash) => {
      if (err) return reject(err);
      resolve({ hash, salt });
    });
  });
}

function verifyPassword(password, hash, salt) {
  return new Promise((resolve, reject) => {
    crypto.scrypt(password, salt, SCRYPT_KEYLEN, (err, computed) => {
      if (err) return reject(err);
      // 定长时间比较，防时序侧信道
      if (hash.length !== computed.length) return resolve(false);
      resolve(crypto.timingSafeEqual(hash, computed));
    });
  });
}

// ---- JWT ----

function signToken({ userId, email }, { secret, expiresIn }) {
  return jwt.sign({ userId, email }, secret, { expiresIn });
}

// refresh token：带 kind: 'refresh' 声明，与 access token 共用同一密钥签发。
// 无状态方案不落库、无黑名单，登出仅清本地。createRequireAuth 会拒绝
// kind === 'refresh' 的 Bearer token，避免把 refresh token 误当 access 用。
function signRefreshToken({ userId, email }, { secret, expiresIn }) {
  return jwt.sign({ kind: 'refresh', userId, email }, secret, { expiresIn });
}

// 校验 refresh token：先走 verifyToken（含 isRevoked 钩子，无状态方案不传），
// 再强制要求 kind === 'refresh'，防止把 access token 拿来当 refresh token 用。
async function verifyRefreshToken(token, secret, isRevoked) {
  const payload = await verifyToken(token, secret, isRevoked);
  if (payload.kind !== 'refresh') {
    const err = new Error('not a refresh token');
    err.code = 'invalid_token';
    throw err;
  }
  return payload;
}

// 校验 token，返回 payload 或抛错。
// isRevoked 钩子预留：Phase 2 接 Redis 黑名单，签名 (payload) => Promise<boolean>
async function verifyToken(token, secret, isRevoked) {
  const payload = jwt.verify(token, secret);
  if (isRevoked && await isRevoked(payload)) {
    const err = new Error('token revoked');
    err.code = 'token_revoked';
    throw err;
  }
  return payload;
}

// 从请求头解析 Bearer token
function extractBearerToken(req) {
  const auth = req.headers.authorization || '';
  if (auth.toLowerCase().startsWith('bearer ')) return auth.slice(7).trim();
  // 兼容 x-token-monitor-secret 头（与现有 hub 一致，但 SaaS 场景下装的是 JWT）
  return String(req.headers['x-token-monitor-secret'] || '').trim();
}

// ---- 中间件 ----

// 创建 requireAuth 中间件工厂，闭包捕获 secret 和可选的 isRevoked 钩子
function createRequireAuth({ secret, isRevoked }) {
  if (!secret) {
    throw new Error('SAAS_HUB_JWT_SECRET must be set');
  }
  return async function requireAuth(req, res, next) {
    const token = extractBearerToken(req);
    const fail = (status, error, message) => {
      // 已经写响应 + 调 next 传 error：让上层 Promise reject，但上层据此判断
      // res.writableEnded 跳过二次写，避免 ERR_HTTP_HEADERS_SENT 崩进程
      sendAuthError(res, status, error, message);
      next(new Error(error));
    };
    if (!token) {
      return fail(401, 'unauthorized', 'Missing or malformed Authorization header');
    }
    try {
      const payload = await verifyToken(token, secret, isRevoked);
      // refresh token 只允许用于 /api/auth/refresh，绝不能当 Bearer 访问数据接口
      if (payload.kind === 'refresh') {
        return fail(401, 'invalid_token', 'Invalid token type');
      }
      req.userId = payload.userId;
      req.email = payload.email;
      next();
    } catch (error) {
      // 区分过期与无效，便于前端触发重新登录
      if (error.name === 'TokenExpiredError') {
        return fail(401, 'token_expired', 'JWT expired');
      }
      if (error.code === 'token_revoked') {
        return fail(401, 'token_revoked', 'Token has been revoked');
      }
      return fail(401, 'invalid_token', 'Invalid JWT');
    }
  };
}

function sendAuthError(res, status, error, message) {
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store'
  });
  res.end(JSON.stringify({ error, message }));
}

// ---- 校验工具 ----

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function isValidEmail(email) {
  return typeof email === 'string' && EMAIL_RE.test(email) && email.length <= 255;
}

function isValidPassword(password, minLength = 8) {
  return typeof password === 'string' && password.length >= minLength && password.length <= 256;
}

module.exports = {
  generateSalt,
  hashPassword,
  verifyPassword,
  signToken,
  signRefreshToken,
  verifyToken,
  verifyRefreshToken,
  extractBearerToken,
  createRequireAuth,
  isValidEmail,
  isValidPassword,
  SCRYPT_KEYLEN
};
