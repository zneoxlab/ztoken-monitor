import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ztoken_monitor/core/network/sse_client.dart';
import 'package:ztoken_monitor/core/storage/prefs_storage.dart';
import 'package:ztoken_monitor/core/update/app_update_dialog.dart';
import 'package:ztoken_monitor/core/update/app_update_lifecycle.dart';
import 'package:ztoken_monitor/core/update/app_update_policy.dart';
import 'package:ztoken_monitor/core/update/app_update_service.dart';
import 'package:ztoken_monitor/features/me/me_page.dart';
import 'package:ztoken_monitor/theme/app_theme.dart';
import 'package:ztoken_monitor/theme/app_colors.dart';

void main() {
  PlatformUpdatePolicy policy() => PlatformUpdatePolicy(
    enabled: true,
    latestVersion: '1.0.1',
    latestBuild: 2003,
    minimumBuild: 2000,
    delivery: AppUpdateDelivery.direct,
    updateUri: Uri.parse('https://zt.example.com/app.apk'),
    sha256: '',
    releaseNotes: '修复问题',
  );

  AppUpdateCheckResult available(AppUpdateUrgency urgency) =>
      AppUpdateCheckResult(
        status: AppUpdateCheckStatus.updateAvailable,
        urgency: urgency,
        platformPolicy: policy(),
      );

  Widget harness({required AppUpdateChecker checker, required Widget child}) =>
      ProviderScope(
        overrides: [
          appUpdateCheckerProvider.overrideWithValue(checker),
          appUpdateActionProvider.overrideWithValue(
            (_) async => const AppUpdateActionResult(
              status: AppUpdateActionStatus.launched,
            ),
          ),
          appUpdateAvailabilityProvider.overrideWithValue((_) async => true),
        ],
        child: MaterialApp(
          theme: buildThemeData(graphiteMint),
          home: Scaffold(body: child),
        ),
      );

  testWidgets('“我的 → 关于”包含检查更新入口', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          appUpdateCheckerProvider.overrideWithValue(
            ({required trigger}) async => const AppUpdateCheckResult(
              status: AppUpdateCheckStatus.upToDate,
            ),
          ),
          sseConnectionStateProvider.overrideWith(
            (ref) => Stream.value(SseConnectionState.disconnected),
          ),
        ],
        child: MaterialApp(
          theme: buildThemeData(graphiteMint),
          home: const MePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('检查更新'), findsOneWidget);
  });

  testWidgets('手动检查已是最新版本时显示提示', (tester) async {
    await tester.pumpWidget(
      harness(
        checker: ({required trigger}) async =>
            const AppUpdateCheckResult(status: AppUpdateCheckStatus.upToDate),
        child: const AppUpdateCheckRow(),
      ),
    );

    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();

    expect(find.text('已是最新版本'), findsOneWidget);
  });

  testWidgets('普通更新显示稍后和立即更新', (tester) async {
    await tester.pumpWidget(
      harness(
        checker: ({required trigger}) async =>
            available(AppUpdateUrgency.optional),
        child: const AppUpdateLifecycle(child: Text('body')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('发现新版本 v1.0.1'), findsOneWidget);
    expect(find.text('稍后'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
  });

  testWidgets('强制更新不可稍后且点击遮罩不关闭', (tester) async {
    await tester.pumpWidget(
      harness(
        checker: ({required trigger}) async =>
            available(AppUpdateUrgency.required),
        child: const AppUpdateLifecycle(child: Text('body')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('稍后'), findsNothing);
    expect(find.text('立即更新'), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 v1.0.1'), findsOneWidget);
  });

  testWidgets('自动检查网络失败不打扰用户', (tester) async {
    await tester.pumpWidget(
      harness(
        checker: ({required trigger}) async => const AppUpdateCheckResult(
          status: AppUpdateCheckStatus.failed,
          failureKind: AppUpdateFailureKind.network,
        ),
        child: const AppUpdateLifecycle(child: Text('body')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('当前渠道无法执行策略时不显示无效更新按钮', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appUpdateCheckerProvider.overrideWithValue(
            ({required trigger}) async => available(AppUpdateUrgency.optional),
          ),
          appUpdateAvailabilityProvider.overrideWithValue((_) async => false),
        ],
        child: MaterialApp(
          theme: buildThemeData(graphiteMint),
          home: const Scaffold(body: AppUpdateLifecycle(child: Text('body'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('立即更新'), findsNothing);
  });

  testWidgets('首帧和恢复前台均触发自动检查', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      harness(
        checker: ({required trigger}) async {
          calls++;
          return const AppUpdateCheckResult(
            status: AppUpdateCheckStatus.upToDate,
          );
        },
        child: const AppUpdateLifecycle(child: Text('body')),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
}
