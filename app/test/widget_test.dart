// 骨架冒烟测试:未认证 → 路由守卫重定向到登录页,登录页关键元素渲染。
// 已认证态的 home 渲染留待 Task 7 接真实数据后用 stats mock 测。

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ztoken_monitor/app.dart';
import 'package:ztoken_monitor/core/network/auth_mode.dart';
import 'package:ztoken_monitor/core/network/dio_client.dart';
import 'package:ztoken_monitor/core/storage/prefs_storage.dart';

void main() {
  setUp(() {
    // flutter_secure_storage 测试环境需 mock 平台通道,否则 load() hang
    FlutterSecureStorage.setMockInitialValues({});
  });

  // 测试用 dio:指向不存在的端口 + 极短超时,健康检查/提交秒失败不阻塞。
  Dio testDio() => Dio(BaseOptions(
        baseUrl: 'http://127.0.0.1:1',
        connectTimeout: const Duration(milliseconds: 50),
        receiveTimeout: const Duration(milliseconds: 50),
      ));

  testWidgets('未认证 → 进登录页,关键元素渲染', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      // 健康检查会发 GET /api/health;指向不存在端口,快速失败不阻塞测试
      dioProvider.overrideWithValue(testDio()),
    ]);
    addTearDown(container.dispose);
    // 恢复登录态(mock 空 secure storage → 未认证)
    await container.read(authProvider.notifier).load();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ZtokenMonitorApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 路由守卫:未认证应到登录页
    expect(find.text('ZT助手'), findsOneWidget);
    expect(find.text('所有 AI 工具的用量,一处总览'), findsOneWidget);
    // 段控两项
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('注册'), findsOneWidget);
    // 字段 label
    expect(find.text('邮箱'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    // 主按钮(默认登录模式)
    expect(find.text('登录并连接'), findsOneWidget);
  });

  testWidgets('切到注册 → 按钮文案变"注册并连接"', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      dioProvider.overrideWithValue(testDio()),
    ]);
    addTearDown(container.dispose);
    await container.read(authProvider.notifier).load();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ZtokenMonitorApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 点"注册"段控
    await tester.tap(find.text('注册'));
    await tester.pumpAndSettle();

    expect(find.text('注册并连接'), findsOneWidget);
    expect(find.text('登录并连接'), findsNothing);
  });

  testWidgets('空输入提交 → 红字校验提示', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      dioProvider.overrideWithValue(testDio()),
    ]);
    addTearDown(container.dispose);
    await container.read(authProvider.notifier).load();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ZtokenMonitorApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 直接点登录(邮箱密码都空)
    await tester.tap(find.text('登录并连接'));
    await tester.pumpAndSettle();

    expect(find.text('请填写邮箱和密码'), findsOneWidget);
  });
}
