'use strict';

const test = require('node:test');
const assert = require('node:assert');
const auth = require('../src/auth');

test('hashPassword / verifyPassword 往返', async () => {
  const { hash, salt } = await auth.hashPassword('correct horse battery staple');
  assert.equal(hash.length, auth.SCRYPT_KEYLEN);
  assert.equal(salt.length, 16);
  const ok = await auth.verifyPassword('correct horse battery staple', hash, salt);
  assert.equal(ok, true);
});

test('verifyPassword 拒绝错误密码', async () => {
  const { hash, salt } = await auth.hashPassword('right-password');
  const ok = await auth.verifyPassword('wrong-password', hash, salt);
  assert.equal(ok, false);
});

test('相同密码不同 salt 产生不同 hash', async () => {
  const a = await auth.hashPassword('same');
  const b = await auth.hashPassword('same');
  assert.notDeepEqual(a.salt, b.salt);
  assert.notDeepEqual(a.hash, b.hash);
});

test('signToken / verifyToken 往返', async () => {
  const token = auth.signToken({ userId: 42, email: 'a@b.com' }, { secret: 'test-secret', expiresIn: '1h' });
  // verifyToken 是 async，必须 await
  const payload = await auth.verifyToken(token, 'test-secret');
  assert.equal(payload.userId, 42);
  assert.equal(payload.email, 'a@b.com');
  assert.ok(payload.exp > Math.floor(Date.now() / 1000));
});

test('verifyToken 拒绝错误密钥', async () => {
  const token = auth.signToken({ userId: 1 }, { secret: 'right', expiresIn: '1h' });
  // verifyToken 是 async，用 rejects
  await assert.rejects(() => auth.verifyToken(token, 'wrong'), (err) => err.name === 'JsonWebTokenError');
});

test('verifyToken 拒绝过期 token', async () => {
  // expiresIn: -1s 已过期
  const token = auth.signToken({ userId: 1 }, { secret: 's', expiresIn: '-1s' });
  await assert.rejects(() => auth.verifyToken(token, 's'), (err) => err.name === 'TokenExpiredError');
});

test('verifyToken isRevoked 钩子生效', async () => {
  const token = auth.signToken({ userId: 1 }, { secret: 's', expiresIn: '1h' });
  const isRevoked = async () => true;
  await assert.rejects(() => auth.verifyToken(token, 's', isRevoked), /revoked/);
});

test('extractBearerToken 解析 Authorization 头', () => {
  assert.equal(auth.extractBearerToken({ headers: { authorization: 'Bearer abc123' } }), 'abc123');
  assert.equal(auth.extractBearerToken({ headers: { authorization: 'bearer abc123' } }), 'abc123');
  assert.equal(auth.extractBearerToken({ headers: { 'x-token-monitor-secret': 'xyz' } }), 'xyz');
  assert.equal(auth.extractBearerToken({ headers: {} }), '');
});

test('isValidEmail 校验', () => {
  assert.equal(auth.isValidEmail('a@b.com'), true);
  assert.equal(auth.isValidEmail('bad'), false);
  assert.equal(auth.isValidEmail('a@'), false);
  assert.equal(auth.isValidEmail(''), false);
  assert.equal(auth.isValidEmail(null), false);
});

test('isValidPassword 校验', () => {
  assert.equal(auth.isValidPassword('12345678'), true);
  assert.equal(auth.isValidPassword('short'), false);
  assert.equal(auth.isValidPassword(''), false);
  assert.equal(auth.isValidPassword('1234567', 8), false);
  assert.equal(auth.isValidPassword('1234567', 7), true);
});

test('createRequireAuth 缺 secret 抛错', () => {
  assert.throws(() => auth.createRequireAuth({ secret: '' }), /JWT_SECRET/);
});

test('requireAuth 中间件：无 token 返回 401', async () => {
  const requireAuth = auth.createRequireAuth({ secret: 's' });
  const written = {};
  const res = {
    writeHead: (status, headers) => { written.status = status; written.headers = headers; },
    end: (body) => { written.body = body; }
  };
  // 失败时先 sendAuthError（写 401 响应）再调 next(err) 让上层 reject；
  // next 收到的是 error，响应已写过 401
  let nextError = null;
  await new Promise((resolve) => {
    requireAuth({ headers: {} }, res, (err) => { nextError = err; });
    setImmediate(resolve);
  });
  assert.ok(nextError, '失败时应调 next 传 error');
  assert.equal(written.status, 401);
  assert.ok(written.body.includes('unauthorized'));
});

test('requireAuth 中间件：有效 token 挂 userId', async () => {
  const requireAuth = auth.createRequireAuth({ secret: 's' });
  const token = auth.signToken({ userId: 99, email: 'x@y.com' }, { secret: 's', expiresIn: '1h' });
  const req = { headers: { authorization: `Bearer ${token}` } };
  await new Promise((resolve, reject) => {
    requireAuth(req, {}, (err) => { if (err) return reject(err); resolve(); });
  });
  assert.equal(req.userId, 99);
  assert.equal(req.email, 'x@y.com');
});

test('signRefreshToken / verifyRefreshToken 往返', async () => {
  const token = auth.signRefreshToken({ userId: 42, email: 'a@b.com' }, { secret: 'test-secret', expiresIn: '90d' });
  const payload = await auth.verifyRefreshToken(token, 'test-secret');
  assert.equal(payload.kind, 'refresh');
  assert.equal(payload.userId, 42);
  assert.equal(payload.email, 'a@b.com');
});

test('verifyRefreshToken 拒绝 access token（无 kind）', async () => {
  const accessToken = auth.signToken({ userId: 42, email: 'a@b.com' }, { secret: 's', expiresIn: '1h' });
  await assert.rejects(
    () => auth.verifyRefreshToken(accessToken, 's'),
    (err) => err.code === 'invalid_token'
  );
});

test('verifyRefreshToken 拒绝过期 refresh token', async () => {
  const expired = auth.signRefreshToken({ userId: 1 }, { secret: 's', expiresIn: '-1s' });
  await assert.rejects(() => auth.verifyRefreshToken(expired, 's'), (err) => err.name === 'TokenExpiredError');
});

test('requireAuth 拒绝 refresh token 当 Bearer', async () => {
  const requireAuth = auth.createRequireAuth({ secret: 's' });
  const refreshToken = auth.signRefreshToken({ userId: 7 }, { secret: 's', expiresIn: '90d' });
  const written = {};
  const res = {
    writeHead: (status, headers) => { written.status = status; written.headers = headers; },
    end: (body) => { written.body = body; }
  };
  let nextError = null;
  await new Promise((resolve) => {
    requireAuth({ headers: { authorization: `Bearer ${refreshToken}` } }, res, (err) => { nextError = err; });
    setImmediate(resolve);
  });
  assert.ok(nextError, '失败时应调 next 传 error');
  assert.equal(written.status, 401);
  assert.ok(written.body.includes('invalid_token'));
});
