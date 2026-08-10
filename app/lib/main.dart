import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/network/auth_mode.dart';
import 'core/storage/prefs_storage.dart';

// 入口:Riverpod 作用域包裹整个应用。
// 启动顺序:
//  1. await SharedPreferences 初始化,override 注入同步可用实例
//     (主题/设置 provider 首帧即可渲染,无需等异步加载);
//  2. await AuthNotifier.load() 从 secure_storage 恢复凭证,
//     这样路由守卫首帧就有正确鉴权状态(已登录直进总览,免登)。
// 用 ProviderContainer + UncontrolledProviderScope 显式持有容器,
// 以便在 runApp 前触发 load()。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
  ]);

  // 恢复登录态:secure_storage 读凭证,判定 SaaS / 自建 Hub / 未认证。
  await container.read(authProvider.notifier).load();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ZtokenMonitorApp(),
    ),
  );
}
