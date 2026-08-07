'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { createSseRegistry } = require('../src/sse');

// 构造一个 mock res，收集所有 write 调用
function mockRes() {
  const chunks = [];
  return {
    write: (chunk) => chunks.push(chunk),
    end: () => {},
    chunks,
    writtenText: () => chunks.join('')
  };
}

// 每个测试用独立 registry，结尾 closeAll 清理 30s 心跳 timer，避免 node:test hang
test('broadcastStats 只发给指定 userId 的连接', () => {
  const registry = createSseRegistry();
  try {
    const resA = mockRes();
    const resB = mockRes();
    registry.add(1, resA);
    registry.add(2, resB);

    registry.broadcastStats(1, { devices: [] }, 'ingest');

    assert.ok(resA.writtenText().includes('"reason":"ingest"'));
    assert.equal(resB.writtenText(), '');
  } finally {
    registry.closeAll();
  }
});

test('不同用户的帧互不可见', () => {
  const registry = createSseRegistry();
  try {
    const resA = mockRes();
    const resB = mockRes();
    registry.add(1, resA);
    registry.add(2, resB);

    registry.broadcastStats(1, { tag: 'A' }, 'ingest');
    registry.broadcastStats(2, { tag: 'B' }, 'ingest');

    assert.ok(resA.writtenText().includes('"tag":"A"'));
    assert.ok(!resA.writtenText().includes('"tag":"B"'));
    assert.ok(resB.writtenText().includes('"tag":"B"'));
    assert.ok(!resB.writtenText().includes('"tag":"A"'));
  } finally {
    registry.closeAll();
  }
});

test('同用户多连接都收到广播', () => {
  const registry = createSseRegistry();
  try {
    const res1 = mockRes();
    const res2 = mockRes();
    registry.add(1, res1);
    registry.add(1, res2);

    registry.broadcastStats(1, { x: 1 }, 'ingest');

    assert.ok(res1.writtenText().includes('"x":1'));
    assert.ok(res2.writtenText().includes('"x":1'));
  } finally {
    registry.closeAll();
  }
});

test('cleanup 移除连接后不再收广播', () => {
  const registry = createSseRegistry();
  try {
    const res = mockRes();
    const cleanup = registry.add(1, res);
    cleanup();

    registry.broadcastStats(1, { x: 1 }, 'ingest');
    assert.equal(res.writtenText(), '');
    assert.equal(registry.size(1), 0);
  } finally {
    registry.closeAll();
  }
});

test('broadcastStats 对无连接的 userId 静默', () => {
  const registry = createSseRegistry();
  try {
    registry.broadcastStats(999, { x: 1 }, 'ingest');
    assert.equal(registry.size(999), 0);
  } finally {
    registry.closeAll();
  }
});

test('sendSnapshot 发首帧', () => {
  const registry = createSseRegistry();
  try {
    const res = mockRes();
    registry.sendSnapshot(res, { devices: [] });
    assert.ok(res.writtenText().includes('event: snapshot'));
    assert.ok(res.writtenText().includes('"reason":"snapshot"'));
  } finally {
    registry.closeAll();
  }
});

test('broadcastStats 跳过已断开的连接', () => {
  const registry = createSseRegistry();
  try {
    const live = mockRes();
    const dead = mockRes();
    dead.destroyed = true;
    registry.add(1, live);
    registry.add(1, dead);

    registry.broadcastStats(1, { x: 1 }, 'ingest');

    assert.ok(live.writtenText().includes('"x":1'));
    assert.equal(registry.size(1), 1);
  } finally {
    registry.closeAll();
  }
});

test('add 会清理同用户已断开的旧连接', () => {
  const registry = createSseRegistry();
  try {
    const dead = mockRes();
    dead.destroyed = true;
    registry.add(1, dead);
    assert.equal(registry.size(1), 1);

    registry.add(1, mockRes());
    assert.equal(registry.size(1), 1);
  } finally {
    registry.closeAll();
  }
});

test('size 返回每用户连接数', () => {
  const registry = createSseRegistry();
  try {
    registry.add(1, mockRes());
    registry.add(1, mockRes());
    registry.add(2, mockRes());
    assert.equal(registry.size(1), 2);
    assert.equal(registry.size(2), 1);
    assert.equal(registry.size(3), 0);
  } finally {
    registry.closeAll();
  }
});
