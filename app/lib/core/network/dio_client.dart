import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_mode.dart';
import 'auth_interceptor.dart';

// ============================================================
// dio 客户端 —— 全局唯一 Dio 实例 + 鉴权拦截器。
// 对照 GOAL.md §6.1/§6.2、saas-hub/README.md §鉴权。
//
// baseUrl 来自 hubUrlProvider(SaaS 默认 / 自建 Hub 可改)。
// 鉴权:请求拦截器注入 Authorization(SaaS→JWT / 自建→hubSecret);
// 401 滚动续期:用 refreshToken 调 /api/auth/refresh 换发新 token 对,
//   并发锁(首个 401 触发续期,其余等同一结果),成功重放原请求,
//   失败(refresh 也 401)→ clearSession 回登录页。
// 健康检查/登录/注册/续期端点本身不带 Authorization,也不触发续期。
// ============================================================

// 默认超时:登录/健康检查等轻量接口。
const kHubConnectTimeout = Duration(seconds: 15);
const kHubFastReceiveTimeout = Duration(seconds: 15);
// /api/stats、/api/history 等聚合接口在设备多或 Hub 负载高时可能较慢,
// 15s 过短会导致已登录但全页「无法加载」(见 receiveTimeout 日志)。
const kHubDataReceiveTimeout = Duration(seconds: 90);

final dioProvider = Provider<Dio>((ref) {
  final hubUrl = ref.watch(hubUrlProvider);
  final dio = Dio(BaseOptions(
    baseUrl: hubUrl,
    connectTimeout: kHubConnectTimeout,
    receiveTimeout: kHubFastReceiveTimeout,
    headers: {'Accept': 'application/json'},
  ));
  dio.interceptors.add(AuthInterceptor(ref: ref));
  // 仅 debug 打印请求/响应概要(不含 Authorization 头)
  if (kDebugMode) {
    dio.interceptors.add(LogInterceptor(
      requestHeader: false,
      responseHeader: false,
      request: false,
      responseBody: false,
    ));
  }
  ref.onDispose(dio.close);
  return dio;
});

