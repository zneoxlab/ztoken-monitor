'use strict';

// 认证路由：/api/auth/register、/api/auth/login、/api/auth/refresh
// 复用 src/shared/http.js 的 readJsonBody，但响应用本地 sendJson（带可配置 CORS）

const db = require('../db');
const auth = require('../auth');

function createAuthRoutes({ pool, jwtSecret, jwtExpiresIn, jwtRefreshExpiresIn, passwordMinLength, sendJson }) {
  // POST /api/auth/register
  async function register(req, res) {
    let body;
    try {
      body = await readJsonBody(req);
    } catch (error) {
      return sendJson(res, 400, { error: 'bad_request', message: error.message });
    }
    const { email, password } = body || {};
    if (!auth.isValidEmail(email)) {
      return sendJson(res, 400, { error: 'bad_request', message: 'Invalid email' });
    }
    if (!auth.isValidPassword(password, passwordMinLength)) {
      return sendJson(res, 400, { error: 'bad_request', message: `Password must be at least ${passwordMinLength} characters` });
    }

    const { hash, salt } = await auth.hashPassword(password);
    try {
      const user = await db.createUser(pool, { email: email.toLowerCase(), passwordHash: hash, passwordSalt: salt });
      const token = auth.signToken({ userId: user.id, email: user.email }, { secret: jwtSecret, expiresIn: jwtExpiresIn });
      const refreshToken = auth.signRefreshToken({ userId: user.id, email: user.email }, { secret: jwtSecret, expiresIn: jwtRefreshExpiresIn });
      return sendJson(res, 200, { ok: true, token, refreshToken, user: { id: user.id, email: user.email } });
    } catch (error) {
      // email 冲突（ER_DUP_ENTRY）
      if (error.code === 'ER_DUP_ENTRY') {
        return sendJson(res, 409, { error: 'email_taken', message: 'Email already registered' });
      }
      throw error;
    }
  }

  // POST /api/auth/login
  async function login(req, res) {
    let body;
    try {
      body = await readJsonBody(req);
    } catch (error) {
      return sendJson(res, 400, { error: 'bad_request', message: error.message });
    }
    const { email, password } = body || {};
    if (!email || !password) {
      return sendJson(res, 400, { error: 'bad_request', message: 'Email and password required' });
    }

    const user = await db.findUserByEmail(pool, String(email).toLowerCase());
    // 不区分用户不存在与密码错，防邮箱枚举
    const fallback = () => sendJson(res, 401, { error: 'invalid_credentials', message: 'Invalid email or password' });
    if (!user) return fallback();

    const ok = await auth.verifyPassword(password, user.passwordHash, user.passwordSalt);
    if (!ok) return fallback();

    const token = auth.signToken({ userId: user.id, email: user.email }, { secret: jwtSecret, expiresIn: jwtExpiresIn });
    const refreshToken = auth.signRefreshToken({ userId: user.id, email: user.email }, { secret: jwtSecret, expiresIn: jwtRefreshExpiresIn });
    return sendJson(res, 200, { ok: true, token, refreshToken, user: { id: user.id, email: user.email } });
  }

  // POST /api/auth/refresh
  // 用 refresh token 换发新 access token + 新 refresh token（滚动续期）。无状态方案
  // 不落库，旧 refresh token 在自身过期前仍有效；widget 靠它维持活跃用户登录态。
  async function refresh(req, res) {
    let body;
    try {
      body = await readJsonBody(req);
    } catch (error) {
      return sendJson(res, 400, { error: 'bad_request', message: error.message });
    }
    const { refreshToken } = body || {};
    if (!refreshToken) {
      return sendJson(res, 400, { error: 'bad_request', message: 'refreshToken required' });
    }
    try {
      const payload = await auth.verifyRefreshToken(refreshToken, jwtSecret);
      const token = auth.signToken({ userId: payload.userId, email: payload.email }, { secret: jwtSecret, expiresIn: jwtExpiresIn });
      const nextRefreshToken = auth.signRefreshToken({ userId: payload.userId, email: payload.email }, { secret: jwtSecret, expiresIn: jwtRefreshExpiresIn });
      return sendJson(res, 200, { ok: true, token, refreshToken: nextRefreshToken });
    } catch (error) {
      // 与 requireAuth 相同的错误码映射：过期 → token_expired，其余 → invalid_token
      if (error.name === 'TokenExpiredError') {
        return sendJson(res, 401, { error: 'token_expired', message: 'Refresh token expired' });
      }
      return sendJson(res, 401, { error: 'invalid_token', message: error.message || 'Invalid refresh token' });
    }
  }

  return { register, login, refresh };
}

// 从 src/shared/http.js 引入 readJsonBody（纯函数，复用）
const { readJsonBody } = require('../../../src/shared/http');

module.exports = { createAuthRoutes };
