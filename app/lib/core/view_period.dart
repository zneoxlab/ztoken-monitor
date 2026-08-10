import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'format/formatters.dart';
import 'models/stats.dart';

// 全局视图周期:总览 / 明细 / 设备 / 趋势 共用。
enum ViewPeriod { today, month, year, allTime }

extension ViewPeriodX on ViewPeriod {
  ViewPeriod get next => switch (this) {
        ViewPeriod.today => ViewPeriod.month,
        ViewPeriod.month => ViewPeriod.year,
        ViewPeriod.year => ViewPeriod.allTime,
        ViewPeriod.allTime => ViewPeriod.today,
      };

  String get shortLabel => switch (this) {
        ViewPeriod.today => '今日',
        ViewPeriod.month => '本月',
        ViewPeriod.year => '本年',
        ViewPeriod.allTime => '累计',
      };
}

final viewPeriodProvider = StateProvider<ViewPeriod>((ref) => ViewPeriod.today);

String viewPeriodSubtitle(ViewPeriod period) {
  final now = DateTime.now();
  return switch (period) {
    ViewPeriod.today => '今日 · ${formatDateShort(now)}',
    ViewPeriod.month => '本月 · ${now.month}月',
    ViewPeriod.year => '本年 · ${now.year}',
    ViewPeriod.allTime => '累计',
  };
}

/// 明细会话/项目段协议无 allTime/本年,回落到本月。
ViewPeriod effectiveBreakdownPeriod(ViewPeriod period, {required bool sessionsOrProjects}) {
  if (!sessionsOrProjects) return period;
  return switch (period) {
    ViewPeriod.today => ViewPeriod.today,
    _ => ViewPeriod.month,
  };
}

Period? resolvePeriod(ViewPeriod period, Periods? periods, HistoryPreview? history) {
  switch (period) {
    case ViewPeriod.today:
      return periods?.today;
    case ViewPeriod.month:
      return periods?.month;
    case ViewPeriod.allTime:
      return periods?.allTime;
    case ViewPeriod.year:
      return _yearPeriod(periods?.allTime, history);
  }
}

Period? resolveDevicePeriod(
  ViewPeriod period,
  DeviceRecord device,
  Periods? aggregatePeriods,
  HistoryPreview? history,
) {
  final periods = device.periods;
  if (periods == null) return null;
  switch (period) {
    case ViewPeriod.today:
      return periods.today;
    case ViewPeriod.month:
      return periods.month;
    case ViewPeriod.allTime:
      return periods.allTime;
    case ViewPeriod.year:
      final aggYear = resolvePeriod(ViewPeriod.year, aggregatePeriods, history);
      final devAll = periods.allTime;
      final aggAll = aggregatePeriods?.allTime;
      if (aggYear == null || devAll == null || aggAll == null || aggAll.totalTokens <= 0) {
        return periods.month;
      }
      final ratio = aggYear.totalTokens / aggAll.totalTokens;
      return Period(
        totalTokens: (devAll.totalTokens * ratio).round(),
        costUsd: devAll.costUsd * ratio,
        clients: devAll.clients,
        clientCosts: devAll.clientCosts.map((k, v) => MapEntry(k, v * ratio)),
        clientCacheReads: _scaleIntMap(devAll.clientCacheReads, ratio),
        clientOutputs: _scaleIntMap(devAll.clientOutputs, ratio),
      );
  }
}

Period _yearPeriod(Period? allTime, HistoryPreview? history) {
  final prefix = '${DateTime.now().year}-';
  final rows = (history?.daily ?? []).where((d) => d.date.startsWith(prefix));
  final tokens = rows.fold<int>(0, (s, d) => s + d.tokens);
  final cost = rows.fold<double>(0, (s, d) => s + d.cost);
  if (allTime == null || allTime.totalTokens <= 0) {
    return Period(totalTokens: tokens, costUsd: cost);
  }
  final ratio = tokens / allTime.totalTokens;
  return _scalePeriod(allTime, ratio, totalTokens: tokens, costUsd: cost);
}

Period _scalePeriod(Period source, double ratio, {int? totalTokens, double? costUsd}) {
  return Period(
    totalTokens: totalTokens ?? (source.totalTokens * ratio).round(),
    costUsd: costUsd ?? source.costUsd * ratio,
    clients: _scaleIntMap(source.clients, ratio),
    clientCosts: _scaleDoubleMap(source.clientCosts, ratio),
    models: _scaleIntMap(source.models, ratio),
    modelCosts: _scaleDoubleMap(source.modelCosts, ratio),
    clientCacheReads: _scaleIntMap(source.clientCacheReads, ratio),
    clientCacheWrites: _scaleIntMap(source.clientCacheWrites, ratio),
    clientOutputs: _scaleIntMap(source.clientOutputs, ratio),
    clientModels: _scaleNestedIntMap(source.clientModels, ratio),
    modelCacheReads: _scaleIntMap(source.modelCacheReads, ratio),
    modelCacheWrites: _scaleIntMap(source.modelCacheWrites, ratio),
    modelOutputs: _scaleIntMap(source.modelOutputs, ratio),
  );
}

Map<String, double> _scaleDoubleMap(Map<String, double> source, double ratio) {
  if (ratio <= 0 || source.isEmpty) return const {};
  return source.map((k, v) => MapEntry(k, v * ratio));
}

