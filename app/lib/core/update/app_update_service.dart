import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/prefs_storage.dart';
import 'app_update_platform.dart';
import 'app_update_policy.dart';

const kUpdatePolicyUrl = 'https://zt.zneox.com/app-update.json';
const kAutomaticUpdateCheckInterval = Duration(hours: 12);

enum AppUpdateCheckTrigger { automatic, manual }

enum AppUpdateCheckStatus {
  disabled,
  unsupported,
  throttled,
  upToDate,
  updateAvailable,
  failed,
}

enum AppUpdateFailureKind { configuration, network, invalidPolicy }

typedef AppUpdatePolicyFetcher = Future<Map<String, dynamic>> Function(Uri uri);
typedef AppUpdateClock = DateTime Function();
typedef AppUpdateChecker =
    Future<AppUpdateCheckResult> Function({
      required AppUpdateCheckTrigger trigger,
    });

final class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.status,
    this.urgency = AppUpdateUrgency.none,
    this.platformPolicy,
    this.failureKind,
    this.error,
  });

  final AppUpdateCheckStatus status;
  final AppUpdateUrgency urgency;
  final PlatformUpdatePolicy? platformPolicy;
  final AppUpdateFailureKind? failureKind;
  final Object? error;

  bool get shouldPrompt =>
      status == AppUpdateCheckStatus.updateAvailable &&
      urgency != AppUpdateUrgency.none;
}

final class AppUpdateService {
  AppUpdateService({
    required SharedPreferences preferences,
    required AppUpdatePlatformInfo platform,
    required Uri? policyUri,
    required AppUpdatePolicyFetcher fetchPolicy,
    AppUpdateClock? now,
  }) : _preferences = preferences,
       _platform = platform,
       _policyUri = policyUri,
       _fetchPolicy = fetchPolicy,
       _now = now ?? DateTime.now;

  final SharedPreferences _preferences;
  final AppUpdatePlatformInfo _platform;
  final Uri? _policyUri;
  final AppUpdatePolicyFetcher _fetchPolicy;
  final AppUpdateClock _now;

  Future<AppUpdateCheckResult> check({
    required AppUpdateCheckTrigger trigger,
  }) async {
    if (!_platform.supported) {
      return const AppUpdateCheckResult(
        status: AppUpdateCheckStatus.unsupported,
      );
    }

    final policyUri = _policyUri;
    if (policyUri == null) {
      return const AppUpdateCheckResult(status: AppUpdateCheckStatus.disabled);
    }
    if (policyUri.scheme != 'https' || policyUri.host.isEmpty) {
      return const AppUpdateCheckResult(
        status: AppUpdateCheckStatus.failed,
        failureKind: AppUpdateFailureKind.configuration,
      );
    }

    if (trigger == AppUpdateCheckTrigger.automatic &&
        _insideAutomaticCheckInterval()) {
      return const AppUpdateCheckResult(status: AppUpdateCheckStatus.throttled);
    }

    try {
      final json = await _fetchPolicy(policyUri);
      final policy = AppUpdatePolicy.fromJson(json, policyUri: policyUri);
      final platformPolicy = policy.policyFor(_platform.operatingSystem);
      if (platformPolicy == null) {
        return const AppUpdateCheckResult(
          status: AppUpdateCheckStatus.unsupported,
        );
      }

      await _preferences.setInt(
        PrefsKeys.appUpdateLastCheckAt,
        _now().millisecondsSinceEpoch,
      );

      if (!platformPolicy.enabled) {
        return AppUpdateCheckResult(
          status: AppUpdateCheckStatus.disabled,
          platformPolicy: platformPolicy,
        );
      }

      final urgency = platformPolicy.evaluateUpdate(
        currentBuild: _platform.currentBuild,
      );
      if (urgency == AppUpdateUrgency.none) {
        return AppUpdateCheckResult(
          status: AppUpdateCheckStatus.upToDate,
          platformPolicy: platformPolicy,
        );
      }
      return AppUpdateCheckResult(
        status: AppUpdateCheckStatus.updateAvailable,
        urgency: urgency,
        platformPolicy: platformPolicy,
      );
    } on FormatException catch (error) {
      return AppUpdateCheckResult(
        status: AppUpdateCheckStatus.failed,
        failureKind: AppUpdateFailureKind.invalidPolicy,
        error: error,
      );
    } catch (error) {
      return AppUpdateCheckResult(
        status: AppUpdateCheckStatus.failed,
        failureKind: AppUpdateFailureKind.network,
        error: error,
      );
    }
  }

  bool _insideAutomaticCheckInterval() {
    final lastMillis = _preferences.getInt(PrefsKeys.appUpdateLastCheckAt);
    if (lastMillis == null) return false;
    final elapsed = _now().difference(
      DateTime.fromMillisecondsSinceEpoch(lastMillis),
    );
    return !elapsed.isNegative && elapsed < kAutomaticUpdateCheckInterval;
  }
}

final updatePolicyDioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: const {'Accept': 'application/json'},
    ),
  );
  ref.onDispose(() => dio.close(force: true));
  return dio;
});

final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  final configured = kUpdatePolicyUrl.trim();
  final policyUri = configured.isEmpty ? null : Uri.tryParse(configured);
  final dio = ref.watch(updatePolicyDioProvider);
  return AppUpdateService(
    preferences: ref.watch(sharedPreferencesProvider),
    platform: currentAppUpdatePlatform(),
    policyUri: policyUri,
    fetchPolicy: (uri) async {
      final response = await dio.getUri<dynamic>(uri);
      final data = response.data;
      if (data is! Map) {
        throw const FormatException('更新策略响应必须是 JSON 对象');
      }
      return data.map((key, value) => MapEntry('$key', value));
    },
  );
});

final appUpdateCheckerProvider = Provider<AppUpdateChecker>((ref) {
  final service = ref.watch(appUpdateServiceProvider);
  return ({required trigger}) => service.check(trigger: trigger);
});
