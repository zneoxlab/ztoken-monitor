'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const { splitSqlStatements } = require('../scripts/migrate');

test('迁移 SQL 的行注释不会吞掉紧随其后的建表语句', () => {
  const schema = fs.readFileSync(path.join(__dirname, '..', 'sql', 'schema.sql'), 'utf8');
  const statements = splitSqlStatements(schema);
  assert.ok(statements.some((statement) => statement.startsWith('CREATE TABLE IF NOT EXISTS schema_migrations')));
  assert.ok(statements.some((statement) => statement.startsWith('CREATE TABLE IF NOT EXISTS push_deliveries')));
});

test('配额推送迁移文件可被版本化发现', () => {
  const migrationsPath = path.join(__dirname, '..', 'sql', 'migrations');
  const files = fs.readdirSync(migrationsPath).filter((file) => /^\d+_[a-z0-9_-]+\.(sql|js)$/i.test(file));
  assert.deepEqual(files, ['001_quota_push.sql', '002_quota_push_runtime_columns.js']);
  const sql = fs.readFileSync(path.join(migrationsPath, files[0]), 'utf8');
  const statements = splitSqlStatements(sql);
  assert.ok(statements.some((statement) => statement.startsWith('CREATE TABLE IF NOT EXISTS notification_events')));
  assert.equal(typeof require('../sql/migrations/002_quota_push_runtime_columns').up, 'function');
  assert.match(sql, /state_key CHAR\(64\) NOT NULL/);
  assert.doesNotMatch(
    sql,
    /PRIMARY KEY \(user_id, rule_id, target_id, window_id\)/,
    'utf8mb4 可变长字段不能组成超过 InnoDB 上限的主键'
  );
  assert.match(sql, /token_ciphertext TEXT NOT NULL/);
});

test('002 在替换旧 state 主键前先建立外键所需的 user_id 索引', () => {
  const source = fs.readFileSync(
    path.join(__dirname, '..', 'sql', 'migrations', '002_quota_push_runtime_columns.js'),
    'utf8'
  );
  const addIndexAt = source.indexOf(
    'ADD INDEX idx_quota_notification_state_user_rule (user_id, rule_id)'
  );
  const replacePrimaryAt = source.indexOf(
    'DROP PRIMARY KEY, ADD PRIMARY KEY (state_key)'
  );
  assert.ok(addIndexAt >= 0 && replacePrimaryAt >= 0);
  assert.ok(addIndexAt < replacePrimaryAt);
});
