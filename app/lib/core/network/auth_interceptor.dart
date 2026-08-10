import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_mode.dart';
import 'auth_paths.dart';
import 'dio_client.dart';

// ============================================================
// AuthInterceptor —— 鉴权注入 + 401 滚动续期。
//
// onRequest:非免鉴权路径注入 Authorization(读 authProvider 当前 state)。
// onError:401 且非免鉴权路径 → 触发一次续期(并发锁),成功则重放原请求,
//   失败(refresh 也 401/网络错误)→ clearSession,向上抛 401 让 UI 回登录。
//
// 续期并发锁:首个 401 调 /api/auth/refresh 并用 Completer 广播;
//   并发的其他 401 等同一 future,避免并发刷新导致 refresh token 被多次换发
//   (滚动续期下旧 refresh 即作废,第二次必失败)。锁针对"本次续期",
//   续期结束即释放;下一轮 401 可再触发。
// ============================================================

class AuthInterceptor extends Interceptor {
  AuthInterceptor({required this.ref});

  final Ref ref;

  // 续期并发锁:进行中时非空,完成后置 null。
  Completer<String?>? _refreshCompleter;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final auth = ref.read(authProvider);
    if (!isNoAuthPath(options.path) && auth.authorizationHeader != null) {
      options.headers['Authorization'] = auth.authorizationHeader;
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;
    final path = err.requestOptions.path;

    // 仅 401 且非免鉴权路径(续期端点自身 401 不在此处理,直接抛)才续期
    if (status != 401 || isNoAuthPath(path)) {
      handler.next(err);
      return;
    }

    // 未携带 refresh token → 无法续期,清会话后抛
    final auth = ref.read(authProvider);
    if (auth.refreshToken == null || auth.refreshToken!.isEmpty) {
      await _clearAndFail();
      handler.next(err);
      return;
    }

    final newToken = await _ensureRefresh();
    if (newToken == null) {
      // 续期失败(refresh 过期/无效)→ 清会话,抛原 401
      await _clearAndFail();
      handler.next(err);
      return;
    }

    // 续期成功:替换原请求头,重放
    try {
      final clone = await ref.read(dioProvider).fetch(
            err.requestOptions.copyWith(
              headers: {
                ...err.requestOptions.headers,
                'Authorization': 'Bearer $newToken',
              },
            ),
          );
      handler.resolve(clone);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  // 触发/等待续期:若已有进行中的续期则复用其结果(并发锁)。
  // 返回新 accessToken;失败返回 null。
  Future<String?> _ensureRefresh() {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }
    final c = Completer<String?>();
    _refreshCompleter = c;
    _doRefresh().then(c.complete).catchError((_) => c.complete(null));
    return c.future;
  }

  // 实际调 /api/auth/refresh。成功写回 secure_storage + 更新 AuthState。
  Future<String?> _doRefresh() async {
    final auth = ref.read(authProvider);
    final refreshToken = auth.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return null;

    final dio = ref.read(dioProvider);
    try {
      final resp = await dio.post<dynamic>(
        '/api/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final data = resp.data as Map<String, dynamic>?;
      if (data == null || data['ok'] != true) return null;
      final accessToken = data['token'] as String?;
      final newRefresh = data['refreshToken'] as String?;
      if (accessToken == null) return null;
      // 滚动续期:整体替换 token 对,更新 AuthState + secure_storage
      await ref
          .read(authProvider.notifier)
          .onTokenRefreshed(accessToken: accessToken, refreshToken: newRefresh ?? refreshToken);
      return accessToken;
    } catch (_) {
      return null;
    } finally {
      _refreshCompleter = null;
    }
  }

  Future<void> _clearAndFail() async {
    await ref.read(authProvider.notifier).clearSession();
  }
}
