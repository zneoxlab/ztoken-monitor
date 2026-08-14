'use strict';

// 数据库迁移脚本：建库 + 跑完整基线 + 记录并执行增量迁移。
// 用法：npm run migrate
// 读取 .env 里的 MySQL 配置（不含 database，先建库再切库）

const fs = require('node:fs');
const path = require('node:path');
const mysql = require('mysql2/promise');
const { loadConfig } = require('../src/config');

function splitSqlStatements(sql) {
  // 当前仓库的迁移不使用存储过程或 DELIMITER；逐行去注释后按分号拆分足够，
  // 且不会把以 -- 开头的说明与紧随其后的 CREATE 合成一段而跳过。
  return sql
    .split('\n')
    .filter((line) => !line.trim().startsWith('--'))
    .join('\n')
    .split(';')
    .map((statement) => statement.trim())
    .filter(Boolean);
}

async function executeSqlFile(conn, filePath) {
  const sql = fs.readFileSync(filePath, 'utf8');
  const statements = splitSqlStatements(sql);
  for (const statement of statements) await conn.query(statement);
  return statements.length;
}

async function applyMigrations(conn, migrationsPath) {
  await conn.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(128) NOT NULL,
    applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (version)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`);
  const files = fs.readdirSync(migrationsPath)
    .filter((file) => /^\d+_[a-z0-9_-]+\.(sql|js)$/i.test(file))
    .sort();
  for (const version of files) {
    const [rows] = await conn.execute(
      'SELECT version FROM schema_migrations WHERE version = :version LIMIT 1',
      { version }
    );
    if (rows.length > 0) continue;
    // MySQL 对 CREATE/ALTER TABLE 会隐式提交，不能假装这里有跨 DDL 的原子事务。
    // 每条迁移均需幂等：中断后下次会重放 CREATE IF NOT EXISTS，成功后才写版本号。
    const migrationPath = path.join(migrationsPath, version);
    const statements = version.endsWith('.js')
      ? await require(migrationPath).up(conn)
      : await executeSqlFile(conn, migrationPath);
    await conn.execute('INSERT INTO schema_migrations (version) VALUES (:version)', { version });
    console.log(`Migration applied: ${version} (${statements} statements).`);
  }
}

async function migrate() {
  const config = loadConfig();
  const schemaPath = config.schemaPath;

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

    // 切到目标库，先应用完整基线。基线保证新安装立即具备完整表结构；
    // 增量脚本在 schema_migrations 中记录，供旧安装升级与审计。
    await conn.changeUser({ database: dbName });
    const statements = await executeSqlFile(conn, schemaPath);
    console.log(`Schema applied: ${statements} statements from ${path.basename(schemaPath)}.`);
    await applyMigrations(conn, path.join(__dirname, '..', 'sql', 'migrations'));
  } finally {
    await conn.end();
  }
}

if (require.main === module) {
  migrate().catch((err) => {
    console.error('Migration failed:', err.message);
    process.exit(1);
  });
}

module.exports = { migrate, splitSqlStatements, executeSqlFile, applyMigrations };
