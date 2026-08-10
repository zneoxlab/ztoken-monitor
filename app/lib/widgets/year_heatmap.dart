import '../core/models/stats.dart';
import '../core/view_period.dart';

// ============================================================
// 活动热力图:默认近一年(365天);仅「累计」展示全部历史。
// ============================================================

class HeatmapCellMeta {
  const HeatmapCellMeta({required this.date, required this.tokens, this.label = ''});
  final String date; // YYYY-MM-DD,空=占位格
  final int tokens;
  final String label; // 月份轴或日号
}

class YearGrid {
  const YearGrid({
    required this.levels,
    required this.monthLabels,
    this.cells = const [],
  });
  final List<List<int>> levels;
  final List<String> monthLabels;
  final List<List<HeatmapCellMeta?>> cells;
}

class _DayCell {
  const _DayCell({required this.date, required this.tokens});
  final DateTime date;
  final int tokens;
}

YearGrid buildActivityHeatmapGrid(List<HistoryDay> daily, ViewPeriod period) {
  final map = _dailyTokenMap(daily);
  final maxTok = _maxTokens(daily);
  if (period == ViewPeriod.allTime) {
    return _buildRangeGrid(map, maxTok, _fullHistoryRange(daily));
  }
  return _buildRangeGrid(map, maxTok, _rollingYearRange());
}

String activityScopeLabel(ViewPeriod period) {
  return period == ViewPeriod.allTime ? '全部' : '近一年';
}

/// 活动卡右上角:连续天数 / 活跃天数切换文案。
String? activityHeatmapStreakText({
  required HistorySummary? summary,
  required List<HistoryDay> daily,
  required bool showActiveDays,
}) {
  if (showActiveDays) {
    final fromSummary = summary?.activeDays ?? 0;
    final days = fromSummary > 0 ? fromSummary : daily.where((d) => d.tokens > 0).length;
    return days > 0 ? '活跃 $days 天' : null;
  }
  final streak = summary?.currentStreak ?? 0;
  return streak > 0 ? '连续 $streak 天' : null;
}

Map<String, int> _dailyTokenMap(List<HistoryDay> daily) {
  final map = <String, int>{};
  for (final d in daily) {
    if (d.date.isEmpty) continue;
    map[d.date] = d.tokens;
  }
  return map;
}

int _maxTokens(List<HistoryDay> daily) {
  var maxTok = 0;
  for (final d in daily) {
    if (d.tokens > maxTok) maxTok = d.tokens;
  }
  return maxTok;
}

({DateTime start, DateTime end}) _rollingYearRange() {
  final today = _todayDate();
  return (start: today.subtract(const Duration(days: 364)), end: today);
}

({DateTime start, DateTime end}) _fullHistoryRange(List<HistoryDay> daily) {
  final today = _todayDate();
  DateTime? earliest;
  for (final d in daily) {
    final dt = DateTime.tryParse(d.date);
    if (dt == null) continue;
    final day = DateTime(dt.year, dt.month, dt.day);
    if (earliest == null || day.isBefore(earliest)) earliest = day;
  }
  return (start: earliest ?? today, end: today);
}

YearGrid _buildRangeGrid(
  Map<String, int> map,
  int maxTok,
  ({DateTime start, DateTime end}) range,
) {
  final days = <DateTime>[];
  var cursor = range.start;
  final end = range.end;
  while (!cursor.isAfter(end)) {
    days.add(cursor);
    cursor = cursor.add(const Duration(days: 1));
  }
  final leadBlanks = days.first.weekday - 1;
  final cells = <_DayCell?>[];
  for (var i = 0; i < leadBlanks; i++) {
    cells.add(null);
  }
  for (final dt in days) {
    cells.add(_DayCell(date: dt, tokens: map[_isoDate(dt)] ?? 0));
  }
  while (cells.length % 7 != 0) {
    cells.add(null);
  }
  return _gridFromCells(cells, maxTok);
}

YearGrid _gridFromCells(List<_DayCell?> cells, int maxTok) {
  final levels = <List<int>>[];
  final monthLabels = <String>[];
  final meta = <List<HeatmapCellMeta?>>[];
  int? lastMonth;

  for (var c = 0; c < cells.length; c += 7) {
    final col = cells.sublist(c, c + 7);
    _DayCell? firstCell;
    for (final x in col) {
      if (x != null) {
        firstCell = x;
        break;
      }
    }
    final month = firstCell?.date.month;
    if (month != null && month != lastMonth) {
      monthLabels.add('$month月');
      lastMonth = month;
    } else {
      monthLabels.add('');
    }

    levels.add(col.map((x) => x == null ? 0 : _intensity(x.tokens, maxTok)).toList());
    meta.add(col.map((x) {
      if (x == null) return null;
      return HeatmapCellMeta(date: _isoDate(x.date), tokens: x.tokens);
    }).toList());
  }

  return YearGrid(levels: levels, monthLabels: monthLabels, cells: meta);
}

/// 兼容旧调用:近一年(365天)网格。
YearGrid buildYearGrid(List<HistoryDay> daily) {
  return buildActivityHeatmapGrid(daily, ViewPeriod.today);
}

DateTime _todayDate() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

String _isoDate(DateTime dt) {
  final y = dt.year.toString();
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

int _intensity(int tokens, int max) {
  if (tokens <= 0) return 0;
  if (max <= 0) return 1;
  final ratio = tokens / max;
  if (ratio >= 0.75) return 4;
  if (ratio >= 0.5) return 3;
  if (ratio >= 0.25) return 2;
  return 1;
}
