import 'package:flutter_test/flutter_test.dart';
import 'package:ztoken_monitor/core/update/app_update_policy.dart';

void main() {
  final policyUri = Uri.parse('https://zt.example.com/app-update.json');

  Map<String, dynamic> platform({
    bool enabled = true,
    int latestBuild = 2002,
    int minimumBuild = 2000,
    String delivery = 'direct',
    String updateUrl = 'downloads/ZT-Monitor-Android.apk',
    String sha256 = '',
  }) => {
    'enabled': enabled,
    'latestVersion': '1.0.0',
    'latestBuild': latestBuild,
    'minimumBuild': minimumBuild,
    'delivery': delivery,
    'updateUrl': updateUrl,
    'sha256': sha256,
    'releaseNotes': '正式版发布',
  };

  Map<String, dynamic> manifest({Map<String, dynamic>? android}) => {
    'schemaVersion': 1,
    'ios': platform(enabled: false, delivery: 'store', updateUrl: ''),
    'android': android ?? platform(),
    'ohos': platform(enabled: false, delivery: 'store', updateUrl: ''),
  };

  group('AppUpdatePolicy 解析', () {
    test('解析平台策略并基于策略地址解析相对 APK 路径', () {
      final policy = AppUpdatePolicy.fromJson(manifest(), policyUri: policyUri);

      final android = policy.policyFor('android');
      expect(android, isNotNull);
      expect(android!.enabled, isTrue);
      expect(android.delivery, AppUpdateDelivery.direct);
      expect(
        android.updateUri.toString(),
        'https://zt.example.com/downloads/ZT-Monitor-Android.apk',
      );
      expect(policy.policyFor('windows'), isNull);
    });

    test('禁用平台允许空更新地址', () {
      final policy = AppUpdatePolicy.fromJson(manifest(), policyUri: policyUri);

      expect(policy.policyFor('ios')!.enabled, isFalse);
      expect(policy.policyFor('ios')!.updateUri, isNull);
    });

    test('拒绝未知 schemaVersion', () {
      expect(
        () => AppUpdatePolicy.fromJson({
          ...manifest(),
          'schemaVersion': 2,
        }, policyUri: policyUri),
        throwsFormatException,
      );
    });

    test('拒绝缺失字段、负构建号和 minimumBuild 大于 latestBuild', () {
      final missing = platform()..remove('latestVersion');
      expect(
        () => AppUpdatePolicy.fromJson(
          manifest(android: missing),
          policyUri: policyUri,
        ),
        throwsFormatException,
      );
      expect(
        () => AppUpdatePolicy.fromJson(
          manifest(android: platform(latestBuild: -1)),
          policyUri: policyUri,
        ),
        throwsFormatException,
      );
      expect(
        () => AppUpdatePolicy.fromJson(
          manifest(android: platform(latestBuild: 2, minimumBuild: 3)),
          policyUri: policyUri,
        ),
        throwsFormatException,
      );
    });

    test('拒绝未知交付方式和非 HTTPS 地址', () {
      expect(
        () => AppUpdatePolicy.fromJson(
          manifest(android: platform(delivery: 'sideways')),
          policyUri: policyUri,
        ),
        throwsFormatException,
      );
      expect(
        () => AppUpdatePolicy.fromJson(
          manifest(
            android: platform(updateUrl: 'http://zt.example.com/app.apk'),
          ),
          policyUri: policyUri,
        ),
        throwsFormatException,
      );
    });

    test('官网直装包必须与策略文件同源', () {
      expect(
        () => AppUpdatePolicy.fromJson(
          manifest(
            android: platform(
              updateUrl: 'https://download.example.com/app.apk',
            ),
          ),
          policyUri: policyUri,
        ),
        throwsFormatException,
      );

      expect(
        () => AppUpdatePolicy.fromJson(
          manifest(
            android: platform(
              delivery: 'store',
              updateUrl: 'https://store.example.com/app',
            ),
          ),
          policyUri: policyUri,
        ),
        returnsNormally,
      );
    });
  });

  group('版本判定', () {
    test('当前构建不低于最新构建时无需更新', () {
      final policy = AppUpdatePolicy.fromJson(manifest(), policyUri: policyUri);
      expect(
        policy.policyFor('android')!.evaluateUpdate(currentBuild: 2002),
        AppUpdateUrgency.none,
      );
      expect(
        policy.policyFor('android')!.evaluateUpdate(currentBuild: 2003),
        AppUpdateUrgency.none,
      );
    });

    test('低于最低构建时强制更新', () {
      final policy = AppUpdatePolicy.fromJson(manifest(), policyUri: policyUri);
      expect(
        policy.policyFor('android')!.evaluateUpdate(currentBuild: 1999),
        AppUpdateUrgency.required,
      );
    });

    test('有新版本但仍受支持时普通更新', () {
      final policy = AppUpdatePolicy.fromJson(manifest(), policyUri: policyUri);
      expect(
        policy.policyFor('android')!.evaluateUpdate(currentBuild: 2001),
        AppUpdateUrgency.optional,
      );
    });

    test('禁用平台不触发更新', () {
      final policy = AppUpdatePolicy.fromJson(manifest(), policyUri: policyUri);
      expect(
        policy.policyFor('ios')!.evaluateUpdate(currentBuild: 1),
        AppUpdateUrgency.none,
      );
    });
  });
}
