import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/prefs_storage.dart';
import 'app_colors.dart';
import 'theme_extension.dart';
import 'theme_mode.dart';

// ============================================================
// 主题构建器 + Riverpod provider。
// 4 主题(石墨薄荷/星海蓝/黑曜/纸白)× 2 材质(默认/透明玻璃)。
// 默认跟随系统:深色→石墨薄荷,浅色→纸白。
// 用户选择由 prefs_storage 的 settingsProvider 持久化(shared_preferences);
// 此处只负责把 AppSettings 转成 ThemeData。
// ============================================================

// 根据主题模式 + 系统亮度,解析出实际使用的 AppColorTokens。
// 跟随系统时:深色→石墨薄荷,浅色→纸白(GOAL.md §7 约定)。
AppColorTokens resolveTokens(AppThemeMode mode, Brightness platformBrightness) {
  switch (mode) {
    case AppThemeMode.graphiteMint:
      return graphiteMint;
    case AppThemeMode.starryBlue:
      return starryBlue;
    case AppThemeMode.obsidian:
      return obsidian;
    case AppThemeMode.porcelain:
      return porcelain;
    case AppThemeMode.system:
      return platformBrightness == Brightness.dark
          ? graphiteMint
          : porcelain;
  }
}

// 由 AppColorTokens 构建 ThemeData。
ThemeData buildThemeData(AppColorTokens t) {
  final colorScheme = ColorScheme(
    brightness: t.brightness,
    primary: t.accent,
    onPrimary: t.brightness == Brightness.light
        ? Colors.white
        : const Color(0xFF14201A),
    secondary: t.accent,
    onSecondary: t.brightness == Brightness.light
        ? Colors.white
        : const Color(0xFF14201A),
    error: t.red,
    onError: Colors.white,
    surface: t.panel,
    onSurface: t.text,
    surfaceContainerHighest: t.panel2,
  );

  final baseTypography = t.brightness == Brightness.dark
      ? Typography.material2021(platform: TargetPlatform.iOS).white
      : Typography.material2021(platform: TargetPlatform.iOS).black;

  return ThemeData(
    useMaterial3: true,
    brightness: t.brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: t.bg,
    // 卡片默认背景用 panel,边框用 line
    cardTheme: CardThemeData(
      color: t.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusCard),
        side: BorderSide(color: t.line),
      ),
      margin: EdgeInsets.zero,
    ),
    // 底部导航栏:背景用 tabbarBg,选中色 accent,未选中 faint
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.tabbarBg,
      indicatorColor: t.accent.withValues(alpha: 0.16),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 10, color: t.faint),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? t.accent : t.faint, size: 23);
      }),
    ),
    // 文字默认色随深浅主题切换
    textTheme: baseTypography.copyWith(
      bodyLarge: TextStyle(color: t.text),
      bodyMedium: TextStyle(color: t.text),
      bodySmall: TextStyle(color: t.muted),
    ),
    dividerTheme: DividerThemeData(color: t.line, thickness: 1),
    extensions: [AppThemeTokens(tokens: t)],
  );
}

// ============================================================
// 三个 provider 供 MaterialApp 消费:themeMode + lightTheme + darkTheme。
// 跟随系统时显式监听 platformBrightness 并映射为 ThemeMode.light/dark,
// 避免部分平台(尤其鸿蒙)下 ThemeMode.system 始终回落浅色的问题。
// ============================================================

// 监听系统亮度变化,驱动「跟随系统」主题切换。
class PlatformBrightnessNotifier extends StateNotifier<Brightness> {
  PlatformBrightnessNotifier()
      : super(WidgetsBinding.instance.platformDispatcher.platformBrightness) {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    _previousHandler = dispatcher.onPlatformBrightnessChanged;
    dispatcher.onPlatformBrightnessChanged = _onPlatformBrightnessChanged;
  }

  VoidCallback? _previousHandler;

  void _onPlatformBrightnessChanged() {
    _previousHandler?.call();
    syncFromPlatform();
  }

  // 供生命周期桥接在 resumed 时补读(鸿蒙 SettingsChannel 推送可能晚于首帧)。
  void syncFromPlatform() {
    final next = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    if (state != next) state = next;
  }

  void disposeListener() {
    WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
        _previousHandler;
  }
}

final platformBrightnessProvider =
    StateNotifierProvider<PlatformBrightnessNotifier, Brightness>((ref) {
  final notifier = PlatformBrightnessNotifier();
  ref.onDispose(notifier.disposeListener);
  return notifier;
});

// 挂在 MaterialApp 内:补监听 didChangePlatformBrightness + resumed 时重读亮度。
class PlatformBrightnessLifecycleSync extends ConsumerStatefulWidget {
  const PlatformBrightnessLifecycleSync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PlatformBrightnessLifecycleSync> createState() =>
      _PlatformBrightnessLifecycleSyncState();
}

class _PlatformBrightnessLifecycleSyncState extends ConsumerState<PlatformBrightnessLifecycleSync>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(platformBrightnessProvider.notifier).syncFromPlatform();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    ref.read(platformBrightnessProvider.notifier).syncFromPlatform();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(platformBrightnessProvider.notifier).syncFromPlatform();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// themeModeFor / effectiveMaterial / ThemeSettings 见 theme_mode.dart。
// 此处 provider 从 prefs_storage 的 settingsProvider 派生(已持久化)。

final themeModeProvider = Provider<ThemeMode>((ref) {
  final settings = ref.watch(settingsProvider);
  final platformBrightness = ref.watch(platformBrightnessProvider);
  return resolveMaterialThemeMode(settings.themeMode, platformBrightness);
});

// 设置页展示顺序(与 AppThemeMode 枚举序不同,勿用 .index 直接映射)。
const themePickerOptions = <(AppThemeMode mode, String label)>[
  (AppThemeMode.system, '跟随系统'),
  (AppThemeMode.graphiteMint, '石墨'),
  (AppThemeMode.starryBlue, '星海蓝'),
  (AppThemeMode.obsidian, '黑曜'),
  (AppThemeMode.porcelain, '纸白'),
];

int themePickerIndex(AppThemeMode mode) {
  final idx = themePickerOptions.indexWhere((e) => e.$1 == mode);
  return idx < 0 ? 0 : idx;
}

AppThemeMode themeModeFromPickerIndex(int index) {
  if (index < 0 || index >= themePickerOptions.length) return AppThemeMode.system;
  return themePickerOptions[index].$1;
}

// 浅色 ThemeData:跟随系统时用纸白,强制浅色主题同理。
final lightThemeProvider = Provider<ThemeData>((ref) {
  final settings = ref.watch(settingsProvider);
  return buildThemeData(resolveTokens(settings.themeMode, Brightness.light));
});

// 深色 ThemeData:跟随系统时用石墨薄荷,强制深色主题用对应色板。
final darkThemeProvider = Provider<ThemeData>((ref) {
  final settings = ref.watch(settingsProvider);
  return buildThemeData(resolveTokens(settings.themeMode, Brightness.dark));
});

// 当前生效的材质 provider(含降级逻辑)。GlassCard 等组件读这个。
// glassDowngraded 当前恒 false;任务7 帧率监测接入后由独立 provider 注入。
final effectiveMaterialProvider = Provider<AppMaterial>((ref) {
  final settings = ref.watch(settingsProvider);
  return effectiveMaterial(ThemeSettings(
    mode: settings.themeMode,
    material: settings.material,
  ));
});
