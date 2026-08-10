import 'package:flutter/material.dart';

import '../theme/theme_extension.dart';

// ============================================================
// StackedBars —— 总览 14 天堆叠柱,对照原型 .bars。
// 不用 fl_chart:固定柱状无坐标轴/触摸交互,自绘更轻(UI-IMPL.md §11)。
// fl_chart 只用于趋势页的花费面积图(LineChart)和月度堆叠柱(BarChart)。
// Row(crossAxisAlignment: end, gap 5);每柱 Expanded →
//   Column(mainAxisAlignment: end) 叠 Container(高度=占比×96,厂商色)段,
//   首尾段圆角 3。底部 .bars-x 9 faint 日期标签由调用方自行拼接。
// ============================================================

class StackedSegment {
  const StackedSegment({required this.value, required this.color});
  final double value; // 原始数值(非占比,按 maxValue 归一化)
  final Color color;
}

class StackedDay {
  const StackedDay({required this.segments, this.label});
  final List<StackedSegment> segments;
  final String? label; // 底部日期标签(如 "8/6"),null 不显
}

class StackedBars extends StatelessWidget {
  const StackedBars({
    super.key,
    required this.days,
    required this.maxValue, // 归一化基准(14 天单日峰值)
    this.height = 96,
  });

  final List<StackedDay> days;
  final double maxValue;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // .bars:96 高,底端对齐
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < days.length; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Expanded(child: _Bar(day: days[i], maxValue: maxValue, height: height)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        // .bars-x:9 faint,与柱等宽对齐
        Row(
          children: [
            for (var i = 0; i < days.length; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              Expanded(
                child: Text(
                  days[i].label ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9, color: t.faint),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.day, required this.maxValue, required this.height});

  final StackedDay day;
  final double maxValue;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Column-reverse:段从底往上叠;CSS .b 是 column-reverse
    final children = <Widget>[];
    for (var i = 0; i < day.segments.length; i++) {
      final s = day.segments[i];
      final h = maxValue > 0 ? (s.value / maxValue) * height : 0.0;
      if (h <= 0) continue;
      // 首段(底)和末段(顶)圆角 3
      final isFirst = i == 0;
      final isLast = i == day.segments.length - 1;
      children.add(
        Container(
          width: double.infinity,
          height: h,
          decoration: BoxDecoration(
            color: s.color,
            borderRadius: BorderRadius.vertical(
              top: isLast ? const Radius.circular(3) : Radius.zero,
              bottom: isFirst ? const Radius.circular(3) : Radius.zero,
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: children.reversed.toList(), // reverse:第一段画在最底
    );
  }
}
