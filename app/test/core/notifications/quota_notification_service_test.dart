import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ztoken_monitor/core/notifications/quota_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/quota_notifications');
  final calls = <MethodCall>[];

  setUp(calls.clear);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('测试通知先请求权限，再调用原生系统通知', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'requestPermission' ? true : null;
        });

    final sent = await QuotaNotificationService(
      channel: channel,
    ).showTestNotification();

    expect(sent, isTrue);
    expect(calls.map((call) => call.method), [
      'requestPermission',
      'showQuotaNotification',
    ]);
    expect(calls.last.arguments, containsPair('title', '配额通知测试'));
    expect(calls.last.arguments, containsPair('tag', 'quota-test'));
  });

  test('通知权限被拒绝时不调用系统通知', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return false;
        });

    final sent = await QuotaNotificationService(
      channel: channel,
    ).showTestNotification();

    expect(sent, isFalse);
    expect(calls.map((call) => call.method), ['requestPermission']);
  });
}
