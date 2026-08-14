import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ztoken_monitor/core/notifications/notification_models.dart';
import 'package:ztoken_monitor/features/limits/widgets/quota_notification_settings.dart';
import 'package:ztoken_monitor/theme/app_colors.dart';
import 'package:ztoken_monitor/theme/app_theme.dart';

void main() {
  final target = NotificationTarget(
    id: 'codex:a',
    provider: 'codex',
    accountLabel: '个人账户',
    windows: const [
      NotificationWindowTarget(id: 'five-hour', label: '5 小时'),
      NotificationWindowTarget(id: 'weekly', label: '每周'),
    ],
  );
  late NotificationRulesDocument document;

  setUp(() {
    document = NotificationRulesDocument(
      rules: [
        QuotaNotificationRule(
          id: 'rule-a',
          targetId: target.id,
          enabled: true,
          refreshEnabled: true,
          warningEnabled: true,
          thresholdPercent: 20,
          windowIds: const ['five-hour', 'weekly'],
        ),
      ],
    );
  });

  Future<void> pumpDialog(
    WidgetTester tester, {
    Size size = const Size(800, 700),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildThemeData(porcelain),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: QuotaNotificationSettingsDialog(
              target: target,
              document: document,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('账户通知设置展示刷新、剩余阈值和可多选的当前窗口', (tester) async {
    await pumpDialog(tester);

    expect(find.text('额度刷新通知'), findsOneWidget);
    expect(find.text('剩余低于此值提醒'), findsOneWidget);
    expect(find.text('5 小时'), findsOneWidget);
    expect(find.text('每周'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
  });

  testWidgets('窄屏和放大字体下配置内容可滚动且无布局溢出', (tester) async {
    await pumpDialog(tester, size: const Size(320, 568), textScale: 1.5);

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('启用配额通知'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
