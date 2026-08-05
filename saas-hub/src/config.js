'use strict';

// SaaS Hub 配置加载：env 优先，前缀用 SAAS_HUB_* 避免与主项目 TOKEN_MONITOR_* 冲突
//
// 注意：不复用 src/shared/config.js 的 loadDotEnv，因为它的 require('dotenv') 会从
// 主项目根目录解析 node_modules，而 saas-hub 是独立 package（node_modules 在 saas-hub/）。
// 这里直接用 saas-hub 自己的 dotenv，保持自包含。parseArgs 是纯函数无外部依赖，可安全复用。

const path = require('node:path');
const dotenv = require('dotenv');
const { parseArgs } = require('../../src/shared/config');

// 解析 MySQL 连接配置：SAAS_HUB_MYSQL_URL 优先，否则用分字段
function resolveMysqlConfig(env) {
  const url = String(env.SAAS_HUB_MYSQL_URL || '').trim();
  if (url) return { connectionUri: url };
  return {
    host: String(env.SAAS_HUB_MYSQL_HOST || '127.0.0.1'),
    port: Number(env.SAAS_HUB_MYSQL_PORT || 3306),
    user: String(env.SAAS_HUB_MYSQL_USER || 'root'),
    password: String(env.SAAS_HUB_MYSQL_PASSWORD || ''),
    database: String(env.SAAS_HUB_MYSQL_DATABASE || 'token_monitor_saas')
  };
}

// 解析 access token 过期时间：支持 '90d'/'1h'/'3600' 形式，jsonwebtoken 原生识别。
// 默认 90 天；活跃用户由 widget 静默续期，闲置超过该时长才需要重新登录。
function resolveJwtExpiresIn(env) {
  return String(env.SAAS_HUB_JWT_EXPIRES_IN || '90d').trim() || '90d';
}

// 解析 refresh token 过期时间：默认与 access 一致（90 天）。每次续期都会换发新的
// refresh token，因此活跃用户的登录态可以无限滚动，闲置用户则在该时长后被登出。
function resolveJwtRefreshExpiresIn(env) {
  return String(env.SAAS_HUB_REFRESH_EXPIRES_IN || '90d').trim() || '90d';
}

function loadConfig(env = process.env, argv = process.argv.slice(2)) {
  // 加载 saas-hub 自己的 .env（dotenv 从 saas-hub/node_modules 解析）
  dotenv.config({ path: path.join(__dirname, '..', '.env'), quiet: true });
  const args = parseArgs(argv);
  const port = Number(args.port || env.SAAS_HUB_PORT || 8787);
  const host = String(args.host || env.SAAS_HUB_HOST || '0.0.0.0');
  const jwtSecret = String(args.jwtSecret || env.SAAS_HUB_JWT_SECRET || '').trim();
  const staleAfterMs = Number(args.staleAfterMs || env.SAAS_HUB_STALE_AFTER_MS || 10 * 60 * 1000);
  const passwordMinLength = Number(env.SAAS_HUB_PASSWORD_MIN_LENGTH || 8);
  const corsOrigin = String(env.SAAS_HUB_CORS_ORIGIN || '*').trim();
  const mysqlConnectionLimit = Number(env.SAAS_HUB_MYSQL_CONNECTION_LIMIT || 10);

  return {
    port,
    host,
    jwtSecret,
    jwtExpiresIn: resolveJwtExpiresIn(env),
    jwtRefreshExpiresIn: resolveJwtRefreshExpiresIn(env),
    staleAfterMs,
    passwordMinLength,
    corsOrigin,
    mysql: { ...resolveMysqlConfig(env), connectionLimit: mysqlConnectionLimit },
    // schema.sql 路径，供 migrate 脚本使用
    schemaPath: path.join(__dirname, '..', 'sql', 'schema.sql')
  };
}

module.exports = { loadConfig, resolveMysqlConfig, resolveJwtExpiresIn, resolveJwtRefreshExpiresIn };
