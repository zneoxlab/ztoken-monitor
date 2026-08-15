'use strict';

/**
 * DeepSeek Harness (dsh) 会话用量本地解析器。
 *
 * 读取 $DSH_HOME/sessions 下按 <编码cwd>/<会话id>/session.jsonl.zstd 组织的多帧压缩文件，
 * 按 assistant/message 事件里的 data.usage 聚合 token 用量，输出与 tokscale JSON
 * 同构的结果，可直接喂给 extractUsageFromTokscale 或与 tokscale 结果合并。
 *
 * 为什么需要本地解析器：tokscale 已发布版本（4.13.0）尚不认识 client id `dsh`，
 * 未知 --client 值会让 tokscale 直接 exit 2、拖垮整次扫描；而 master 分支虽已合并
 * dsh 支持但未发布。这里镜像 promaUsage.js 的模式做本地解析，并在 collector 里做
 * 运行时能力检测——一旦 bundled tokscale 认识 dsh，自动切回原生支持，避免重复计数。
 *
 * 仅依赖 Node 内置模块（fs/os/path/zlib），绝不 vendored 进 Worker
 * （Worker 不解析本地会话，且 node:zlib 在 Worker 运行时不可用）。
 */

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const zlib = require('node:zlib');

// 重导出 promaUsage 的计价函数，避免在本文件复制一份实现——
// 两者的 entry 结构都遵循 estimatedRowCost 的契约（input/output/cacheRead/cacheWrite 桶）。
const { estimatedRowCost } = require('./promaUsage');

const DSH_CLIENT = 'dsh';
const DSH_SOURCE_CHECK_ID = 'dsh-sessions';

// DSH 把会话写在 $DSH_HOME/sessions 下；DSH_HOME 默认 ~/.dsh（与上游 tokscale dsh.rs 一致）。
const DSH_HOME = process.env.DSH_HOME || path.join(os.homedir(), '.dsh');
const DSH_SESSIONS_ROOT = path.join(DSH_HOME, 'sessions');

// zstd 帧魔数。DSH 每次 flush 追加一帧，单文件可达上千帧；
// node:zlib.zstdDecompressSync 只解第一帧，必须按魔数切分后逐帧解码。
const ZSTD_MAGIC = Buffer.from([0x28, 0xb5, 0x2f, 0xfd]);

module.exports = {
  DSH_CLIENT,
  DSH_SOURCE_CHECK_ID,
  DSH_HOME,
  DSH_SESSIONS_ROOT,
  zstdFrames,
  decodeZstdFrames,
  parseSessionFile,
  collectDshRows,
  estimatedRowCost,
  buildDshTokscaleJson,
  buildDshPeriods,
  buildDshHistoryGraph
};

function numberValue(value) {
  const n = Number(value || 0);
  return Number.isFinite(n) ? n : 0;
}

// DSH 的 time 字段已是毫秒（实测 13 位 epoch ms），这里只做防御性规整，
// 不像 promaUsage 那样按量级猜测秒/毫秒——避免把毫秒当秒再 ×1000 放大。
function timestampMs(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return value > 0 ? value : 0;
  if (typeof value === 'string' && value.trim()) {
    const numeric = Number(value);
    if (Number.isFinite(numeric)) return numeric > 0 ? numeric : 0;
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? 0 : parsed;
  }
  return 0;
}

function normalizedModelId(value) {
  return String(value || '').trim().toLowerCase();
}

