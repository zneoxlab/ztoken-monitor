import 'package:flutter/material.dart';

// ============================================================
// 主题模式 / 材质枚举 + ThemeSettings —— 纯数据,无任何依赖。
// 单独成文件,避免 app_theme(主题构建)与 prefs_storage(设置持久化)
// 互相 import 造成循环依赖。两者都依赖此文件。
// ============================================================

// 主题枚举:顺序与 appColorTokensList 对应,供设置页切换。
enum AppThemeMode {
  graphiteMint, // 石墨薄荷(默认深色)
  starryBlue, // 星海蓝
  obsidian, // 黑曜
  porcelain, // 纸白(浅色)
  system, // 跟随系统
}

// 外观材质:与四色主题正交。对照 themes.css 的 body.glass。
enum AppMaterial {
  solid, // 默认:实色卡片
  glass, // 透明玻璃:半透明 + 模糊 + 高光
}

// 主题选择状态。mode/material 来自用户设置(prefs_storage 持久化),
// glassDowngraded 由性能监测层(任务7 帧率监测)动态置位,不持久化。
class ThemeSettings {
  const ThemeSettings({
    this.mode = AppThemeMode.system,
    this.material = AppMaterial.solid,
    this.glassDowngraded = false,
  });

  final AppThemeMode mode;
  final AppMaterial material;
  final bool glassDowngraded;

  ThemeSettings copyWith({
    AppThemeMode? mode,
    AppMaterial? material,
    bool? glassDowngraded,
  }) {
    return ThemeSettings(
      mode: mode ?? this.mode,
      material: material ?? this.material,
      glassDowngraded: glassDowngraded ?? this.glassDowngraded,
    );
  }
}

// 实际生效的材质:用户选 glass 但被降级时,回落到 solid。
AppMaterial effectiveMaterial(ThemeSettings s) {
  if (s.material == AppMaterial.glass && s.glassDowngraded) {
    return AppMaterial.solid;
  }
  return s.material;
}

// themeMode:跟随系统用 system;选了具体主题则用其 brightness 定 mode。
// 注意:部分平台(鸿蒙等)对 ThemeMode.system 支持不完整,MaterialApp 层请用
// resolveMaterialThemeMode() 显式映射为 light/dark。
ThemeMode themeModeFor(AppThemeMode mode) {
  switch (mode) {
    case AppThemeMode.system:
      return ThemeMode.system;
    case AppThemeMode.graphiteMint:
    case AppThemeMode.starryBlue:
    case AppThemeMode.obsidian:
      return ThemeMode.dark;
    case AppThemeMode.porcelain:
      return ThemeMode.light;
  }
}

// 跟随系统时按平台亮度选 light/dark;强制主题则忽略平台亮度。
ThemeMode resolveMaterialThemeMode(
  AppThemeMode mode,
  Brightness platformBrightness,
) {
  switch (mode) {
    case AppThemeMode.system:
      return platformBrightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light;
    case AppThemeMode.graphiteMint:
    case AppThemeMode.starryBlue:
    case AppThemeMode.obsidian:
      return ThemeMode.dark;
    case AppThemeMode.porcelain:
      return ThemeMode.light;
  }
}
