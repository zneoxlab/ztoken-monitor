import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/network/stats_repository.dart';
import 'core/home_widget/home_widget_sync.dart';
import 'core/router.dart';
import 'core/update/app_update_lifecycle.dart';
import 'theme/app_theme.dart';

// 应用根 Widget:装配 MaterialApp.router。
// 主题系统:themeMode + lightTheme + darkTheme 三 provider 驱动,
// 4 主题(石墨薄荷/星海蓝/黑曜/纸白)× 2 材质(默认/透明玻璃)。
// 材质由 effectiveMaterialProvider 决定,GlassCard 等组件自行读取。
class ZtokenMonitorApp extends ConsumerWidget {
  const ZtokenMonitorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(sessionDataLifecycleProvider);
    ref.watch(platformBrightnessProvider);
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final lightTheme = ref.watch(lightThemeProvider);
    final darkTheme = ref.watch(darkThemeProvider);

    // 状态栏沉浸式:外层先按平台亮度,builder 内再按实际生效主题修正。
    final platformDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: platformDark
          ? Brightness.light
          : Brightness.dark,
      statusBarBrightness: platformDark ? Brightness.dark : Brightness.light,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: MaterialApp.router(
        title: 'ZT助手',
        debugShowCheckedModeBanner: false,
        themeMode: themeMode,
        theme: lightTheme,
        darkTheme: darkTheme,
        routerConfig: router,
        builder: (context, child) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return HomeWidgetSync(
            router: router,
            child: AppUpdateLifecycle(
              child: PlatformBrightnessLifecycleSync(
                child: AnnotatedRegion<SystemUiOverlayStyle>(
                  value: SystemUiOverlayStyle(
                    statusBarColor: Colors.transparent,
                    statusBarIconBrightness: isDark
                        ? Brightness.light
                        : Brightness.dark,
                    statusBarBrightness: isDark
                        ? Brightness.dark
                        : Brightness.light,
                  ),
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