function localDateKey(timestamp) {
  const date = new Date(timestamp);
  if (Number.isNaN(date.getTime())) return '';
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/**
 * 按 zstd 魔数切分 buffer 成若干完整帧的数组。
 * DSH 文件是 append-only：每次 flush 追加一帧，文件结尾可能是半帧（torn tail），
 * 解码时按帧逐个 try/catch，坏帧跳过即可。
 */
function zstdFrames(buffer) {
  if (!Buffer.isBuffer(buffer)) buffer = Buffer.from(buffer);
  const frames = [];
  let cursor = 0;
  while (cursor < buffer.length) {
    const start = buffer.indexOf(ZSTD_MAGIC, cursor);
    if (start < 0) break;
    // 下一帧起点即本帧终点；最后一帧延伸到 buffer 末尾（可能含 torn 尾）。
    const next = buffer.indexOf(ZSTD_MAGIC, start + ZSTD_MAGIC.length);
    const end = next < 0 ? buffer.length : next;
    frames.push(buffer.subarray(start, end));
    cursor = next < 0 ? buffer.length : next;
  }
  return frames;
}

/**
 * 解码多帧 zstd buffer 为拼接后的文本。
 *
 * 关键约束：node:zlib.zstdDecompressSync 只解第一帧，所以这里必须逐帧解码拼接。
 * 运行时守卫——Node 22.13/22.14 还没有 zstdDecompressSync（22.15+ 才有）：
 * 此时返回空串让 dsh 静默贡献 0，绝不抛异常拖垮整次扫描。
 */
function decodeZstdFrames(buffer) {
  if (typeof zlib.zstdDecompressSync !== 'function') return '';
  const chunks = [];
  for (const frame of zstdFrames(buffer)) {
    try {
      chunks.push(zlib.zstdDecompressSync(frame).toString('utf8'));
    } catch (_) {
      // 镜像上游 tokscale dsh.rs 的语义：坏帧（torn tail / 假魔数）直接跳过，
      // 既不抛错也不尝试拼接——假魔数场景远少于 torn tail，合并处理徒增复杂度。
    }
  }
  return chunks.join('');
}

/**
 * 从 DSH 的 usage 对象拆出各 token 桶。
 *
 * 关键语义（镜像 tokscale dsh.rs）：reasoning 是 output 的子集——
 * upstream 的 outputTokens 已包含 reasoningTokens，所以展示用的 output 桶要减掉它，
 * 同时单独保留 reasoning 桶供历史图展示；token 总量只算 input/output/cacheRead/cacheWrite，
 * 不重复加 reasoning（与 reasonix 不同：reasonix 的 output 与 reasoning 是不相交字段）。
 */
function tokensFromUsage(usage) {
  const u = usage || {};
  const input = numberValue(u.inputTokens ?? u.input_tokens ?? u.input);
  const outputTotal = numberValue(u.outputTokens ?? u.output_tokens ?? u.output);
  const reasoning = Math.max(0, numberValue(u.reasoningTokens ?? u.reasoning_tokens ?? u.reasoning));
  const cacheRead = numberValue(u.cacheReadTokens ?? u.cache_read_tokens ?? u.cacheRead);
  const cacheWrite = numberValue(u.cacheWriteTokens ?? u.cache_write_tokens ?? u.cacheWrite);
  // output 桶减去 reasoning 子集后表示"非推理输出"，避免与 reasoning 桶重复计入总量。
  const output = Math.max(0, outputTotal - reasoning);
  return { input, output, cacheRead, cacheWrite, reasoning };
}

/**
 * 解析单个会话文件的原始文本（已解压的 JSONL），返回每条带 usage 的 assistant/message 一行。
 *
 * 严格镜像 tokscale crates/tokscale-core/src/sessions/dsh.rs 的状态机：
 * - session 事件取 id（缺失回落目录名 / 'unknown'）与可选 seedLength（fork 继承段边界）；
 * - request/header 的 data.header.config.{provider,model} 作为无 source 消息的回落值；
 * - user/message 置位 pendingUserMessage，给下一条无 turn 的 assistant 消息当回合起点；
 * - assistant/message 是唯一产出用量行的事件，按 seedLength、空 usage、去重三道闸过滤。
 */
function collectSessionRowsFromText(text, fallbackSessionId) {
  const lines = String(text || '').split(/\r?\n/);
  let sessionId = fallbackSessionId || 'unknown';
  let seedLength = 0;
  let lastProvider = 'unknown';
  let lastModel = 'unknown';
  let pendingUserMessage = false;
  const seenDedup = new Set();
  const rows = [];

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    let event;
    try {
      event = JSON.parse(trimmed);
    } catch (_) {
      continue; // 跳过无法解析的行（torn 帧、写入中途的非完整 JSON）
    }

    switch (event.type) {
      case 'session': {
        // DSH 的 session 事件 id 在顶层（实测所有文件都是如此），不是 data.id。
        const id = event.id || event.data?.id;
        if (id) sessionId = String(id);
        const seed = numberValue(event.seedLength ?? event.data?.seedLength);
        if (seed > 0) seedLength = seed; // 仅取正值；缺失即视为无 fork 继承段。
        break;
      }
      case 'request/header': {
        const cfg = event.data?.header?.config || {};
        if (cfg.provider) lastProvider = String(cfg.provider);
        if (cfg.model) lastModel = String(cfg.model);
        break;
      }
      case 'user/message': {
        pendingUserMessage = true;
        break;
      }
      case 'assistant/message': {
        // fork 继承段：seq 小于 seedLength 的事件来自被 fork 的种子会话，不计入本次统计。
        const seq = numberValue(event.seq);
        if (seedLength > 0 && seq > 0 && seq < seedLength) break;

        const usage = event.data?.usage;
        if (!usage) break;
        const tokens = tokensFromUsage(usage);
        const total = tokens.input + tokens.output + tokens.cacheRead + tokens.cacheWrite;
        // 全 0 的 usage 行（如纯 tool-use 无生成）不产出用量行。
        if (total === 0 && tokens.reasoning === 0) break;

        const createdAt = timestampMs(event.time ?? event.data?.time);
        const source = event.data?.message?.source || {};
        const provider = String(source.provider || lastProvider || 'unknown');
        const model = String(source.model || lastModel || 'unknown');

        // 回合归属：data.turn 存在则以 turn 号去重；否则消费 pendingUserMessage。
        // 这里只用于去重 key 不影响 token 聚合，故不再单独记录 turn。
        if (event.data?.turn === undefined && event.data?.turn === null) {
          if (pendingUserMessage) pendingUserMessage = false;
        }

        // 去重 identity：优先用 message.id（消息级唯一），缺失回落 sessionId（会话级）。
        const msgId = event.data?.message?.id;
        const identity = msgId ? `msg:${msgId}` : `sid:${sessionId}`;
        const dedupKey = `dsh:${identity}:${createdAt}:${provider}:${model}:${tokens.input}:${tokens.output}:${tokens.cacheRead}:${tokens.cacheWrite}:${tokens.reasoning}`;
        if (seenDedup.has(dedupKey)) break;
        seenDedup.add(dedupKey);

        rows.push({
          sessionId,
          model,
          provider,
          input: tokens.input,
          output: tokens.output,
          cacheRead: tokens.cacheRead,
          cacheWrite: tokens.cacheWrite,
          reasoning: tokens.reasoning,
          createdAt,
          messages: 1
        });
        break;
      }
      default:
        break;
    }
  }
  return rows;
}

