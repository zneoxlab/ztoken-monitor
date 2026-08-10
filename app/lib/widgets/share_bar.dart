import 'package:flutter/material.dart';

import '../theme/theme_extension.dart';

// ============================================================
// ShareBar —— 占比条,对照原型 .share-bar。
// 两种形态:
//  (1) 单段 .share-bar:4 高,panel2 底 radius 2,内 FractionallySizedBox
//      填充色为厂商色。
//  (2) 多段彩虹条(工具/设备占比):Row 若干 Expanded(flex:percent) + Container,
//      整体 ClipRRect radius 5,高 10。
// ============================================================

// 单段占比条。share 0..1,color 为厂商色。
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.share, required this.color});

  final double share;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Container(
      height: 4,
      margin: const EdgeInsets.only(top: 7),
      decoration: BoxDecoration(
        color: t.panel2,
        borderRadius: BorderRadius.circular(2),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: share.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

// 一段彩虹条(多厂商占比)。
class RainbowSegment {
  const RainbowSegment({required this.percent, required this.color});
  final int percent; // 整数百分比,flex 值
  final Color color;
}

// 多段彩虹条:Row Expanded(flex:percent) + Container,ClipRRect radius 5,高 10。
class RainbowBar extends StatelessWidget {
  const RainbowBar({super.key, required this.segments});

  final List<RainbowSegment> segments;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            for (final s in segments)
              if (s.percent > 0)
                Expanded(
                  flex: s.percent,
                  child: Container(color: s.color),
                ),
          ],
        ),
      ),
    );
  }
}
