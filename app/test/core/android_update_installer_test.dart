import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ztoken_monitor/core/update/android_update_installer.dart';
import 'package:ztoken_monitor/core/update/app_update_action.dart';
import 'package:ztoken_monitor/core/update/app_update_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/app_update');
  final calls = <MethodCall>[];

  PlatformUpdatePolicy policy({
    AppUpdateDelivery delivery = AppUpdateDelivery.direct,
    String sha256 =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  }) => PlatformUpdatePolicy(
    enabled: true,
    latestVersion: '1.0.1',
    latestBuild: 2003,
    minimumBuild: 2002,
    delivery: delivery,
    updateUri: Uri.parse('https://zt.example.com/downloads/app.apk'),
    sha256: sha256,
    releaseNotes: '测试更新',
  );

  setUp(() {
    calls.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('官网渠道下载到原生缓存目录后请求校验并安装', () async {
    String? downloadedUrl;
    String? downloadedPath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'getDistribution' => 'website',
            'getCacheDirectory' => '/trusted/cache',
            'verifyAndInstallApk' => 'installerOpened',
            _ => throw MissingPluginException(),
          };
        });
    final installer = AndroidUpdateInstaller(
      channel: channel,
      downloader: (source, destination) async {
        downloadedUrl = source.toString();
        downloadedPath = destination;
      },
    );

    final result = await installer.perform(policy());

    expect(result.status, AppUpdateActionStatus.launched);
    expect(downloadedUrl, 'https://zt.example.com/downloads/app.apk');
    expect(downloadedPath, '/trusted/cache/zt-monitor-update.apk');
    final installCall = calls.singleWhere(
      (call) => call.method == 'verifyAndInstallApk',
    );
    expect(installCall.arguments, containsPair('sha256', policy().sha256));
    expect(
      installCall.arguments,
      containsPair('path', '/trusted/cache/zt-monitor-update.apk'),
    );
  });

  test('商店渠道不触发 APK 下载和安装', () async {
    var downloaded = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getDistribution') return 'store';
          throw MissingPluginException();
        });
    final installer = AndroidUpdateInstaller(
      channel: channel,
      downloader: (_, _) async => downloaded = true,
    );

    final result = await installer.perform(policy());

    expect(result.status, AppUpdateActionStatus.unavailable);
    expect(downloaded, isFalse);
    expect(calls.map((call) => call.method), ['getDistribution']);
  });

  test('渠道预检只允许官网版处理直装策略', () async {
    var distribution = 'website';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getDistribution') return distribution;
          throw MissingPluginException();
        });
    final installer = AndroidUpdateInstaller(
      channel: channel,
      downloader: (_, _) async {},
    );

    expect(await installer.supports(policy()), isTrue);
    distribution = 'store';
    expect(await installer.supports(policy()), isFalse);
  });

  test('缺少 SHA-256 时拒绝直装', () async {
    final installer = AndroidUpdateInstaller(
      channel: channel,
      downloader: (_, _) async {},
    );

    final result = await installer.perform(policy(sha256: ''));

    expect(result.status, AppUpdateActionStatus.unavailable);
    expect(result.message, contains('SHA-256'));
  });

  test('原生层要求授权安装未知应用时返回可恢复状态', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            'getDistribution' => 'website',
            'getCacheDirectory' => '/trusted/cache',
            'verifyAndInstallApk' => 'permissionRequired',
            _ => throw MissingPluginException(),
          };
        });
    final installer = AndroidUpdateInstaller(
      channel: channel,
      downloader: (_, _) async {},
    );

    final result = await installer.perform(policy());

    expect(result.status, AppUpdateActionStatus.permissionRequired);
  });

  test('原生层校验失败不打开安装器', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            'getDistribution' => 'website',
            'getCacheDirectory' => '/trusted/cache',
            'verifyAndInstallApk' => throw PlatformException(
              code: 'sha_mismatch',
            ),
            _ => throw MissingPluginException(),
          };
        });
    final installer = AndroidUpdateInstaller(
      channel: channel,
      downloader: (_, _) async {},
    );

    final result = await installer.perform(policy());

    expect(result.status, AppUpdateActionStatus.failed);
    expect(result.message, contains('校验失败'));
  });
}
