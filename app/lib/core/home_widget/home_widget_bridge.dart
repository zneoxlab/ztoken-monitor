import 'dart:async';

import 'package:flutter/services.dart';

import 'home_widget_snapshot.dart';

typedef HomeWidgetActionHandler =
    FutureOr<void> Function(String route, bool refresh);

class HomeWidgetBridge {
  HomeWidgetBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.zneox.ztoken_monitor/home_widget';
  final MethodChannel _channel;
  HomeWidgetActionHandler? _actionHandler;

  Future<void> update(HomeWidgetSnapshot snapshot) async {
    try {
      await _channel.invokeMethod<void>(
        'updateWidget',
        snapshot.toChannelMap(),
      );
    } on MissingPluginException {
      // iOS/Web/鸿蒙暂未注册 Android 原生桥；不影响 App 主流程。
    } on PlatformException {
      // 小组件永远不能阻塞主 App 数据刷新。
    }
  }

  Future<void> startActionHandling(HomeWidgetActionHandler handler) async {
    _actionHandler = handler;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'openRoute') return;
      await _dispatchAction(call.arguments);
    });
    try {
      final pending = await _channel.invokeMethod<Object?>('getPendingAction');
      await _dispatchAction(pending);
    } on MissingPluginException {
      // 非 Android 平台正常无桥。
    } on PlatformException {
      // 路由桥失败不影响 App 启动。
    }
  }

  Future<void> stopActionHandling() async {
    _actionHandler = null;
    _channel.setMethodCallHandler(null);
  }

  Future<void> _dispatchAction(Object? raw) async {
    if (raw is! Map || _actionHandler == null) return;
    final route = raw['route'];
    final refresh = raw['refresh'];
    if (route is! String || route.isEmpty) return;
    await _actionHandler!(route, refresh == true);
  }
}
