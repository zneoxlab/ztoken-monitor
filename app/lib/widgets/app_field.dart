import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/theme_extension.dart';

// ============================================================
// AppField —— 表单字段(label + TextField),对照原型 .field/.input。
// TextField 必须去 M3 默认样式(UI-IMPL.md §10):
//   filled panel2、OutlineInputBorder radius 10 borderSide line、
//   contentPadding 12×13、isDense、字号 14 text。
// label 在输入框上方独立一行(11.5 muted,mb 6),非 floatingLabel。
// ============================================================

class AppField extends StatelessWidget {
  const AppField({
    super.key,
    required this.label,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.placeholder,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
    this.autofillHints,
  });

  final String label;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? placeholder; // 占位文本(色 faint)
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // label:11.5 muted,mb 6
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label, style: TextStyle(fontSize: 11.5, color: t.muted)),
          ),
          TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            focusNode: focusNode,
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            autofillHints: autofillHints,
            style: TextStyle(fontSize: 14, color: t.text),
            cursorColor: t.accent,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: t.panel2,
              hintText: placeholder,
              hintStyle: TextStyle(fontSize: 14, color: t.faint),
              contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(kRadiusSmall),
                borderSide: BorderSide(color: t.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(kRadiusSmall),
                borderSide: BorderSide(color: t.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(kRadiusSmall),
                borderSide: BorderSide(color: t.accent, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
