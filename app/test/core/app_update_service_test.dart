import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ztoken_monitor/core/update/app_update_platform.dart';
import 'package:ztoken_monitor/core/update/app_update_policy.dart';
import 'package:ztoken_monitor/core/update/app_update_service.dart';

void main() {
  test('正式更新策略地址直接内置在 App 中', () {
    expect(kUpdatePolicyUrl, 'https://zt.zneox.com/app-update.json');
  });

  final now = DateTime.utc(2026, 8, 9, 12);
  final policyUri = Uri.parse('https://zt.example.com/app-update.json');

  Map<String, dynamic> platform({
    bool enabled = true,
    int latestBuild = 2003,
    int minimumBuild = 2000,
    String delivery = 'direct',
    String updateUrl = 'downloads/ZT-Monitor-Android.apk',
  }) => {
    'enabled': enabled,
    'latestVersion': '1.0.1',
    'latestBuild': latestBuild,
    'minimumBuild': minimumBuild,
    'delivery': delivery,
    'updateUrl': updateUrl,
    'sha256': '',
    'releaseNotes': '修复问题',
  };

  Map<String, dynamic> manifest({
    Map<String, dynamic>? android,
    Map<String, dynamic>? ohos,
  }) => {
    'schemaVersion': 1,
    'ios': platform(enabled: false, delivery: 'store', updateUrl: ''),
    'android': android ?? platform(),
    'ohos':
        ohos ??
        platform(
          latestBuild: 1000001,
          minimumBuild: 1000000,
          delivery: 'store',
          updateUrl: 'https://appgallery.example.com/app',
        ),
  };

  Future<SharedPreferences> prefs([
    Map<String, Object> values = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  AppUpdatePlatformInfo android() => const AppUpdatePlatformInfo(
    operatingSystem: 'android',
    currentBuild: 2002,
    supported: true,
  );

  test('从固定 URL 拉取策略且返回普通更新', () async {
    final seen = <Uri>[];
    final service = AppUpdateService(
      preferences: await prefs(),
      platform: android(),
      policyUri: policyUri,
      now: () => now,
      fetchPolicy: (uri) async {
        seen.add(uri);
        return manifest();
      },
    );

    final result = await service.check(
      trigger: AppUpdateCheckTrigger.automatic,
    );

    expect(seen, [policyUri]);
    expect(result.status, AppUpdateCheckStatus.updateAvailable);
    expect(result.urgency, AppUpdateUrgency.optional);
    expect(result.platformPolicy?.latestBuild, 2003);
  });

  test('未配置策略 URL 时禁用且不发请求', () async {
    var calls = 0;
    final service = AppUpdateService(
      preferences: await prefs(),
      platform: android(),
      policyUri: null,
      now: () => now,
      fetchPolicy: (_) async {
        calls++;
        return manifest();
      },
    );

    final result = await service.check(trigger: AppUpdateCheckTrigger.manual);

    expect(result.status, AppUpdateCheckStatus.disabled);
    expect(calls, 0);
  });

  test('成功检查后 12 小时内自动检查被节流', () async {
    final storage = await prefs();
    var calls = 0;
    final service = AppUpdateService(
      preferences: storage,
      platform: android(),
      policyUri: policyUri,
      now: () => now,
      fetchPolicy: (_) async {
        calls++;
        return manifest();
      },
    );

    expect(
      (await service.check(trigger: AppUpdateCheckTrigger.automatic)).status,
      AppUpdateCheckStatus.updateAvailable,
    );
    expect(
      (await service.check(trigger: AppUpdateCheckTrigger.automatic)).status,
      AppUpdateCheckStatus.throttled,
    );
    expect(calls, 1);
  });

  test('手动检查绕过 12 小时节流', () async {
    final storage = await prefs({
      'app_update.last_check_at': now.millisecondsSinceEpoch,
    });
    var calls = 0;
    final service = AppUpdateService(
      preferences: storage,
      platform: android(),
      policyUri: policyUri,
      now: () => now,
      fetchPolicy: (_) async {
        calls++;
        return manifest();
      },
    );

    final result = await service.check(trigger: AppUpdateCheckTrigger.manual);

    expect(result.status, AppUpdateCheckStatus.updateAvailable);
    expect(calls, 1);
  });

  test('网络错误和无效策略转换为非致命失败结果', () async {
    final network = AppUpdateService(
      preferences: await prefs(),
      platform: android(),
      policyUri: policyUri,
      now: () => now,
      fetchPolicy: (_) async => throw Exception('timeout'),
    );
    expect(
      (await network.check(trigger: AppUpdateCheckTrigger.manual)).failureKind,
      AppUpdateFailureKind.network,
    );

    final invalid = AppUpdateService(
      preferences: await prefs(),
      platform: android(),
      policyUri: policyUri,
      now: () => now,
      fetchPolicy: (_) async => {...manifest(), 'schemaVersion': 99},
    );
    expect(
      (await invalid.check(trigger: AppUpdateCheckTrigger.manual)).failureKind,
      AppUpdateFailureKind.invalidPolicy,
    );
  });

  test('HarmonyOS 使用独立构建号序列', () async {
    final service = AppUpdateService(
      preferences: await prefs(),
      platform: const AppUpdatePlatformInfo(
        operatingSystem: 'ohos',
        currentBuild: 1000000,
        supported: true,
      ),
      policyUri: policyUri,
      now: () => now,
      fetchPolicy: (_) async => manifest(),
    );

    final result = await service.check(trigger: AppUpdateCheckTrigger.manual);
    expect(result.status, AppUpdateCheckStatus.updateAvailable);
    expect(result.platformPolicy?.latestBuild, 1000001);
  });

  test('Web 等不支持平台不发请求', () async {
    var calls = 0;
    final service = AppUpdateService(
      preferences: await prefs(),
      platform: const AppUpdatePlatformInfo(
        operatingSystem: 'web',
        currentBuild: 0,
        supported: false,
      ),
      policyUri: policyUri,
      now: () => now,
      fetchPolicy: (_) async {
        calls++;
        return manifest();
      },
    );

    final result = await service.check(trigger: AppUpdateCheckTrigger.manual);
    expect(result.status, AppUpdateCheckStatus.unsupported);
    expect(calls, 0);
  });
}
