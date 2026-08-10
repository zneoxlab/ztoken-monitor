import 'package:flutter_test/flutter_test.dart';
import 'package:ztoken_monitor/core/models/stats.dart';
import 'package:ztoken_monitor/core/view_period.dart';

void main() {
  group('ViewPeriod', () {
    test('cycles through all four periods', () {
      expect(ViewPeriod.today.next, ViewPeriod.month);
      expect(ViewPeriod.month.next, ViewPeriod.year);
      expect(ViewPeriod.year.next, ViewPeriod.allTime);
      expect(ViewPeriod.allTime.next, ViewPeriod.today);
    });

    test('effectiveBreakdownPeriod clamps sessions to month for year/allTime', () {
      expect(
        effectiveBreakdownPeriod(ViewPeriod.year, sessionsOrProjects: true),
        ViewPeriod.month,
      );
      expect(
        effectiveBreakdownPeriod(ViewPeriod.today, sessionsOrProjects: true),
        ViewPeriod.today,
      );
    });

    test('resolvePeriod year aggregates daily rows', () {
      const history = HistoryPreview(daily: [
        HistoryDay(date: '2026-01-15', tokens: 100, cost: 1),
        HistoryDay(date: '2026-08-06', tokens: 50, cost: 0.5),
      ]);
      const allTime = Period(totalTokens: 1000, costUsd: 10, clientOutputs: const {'claude': 200});
      const periods = Periods(allTime: allTime);
      final year = resolvePeriod(ViewPeriod.year, periods, history);
      expect(year?.totalTokens, 150);
      expect(year?.costUsd, closeTo(1.5, 0.001));
    });

    test('dailyForViewPeriod filters by month', () {
      const daily = [
        HistoryDay(date: '2026-07-31', tokens: 10),
        HistoryDay(date: '2026-08-06', tokens: 20),
      ];
      final month = dailyForViewPeriod(daily, ViewPeriod.month);
      expect(month.length, 1);
      expect(month.first.tokens, 20);
    });
  });
}
