import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/view_period.dart';
import '../../core/format/formatters.dart';
import '../../core/models/stats.dart';
import '../../core/network/stats_repository.dart';
import '../../core/storage/prefs_storage.dart';
import '../../theme/glass_material.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/heatmap_grid.dart';
import '../../widgets/model_usage_bars.dart';
import '../../widgets/period_toggle.dart';
import '../../widgets/year_heatmap.dart';

// ============================================================
// 使用趋势(原型 ⑦,二级页)。数据:GET /api/history 全量(historyProvider)。
// 内容:
//   ① streak 双卡:当前连续 / 最长连续 + 近 30 天日均。
//   ② 全年热力图(52 周,横向滚动)—— 复用 buildYearGrid + HeatmapGrid。
//   ③ 每月用量柱(近 12 月,单色 tokens;协议 monthly 无 perClient,
//      "按工具/按模型"段控 M1 不做)。
//   ④ 近 12 周花费面积图(fl_chart LineChart)。
// 空态:无历史显示"历史由桌面端保留会话用量后积累"。
// 二级页:顶部带返回箭头,无底部标签栏。
// ============================================================

class TrendPage extends ConsumerWidget {
  const TrendPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(historyProvider);
    final currency = ref.watch(settingsProvider).displayCurrency;
    final viewPeriod = ref.watch(viewPeriodProvider);
    final stats = ref.watch(statsProvider).valueOrNull;
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: async.when(
            loading: () => const _Loading(),
            error: (e, st) => _Error(onRetry: () => ref.refresh(historyProvider)),
            data: (history) {
              final daily = history.daily;
              final monthly = history.monthly;
              final summary = history.summary;
              final periodData = resolvePeriod(viewPeriod, stats?.periods, history);
              if (daily.isEmpty && monthly.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    const _BackHeader(title: '使用趋势'),
                    const SizedBox(height: 40),
                    const _EmptyState(),
                  ],
                );
              }
              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  const _BackHeader(title: '使用趋势'),
                  const SizedBox(height: 6),
                  _PeriodSummaryCards(
                    viewPeriod: viewPeriod,
                    period: periodData,
                    daily: daily,
                    summary: summary,
                    currency: currency,
                  ),
                  const SizedBox(height: 10),
                  _HeatmapCard(daily: daily, viewPeriod: viewPeriod, summary: summary),
                  const SizedBox(height: 10),
                  _UsageBarsCard(daily: daily, monthly: monthly, viewPeriod: viewPeriod),
                  const SizedBox(height: 10),
                  _PeriodSpendCard(daily: daily, currency: currency, viewPeriod: viewPeriod),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// 顶部带返回箭头的标题(二级页,无底部 tab)。
class _BackHeader extends StatelessWidget {
  const _BackHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.arrow_back_ios_new, size: 18, color: t.text),
            ),
          ),
          Expanded(
            child: Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: t.text)),
          ),
          const PeriodToggle(),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(height: 12),
          Text('加载历史…', style: TextStyle(fontSize: 12, color: t.muted)),
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 40, color: t.faint),
          const SizedBox(height: 12),
          Text('无法加载历史', style: TextStyle(fontSize: 13, color: t.muted)),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(10)),
              child: Text('重试', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF14201A))),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Column(
      children: [
        Icon(Icons.show_chart, size: 48, color: t.faint),
        const SizedBox(height: 12),
        Text('暂无历史数据', style: TextStyle(fontSize: 14, color: t.muted)),
        const SizedBox(height: 6),
        Text('历史由桌面端保留会话用量后积累', style: TextStyle(fontSize: 12, color: t.faint)),
      ],
    );
  }
}

// 周期汇总三卡:随全局 viewPeriod 变化。
class _PeriodSummaryCards extends StatelessWidget {
  const _PeriodSummaryCards({
    required this.viewPeriod,
    required this.period,
    required this.daily,
    required this.summary,
    required this.currency,
  });

  final ViewPeriod viewPeriod;
  final Period? period;
  final List<HistoryDay> daily;
  final HistorySummary? summary;
  final DisplayCurrency currency;

