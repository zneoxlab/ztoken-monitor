import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/format/formatters.dart';
import '../theme/theme_extension.dart';

// 近 N 天 tokens 面积折线图(对照桌面 home-area-chart / areaLineChart)。
class TokenAreaChart extends StatelessWidget {
  const TokenAreaChart({
    super.key,
    required this.values,
    this.height = 96,
    this.dateLabels = const [],
  });

  final List<int> values;
  final double height;
  final List<String> dateLabels;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    if (values.isEmpty) return SizedBox(height: height);

    final maxVal = values.fold<int>(0, (m, v) => v > m ? v : m);
    final spots = [
      for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i].toDouble()),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxVal == 0 ? 1 : maxVal * 1.12,
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: t.accent,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: t.accent.withValues(alpha: 0.18),
                  ),
                ),
              ],
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => t.panel,
                    tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                  getTooltipItems: (spots) {
                    if (spots.isEmpty) return [];
                    final idx = spots.first.x.round();
                    final label = idx >= 0 && idx < dateLabels.length && dateLabels[idx].isNotEmpty
                        ? dateLabels[idx]
                        : '';
                    final value = formatTokensCompact(spots.first.y.round());
                    return [
                      LineTooltipItem(
                        label.isEmpty ? value : '$label\n$value',
                        TextStyle(color: t.text, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ];
                  },
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    interval: maxVal == 0 ? 1 : maxVal / 2,
                    getTitlesWidget: (v, meta) {
                      if (v < 0) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          formatTokensCompact(v.round()),
                          style: TextStyle(fontSize: 8.5, color: t.faint),
                          textAlign: TextAlign.right,
                        ),
                      );
                    },
                  ),
                ),
              ),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
        if (dateLabels.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(width: 34),
              for (var i = 0; i < dateLabels.length; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    dateLabels[i],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(fontSize: 9, color: t.faint),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
