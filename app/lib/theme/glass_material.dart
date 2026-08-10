import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_colors.dart';
import 'app_theme.dart';
import 'theme_extension.dart';
import 'theme_mode.dart';

// ============================================================
// 透明玻璃材质 —— 对应 app-prototype/themes.css 的 body.glass。
// 实现:BackdropFilter + ImageFilter.blur(sigma≈22, saturate 150%)
//   + 半透明容器(panel 52% / 浅色 55% 白)
//   + 1px 半透明边框(白 16% / 浅色 75%)
//   + 顶部 1px 内高光(白 14% / 浅色 90%)
// 三端(含鸿蒙)零新增插件,全为框架自带能力。
// 极光渐变(AuroraBackground)是屏底背景层,与卡片分离。
// ============================================================

// 玻璃卡片:实色材质下退化为普通 Container(panel 背景 + line 边),
// 玻璃材质下叠加 BackdropFilter 模糊 + 半透明 + 高光。
// 组件层统一用 GlassCard,材质切换由 effectiveMaterialProvider 决定,
// 无需各处判断。
class GlassCard extends ConsumerWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = kRadiusCard,
    this.isHero = false, // hero 卡片:玻璃下边框用 accent 色而非白色
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool isHero;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final material = ref.watch(effectiveMaterialProvider);

    // 实色材质:hero 用 accent 描边 + panel 底(对照 .hero border)
    if (material == AppMaterial.solid) {
      final borderColor = isHero
          ? Color.fromARGB(56, t.accentRgb[0], t.accentRgb[1], t.accentRgb[2])
          : t.line;
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: t.panel,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: child,
      );
    }

    // 玻璃材质:BackdropFilter 模糊 + 半透明填充 + 高光边
    // sigma 22 对应 CSS blur(22px);saturate 通过 ColorFilter 实现。
    final border = isHero
        ? t.accent.withValues(alpha: 0.38) // hero 边框用 accent 38%
        : t.glassBorder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(color: t.glassPanelFill),
            ),
          ),
          // 顶部内高光:1px 渐变线,Liquid Glass 标志性细节
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    t.glassHighlight.withValues(alpha: 0),
                    t.glassHighlight,
                    t.glassHighlight.withValues(alpha: 0),
                  ],
                  stops: const [0.1, 0.5, 0.9],
                ),
              ),
            ),
          ),
          // 内容 + 边框
          Container(
            padding: padding,
            decoration: BoxDecoration(
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(radius),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// AuroraBackground —— 玻璃材质下屏底的极光渐变。
// 对应 themes.css body.glass .phone 的三层 radial-gradient:
//   左上 accent 30% / 右上 紫 #6566f1 20% / 底中 绿 #22c994 16%
// 仅玻璃材质渲染,实色材质返回空(背景交给 scaffold bg)。
// ============================================================
class AuroraBackground extends ConsumerWidget {
  const AuroraBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final material = ref.watch(effectiveMaterialProvider);

    if (material == AppMaterial.solid) {
      return child; // 实色材质无需极光
    }

    final accent = Color.fromARGB(
      77, // 30%
      t.accentRgb[0],
      t.accentRgb[1],
      t.accentRgb[2],
    );

    return Stack(
      children: [
        // 极光三层:左上 accent / 右上 紫 / 底中 绿
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: t.bg,
              gradient: RadialGradient(
                // 用多个渐变叠加近似 CSS 三层 radial-gradient;
                // Flutter 单 RadialGradient 只能一团,故用 Stack 分层。
                center: const Alignment(-0.92, -0.55),
                radius: 1.3,
                colors: [accent, t.bg.withValues(alpha: 0)],
                stops: const [0, 0.62],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.9, -0.28),
                radius: 1.1,
                colors: [
                  const Color(0x1A6566F1), // 紫 10%,减弱卡片区染色
                  t.bg.withValues(alpha: 0),
                ],
                stops: const [0, 0.6],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, 1.08),
                radius: 1.2,
                colors: [
                  const Color(0x2922C994), // 绿 16%
                  t.bg.withValues(alpha: 0),
                ],
                stops: const [0, 0.65],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
