'use strict';

// SSE 客户端注册表：per-user 隔离。
// Map<userId, Set<res>>，广播时只发给该 userId 的连接——这是多租户隔离在 SSE 层的体现。
//
// 与现有 node hub（src/hub/server.js）的 sseClients Set 对应，区别是按 userId 分桶。
// Phase 1 单实例内存即可；Phase 2 多实例时，把 broadcastStats 替换成 Redis pub/sub 实现
// （发布到 stats:user:<userId> channel，每个实例订阅并广播给本地连接）。

const SSE_HEARTBEAT_MS = 30000;

function sseFormat(event, data) {
  return `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
}

function createSseRegistry() {
  // userId -> Set<res>
  const clientsByUser = new Map();
  // res -> { userId, heartbeat } 用于 cleanup
  const meta = new WeakMap();

  function getUserSet(userId) {
    let set = clientsByUser.get(userId);
    if (!set) {
      set = new Set();
      clientsByUser.set(userId, set);
    }
    return set;
  }

  // 注册一个连接，返回 cleanup 函数
  function add(userId, res) {
    const set = getUserSet(userId);
    set.add(res);
    const heartbeat = setInterval(() => {
      try { res.write(': hb\n\n'); } catch (_) { /* 连接已断，cleanup 会处理 */ }
    }, SSE_HEARTBEAT_MS);
    meta.set(res, { userId, heartbeat });
    return () => remove(userId, res);
  }

  function remove(userId, res) {
    const m = meta.get(res);
    if (m) {
      clearInterval(m.heartbeat);
      meta.delete(res);
    }
    const set = clientsByUser.get(userId);
    if (set) {
      set.delete(res);
      if (set.size === 0) clientsByUser.delete(userId);
    }
  }

  // 广播 stats 帧给某 userId 的所有连接（不同用户的帧互不可见）
  function broadcastStats(userId, stats, reason = 'update', at = new Date().toISOString()) {
    const set = clientsByUser.get(userId);
    if (!set || set.size === 0) return;
    const payload = sseFormat('stats', { type: 'stats', reason, stats, at });
    for (const res of set) {
      try { res.write(payload); } catch (_) { remove(userId, res); }
    }
  }

  // 连接建立时发首帧 snapshot
  function sendSnapshot(res, stats, at = new Date().toISOString()) {
    res.write(sseFormat('snapshot', { type: 'stats', reason: 'snapshot', stats, at }));
  }

  function size(userId) {
    return clientsByUser.get(userId)?.size || 0;
  }

  function closeAll() {
    for (const [, set] of clientsByUser) {
      for (const res of set) {
        const m = meta.get(res);
        if (m) clearInterval(m.heartbeat);
        try { res.end(); } catch (_) {}
      }
    }
    clientsByUser.clear();
  }

  return { add, remove, broadcastStats, sendSnapshot, size, closeAll };
}

module.exports = { createSseRegistry, sseFormat, SSE_HEARTBEAT_MS };
