import 'package:flutter/material.dart';

import '../theme/theme_extension.dart';

// ============================================================
// AppButton —— 主按钮,对照原型 .btn / .btn.ghost。
// 不用 ElevatedButton:有阴影/最小高 40 不符(UI-IMPL.md §10)。
// 主按钮:48 高(=padding 13×2 + 行高),accent 底,radius 10,
//   字 15/w700,深色主题字色 #14201A、浅色主题白。
// ghost 变体:透明底 + line 边 + text 字 15/w600。
// 加载态:文字换 18×18 白色 CircularProgressIndicator,禁用点击。
// ============================================================

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.ghost = false,
  });

  final String label;
  final VoidCallback? onPressed; // null = 禁用
  final bool loading;
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    // 深色主题主按钮字色 #14201A(accent 是浅薄荷),浅色主题白(accent 深色)
    final isDark = t.brightness == Brightness.dark;
    final textColor = ghost
        ? t.text
        : (isDark ? const Color(0xFF14201A) : Colors.white);
    final spinnerColor = ghost ? t.text : textColor;

    final enabled = onPressed != null && !loading;

    return GestureDetector(
      onTap: enabled ? onPressed : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ghost ? Colors.transparent : t.accent,
          borderRadius: BorderRadius.circular(10),
          border: ghost ? Border.all(color: t.line) : null,
        ),
        child: loading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: spinnerColor,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: ghost ? FontWeight.w600 : FontWeight.w700,
                  color: textColor,
                ),
              ),
      ),
    );
  }
}
