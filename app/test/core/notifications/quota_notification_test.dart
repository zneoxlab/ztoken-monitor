import 'package:flutter_test/flutter_test.dart';
import 'package:ztoken_monitor/core/models/stats.dart';
import 'package:ztoken_monitor/core/network/auth_mode.dart';
import 'package:ztoken_monitor/core/notifications/quota_notification.dart';

void main() {
  test('SaaS 不走本地差分通知，避免与服务端推送重复', () {
    expect(usesLocalQuotaNotificationFallback(AuthMode.saas), isFalse);
    expect(usesLocalQuotaNotificationFallback(AuthMode.selfHosted), isTrue);
  });

  test('首次快照只建立基线,不发送通知', () {
    final events = detectQuotaNotificationEvents(
      previous: null,
      current: _limits(usedPercent: 95),
      thresholdPercent: 80,
    );

    expect(events, isEmpty);
  });

  test('额度从阈值之上跌到阈值以内时提醒一次', () {
    final events = detectQuotaNotificationEvents(
      previous: _limits(usedPercent: 10),
      current: _limits(usedPercent: 85),
      thresholdPercent: 80,
    );

    expect(events, hasLength(1));
    expect(events.single.kind, QuotaNotificationKind.low);
    expect(events.single.providerName, 'Codex');
    expect(events.single.windowLabel, '每周');
    expect(events.single.remainingPercent, 15);
    expect(quotaNotificationTitle(events.single.kind), '配额接近上限');
  });

  test('同一低额度快照不重复提醒，只有刷新到 100% 才发送刷新通知', () {
    final low = _limits(usedPercent: 85);
    expect(
      detectQuotaNotificationEvents(
        previous: low,
        current: low,
        thresholdPercent: 80,
      ),
      isEmpty,
    );

    final recoveredButNotReset = detectQuotaNotificationEvents(
      previous: low,
      current: _limits(usedPercent: 10),
      thresholdPercent: 80,
    );
    expect(recoveredButNotReset, isEmpty);

    final refreshed = detectQuotaNotificationEvents(
      previous: _limits(usedPercent: 10),
      current: _limits(usedPercent: 0),
      thresholdPercent: 80,
    );
    expect(refreshed, hasLength(1));
    expect(refreshed.single.kind, QuotaNotificationKind.refreshed);
    expect(refreshed.single.remainingPercent, 100);
    expect(quotaNotificationBody(refreshed), 'Codex 每周 · 剩余 100%');
  });

  test('金额型 credits 和 spend 不参与百分比阈值通知', () {
    final previous = LimitsAgg(
      providers: [
        _provider(
          windows: const [
            LimitsWindow(kind: 'billing', metric: 'credits', remaining: 20),
            LimitsWindow(kind: 'billing', metric: 'spend', used: 1, limit: 10),
          ],
        ),
      ],
    );
    final current = LimitsAgg(
      providers: [
        _provider(
          windows: const [
            LimitsWindow(kind: 'billing', metric: 'credits', remaining: 0),
            LimitsWindow(kind: 'billing', metric: 'spend', used: 10, limit: 10),
          ],
        ),
      ],
    );

    expect(
      detectQuotaNotificationEvents(
        previous: previous,
        current: current,
        thresholdPercent: 80,
      ),
      isEmpty,
    );
  });
}

LimitsAgg _limits({required int usedPercent}) {
  return LimitsAgg(
    providers: [
      _provider(
        windows: [
          LimitsWindow(kind: 'weekly', label: '每周', usedPercent: usedPercent),
        ],
      ),
    ],
  );
}

LimitsProvider _provider({required List<LimitsWindow> windows}) {
  return LimitsProvider(
    provider: 'codex',
    status: 'ok',
    accountKey: 'account',
    windows: windows,
  );
}
