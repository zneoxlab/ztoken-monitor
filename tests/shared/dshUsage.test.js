'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const zlib = require('node:zlib');
const test = require('node:test');

const {
  buildDshTokscaleJson,
  buildDshPeriods,
  buildDshHistoryGraph,
  collectDshRows,
  decodeZstdFrames,
  zstdFrames
} = require('../../src/shared/dshUsage');
const { extractUsageFromTokscale } = require('../../src/shared/usage');

// Node 22.15+ 才有同步 zstd API；没有就跳过依赖解压的用例，
// 但仍要断言 collectDshRows 在缺该 API 时优雅返回 [] 不抛错。
const HAS_ZSTD_SYNC = typeof zlib.zstdCompressSync === 'function'
  && typeof zlib.zstdDecompressSync === 'function';

// 把若干 JSON 事件行逐行压缩成多帧 zstd buffer（每行一帧），还原 DSH 的写入格式。
function encodeFrames(events) {
  return Buffer.concat(events.map((event) => zlib.zstdCompressSync(Buffer.from(`${JSON.stringify(event)}\n`))));
}

// 拼成带 torn 尾的坏帧，验证逐帧解码跳过坏帧而不整体失败。
function encodeFramesWithTornTail(events) {
  const good = encodeFrames(events);
  const garbage = Buffer.from([0x28, 0xb5, 0x2f, 0xfd, 0x00, 0x01, 0x02, 0xff]); // 假魔数 + 残缺负载
  return Buffer.concat([good, garbage]);
}

function assistantMessage({ id, seq = 100, time = 1786681868989, turn = 1, model = 'deepseek-v4-flash', provider = 'ps', input = 0, output = 0, cacheRead = 0, cacheWrite = 0, reasoning = 0 }) {
  return {
    type: 'assistant/message',
    seq,
    time,
    data: {
      turn,
      step: 1,
      usage: { inputTokens: input, outputTokens: output, cacheReadTokens: cacheRead, cacheWriteTokens: cacheWrite, reasoningTokens: reasoning },
      message: { id, role: 'assistant', source: { provider, model } }
    }
  };
}

function sessionEvent({ id = 'session-test-1', createdAt = 1786681776194, seedLength } = {}) {
  const evt = { type: 'session', version: 0, id, createdAt, cwd: '/tmp', agentPreset: 'standard' };
  if (seedLength !== undefined) evt.seedLength = seedLength;
  return evt;
}

function requestHeader({ provider = 'ps', model = 'deepseek-v4-flash', seq = 11, time = 1786681864057 } = {}) {
  return { type: 'request/header', seq, time, data: { header: { config: { provider, model } } } };
}

// 构造一个临时 DSH sessions 根目录：<root>/<encodedCwd>/<sessionId>/session.jsonl.zstd
function makeSessionTree(events, sessionId = 'session-test-1', encodedCwd = '--tmp--') {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'dsh-usage-'));
  const sessionDir = path.join(root, encodedCwd, sessionId);
  fs.mkdirSync(sessionDir, { recursive: true });
  const file = path.join(sessionDir, 'session.jsonl.zstd');
  const buffer = HAS_ZSTD_SYNC ? encodeFrames(events) : Buffer.from(events.map((e) => JSON.stringify(e)).join('\n') + '\n');
  fs.writeFileSync(file, buffer);
  return { root, file, sessionId };
}

test('dsh daily window filters messages before per-model aggregation', () => {
  if (!HAS_ZSTD_SYNC) return;
  const yesterday = Date.parse('2026-07-08T23:50:00.000Z');
  const todayMs = Date.parse('2026-07-09T00:05:00.000Z');
  const todayStart = Date.parse('2026-07-09T00:00:00.000Z');
  const { root } = makeSessionTree([
    sessionEvent({ createdAt: yesterday }),
    assistantMessage({ id: 'old', time: yesterday, input: 100, output: 1 }),
    assistantMessage({ id: 'today', time: todayMs, input: 40, output: 3, cacheRead: 2 })
  ]);

  const todayUsage = extractUsageFromTokscale(buildDshTokscaleJson({ todayStart }, { roots: [root] }));
  assert.equal(todayUsage.clients.dsh, 45);
  assert.equal(todayUsage.models['deepseek-v4-flash'], 45);

  const monthUsage = extractUsageFromTokscale(buildDshTokscaleJson({ monthStart: Date.parse('2026-07-01T00:00:00.000Z') }, { roots: [root] }));
  assert.equal(monthUsage.clients.dsh, 146);
});

test('dsh multi-frame decode parses every frame and skips a torn tail', () => {
  if (!HAS_ZSTD_SYNC) return;
  const events = [
    sessionEvent(),
    assistantMessage({ id: 'm1', seq: 171, input: 10, output: 4, reasoning: 2 }),
    assistantMessage({ id: 'm2', seq: 200, input: 20, output: 6, cacheRead: 8 })
  ];
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'dsh-usage-'));
  const sessionDir = path.join(root, '--tmp--', 'session-test-1');
  fs.mkdirSync(sessionDir, { recursive: true });
  fs.writeFileSync(path.join(sessionDir, 'session.jsonl.zstd'), encodeFramesWithTornTail(events));

  const rows = collectDshRows({ roots: [root] });
  // torn 帧被跳过，两帧正常事件各产出一条 usage 行。
  assert.equal(rows.length, 2);
});

