import 'package:flutter_test/flutter_test.dart';

import 'package:ztoken_monitor/core/logging/app_log.dart';

void main() {
  test('AppLog 环形缓冲与导出', () {
    AppLog.clear();
    AppLog.info('test', 'hello');
    AppLog.warn('sse', 'reconnect');
    final text = AppLog.export(hubUrl: 'https://hub.test', email: 'a@b.c');
    expect(text, contains('ZT助手 system log'));
    expect(text, contains('[I/test] hello'));
    expect(text, contains('[W/sse] reconnect'));
    expect(text, contains('hubUrl: https://hub.test'));
  });
}