Map<String, Map<String, int>> _scaleNestedIntMap(Map<String, Map<String, int>> source, double ratio) {
  if (ratio <= 0 || source.isEmpty) return const {};
  return source.map((k, inner) => MapEntry(k, inner.map((mk, mv) => MapEntry(mk, (mv * ratio).round()))));
}

Map<String, int> _scaleIntMap(Map<String, int> source, double ratio) {
  if (ratio <= 0 || source.isEmpty) return const {};
  return source.map((k, v) => MapEntry(k, (v * ratio).round()));
}

class HeroStatValues {
  const HeroStatValues({required this.cacheHit, required this.output, required this.activeTime});
  final String cacheHit;
  final String output;
  final String activeTime;
}

HeroStatValues heroStatsForPeriod(ViewPeriod period, Period? data, HistoryPreview? history) {
  if (data == null) {
    return const HeroStatValues(cacheHit: '—', output: '—', activeTime: '—');
  }
  final cacheRead = data.clientCacheReads.values.fold<int>(0, (a, b) => a + b);
  final output = data.clientOutputs.values.fold<int>(0, (a, b) => a + b);
  final cacheMiss = (data.totalTokens - cacheRead - output).clamp(0, data.totalTokens);
  final inputTokens = cacheRead + cacheMiss;
  final hitPct = inputTokens > 0 ? ((cacheRead * 100) / inputTokens).round() : 0;
  final activeMs = _activeTimeMs(period, history);

  return HeroStatValues(
    cacheHit: inputTokens > 0 ? '$hitPct%' : '—',
    output: output > 0 ? formatTokensCompact(output) : '—',
    activeTime: activeMs > 0 ? formatActiveDuration(activeMs) : '—',
  );
}

int _activeTimeMs(ViewPeriod period, HistoryPreview? history) {
  final daily = history?.daily ?? const [];
  switch (period) {
    case ViewPeriod.today:
      return daily.where((d) => d.date.startsWith(_todayIso())).firstOrNull?.activeTimeMs ?? 0;
    case ViewPeriod.month:
      final now = DateTime.now();
      final prefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      return daily.where((d) => d.date.startsWith(prefix)).fold<int>(0, (s, d) => s + d.activeTimeMs);
    case ViewPeriod.year:
      final prefix = '${DateTime.now().year}-';
      return daily.where((d) => d.date.startsWith(prefix)).fold<int>(0, (s, d) => s + d.activeTimeMs);
    case ViewPeriod.allTime:
      return daily.fold<int>(0, (s, d) => s + d.activeTimeMs);
  }
}

String _todayIso() {
  final now = DateTime.now();
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '${now.year}-$m-$d';
}

String _monthPrefix(DateTime now) => '${now.year}-${now.month.toString().padLeft(2, '0')}';

/// 趋势/图表用的日序列,按全局周期裁剪。
List<HistoryDay> dailyForViewPeriod(List<HistoryDay> daily, ViewPeriod period) {
  if (daily.isEmpty) return const [];
  final now = DateTime.now();
  return switch (period) {
    ViewPeriod.today => daily.where((d) => d.date.startsWith(_todayIso())).toList(),
    ViewPeriod.month => daily.where((d) => d.date.startsWith(_monthPrefix(now))).toList(),
    ViewPeriod.year => daily.where((d) => d.date.startsWith('${now.year}-')).toList(),
    ViewPeriod.allTime => daily,
  };
}

/// 热力图:默认近一年;仅「累计」用全量历史。
List<HistoryDay> heatmapDailyForViewPeriod(List<HistoryDay> daily, ViewPeriod period) {
  if (daily.isEmpty) return const [];
  if (period == ViewPeriod.allTime) return daily;
  return daily.length > 365 ? daily.sublist(daily.length - 365) : daily;
}

List<HistoryMonth> monthlyForViewPeriod(List<HistoryMonth> monthly, ViewPeriod period) {
  if (monthly.isEmpty) return const [];
  final now = DateTime.now();
  return switch (period) {
    ViewPeriod.today => const [],
    ViewPeriod.month => monthly.where((m) => m.month == _monthPrefix(now)).toList(),
    ViewPeriod.year => monthly.where((m) => m.month.startsWith('${now.year}-')).toList(),
    ViewPeriod.allTime => monthly.length > 12 ? monthly.sublist(monthly.length - 12) : monthly,
  };
}

String trendSpendChartTitle(ViewPeriod period) {
  return switch (period) {
    ViewPeriod.today => '近14天花费',
    ViewPeriod.month => '本月每日花费',
    ViewPeriod.year => '本年每周花费',
    ViewPeriod.allTime => '近12周花费',
  };
}

/// 趋势页花费折线用的日序列。
List<HistoryDay> trendSpendDailyForViewPeriod(List<HistoryDay> daily, ViewPeriod period) {
  if (daily.isEmpty) return const [];
  switch (period) {
    case ViewPeriod.today:
      return daily.length > 14 ? daily.sublist(daily.length - 14) : daily;
    case ViewPeriod.month:
    case ViewPeriod.year:
      return dailyForViewPeriod(daily, period);
    case ViewPeriod.allTime:
      return daily.length > 84 ? daily.sublist(daily.length - 84) : daily;
  }
}

bool trendSpendAggregateWeekly(ViewPeriod period) =>
    period == ViewPeriod.year || period == ViewPeriod.allTime;
