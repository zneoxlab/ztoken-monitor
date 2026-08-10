import 'package:flutter/material.dart';

import '../theme/theme_extension.dart';

// ============================================================
// AppTag —— 小标签,对照原型 .tag。
// 不用 M3 Chip:高度/形状不符(UI-IMPL.md §0/§8)。
// Container(padding h7 v2,底色按变体,radius 999,child Text 9.5px)。
// 变体 green/amber/grey:实色字 + 同色 12% 透明底。default 即 grey。
// 计划标(Max/Plus)用 green 变体。
// ============================================================

enum AppTagVariant { normal, green, amber, grey }

class AppTag extends StatelessWidget {
  const AppTag({
    super.key,
    required this.text,
    this.variant = AppTagVariant.normal,
  });

  final String text;
  final AppTagVariant variant;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    // 变体 → (字色, 底色=字色 12%)
    final (fg, bg) = switch (variant) {
      AppTagVariant.green => (t.green, t.green.withValues(alpha: 0.12)),
      AppTagVariant.amber => (t.amber, t.amber.withValues(alpha: 0.12)),
      AppTagVariant.grey => (t.faint, t.panel2),
      AppTagVariant.normal => (t.muted, t.panel2),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 9.5, color: fg),
      ),
    );
  }
}
