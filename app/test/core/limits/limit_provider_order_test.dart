import 'package:flutter_test/flutter_test.dart';
import 'package:ztoken_monitor/core/limits/limit_presentation.dart';
import 'package:ztoken_monitor/core/limits/limit_provider_order.dart';
import 'package:ztoken_monitor/core/models/stats.dart';

void main() {
  group('orderedLimitProviders', () {
    final providers = [
      const LimitsProvider(provider: 'copilot', status: 'notConfigured'),
      const LimitsProvider(provider: 'codex', status: 'ok', accountKey: 'a', windows: [
        LimitsWindow(kind: 'weekly', label: 'Weekly', usedPercent: 50),
      ]),
      const LimitsProvider(provider: 'cursor', status: 'ok', accountKey: 'b', windows: [
        LimitsWindow(kind: 'billing', label: 'Total', usedPercent: 10),
      ]),
    ];

    test('default puts configured providers first', () {
      final ordered = orderedLimitProviders(providers);
      expect(ordered.map((p) => p.provider), ['codex', 'cursor', 'copilot']);
    });

    test('saved order is respected', () {
      final key = limitEntryKey(providers[2]);
      final ordered = orderedLimitProviders(providers, savedOrder: [key]);
      expect(ordered.first.provider, 'cursor');
    });
  });

  group('limitWindowLabel', () {
    test('uses wire label when present', () {
      const w = LimitsWindow(kind: 'billing', label: 'Total');
      expect(limitWindowLabel(w), 'Total');
    });

    test('session 300 minutes becomes 5 小时', () {
      const w = LimitsWindow(kind: 'session', windowMinutes: 300);
      expect(limitWindowLabel(w), '5 小时');
    });
  });

  group('limitWindowResetText', () {
    test('falls back to resetDescription', () {
      const w = LimitsWindow(resetDescription: 'Cursor Pro');
      expect(limitWindowResetText(w), 'Cursor Pro');
    });

    test('session window without resetsAt shows rolling window hint', () {
      const w = LimitsWindow(kind: 'session', windowMinutes: 300);
      expect(limitWindowResetText(w), '5 小时滚动窗口');
    });
  });

  group('limitProviderPlanText', () {
    test('uses planLabel with capitalized display', () {
      const p = LimitsProvider(provider: 'codex', status: 'ok', planLabel: 'plus');
      expect(limitProviderPlanText(p), 'Plus');
    });

    test('falls back to accountLabel', () {
      const p = LimitsProvider(provider: 'claude', status: 'ok', accountLabel: 'max');
      expect(limitProviderPlanText(p), 'Max');
    });

    test('not ok status shows status label', () {
      const p = LimitsProvider(provider: 'cursor', status: 'notConfigured');
      expect(limitProviderPlanText(p), '请登录');
    });

    test('thirdparty maps known plan labels', () {
      const p = LimitsProvider(provider: 'thirdparty', status: 'ok', planLabel: 'api key');
      expect(limitProviderPlanText(p), 'API key');
    });

    test('cursor reads membership from accountLabel not account line', () {
      const p = LimitsProvider(
        provider: 'cursor',
        status: 'ok',
        accountLabel: 'Express',
        windows: const [LimitsWindow(kind: 'billing', label: 'Total', usedPercent: 26)],
      );
      expect(limitProviderPlanText(p), 'Express');
      expect(limitAccountLine(p), '—');
    });

    test('cursor falls back to resetDescription', () {
      const p = LimitsProvider(
        provider: 'cursor',
        status: 'ok',
        windows: const [
          LimitsWindow(
            kind: 'billing',
            label: 'Total',
            usedPercent: 10,
            resetDescription: 'Cursor express',
          ),
        ],
      );
      expect(limitProviderPlanText(p), 'Express');
    });
  });

  group('limitHome presentation', () {
    test('limitHomeWindowValue shows remaining percent', () {
      const w = LimitsWindow(kind: 'weekly', usedPercent: 97);
      expect(limitHomeWindowValue(w), '剩余 3%');
    });

    test('sortedLimitWindows orders session before weekly before billing', () {
      const windows = [
        LimitsWindow(kind: 'billing', label: 'Total'),
        LimitsWindow(kind: 'weekly', label: 'Weekly'),
        LimitsWindow(kind: 'session', label: 'Auto'),
      ];
      final sorted = sortedLimitWindows(windows);
      expect(sorted.map((w) => w.kind), ['session', 'weekly', 'billing']);
    });

    test('limitHomeResetText uses compact rolling hint for session windows', () {
      const w = LimitsWindow(kind: 'session', windowMinutes: 300);
      expect(limitHomeResetText(w), '5 小时滚动');
    });

    test('limitHomeWindows keeps at most two windows by priority', () {
      const windows = [
        LimitsWindow(kind: 'billing', label: 'Total', usedPercent: 10),
        LimitsWindow(kind: 'session', label: 'Auto', usedPercent: 14),
        LimitsWindow(kind: 'billing', label: 'API', usedPercent: 0),
        LimitsWindow(kind: 'billing', label: 'Credits', usedPercent: 0, metric: 'credits'),
      ];
      final home = limitHomeWindows(windows);
      expect(home.length, 2);
      expect(home.map((w) => w.label), ['Auto', 'Total']);
    });
  });
}
