import 'package:flutter/material.dart';

import 'app_colors.dart';

// ============================================================
// AppThemeTokens —— 自定义 ThemeExtension。
// 把 app_colors.dart 的色令牌挂到 Theme 上,组件层通过
//   final t = Theme.of(context).extension<AppThemeTokens>()!;
// 取用,不直接依赖 AppColorTokens 常量,便于主题切换时整体替换。
// 对照 app-prototype 的 CSS 变量命名,字段一一对应。
// ============================================================

class AppThemeTokens extends ThemeExtension<AppThemeTokens> {
  const AppThemeTokens({required this.tokens});

  final AppColorTokens tokens;

  // 便捷访问(组件层常用)
  Color get bg => tokens.bg;
  Color get panel => tokens.panel;
  Color get panel2 => tokens.panel2;
  Color get line => tokens.line;
  Color get text => tokens.text;
  Color get muted => tokens.muted;
  Color get faint => tokens.faint;
  Color get accent => tokens.accent;
  List<int> get accentRgb => tokens.accentRgb;
  Color get green => tokens.green;
  Color get red => tokens.red;
  Color get amber => tokens.amber;
  Color get blue => tokens.blue;
  Color get tabbarBg => tokens.tabbarBg;
  Brightness get brightness => tokens.brightness;

  // 玻璃材质相关派生色(委托给 AppColorTokens)
  Color get glassPanelFill => tokens.glassPanelFill;
  Color get glassBorder => tokens.glassBorder;
  Color get glassHighlight => tokens.glassHighlight;

  @override
  AppThemeTokens copyWith({AppColorTokens? tokens}) {
    return AppThemeTokens(tokens: tokens ?? this.tokens);
  }

  @override
  AppThemeTokens lerp(ThemeExtension<AppThemeTokens>? other, double t) {
    if (other is! AppThemeTokens) return this;
    // 主题切换时的颜色插值;Color.lerp 处理 ARGB 通道线性过渡。
    // accentRgb 用整数插值后四舍五入,保证玻璃渐变也能平滑过渡。
    return AppThemeTokens(
      tokens: AppColorTokens(
        brightness: t < 0.5 ? tokens.brightness : other.tokens.brightness,
        bg: Color.lerp(tokens.bg, other.tokens.bg, t)!,
        panel: Color.lerp(tokens.panel, other.tokens.panel, t)!,
        panel2: Color.lerp(tokens.panel2, other.tokens.panel2, t)!,
        line: Color.lerp(tokens.line, other.tokens.line, t)!,
        text: Color.lerp(tokens.text, other.tokens.text, t)!,
        muted: Color.lerp(tokens.muted, other.tokens.muted, t)!,
        faint: Color.lerp(tokens.faint, other.tokens.faint, t)!,
        accent: Color.lerp(tokens.accent, other.tokens.accent, t)!,
        accentRgb: _lerpRgb(tokens.accentRgb, other.tokens.accentRgb, t),
        green: Color.lerp(tokens.green, other.tokens.green, t)!,
        red: Color.lerp(tokens.red, other.tokens.red, t)!,
        amber: Color.lerp(tokens.amber, other.tokens.amber, t)!,
        blue: Color.lerp(tokens.blue, other.tokens.blue, t)!,
        tabbarBg: Color.lerp(tokens.tabbarBg, other.tokens.tabbarBg, t)!,
      ),
    );
  }

  // RGB 三通道整数插值,用于玻璃极光渐变。
  static List<int> _lerpRgb(List<int> a, List<int> b, double t) {
    return List.generate(3, (i) => (a[i] + (b[i] - a[i]) * t).round());
  }
}
