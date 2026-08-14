import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app_version.dart';
import '../network/auth_mode.dart';
import '../storage/prefs_storage.dart';
import '../storage/secure_storage.dart';
import 'notification_rules_repository.dart';

class PushLifecycle with WidgetsBindingObserver {
  PushLifecycle({required Ref ref, MethodChannel? channel})
    : _ref = ref,
      _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.zneox.ztoken_monitor/notifications';

  final Ref _ref;
  final MethodChannel _channel;
  final Set<String> _handledEventIds = <String>{};
  GoRouter? _router;
  bool _started = false;

  Future<void> start(GoRouter router) async {
    _router = router;
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _ref.onDispose(() => WidgetsBinding.instance.removeObserver(this));
    _channel.setMethodCallHandler(_onNativeCall);
    await _restoreHandledEvents();
    await _handlePushEvent(await _safeInvoke<dynamic>('getInitialPushEvent'));
    await reconcile();
  }

  Future<bool> requestPermissionAndSync() async {
    // 仅由配额页成功保存“启用”规则后调用，绝不在登录/启动时弹权限框。
    final granted = await _safeInvoke<bool>('requestPermission');
    if (granted == true) {
      await sync();
    } else {
      await _revokeExistingInstallation();
    }
    return granted == true;
  }

  Future<void> sync() async {
    if (_ref.read(authProvider).mode != AuthMode.saas) return;
    if (!_hasEnabledRules()) return;
    final permission = await _safeInvoke<bool>(
      'getNotificationPermissionStatus',
    );
    if (permission != true) {
      await _revokeExistingInstallation();
      return;
    }
    final tokenInfo = _tokenInfo(
      await _safeInvoke<dynamic>('getRemotePushToken'),
    );
    if (tokenInfo == null || tokenInfo.platform == 'unsupported') return;
    final installationId = await _installationId();
    try {
      await _ref
          .read(notificationRulesRepositoryProvider)
          .registerInstallation(
            installationId: installationId,
            platform: tokenInfo.platform,
            provider: tokenInfo.provider,
            environment: tokenInfo.environment,
            appVersion: kAppVersion,
            token: tokenInfo.token,
          );
    } catch (_) {
      // 推送不可用不影响统计或规则保存；下次启动、令牌刷新仍会重试注册。
    }
  }

  /// 规则加载/保存后统一收敛安装状态：至少一条规则启用才允许读取并上传
  /// 远程令牌；全部关闭时主动撤销服务端安装，但不删除本机稳定安装 id。
  Future<void> reconcile() async {
    if (_ref.read(authProvider).mode != AuthMode.saas) return;
    final rules = _ref.read(notificationRulesProvider).valueOrNull;
    if (rules == null) return;
    if (rules.rules.rules.any((rule) => rule.enabled)) {
      await sync();
    } else {
      await revokeBeforeLogout();
    }
  }

  bool _hasEnabledRules() {
    final data = _ref.read(notificationRulesProvider).valueOrNull;
    return data != null && data.rules.rules.any((rule) => rule.enabled);
  }

  /// 登出前调用。此时 JWT 仍在，Hub 能撤销当前用户的安装绑定。
  Future<void> revokeBeforeLogout() async {
    if (_ref.read(authProvider).mode != AuthMode.saas) return;
    await _revokeExistingInstallation();
  }

