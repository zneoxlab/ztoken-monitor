import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'quota_notification.dart';

// Android/iOS 由原生系统通知实现;鸿蒙/Web 没有注册通道时安全降级为空操作。
class QuotaNotificationService {
  QuotaNotificationService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.zneox.ztoken_monitor/notifications';

  final MethodChannel _channel;
  Future<void>? _permissionFuture;

  Future<void> requestPermission() {
    return _permissionFuture ??= _requestPermission();
  }

  Future<void> _requestPermission() async {
    try {
      await _channel.invokeMethod<Object?>('requestPermission');
    } on MissingPluginException {
      // 鸿蒙/Web/测试环境没有原生通知桥,不影响主流程。
    } on PlatformException {
      // 用户拒绝权限或系统通知不可用时静默降级。
    }
  }

  Future<void> show(
    QuotaNotificationKind kind,
    Iterable<QuotaNotificationEvent> events,
  ) async {
    final list = events.toList();
    if (list.isEmpty) return;
    try {
      await _channel.invokeMethod<Object?>('showQuotaNotification', {
        'title': quotaNotificationTitle(kind),
        'body': quotaNotificationBody(list),
        // 同一类通知更新原通知,避免每次刷新叠加一条系统通知。
        'tag': 'quota-${kind.name}',
      });
    } on MissingPluginException {
      // 非 Android/iOS 平台没有原生实现时安全降级。
    } on PlatformException {
      // 通知失败不能阻塞 SSE/轮询数据流。
    }
  }
}

final quotaNotificationServiceProvider = Provider<QuotaNotificationService>(
  (ref) => QuotaNotificationService(),
);
