import 'package:flutter/material.dart';

import '../theme/theme_extension.dart';

// ============================================================
// MeterBar —— 配额条,对照原型 .meter。
// 不用 M3 LinearProgressIndicator:高度/圆角不符(UI-IMPL.md §0/§7)。
// 头部 Row(空间两端):标签 11.5 muted + 数值 11.5 mono 加粗;
// SizedBox(6);轨道 Container(7 高,panel2,radius 4) + FractionallySizedBox
// 填充(用量分级:<60% accent / ≥60% amber / ≥90% red);
// 底部 10 faint 重置倒计时。
// ============================================================

class MeterBar extends StatelessWidget {
  const MeterBar({
    super.key,
    this.label,
    this.valueText,
    required this.usedPercent, // 0..100,用于轨道填充比例 + 颜色分级
    this.resetText,
    this.compact = false,
  });

  final String? label;
  final String? valueText; // 右侧数值(如 "62%" / "$3.20 / $5.00"),null 不画头部行
  final double usedPercent; // 0..100
  final String? resetText; // 底部重置倒计时,null 不画
  final bool compact; // 首页额度等紧凑场景:更矮、更线性的轨道

  // 用量分级颜色:<60% accent / ≥60% amber / ≥90% red。
  Color _fillColor(AppThemeTokens t) {
    if (usedPercent >= 90) return t.red;
    if (usedPercent >= 60) return t.amber;
    return t.accent;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final fill = _fillColor(t);
    final factor = (usedPercent / 100).clamp(0.0, 1.0);
    final trackHeight = compact ? 4.0 : 7.0;
    final trackRadius = compact ? 2.0 : 4.0;
    final headerGap = compact ? 4.0 : 6.0;
    // 头部行仅当 label 或 valueText 至少一个非空时才渲染
    final showHeader = label != null || valueText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // .mhead:仅当 label/valueText 至少一个非空时渲染
        if (showHeader) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (label != null)
                Text(label!, style: TextStyle(fontSize: 11.5, color: t.muted))
              else
                const SizedBox(),
              if (valueText != null)
                Text(
                  valueText!,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                    fontFamily: 'Menlo',
                    fontFamilyFallback: const ['monospace'],
                  ),
                )
              else
                const SizedBox(),
            ],
          ),
          SizedBox(height: headerGap),
        ],
        Container(
          height: trackHeight,
          decoration: BoxDecoration(
            color: t.panel2,
            borderRadius: BorderRadius.circular(trackRadius),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: factor,
            child: Container(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(trackRadius),
              ),
            ),
          ),
        ),
        if (resetText != null) ...[
          const SizedBox(height: 5),
          // .reset:10 faint
          Text(resetText!, style: TextStyle(fontSize: 10, color: t.faint)),
        ],
      ],
    );
  }
}
