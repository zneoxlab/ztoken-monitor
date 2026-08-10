import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stats.dart';
import 'auth_mode.dart';
import 'dio_client.dart';
import 'sse_client.dart';

// 会话缓存键:登录/登出/切账号时变化,用于重建 statsProvider 与失效 history。
String sessionCacheKey(AuthState auth) {
  if (!auth.isAuthenticated) return '';
  final credential =
      auth.mode == AuthMode.saas ? auth.accessToken : auth.hubSecret;
  return '${auth.mode.name}:${credential ?? ''}:${auth.userEmail ?? ''}';
}

final sessionCacheKeyProvider = Provider<String>((ref) {
  return sessionCacheKey(ref.watch(authProvider));
});

// 在 app 根 watch,确保登出时立刻停 SSE 并清历史缓存(不依赖 stats 页是否在树上)。
final sessionDataLifecycleProvider = Provider<void>((ref) {
  ref.listen<String>(sessionCacheKeyProvider, (previous, next) {
    if (previous == next) return;
    ref.invalidate(historyProvider);
    if (next.isEmpty) {
      ref.read(sseClientProvider).stop();
    }
  });
});

// ============================================================
// Stats 仓库 + 状态 provider。
// 对照 GOAL.md §6.3:冷启动 GET /api/stats 全量 → 渲染 → 建 SSE 增量刷新。
//
// StatsNotifier:StateNotifier<AsyncValue<StatsSnapshot>>
//   init():首帧 GET /api/stats → data;同时订阅 SseClient.stats 流,
//     每帧(SSE 或轮询)用 StatsSnapshot.fromJson 替换 data。
//   错误:GET 失败 → AsyncError(不阻塞后续 SSE);SSE 帧解析失败忽略单帧。
// ============================================================

// 单次拉取:GET /api/stats → StatsSnapshot。供冷启动与轮询降级复用。
Future<StatsSnapshot> fetchStats(Ref ref) async {
  final resp = await ref.read(dioProvider).get<dynamic>(
        '/api/stats',
        options: Options(receiveTimeout: kHubDataReceiveTimeout),
      );
  return StatsSnapshot.fromJson(resp.data);
}

// 拉取完整历史:GET /api/history → {daily, monthly, summary}。
// 与 /api/stats 里被 historyPreview 裁剪成近 30 天的 daily 不同,这里返回全量 daily。
// 热力图需要近一年(365 天)数据,故单独拉这条;不并入 stats(避免撑大每帧 SSE)。
// 懒加载:首页热力图卡 ref.watch 时才发请求。
Future<HistoryPreview> fetchHistory(Ref ref) async {
  final resp = await ref.read(dioProvider).get<dynamic>(
        '/api/history',
        options: Options(receiveTimeout: kHubDataReceiveTimeout),
      );
  return HistoryPreview.fromJson(resp.data);
}

// 完整历史 provider:热力图一年视图用。AsyncValue 天然三态。
final historyProvider = FutureProvider<HistoryPreview>((ref) async {
  return fetchHistory(ref);
});

class StatsNotifier extends StateNotifier<AsyncValue<StatsSnapshot>> {
  StatsNotifier(this._ref, {bool start = true}) : super(const AsyncValue.loading()) {
    if (start) _init();
  }

  final Ref _ref;
  StreamSubscription<Map<String, dynamic>>? _statsSub;

  Future<void> _init() async {
    // 未认证不应进到此 provider(路由守卫拦),但兜底
    if (!_ref.read(authProvider).isAuthenticated) {
      state = const AsyncValue.error('未认证', StackTrace.empty);
      return;
    }
    // 1. 冷启动全量拉取
    try {
      final snapshot = await fetchStats(_ref);
      if (!mounted) return;
      state = AsyncValue.data(snapshot);
    } catch (e, st) {
      if (!mounted) return;
      state = AsyncValue.error(e, st);
      // GET 失败仍继续建 SSE(网络恢复后能补上)
    }
    // 2. 订阅 SSE/轮询增量帧
    _statsSub = _ref.read(sseClientProvider).stats.listen(
      _onStatsFrame,
      onError: (Object e) {
        // SSE 流本身错(不该发生,SseClient 内部已容错);忽略
      },
    );
    // 3. 启动 SSE 连接(若未启动)
    await _ref.read(sseClientProvider).start();
  }

  void _onStatsFrame(Map<String, dynamic> raw) {
    if (!mounted) return;
    try {
      state = AsyncValue.data(StatsSnapshot.fromJson(raw));
    } catch (_) {
      // 单帧解析失败:保留上一个 data,不污染
    }
  }

  // 手动刷新(下拉/回前台):GET 一次 + 确保 SSE 在连。
  Future<void> refresh() async {
    try {
      final snapshot = await fetchStats(_ref);
      if (!mounted) return;
      state = AsyncValue.data(snapshot);
    } catch (_) {
      // 刷新失败保留旧数据
    }
    await _ref.read(sseClientProvider).onResume();
  }

  @override
  void dispose() {
    _statsSub?.cancel();
    super.dispose();
  }
}

// statsProvider:驱动首页等所有数据页。AsyncValue 天然带 loading/data/error。
// 绑定 sessionCacheKey:登出/切账号销毁旧 notifier,避免新登录仍显示上一用户数据。
final statsProvider =
    StateNotifierProvider<StatsNotifier, AsyncValue<StatsSnapshot>>((ref) {
  ref.watch(sessionDataLifecycleProvider);
  final sessionKey = ref.watch(sessionCacheKeyProvider);
  if (sessionKey.isEmpty) {
    return StatsNotifier(ref, start: false);
  }
  return StatsNotifier(ref);
});
