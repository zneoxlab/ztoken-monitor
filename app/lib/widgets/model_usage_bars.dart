import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/format/formatters.dart';
import '../core/models/stats.dart';
import '../theme/theme_extension.dart';
import 'model_chart_colors.dart';

/// 按模型分色的用量柱图(fl_chart 堆叠柱 + 触摸说明)。
class ModelUsageBarChart extends StatelessWidget {
  const ModelUsageBarChart({
    super.key,
    required this.days,
    this.months = const [],
    this.useMonthly = false,
    this.height = 140,
  });

  final List<HistoryDay> days;
  final List<HistoryMonth> months;
  final bool useMonthly;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    if (useMonthly) {
      return _MonthlyChart(months: months, height: height, tokens: t);
    }
    return _DailyChart(days: days, height: height, tokens: t);
  }
}

class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.days, required this.height, required this.tokens});
  final List<HistoryDay> days;
  final double height;
  final AppThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final models = topModelsFromDays(days);
    final hasModels = models.isNotEmpty;
    final maxTok = days.fold<int>(0, (m, d) => d.tokens > m ? d.tokens : m);

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: maxTok == 0 ? 1 : maxTok * 1.1,
          barGroups: [
            for (var i = 0; i < days.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  () {
                    final stacks = hasModels ? _stackItems(days[i], models, tokens) : const <BarChartRodStackItem>[];
                    return BarChartRodData(
                      toY: days[i].tokens.toDouble(),
                      width: days.length > 20 ? 6 : 10,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      color: stacks.isEmpty ? tokens.accent : Colors.transparent,
                      rodStackItems: stacks,
                    );
                  }(),
                ],
              ),
          ],
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => tokens.panel,
              tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                if (groupIndex < 0 || groupIndex >= days.length) return null;
                return _tooltipItem(days[groupIndex], models, tokens, hasModels);
              },
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: 1,
                getTitlesWidget: (v, _) => _dayLabel(days, v.toInt(), tokens),
              ),
            ),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }
}

class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart({required this.months, required this.height, required this.tokens});
  final List<HistoryMonth> months;
  final double height;
  final AppThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    if (months.isEmpty) return const SizedBox.shrink();
    final models = topModelsFromMonths(months);
    final hasModels = models.isNotEmpty;
    final maxTok = months.fold<int>(0, (m, e) => e.tokens > m ? e.tokens : m);

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: maxTok == 0 ? 1 : maxTok * 1.1,
          barGroups: [
            for (var i = 0; i < months.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  () {
                    final stacks = hasModels ? _monthStackItems(months[i], models, tokens) : const <BarChartRodStackItem>[];
                    return BarChartRodData(
                      toY: months[i].tokens.toDouble(),
                      width: months.length > 8 ? 7 : 10,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      color: stacks.isEmpty ? tokens.accent : Colors.transparent,
                      rodStackItems: stacks,
                    );
                  }(),
                ],
              ),
          ],
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => tokens.panel,
              tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                if (groupIndex < 0 || groupIndex >= months.length) return null;
                return _monthTooltipItem(months[groupIndex], models, tokens, hasModels);
              },
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: months.length > 8 ? 26 : 22,
                interval: 1,
                getTitlesWidget: (v, _) => _monthLabel(months, v.toInt(), tokens),
              ),
            ),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }
}

List<BarChartRodStackItem> _stackItems(HistoryDay day, List<String> models, AppThemeTokens t) {
  var from = 0.0;
  final items = <BarChartRodStackItem>[];
  for (var i = 0; i < models.length; i++) {
    final model = models[i];
    final tok = day.perModel[model]?.tokens ?? 0;
    if (tok <= 0) continue;
    final to = from + tok;
    items.add(BarChartRodStackItem(from, to, colorForModel(model, i)));
    from = to;
  }
  final other = day.tokens - from.round();
  if (other > 0) {
    items.add(BarChartRodStackItem(from, from + other, colorForModel('__other__', models.length)));
  }
  return items;
}

List<BarChartRodStackItem> _monthStackItems(HistoryMonth month, List<String> models, AppThemeTokens t) {
  var from = 0.0;
  final items = <BarChartRodStackItem>[];
  for (var i = 0; i < models.length; i++) {
    final model = models[i];
    final tok = month.perModel[model]?.tokens ?? 0;
    if (tok <= 0) continue;
    final to = from + tok;
    items.add(BarChartRodStackItem(from, to, colorForModel(model, i)));
    from = to;
  }
  final other = month.tokens - from.round();
  if (other > 0) {
    items.add(BarChartRodStackItem(from, from + other, colorForModel('__other__', models.length)));
  }
  return items;
}