/**
 * 读取并解析单个 session.jsonl[.zstd] 文件。
 *
 * 按文件首 4 字节是否等于 zstd 魔数分派解压方式，不按文件名判断——
 * DSH 也可能写出未压缩的 session.jsonl 变体。fallbackSessionId 取所在目录名，
 * 以便 session 事件缺失时仍能归因（实测 session.id 总存在，这是兜底）。
 */
function parseSessionFile(filePath, options = {}) {
  let buffer;
  try {
    buffer = fs.readFileSync(filePath);
  } catch (_) {
    return [];
  }
  const fallback = options.fallbackSessionId
    || `session-${path.basename(path.dirname(filePath))}`;
  const looksZstd = buffer.length >= 4 && buffer.subarray(0, 4).equals(ZSTD_MAGIC);
  const text = looksZstd ? decodeZstdFrames(buffer) : buffer.toString('utf8');
  return collectSessionRowsFromText(text, fallback);
}

/**
 * 遍历 DSH_SESSIONS_ROOT 下所有会话文件，返回全部用量行。
 *
 * 每个 tick 读一次（每文件只读一次），由调用方据此派生 today/month/allTime/history，
 * 避免为每个窗口重复打开同一批压缩文件。roots 可注入便于测试与多 DSH_HOME。
 */
