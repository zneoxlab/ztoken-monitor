import 'package:flutter_test/flutter_test.dart';
import 'package:ztoken_monitor/core/models/stats.dart';
import 'package:ztoken_monitor/core/view_period.dart';

void main() {
  group('resolvePeriod year', () {
    test('scales client and model breakdown maps', () {
      const history = HistoryPreview(daily: [
        HistoryDay(date: '2026-08-01', tokens: 50, cost: 0.5),
        HistoryDay(date: '2026-08-06', tokens: 50, cost: 0.5),
      ]);
      const allTime = Period(
        totalTokens: 1000,
        costUsd: 10,
        clients: const {'claude': 800, 'codex': 200},
        models: const {'gpt-4': 600, 'claude-opus': 400},
        clientCosts: const {'claude': 8, 'codex': 2},
        modelCosts: const {'gpt-4': 6, 'claude-opus': 4},
        modelCacheReads: const {'gpt-4': 300},
        modelOutputs: const {'gpt-4': 100},
      );
      const periods = Periods(allTime: allTime);
      final year = resolvePeriod(ViewPeriod.year, periods, history);
      expect(year?.totalTokens, 100);
      expect(year?.clients['claude'], 80);
      expect(year?.models['gpt-4'], 60);
      expect(year?.modelCacheReads['gpt-4'], 30);
      expect(year?.modelOutputs['gpt-4'], 10);
    });
  });
}
