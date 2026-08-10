import 'package:flutter/material.dart';

import '../theme/theme_extension.dart';

// ============================================================
// AppSegmented —— 分段控件,对照原型 .seg。
// 不用 M3 SegmentedButton:边框/高度 40/选中描边全是 M3 样式,
// 无法还原原型(高 34、panel2 底、选中 panel 底无描边)(UI-IMPL.md §0/§4)。
// 外层 Container(34 高,panel2,radius 10,padding 3)内 Row 每项 Expanded;
// 选中 AnimatedContainer(panel 底,radius 8,深色加 1px 下阴影),文字 12px。
// ============================================================

class AppSegmented extends StatefulWidget {
  const AppSegmented({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  State<AppSegmented> createState() => _AppSegmentedState();
}

class _AppSegmentedState extends State<AppSegmented> {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;

    return Container(
      height: 34,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: t.panel2,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          for (var i = 0; i < widget.labels.length; i++)
            Expanded(
              child: _SegItem(
                label: widget.labels[i],
                selected: i == widget.selectedIndex,
                isDark: t.brightness == Brightness.dark,
                onTap: () => widget.onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _SegItem extends StatelessWidget {
  const _SegItem({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? t.panel : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          // 深色主题选中项加 1px 下阴影(对照 .seg span.on box-shadow),
          // 浅色省略
          boxShadow: selected && isDark
              ? const [
                  BoxShadow(
                    color: Color(0x59000000),
                    offset: Offset(0, 1),
                    blurRadius: 4,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? t.text : t.muted,
          ),
        ),
      ),
    );
  }
}