function collectDshRows(options = {}) {
  const roots = Array.isArray(options.roots) ? options.roots : [DSH_SESSIONS_ROOT];
  const rows = [];
  for (const root of roots) {
    let entries;
    try {
      entries = fs.readdirSync(root, { withFileTypes: true });
    } catch (_) {
      continue; // 根目录不存在或不可读——dsh 未安装的常态，静默返回空。
    }
    for (const entry of entries) {
      if (!entry.isDirectory()) continue;
      const cwdDir = path.join(root, entry.name); // 编码后的 cwd 目录
      let sessionDirs;
      try {
        sessionDirs = fs.readdirSync(cwdDir, { withFileTypes: true });
      } catch (_) {
        continue;
      }
      for (const sd of sessionDirs) {
        if (!sd.isDirectory()) continue;
        const sessionDir = path.join(cwdDir, sd.name);
        // 优先 session.jsonl.zstd；未来若出现未压缩变体也兜底匹配 session.jsonl。
        for (const name of ['session.jsonl.zstd', 'session.jsonl']) {
          const file = path.join(sessionDir, name);
          if (fs.existsSync(file)) {
            rows.push(...parseSessionFile(file, { fallbackSessionId: sd.name }));
            break;
          }
        }
      }
    }
  }
  return rows;
}

function windowStartMs(windows) {
  return Math.max(0, timestampMs(windows.todayStart), timestampMs(windows.monthStart), timestampMs(windows.allTimeSince));
}

/**
 * 从 DSH 会话用量行构造与 tokscale JSON 同构的结果。
 *
 * 关键：先按 sinceMs 过滤再按 model 聚合——
 * 若改成先聚合再过滤，会按"该 model 在会话内的最早时间"取舍，
 * 把一个跨午夜的会话今天的用量也丢掉（与 proma 同理）。
 */
function buildDshTokscaleJson(windows = {}, options = {}) {
  const sinceMs = windowStartMs(windows);
  const allRows = (Array.isArray(options.rows) ? options.rows : collectDshRows(options))
    .filter((row) => {
      if (!sinceMs) return true;
      if (!row.createdAt) return options.includeUndated === true;
      return row.createdAt >= sinceMs;
    });

  // 按 会话+model 聚合：sessionId 用原始事件 id（不加 proma 那种 @namespace 后缀），
  // 这样未来切回 tokscale 原生 dsh 时会话 id 完全一致，本地→原生切换不会扰动历史。
  const bySessionModel = new Map();
  let totalInput = 0, totalOutput = 0, totalCacheRead = 0, totalCacheWrite = 0, totalReasoning = 0;
  let totalMessages = 0, totalCost = 0;
  for (const row of allRows) {
    const key = `${row.sessionId || 'unknown'} ${row.model}`;
    if (!bySessionModel.has(key)) {
      bySessionModel.set(key, {
        sessionId: row.sessionId || 'unknown',
        model: row.model,
        provider: row.provider || 'unknown',
        input: 0, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0,
        messages: 0, cost: 0, startedAt: 0, lastUsedAt: 0
      });
    }
    const m = bySessionModel.get(key);
    const cost = estimatedRowCost(row, options.pricingByModel);
    m.input += row.input;
    m.output += row.output;
    m.cacheRead += row.cacheRead;
    m.cacheWrite += row.cacheWrite;
    m.reasoning += row.reasoning;
    m.messages += Number(row.messages || 1);
    m.cost += cost === null ? 0 : cost;
    if (row.createdAt && (!m.startedAt || row.createdAt < m.startedAt)) m.startedAt = row.createdAt;
    if (row.createdAt > m.lastUsedAt) m.lastUsedAt = row.createdAt;
  }

  const entries = [];
  for (const m of bySessionModel.values()) {
    entries.push({
      client: DSH_CLIENT,
      mergedClients: null,
      sessionId: m.sessionId,
      model: m.model,
      provider: m.provider,
      input: m.input,
      output: m.output,
      cacheRead: m.cacheRead,
      cacheWrite: m.cacheWrite,
      reasoning: m.reasoning,
      messageCount: m.messages,
      cost: m.cost,
      startedAt: m.startedAt ? new Date(m.startedAt).toISOString() : '',
      lastUsedAt: m.lastUsedAt ? new Date(m.lastUsedAt).toISOString() : '',
      performance: null
    });
    totalInput += m.input;
    totalOutput += m.output;
    totalCacheRead += m.cacheRead;
    totalCacheWrite += m.cacheWrite;
    totalReasoning += m.reasoning;
    totalMessages += m.messages;
    totalCost += m.cost;
  }

  return {
    groupBy: 'client,session,model',
    entries,
    totalInput,
    totalOutput,
    totalCacheRead,
    totalCacheWrite,
    totalReasoning,
    totalMessages,
    totalCost,
    processingTimeMs: 0
  };
}