test('dsh reasoning is a subset of output and stays out of the token total', () => {
  const rows = [{
    sessionId: 'session-test-1',
    model: 'deepseek-v4-pro',
    provider: 'ps',
    input: 100, output: 60, cacheRead: 5, cacheWrite: 0, reasoning: 40,
    createdAt: Date.parse('2026-07-09T12:00:00.000Z'),
    messages: 1
  }];
  const json = buildDshTokscaleJson({}, { rows });
  assert.equal(json.entries[0].output, 60);
  assert.equal(json.entries[0].reasoning, 40);
  const usage = extractUsageFromTokscale(json);
  // 总量不含 reasoning（reasoning 是 output 子集，已在 output 里减掉并单独留存展示）。
  assert.equal(usage.totalTokens, 100 + 60 + 5);
});

test('dsh dedups identical (messageId, time, provider, model, tokens)', () => {
  const events = [
    sessionEvent(),
    assistantMessage({ id: 'dup', seq: 171, input: 50, output: 10 }),
    // 同一条消息的重复事件：所有去重 key 字段都相同 → 只计一次。
    assistantMessage({ id: 'dup', seq: 171, input: 50, output: 10 })
  ];
  // 直接用文本解析（不走压缩），便于无 zstd 环境也能验证去重逻辑。
  const text = events.map((e) => JSON.stringify(e)).join('\n');
  const { collectDshRows } = require('../../src/shared/dshUsage');
  // 通过 parseSessionFile 落盘再读，绕开压缩依赖。
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'dsh-usage-'));
  const sessionDir = path.join(root, '--tmp--', 'session-test-1');
  fs.mkdirSync(sessionDir, { recursive: true });
  fs.writeFileSync(path.join(sessionDir, 'session.jsonl'), `${text}\n`);
  const rows = collectDshRows({ roots: [root] });
  assert.equal(rows.length, 1);
});

test('dsh seedLength skips inherited fork events below the boundary', () => {
  const events = [
    sessionEvent({ seedLength: 10 }),
    assistantMessage({ id: 'inherited', seq: 5, input: 999 }),   // seq < seedLength → 跳过
    assistantMessage({ id: 'fresh', seq: 20, input: 30, output: 5 }) // seq >= seedLength → 计入
  ];
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'dsh-usage-'));
  const sessionDir = path.join(root, '--tmp--', 'session-test-1');
  fs.mkdirSync(sessionDir, { recursive: true });
  fs.writeFileSync(path.join(sessionDir, 'session.jsonl'), `${events.map((e) => JSON.stringify(e)).join('\n')}\n`);
  const rows = collectDshRows({ roots: [root] });
  assert.equal(rows.length, 1);
  assert.equal(rows[0].input, 30);
});

test('dsh falls back to request/header provider+model when a message has no source', () => {
  const events = [
    sessionEvent(),
    requestHeader({ provider: 'deepseek-official', model: 'deepseek-v4-pro' }),
    {
      type: 'assistant/message', seq: 50, time: 1786681800000,
      data: { turn: 1, step: 1, usage: { inputTokens: 12, outputTokens: 3 }, message: { role: 'assistant' } }
      // 注意：message 里没有 source，应回落到上一条 request/header 的 provider/model。
    }
  ];
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'dsh-usage-'));
  const sessionDir = path.join(root, '--tmp--', 'session-test-1');
  fs.mkdirSync(sessionDir, { recursive: true });
  fs.writeFileSync(path.join(sessionDir, 'session.jsonl'), `${events.map((e) => JSON.stringify(e)).join('\n')}\n`);
  const rows = collectDshRows({ roots: [root] });
  assert.equal(rows.length, 1);
  assert.equal(rows[0].provider, 'deepseek-official');
  assert.equal(rows[0].model, 'deepseek-v4-pro');
});

test('dsh keeps raw session id and groups entries by session+model', () => {
  const events = [
    sessionEvent({ id: 'session-abc' }),
    assistantMessage({ id: 'a1', seq: 10, model: 'deepseek-v4-pro', input: 10 }),
    assistantMessage({ id: 'a2', seq: 20, model: 'deepseek-v4-flash', output: 4 })
  ];
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'dsh-usage-'));
  const sessionDir = path.join(root, '--tmp--', 'session-abc');
  fs.mkdirSync(sessionDir, { recursive: true });
  fs.writeFileSync(path.join(sessionDir, 'session.jsonl'), `${events.map((e) => JSON.stringify(e)).join('\n')}\n`);
  const periods = buildDshPeriods({ now: '2026-07-09T13:00:00.000Z', allTimeSince: '2026-01-01', roots: [root] });
  assert.equal(periods.today.groupBy, 'client,session,model');
  assert.deepEqual(periods.today.entries.map((e) => e.sessionId), ['session-abc', 'session-abc']);
  const usage = extractUsageFromTokscale(periods.today);
  const session = usage.sessions['dsh:session-abc'];
  assert.ok(session);
  assert.equal(session.totalTokens, 14);
  assert.equal(session.messageCount, 2);
  assert.deepEqual(session.models, { 'deepseek-v4-pro': 10, 'deepseek-v4-flash': 4 });
});