  Future<void> _revokeExistingInstallation() async {
    final installationId = await _ref
        .read(secureStorageProvider)
        .readPushInstallationId();
    if (installationId == null || installationId.isEmpty) return;
    try {
      await _ref
          .read(notificationRulesRepositoryProvider)
          .revokeInstallation(installationId);
    } catch (_) {
      // 最佳努力：失败时服务端仍会在令牌下一次注册时原子转绑。
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 从系统通知设置返回时重新核对权限并注册/撤销；不主动弹权限框。
      unawaited(reconcile());
    }
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'pushTokenRefreshed':
        // 原生层可能在旧系统回调缓存令牌；没有显式启用规则时不上传。
        await sync();
        return null;
      case 'pushNotificationOpened':
        await _handlePushEvent(call.arguments);
        return null;
    }
  }

  Future<void> _handlePushEvent(dynamic raw) async {
    final event = _asMap(raw);
    if (event.isEmpty) return;
    final eventId = _string(event['eventId'] ?? event['event_id']);
    if (eventId.isNotEmpty) {
      if (_handledEventIds.contains(eventId)) return;
      _handledEventIds.add(eventId);
      await _persistHandledEvents();
    }
    // 只接受本产品的固定目标，不能让通知负载驱动任意路由跳转。
    _router?.go('/limits');
  }

  Future<String> _installationId() async {
    final storage = _ref.read(secureStorageProvider);
    final existing = await storage.readPushInstallationId();
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _uuidV4();
    await storage.writePushInstallationId(id);
    return id;
  }

  Future<void> _restoreHandledEvents() async {
    final raw = _ref
        .read(sharedPreferencesProvider)
        .getString(PrefsKeys.handledPushEventIds);
    if (raw == null || raw.isEmpty) return;
    _handledEventIds.addAll(
      raw.split(',').where((id) => id.isNotEmpty).take(_maxHandledEvents),
    );
  }

  Future<void> _persistHandledEvents() async {
    final values = _handledEventIds.toList(growable: false);
    final recent = values.length <= _maxHandledEvents
        ? values
        : values.sublist(values.length - _maxHandledEvents);
    _handledEventIds
      ..clear()
      ..addAll(recent);
    await _ref
        .read(sharedPreferencesProvider)
        .setString(PrefsKeys.handledPushEventIds, recent.join(','));
  }

  Future<T?> _safeInvoke<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

const _maxHandledEvents = 32;

class _PushTokenInfo {
  const _PushTokenInfo({
    required this.token,
    required this.platform,
    required this.provider,
    required this.environment,
  });

  final String token;
  final String platform;
  final String provider;
  final String environment;
}

_PushTokenInfo? _tokenInfo(dynamic raw) {
  if (raw is String && raw.trim().isNotEmpty) {
    return _PushTokenInfo(
      token: raw.trim(),
      platform: _defaultPlatform(),
      provider: _defaultProvider(),
      environment: 'production',
    );
  }
  final json = _asMap(raw);
  final token = _string(json['token']);
  if (token.isEmpty) return null;
  return _PushTokenInfo(
    token: token,
    platform: _string(json['platform']).isEmpty
        ? _defaultPlatform()
        : _string(json['platform']),
    provider: _string(json['provider']).isEmpty
        ? _defaultProvider()
        : _string(json['provider']),
    environment: _string(json['environment']).isEmpty
        ? 'production'
        : _string(json['environment']),
  );
}

String _defaultPlatform() => switch (defaultTargetPlatform) {
  TargetPlatform.iOS => 'ios',
  TargetPlatform.android => 'android',
  _ => 'unsupported',
};

String _defaultProvider() =>
    defaultTargetPlatform == TargetPlatform.iOS ? 'apns' : 'fcm';

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return const {};
}

String _string(dynamic value) =>
    value is String ? value : value?.toString() ?? '';

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int value) => value.toRadixString(16).padLeft(2, '0');
  final values = bytes.map(hex).join();
  return '${values.substring(0, 8)}-${values.substring(8, 12)}-'
      '${values.substring(12, 16)}-${values.substring(16, 20)}-'
      '${values.substring(20)}';
}

final pushLifecycleProvider = Provider<PushLifecycle>(
  (ref) => PushLifecycle(ref: ref),
);

final pushLifecycleAuthProvider = Provider<void>((ref) {
  ref.listen<AuthMode>(authProvider.select((auth) => auth.mode), (
    previous,
    next,
  ) {
    if (next == AuthMode.saas) {
      unawaited(ref.read(pushLifecycleProvider).reconcile());
    }
  });
  ref.listen<String?>(
    notificationRulesProvider.select(
      (state) => state.valueOrNull?.rules.updatedAt,
    ),
    (previous, next) {
      if (ref.read(authProvider).mode == AuthMode.saas) {
        unawaited(ref.read(pushLifecycleProvider).reconcile());
      }
    },
  );
});
