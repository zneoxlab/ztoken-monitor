import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'quota_notification.dart';

// Android/iOS 由原生系统通知实现;鸿蒙/Web 没有注册通道时安全降级为空操作。
class QuotaNotificationService {
  QuotaNotificationService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.zneox.ztoken_monitor/notifications';

  final MethodChannel _channel;
  Future<bool>? _permissionFuture;

  Future<bool> requestPermission() {
    final pending = _permissionFuture;
    if (pending != null) return pending;
    late final Future<bool> request;
    request = _requestPermission().whenComplete(() {
      if (identical(_permissionFuture, request)) _permissionFuture = null;
    });
    _permissionFuture = request;
    return request;
  }

  Future<bool> _requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') == true;
    } on MissingPluginException {
      // 鸿蒙/Web/测试环境没有原生通知桥,不影响主流程。
      return false;
    } on PlatformException {
      // 用户拒绝权限或系统通知不可用时静默降级。
      return false;
    }
  }

  /// 由设置页显式触发，只验证本机通知权限和系统展示链路，不伪装成
  /// Hub 已成功完成 FCM/APNs 远程投递。
  Future<bool> showTestNotification() async {
    if (!await requestPermission()) return false;
    try {
      await _channel.invokeMethod<Object?>('showQuotaNotification', {
        'title': '配额通知测试',
        'body': '测试通知已送达，额度刷新和预警将在这里显示。',
        'tag': 'quota-test',
      });
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
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
