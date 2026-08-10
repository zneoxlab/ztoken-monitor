import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'prefs_storage.dart' show sharedPreferencesProvider;

// ============================================================
// 安全存储 —— JWT / refreshToken / 自建 Hub 共享密钥。
// 主后端:flutter_secure_storage(iOS Keychain / Android Keystore /
//   鸿蒙 ohos 适配包)。均为 federated plugin,const 实例即可。
// 降级后端:SharedPreferences(明文)。仅当 secure 写/读失败时启用 ——
//   鸿蒙首次加密初始化(RSA 密钥生成)偶发抛 PlatformException,会导致 token
//   写不进、下次启动 load 不到而要求重登。降级到 prefs 保住"登录态保持",
//   代价是明文(同 OS 用户进程可读,与桌面端 credentials.json 同等级)。
//   凭证绝不上云、不随账户同步(GOAL.md §6.1 滚动续期本地替换)。
// ============================================================

// 存储键:固定常量,迁移时视为兼容性表面。
class SecureKeys {
  const SecureKeys._();
  static const accessToken = 'auth.access_token';
  static const refreshToken = 'auth.refresh_token';
  static const hubSecret = 'hub.secret'; // 自建 Hub 共享密钥
  static const userId = 'auth.user_id';
  static const userEmail = 'auth.user_email';
}

// prefs 降级键(加前缀避免与 settings 键冲突)。
class _PrefsKeys {
  const _PrefsKeys._();
  static const accessToken = 'fallback.auth.access_token';
  static const refreshToken = 'fallback.auth.refresh_token';
  static const hubSecret = 'fallback.hub.secret';
  static const userId = 'fallback.auth.user_id';
  static const userEmail = 'fallback.auth.user_email';
}

// 单例封装:对外暴露读写/删除,屏蔽 FlutterSecureStorage 的 options 细节。
class SecureStorage {
  SecureStorage({FlutterSecureStorage? storage, SharedPreferences? prefs})
      : _storage = storage ?? const FlutterSecureStorage(),
        _prefs = prefs;

  final FlutterSecureStorage _storage;
  final SharedPreferences? _prefs; // 降级后端,可能为 null(测试可不注入)

  // 统一写:先试 secure;失败降级 prefs(若有)。
  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      // secure 写成功:清掉可能的 prefs 降级副本,避免后续读到旧值
      await _prefs?.remove(_prefsKey(key));
    } catch (e) {
      debugPrint('[secure] write $key 失败,降级到 prefs: $e');
      await _prefs?.setString(_prefsKey(key), value);
    }
  }

  // 统一读:先试 secure;空或异常则读 prefs 降级副本。
  Future<String?> _read(String key) async {
    try {
      final v = await _storage.read(key: key);
      if (v != null && v.isNotEmpty) return v;
    } catch (e) {
      debugPrint('[secure] read $key 失败,尝试 prefs 降级: $e');
    }
    return _prefs?.getString(_prefsKey(key));
  }

  // secure key → prefs key 映射。
  String _prefsKey(String secureKey) {
    switch (secureKey) {
      case SecureKeys.accessToken:
        return _PrefsKeys.accessToken;
      case SecureKeys.refreshToken:
        return _PrefsKeys.refreshToken;
      case SecureKeys.hubSecret:
        return _PrefsKeys.hubSecret;
      case SecureKeys.userId:
        return _PrefsKeys.userId;
      case SecureKeys.userEmail:
        return _PrefsKeys.userEmail;
      default:
        return 'fallback.$secureKey';
    }
  }

  // ---- access token ----
  Future<String?> readAccessToken() => _read(SecureKeys.accessToken);
  Future<void> writeAccessToken(String token) => _write(SecureKeys.accessToken, token);

  // ---- refresh token(滚动续期:旧值作废,整体替换) ----
  Future<String?> readRefreshToken() => _read(SecureKeys.refreshToken);
  Future<void> writeRefreshToken(String token) => _write(SecureKeys.refreshToken, token);

  // ---- 自建 Hub 共享密钥(自建模式鉴权头,无登录/续期) ----
  Future<String?> readHubSecret() => _read(SecureKeys.hubSecret);
  Future<void> writeHubSecret(String secret) => _write(SecureKeys.hubSecret, secret);

  // ---- 用户信息(login 返回 {id, email}) ----
  Future<String?> readUserId() => _read(SecureKeys.userId);
  Future<String?> readUserEmail() => _read(SecureKeys.userEmail);
  Future<void> writeUser({required String id, required String email}) async {
    await _write(SecureKeys.userId, id);
    await _write(SecureKeys.userEmail, email);
  }

  // 登录成功后一次性写入全部凭证。
  Future<void> writeSession({
    required String accessToken,
    required String refreshToken,
    required String userId,
    required String userEmail,
  }) async {
    await writeAccessToken(accessToken);
    await writeRefreshToken(refreshToken);
    await writeUser(id: userId, email: userEmail);
  }

  // 续期成功后替换 token 对(滚动续期:整体替换,旧 refreshToken 作废)。
  Future<void> replaceTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await writeAccessToken(accessToken);
    await writeRefreshToken(refreshToken);
  }

  // 登出/续期失败:清全部凭证(secure + prefs 降级副本),回登录页。
  Future<void> clearAll() async {
    try {
      await _storage.deleteAll();
    } catch (e) {
      debugPrint('[secure] deleteAll 失败(忽略): $e');
    }
    // 清 prefs 降级副本
    await _prefs?.remove(_PrefsKeys.accessToken);
    await _prefs?.remove(_PrefsKeys.refreshToken);
    await _prefs?.remove(_PrefsKeys.hubSecret);
    await _prefs?.remove(_PrefsKeys.userId);
    await _prefs?.remove(_PrefsKeys.userEmail);
  }

  // 是否已登录:access + refresh 同时存在视为已认证。
  // 自建 Hub 模式不登录,该检查不适用(任务4 拦截器区分两种模式)。
  Future<bool> get isAuthenticated async {
    final access = await readAccessToken();
    final refresh = await readRefreshToken();
    return access != null && access.isNotEmpty &&
        refresh != null && refresh.isNotEmpty;
  }
}

// Riverpod provider:全局单例。注入 SharedPreferences 供降级。测试时可 override。
final secureStorageProvider = Provider<SecureStorage>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SecureStorage(prefs: prefs);
});