BarTooltipItem? _tooltipItem(HistoryDay day, List<String> models, AppThemeTokens t, bool hasModels) {
  final title = _formatDayTitle(day.date);
  if (!hasModels) {
    return BarTooltipItem(
      '$title\n${formatTokensCompact(day.tokens)}',
      TextStyle(color: t.text, fontSize: 11, fontWeight: FontWeight.w600),
    );
  }
  final lines = <String>[title];
  for (var i = 0; i < models.length; i++) {
    final tok = day.perModel[models[i]]?.tokens ?? 0;
    if (tok <= 0) continue;
    lines.add('${models[i]}: ${formatTokensCompact(tok)}');
  }
  final accounted = models.fold<int>(0, (s, m) => s + (day.perModel[m]?.tokens ?? 0));
  final other = day.tokens - accounted;
  if (other > 0) lines.add('其他: ${formatTokensCompact(other)}');
  lines.add('合计: ${formatTokensCompact(day.tokens)}');
  return BarTooltipItem(
    lines.join('\n'),
    TextStyle(color: t.text, fontSize: 11, fontWeight: FontWeight.w500, height: 1.35),
  );
}

BarTooltipItem? _monthTooltipItem(HistoryMonth month, List<String> models, AppThemeTokens t, bool hasModels) {
  final title = _formatMonthTitle(month.month);
  if (!hasModels) {
    return BarTooltipItem(
      '$title\n${formatTokensCompact(month.tokens)}',
      TextStyle(color: t.text, fontSize: 11, fontWeight: FontWeight.w600),
    );
  }
  final lines = <String>[title];
  for (final model in models) {
    final tok = month.perModel[model]?.tokens ?? 0;
    if (tok <= 0) continue;
    lines.add('$model: ${formatTokensCompact(tok)}');
  }
  final accounted = models.fold<int>(0, (s, m) => s + (month.perModel[m]?.tokens ?? 0));
  final other = month.tokens - accounted;
  if (other > 0) lines.add('其他: ${formatTokensCompact(other)}');
  lines.add('合计: ${formatTokensCompact(month.tokens)}');
  return BarTooltipItem(
    lines.join('\n'),
    TextStyle(color: t.text, fontSize: 11, fontWeight: FontWeight.w500, height: 1.35),
  );
}

Widget _dayLabel(List<HistoryDay> days, int idx, AppThemeTokens t) {
  if (days.isEmpty || idx < 0 || idx >= days.length) return const SizedBox.shrink();
  if (days.length > 14) {
    if (idx != 0 && idx != days.length - 1 && idx != days.length ~/ 2) {
      return const SizedBox.shrink();
    }
  }
  final dt = DateTime.tryParse(days[idx].date);
  final label = dt != null ? '${dt.day}' : days[idx].date;
  return Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(label, style: TextStyle(fontSize: 9, color: t.faint)),
  );
}

Widget _monthLabel(List<HistoryMonth> months, int idx, AppThemeTokens t) {
  if (months.isEmpty || idx < 0 || idx >= months.length) return const SizedBox.shrink();
  final m = months[idx].month;
  final dt = DateTime.tryParse('$m-01');
  final label = dt != null ? '${dt.month}月' : m;
  return Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      label,
      style: TextStyle(fontSize: 8.5, color: t.muted),
      maxLines: 1,
      overflow: TextOverflow.visible,
      softWrap: false,
    ),
  );
}

String _formatDayTitle(String iso) {
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  return '${dt.month}月${dt.day}日';
}

String _formatMonthTitle(String ym) {
  final dt = DateTime.tryParse('$ym-01');
  if (dt == null) return ym;
  return '${dt.year}年${dt.month}月';
}

/// 当前月完整日序列(含无数据日),用于按日柱图。
List<HistoryDay> fullMonthDailySeries(List<HistoryDay> daily) {
  final now = DateTime.now();
  final prefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';
  final map = <String, HistoryDay>{};
  for (final d in daily) {
    if (d.date.startsWith(prefix)) map[d.date] = d;
  }
  final lastDay = DateTime(now.year, now.month + 1, 0).day;
  return [
    for (var day = 1; day <= lastDay; day++)
      map['$prefix-${day.toString().padLeft(2, '0')}'] ??
          HistoryDay(date: '$prefix-${day.toString().padLeft(2, '0')}'),
  ];
}
