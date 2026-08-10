import 'package:flutter/material.dart';

import '../theme/theme_extension.dart';

// ============================================================
// AppPageHeader —— 页面顶部标题栏,对照原型 .appbar。
// 不用 M3 AppBar:它的高度/elevation/标题字号是 M3 规范,
// 原型标题是 22px 加粗内嵌在页面里(UI-IMPL.md §0/§1)。
// 结构:Row(空间两端)→ 左侧 Column(标题 22/w700 + 副标题 12 muted),
// 右侧 trailing(如 LiveDot / 图标按钮)。
// ============================================================

class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.titleTrailing,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  /// 标题右侧内联组件(如实时绿点)。
  final Widget? titleTrailing;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                    if (titleTrailing != null) ...[
                      const SizedBox(width: 8),
                      titleTrailing!,
                    ],
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 12, color: t.muted),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
