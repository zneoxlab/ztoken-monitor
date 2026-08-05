'use strict';

// 数据库迁移脚本：建库 + 跑 schema.sql
// 用法：npm run migrate
// 读取 .env 里的 MySQL 配置（不含 database，先建库再切库）

const fs = require('node:fs');
const path = require('node:path');
const mysql = require('mysql2/promise');
const { loadConfig } = require('../src/config');

async function migrate() {
  const config = loadConfig();
  const schemaPath = config.schemaPath;
  const schema = fs.readFileSync(schemaPath, 'utf8');

  // 先用不含 database 的连接建库，再切到目标库跑 schema
  // resolveMysqlConfig 返回 connectionUri 或分字段两种形态
  const baseConn = config.mysql.connectionUri
    ? { uri: config.mysql.connectionUri.replace(/\/[^/?]*$/, '/') }
    : {
        host: config.mysql.host,
        port: config.mysql.port,
        user: config.mysql.user,
        password: config.mysql.password
      };

  const dbName = config.mysql.connectionUri
    ? (config.mysql.connectionUri.match(/\/([^/?]+)(\?|$)/) || [])[1] || 'token_monitor_saas'
    : config.mysql.database;

  const conn = await mysql.createConnection(baseConn);
  try {
    // 建库（不存在则创建），字符集 utf8mb4
    await conn.query(`CREATE DATABASE IF NOT EXISTS \`${dbName}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`);
    console.log(`Database '${dbName}' ensured.`);

    // 切到目标库，按分号拆分执行 schema 语句
    // 先按行去掉 -- 注释（否则注释和 CREATE TABLE 会在同一片段里，
    // 被 startsWith('--') 整段过滤，导致一条建表都没执行）
    await conn.changeUser({ database: dbName });
    const cleaned = schema
      .split('\n')
      .filter((line) => !line.trim().startsWith('--'))
      .join('\n');
    const statements = cleaned
      .split(';')
      .map((s) => s.trim())
      .filter(Boolean);
    for (const stmt of statements) {
      await conn.query(stmt);
    }
    console.log(`Schema applied: ${statements.length} statements from ${path.basename(schemaPath)}.`);
  } finally {
    await conn.end();
  }
}

migrate().catch((err) => {
  console.error('Migration failed:', err.message);
  process.exit(1);
});