test('dsh periods read each session file once across all three windows', () => {
  const events = [
    sessionEvent(),
    assistantMessage({ id: 'only', seq: 10, input: 10 })
  ];
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'dsh-usage-'));
  const sessionDir = path.join(root, '--tmp--', 'session-test-1');
  fs.mkdirSync(sessionDir, { recursive: true });
  const file = path.join(sessionDir, 'session.jsonl');
  fs.writeFileSync(file, `${events.map((e) => JSON.stringify(e)).join('\n')}\n`);
  const originalReadFileSync = fs.readFileSync;
  let reads = 0;
  fs.readFileSync = (...args) => {
    if (args[0] === file) reads += 1;
    return originalReadFileSync(...args);
  };
  try {
    const periods = buildDshPeriods({ now: '2026-07-09T13:00:00.000Z', allTimeSince: '2026-01-01', roots: [root] });
    assert.equal(reads, 1);
    assert.equal(extractUsageFromTokscale(periods.today).totalTokens, 10);
    assert.equal(extractUsageFromTokscale(periods.month).totalTokens, 10);
    assert.equal(extractUsageFromTokscale(periods.allTime).totalTokens, 10);
  } finally {
    fs.readFileSync = originalReadFileSync;
  }
});

test('dsh history keeps per-day and per-model attribution with a reasoning bucket', () => {
  const rows = [
    { sessionId: 's1', model: 'deepseek-v4-pro', provider: 'ps', input: 10, output: 2, cacheRead: 0, cacheWrite: 0, reasoning: 1, createdAt: Date.parse('2026-07-08T12:00:00.000Z'), messages: 1 },
    { sessionId: 's1', model: 'deepseek-v4-flash', provider: 'ps', input: 20, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0, createdAt: Date.parse('2026-07-09T12:00:00.000Z'), messages: 1 }
  ];
  const graph = buildDshHistoryGraph({ rows });
  assert.deepEqual(graph.contributions, [
    { date: '2026-07-08', clients: [{ client: 'dsh', modelId: 'deepseek-v4-pro', tokens: { input: 10, output: 2, cacheRead: 0, cacheWrite: 0, reasoning: 1 }, cost: 0, messages: 1 }] },
    { date: '2026-07-09', clients: [{ client: 'dsh', modelId: 'deepseek-v4-flash', tokens: { input: 20, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0 }, cost: 0, messages: 1 }] }
  ]);
});

test('dsh cost estimates use every populated token category', () => {
  const rows = [{
    sessionId: 's1', model: 'Claude-Sonnet', provider: 'ps',
    input: 10, output: 2, cacheRead: 4, cacheWrite: 3, reasoning: 0,
    createdAt: Date.parse('2026-07-09T12:00:00.000Z'), messages: 1
  }];
  const pricingByModel = {
    'claude-sonnet': {
      inputCostPerToken: 0.000003,
      outputCostPerToken: 0.000015,
      cacheReadInputTokenCost: 0.0000003,
      cacheCreationInputTokenCost: 0.00000375
    }
  };
  const json = buildDshTokscaleJson({}, { rows, pricingByModel });
  assert.ok(Math.abs(json.entries[0].cost - 0.00007245) < 1e-12);
  assert.ok(Math.abs(json.totalCost - 0.00007245) < 1e-12);
  const graph = buildDshHistoryGraph({ rows, pricingByModel });
  assert.ok(Math.abs(graph.contributions[0].clients[0].cost - 0.00007245) < 1e-12);
});

test('dsh leaves an incomplete price out instead of partially estimating it', () => {
  const rows = [{ sessionId: 's1', model: 'custom-model', provider: 'ps', input: 10, output: 2, cacheRead: 0, cacheWrite: 1, reasoning: 0, createdAt: 0, messages: 1 }];
  const json = buildDshTokscaleJson({}, {
    rows,
    pricingByModel: { 'custom-model': { inputCostPerToken: 0.000001, outputCostPerToken: 0.000002 } }
  });
  assert.equal(json.entries[0].cost, 0);
});

test('dsh collectDshRows returns empty without throwing when sessions root is missing', () => {
  const root = path.join(os.tmpdir(), `dsh-missing-${process.pid}-${Date.now()}`);
  assert.deepEqual(collectDshRows({ roots: [root] }), []);
});

test('dsh zstd frame splitter handles a buffer with no magic bytes', () => {
  assert.deepEqual(zstdFrames(Buffer.from('not zstd')), []);
  assert.equal(decodeZstdFrames(Buffer.from('not zstd')), '');
});