/**
 * 计算本地午夜与月初边界，分别构造 today/month/allTime 三个窗口的 tokscale 同构 JSON。
 * allTime 用 includeUndated: true 以兜住无 time 的历史行（与 proma 一致）。
 */
function buildDshPeriods(options = {}) {
  const now = options.now ? new Date(options.now) : new Date();
  const rows = Array.isArray(options.rows) ? options.rows : collectDshRows(options);
  const buildOptions = { rows, pricingByModel: options.pricingByModel };
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0).getTime();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1, 0, 0, 0, 0).getTime();

  return {
    today: buildDshTokscaleJson({ todayStart }, buildOptions),
    month: buildDshTokscaleJson({ monthStart }, buildOptions),
    allTime: buildDshTokscaleJson({ allTimeSince: options.allTimeSince }, { ...buildOptions, includeUndated: true })
  };
}

/**
 * 按日、按 model 构造历史图 contributions，供 collector.js 与 tokscale 图输出合并。
 *
 * reasoning 桶单独累加但不计入 tokens 总和——与 buildDshTokscaleJson 对齐：
 * reasoning 已是 output 的子集，进总量会重复计数。history.js 对非 reasonix 客户端
 * 也不会把 reasoning 加到日总量，与本处的取舍一致。
 */
function buildDshHistoryGraph(options = {}) {
  const byDate = new Map();
  const rows = Array.isArray(options.rows) ? options.rows : collectDshRows(options);
  for (const row of rows) {
    const date = row.createdAt ? localDateKey(row.createdAt) : '';
    if (!date) continue; // 无日期的行无法忠实落到某一天。
    let day = byDate.get(date);
    if (!day) {
      day = { date, clients: [] };
      byDate.set(date, day);
    }
    const modelId = normalizedModelId(row.model) || 'unknown';
    let client = day.clients.find((entry) => entry.modelId === modelId);
    if (!client) {
      client = {
        client: DSH_CLIENT,
        modelId,
        tokens: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0 },
        cost: 0,
        messages: 0
      };
      day.clients.push(client);
    }
    const cost = estimatedRowCost(row, options.pricingByModel);
    client.tokens.input += row.input;
    client.tokens.output += row.output;
    client.tokens.cacheRead += row.cacheRead;
    client.tokens.cacheWrite += row.cacheWrite;
    client.tokens.reasoning += row.reasoning;
    client.cost += cost === null ? 0 : cost;
    client.messages += 1;
  }
  return { contributions: [...byDate.values()].sort((a, b) => a.date.localeCompare(b.date)) };
}
