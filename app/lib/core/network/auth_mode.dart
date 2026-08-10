import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_storage.dart';
import '../storage/prefs_storage.dart';

// ============================================================
// 鉴权模式判定 —— 对照 GOAL.md §6.1/§6.2。
// SaaS 云端模式:JWT 登录,数据接口 Authorization: Bearer <JWT>,
//   401 用 refreshToken 滚动续期重放(dio_client.dart 实现)。
// 自建 Hub 模式:填地址 + 共享密钥,所有请求 Bearer <secret>,
//   无登录/续期流程,协议与 SaaS 一致仅鉴权头不同。
// 未认证:仅 GET /api/health 可用(登录页健康检查)。
// ============================================================

enum AuthMode { saas, selfHosted, unauthenticated }

// 当前鉴权状态:模式 + 当前请求头所需的凭证值。
// dio 拦截器每次请求读这个:saas→accessToken,selfHosted→hubSecret。
@immutable
class AuthState {
  const AuthState({
    this.mode = AuthMode.unauthenticated,
    this.accessToken,
    this.refreshToken,
    this.hubSecret,
    this.userId,
    this.userEmail,
  });

  final AuthMode mode;
  final String? accessToken;
  final String? refreshToken;
  final String? hubSecret; // 自建 Hub 共享密钥
  final String? userId;
  final String? userEmail;

  // 请求头 Authorization 值:null 表示不带(健康检查/未认证)。
  String? get authorizationHeader {
    switch (mode) {
      case AuthMode.saas:
        return accessToken != null ? 'Bearer $accessToken' : null;
      case AuthMode.selfHosted:
        return hubSecret != null ? 'Bearer $hubSecret' : null;
      case AuthMode.unauthenticated:
        return null;
    }
  }

  bool get isAuthenticated => mode != AuthMode.unauthenticated;

  AuthState copyWith({
    AuthMode? mode,
    String? accessToken,
    String? refreshToken,
    String? hubSecret,
    String? userId,
    String? userEmail,
  }) {
    return AuthState(
      mode: mode ?? this.mode,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      hubSecret: hubSecret ?? this.hubSecret,
      userId: userId ?? this.userId,
      userEmail: userEmail ?? this.userEmail,
    );
  }
}

// 持有 AuthState 的 Notifier:启动时从 secure_storage 加载,
// 登录/续期/登出时同步更新。dio 拦截器读它的 state。
// hubUrl 不在此处:由独立 hubUrlProvider 从 settings 派生,供 dio 拼 baseUrl。
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._secure) : super(const AuthState());

  final SecureStorage _secure;

  // 启动加载:从 secure_storage 读凭证,结合 settings.hubUrl 判定模式。
  // 优先级:hubSecret 非空 → selfHosted;accessToken 非空 → saas;否则未认证。
  // 容错:secure_storage 任何异常(鸿蒙首次加密初始化失败/Keychain 权限)
  // 都回落未认证,不让 main 崩成白屏 —— 登录页本就是未认证的目的地。
  Future<void> load() async {
    try {
      final hubSecret = await _secure.readHubSecret();
      final accessToken = await _secure.readAccessToken();

      if (hubSecret != null && hubSecret.isNotEmpty) {
        state = AuthState(mode: AuthMode.selfHosted, hubSecret: hubSecret);
      } else if (accessToken != null && accessToken.isNotEmpty) {
        final refreshToken = await _secure.readRefreshToken();
        final userId = await _secure.readUserId();
        final userEmail = await _secure.readUserEmail();
        state = AuthState(
          mode: AuthMode.saas,
          accessToken: accessToken,
          refreshToken: refreshToken,
          userId: userId,
          userEmail: userEmail,
        );
      } else {
        state = const AuthState();
      }
    } catch (_) {
      // 读凭证失败:视为未认证,正常进登录页
      state = const AuthState();
    }
  }

  // SaaS 登录成功后调用:写入凭证 + 切 saas 模式。
  // 容错:secure_storage 写入(鸿蒙首次加密初始化)失败不阻塞登录 ——
  // 内存 state 仍切 saas,本次会话可用;代价是杀进程后需重登(load 读不到 token)。
  Future<void> onSaasLogin({
    required String accessToken,
    required String refreshToken,
    required String userId,
    required String userEmail,
  }) async {
    try {
      await _secure.writeSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        userId: userId,
        userEmail: userEmail,
      );
    } catch (e) {
      // 写盘失败:仅日志,不阻塞登录流程
      debugPrint('[auth] writeSession 失败(不阻塞登录): $e');
    }
    state = AuthState(
      mode: AuthMode.saas,
      accessToken: accessToken,
      refreshToken: refreshToken,
      userId: userId,
      userEmail: userEmail,
    );
  }

  // 滚动续期成功后调用:整体替换 token 对(旧 refreshToken 作废)。
  Future<void> onTokenRefreshed({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _secure.replaceTokens(accessToken: accessToken, refreshToken: refreshToken);
    state = state.copyWith(accessToken: accessToken, refreshToken: refreshToken);
  }

  // 切到自建 Hub 模式:存 hubSecret + 切模式。
  Future<void> onSelfHostedConfigured(String hubSecret) async {
    await _secure.writeHubSecret(hubSecret);
    state = AuthState(mode: AuthMode.selfHosted, hubSecret: hubSecret);
  }

  // 登出/续期失败:清全部凭证,回未认证。
  Future<void> clearSession() async {
    await _secure.clearAll();
    state = const AuthState();
  }

  // 自建 Hub 模式下改了 hubSecret(设置页)。
  Future<void> refreshHubSecret() async {
    final hubSecret = await _secure.readHubSecret();
    if (hubSecret != null && hubSecret.isNotEmpty) {
      state = AuthState(mode: AuthMode.selfHosted, hubSecret: hubSecret);
    }
  }
}

// hubUrl provider:从 settings 派生(供 dio 拼 baseUrl)。
final hubUrlProvider = Provider<String>((ref) {
  return ref.watch(settingsProvider).hubUrl;
});

// AuthNotifier provider:依赖 secure_storage。
// 启动时未自动 load(避免拦截器首帧依赖异步);由 app 启动流程触发 load()。
final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final secure = ref.watch(secureStorageProvider);
  return AuthNotifier(secure);
});