  @override
  Widget build(BuildContext context) {
    final scoped = dailyForViewPeriod(daily, viewPeriod);
    final tokens = period?.totalTokens ?? scoped.fold<int>(0, (s, d) => s + d.tokens);
    final cost = period?.costUsd ?? scoped.fold<double>(0, (s, d) => s + d.cost);
    final activeDays = scoped.where((d) => d.tokens > 0).length;
    final activeMs = scoped.fold<int>(0, (s, d) => s + d.activeTimeMs);

    late final String label1;
    late final String value1;
    late final String unit1;
    late final String label2;
    late final String value2;
    late final String label3;
    late final String value3;
    late final String unit3;

    switch (viewPeriod) {
      case ViewPeriod.today:
        label1 = '今日 tokens';
        value1 = formatTokensCompact(tokens);
        unit1 = '';
        label2 = '今日花费';
        value2 = formatMoney(cost, currency);
        label3 = '活跃时长';
        value3 = activeMs > 0 ? formatActiveDuration(activeMs) : '—';
        unit3 = '';
      case ViewPeriod.month:
        label1 = '本月 tokens';
        value1 = formatTokensCompact(tokens);
        unit1 = '';
        label2 = '本月花费';
        value2 = formatMoney(cost, currency);
        label3 = '活跃天数';
        value3 = '$activeDays';
        unit3 = '天';
      case ViewPeriod.year:
        label1 = '本年 tokens';
        value1 = formatTokensCompact(tokens);
        unit1 = '';
        label2 = '本年花费';
        value2 = formatMoney(cost, currency);
        label3 = '活跃天数';
        value3 = '$activeDays';
        unit3 = '天';
      case ViewPeriod.allTime:
        label1 = '累计 tokens';
        value1 = formatTokensCompact(tokens);
        unit1 = '';
        label2 = '累计花费';
        value2 = formatMoney(cost, currency);
        label3 = '活跃天数';
        value3 = '${summary?.activeDays ?? activeDays}';
        unit3 = '天';
    }

    final spendFlex = switch (viewPeriod) {
      ViewPeriod.year || ViewPeriod.allTime => 5,
      _ => 4,
    };
    final thirdFlex = viewPeriod == ViewPeriod.year || viewPeriod == ViewPeriod.allTime ? 3 : 4;

    return Row(
      children: [
        Expanded(flex: 4, child: _SummaryMini(label: label1, value: value1, unit: unit1)),
        const SizedBox(width: 10),
        Expanded(flex: spendFlex, child: _SummaryMini(label: label2, value: value2, unit: '')),
        const SizedBox(width: 10),
        Expanded(flex: thirdFlex, child: _SummaryMini(label: label3, value: value3, unit: unit3)),
      ],
    );
  }
}

class _SummaryMini extends StatelessWidget {
  const _SummaryMini({required this.label, required this.value, required this.unit});
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10.5, color: t.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.text, fontFamily: 'Menlo', fontFamilyFallback: const ['monospace']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 2),
                Text(unit, style: TextStyle(fontSize: 12, color: t.muted)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _HeatmapCard extends StatefulWidget {
  const _HeatmapCard({required this.daily, required this.viewPeriod, this.summary});
  final List<HistoryDay> daily;
  final ViewPeriod viewPeriod;
  final HistorySummary? summary;

  @override
  State<_HeatmapCard> createState() => _HeatmapCardState();
}

class _HeatmapCardState extends State<_HeatmapCard> {
  bool _showActiveDays = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final scoped = heatmapDailyForViewPeriod(widget.daily, widget.viewPeriod);
    if (scoped.isEmpty) return const SizedBox.shrink();
    final grid = buildActivityHeatmapGrid(scoped, widget.viewPeriod);
    final scopeStyle = TextStyle(fontSize: 11, color: t.faint);
    final streakStyle = TextStyle(fontSize: 11, color: t.accent);
    final streakText = activityHeatmapStreakText(
      summary: widget.summary,
      daily: widget.daily,
      showActiveDays: _showActiveDays,
    );
    Widget? trailing = Text(activityScopeLabel(widget.viewPeriod), style: scopeStyle);
    if (streakText != null) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(activityScopeLabel(widget.viewPeriod), style: scopeStyle),
          Text(' · ', style: scopeStyle),
          GestureDetector(
            onTap: () => setState(() => _showActiveDays = !_showActiveDays),
            behavior: HitTestBehavior.opaque,
            child: Text(streakText, style: streakStyle),
          ),
        ],
      );
    }
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('活动', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.muted)),
              trailing,
            ],
          ),
          const SizedBox(height: 10),
          HeatmapGrid(levels: grid.levels, monthLabels: grid.monthLabels, cells: grid.cells),
          const SizedBox(height: 8),
          const HeatmapLegend(),
        ],
      ),
    );
  }
}

class _UsageBarsCard extends StatefulWidget {
  const _UsageBarsCard({required this.daily, required this.monthly, required this.viewPeriod});
  final List<HistoryDay> daily;
  final List<HistoryMonth> monthly;
  final ViewPeriod viewPeriod;

  @override
  State<_UsageBarsCard> createState() => _UsageBarsCardState();
}

class _UsageBarsCardState extends State<_UsageBarsCard> {
  bool _showAverage = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final useDaily = widget.viewPeriod == ViewPeriod.month || widget.viewPeriod == ViewPeriod.today;
    final daySeries = widget.viewPeriod == ViewPeriod.month
        ? fullMonthDailySeries(widget.daily)
        : (widget.daily.length > 14 ? widget.daily.sublist(widget.daily.length - 14) : widget.daily);
    final monthSeries = monthlyForViewPeriod(widget.monthly, widget.viewPeriod);
    if (useDaily && daySeries.isEmpty) return const SizedBox.shrink();
    if (!useDaily && monthSeries.isEmpty) return const SizedBox.shrink();

    final title = switch (widget.viewPeriod) {
      ViewPeriod.month => '本月用量',
      ViewPeriod.today => '近14天用量',
      _ => '每月用量 · ${monthSeries.length} 月',
    };

    final peak = useDaily
        ? daySeries.fold<int>(0, (m, d) => d.tokens > m ? d.tokens : m)
        : monthSeries.fold<int>(0, (m, e) => e.tokens > m ? e.tokens : m);
    final total = useDaily
        ? daySeries.fold<int>(0, (s, d) => s + d.tokens)
        : monthSeries.fold<int>(0, (s, m) => s + m.tokens);
    final count = useDaily ? daySeries.length : monthSeries.length;
    final average = count == 0 ? 0 : (total / count).round();
    final metaValue = _showAverage ? average : peak;
    final metaLabel = _showAverage ? '均用量' : '峰值';
    final metaText = metaValue > 0 ? '$metaLabel ${formatTokensCompact(metaValue)}' : null;

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.muted)),
              if (metaText != null)
                GestureDetector(
                  onTap: () => setState(() => _showAverage = !_showAverage),
                  behavior: HitTestBehavior.opaque,
                  child: Text(metaText, style: TextStyle(fontSize: 10.5, color: t.accent)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ModelUsageBarChart(
            days: daySeries,
            months: monthSeries,
            useMonthly: !useDaily,
          ),
        ],
      ),
    );
  }
}

class _PeriodSpendCard extends StatelessWidget {
  const _PeriodSpendCard({required this.daily, required this.currency, required this.viewPeriod});
  final List<HistoryDay> daily;
  final DisplayCurrency currency;
  final ViewPeriod viewPeriod;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final scoped = trendSpendDailyForViewPeriod(daily, viewPeriod);
    if (scoped.isEmpty) return const SizedBox.shrink();

    final weekly = trendSpendAggregateWeekly(viewPeriod);
    final points = <_SpendPoint>[];
    if (weekly) {
      for (var i = 0; i < scoped.length; i += 7) {
        final end = (i + 7 > scoped.length) ? scoped.length : i + 7;
        final slice = scoped.sublist(i, end);
        final sum = slice.fold<double>(0, (a, d) => a + d.cost);
        final start = DateTime.tryParse(slice.first.date);
        points.add(_SpendPoint(cost: sum, anchor: start));
      }
    } else {
      for (final day in scoped) {
        points.add(_SpendPoint(cost: day.cost, anchor: DateTime.tryParse(day.date)));
      }
    }
    if (points.isEmpty) return const SizedBox.shrink();

    final maxSpend = points.fold<double>(0, (a, p) => p.cost > a ? p.cost : a);
    final spots = [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].cost)];
    final hideYAxis = weekly;
    final hideXAxis = !weekly;

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(trendSpendChartTitle(viewPeriod), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.muted)),
              if (maxSpend > 0)
                Text('峰值 ${formatMoney(maxSpend, currency)}', style: TextStyle(fontSize: 10.5, color: t.faint)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxSpend == 0 ? 1 : maxSpend * 1.15,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: t.accent,
                    barWidth: 2.5,
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
                    getTooltipItems: (touched) {
                      if (touched.isEmpty) return [];
                      final idx = touched.first.x.round();
                      if (idx < 0 || idx >= points.length) return [];
                      final p = points[idx];
                      final title = _spendPointTitle(p, weekly);
                      return [
                        LineTooltipItem(
                          title.isEmpty
                              ? formatMoney(p.cost, currency)
                              : '$title\n${formatMoney(p.cost, currency)}',
                          TextStyle(color: t.text, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ];
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: !hideYAxis,
                      reservedSize: hideYAxis ? 0 : 42,
                      interval: maxSpend == 0 ? 1 : maxSpend / 2,
                      getTitlesWidget: (v, meta) {
                        if (v < 0) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            formatMoney(v, currency),
                            style: TextStyle(fontSize: 8.5, color: t.faint),
                            textAlign: TextAlign.right,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: !hideXAxis,
                      reservedSize: hideXAxis ? 0 : 20,
                      interval: 1,
                      getTitlesWidget: (v, meta) => _spendXLabel(points, v.toInt(), weekly, t),
                    ),
                  ),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpendPoint {
  const _SpendPoint({required this.cost, this.anchor});
  final double cost;
  final DateTime? anchor;
}

String _spendPointTitle(_SpendPoint point, bool weekly) {
  final dt = point.anchor;
  if (dt == null) return '';
  if (weekly) return '${dt.month}月${dt.day}日';
  return '${dt.month}月${dt.day}日';
}

Widget _spendXLabel(List<_SpendPoint> points, int idx, bool weekly, AppThemeTokens t) {
  if (points.isEmpty || idx < 0 || idx >= points.length) return const SizedBox.shrink();
  final dt = points[idx].anchor;
  if (dt == null) return const SizedBox.shrink();
  if (weekly) {
    final prev = idx > 0 ? points[idx - 1].anchor : null;
    if (prev != null && prev.month == dt.month) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text('${dt.month}月', style: TextStyle(fontSize: 9, color: t.muted)),
    );
  }
  if (points.length > 14) {
    if (idx != 0 && idx != points.length - 1 && idx != points.length ~/ 2) {
      return const SizedBox.shrink();
    }
  }
  return Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text('${dt.day}', style: TextStyle(fontSize: 8.5, color: t.muted)),
  );
}
