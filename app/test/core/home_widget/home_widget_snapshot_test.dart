import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ztoken_monitor/core/format/formatters.dart';
import 'package:ztoken_monitor/core/home_widget/home_widget_snapshot.dart';
import 'package:ztoken_monitor/core/limits/limit_display_mode.dart';
import 'package:ztoken_monitor/core/models/stats.dart';
import 'package:ztoken_monitor/core/storage/prefs_storage.dart';
import 'package:ztoken_monitor/theme/theme_mode.dart';

void main() {
  final now = DateTime.utc(2026, 8, 10, 12);

  test('未认证时清空桌面数据并显示连接态', () {
    final result = buildHomeWidgetSnapshot(
      isAuthenticated: false,
      stats: const AsyncValue.loading(),
      settings: const AppSettings(),
      platformBrightness: Brightness.dark,
      now: now,
    );

    expect(result.state, HomeWidgetState.disconnected);
    expect(result.quotas, isEmpty);
    expect(result.theme, 'graphiteMint');
  });

  test('本月用量跟随显示货币且用量与额度分别记录时间', () {
    final stats = StatsSnapshot(
      periods: const Periods(
        month: Period(totalTokens: 1260873697, costUsd: 212.60),
      ),
      devices: [
        DeviceRecord(
          deviceId: 'mac',
          updatedAt: now.subtract(const Duration(minutes: 4)).toIso8601String(),
        ),
      ],
      limits: LimitsAgg(
        updatedAt: now.subtract(const Duration(minutes: 1)).toIso8601String(),
      ),
    );
    final result = buildHomeWidgetSnapshot(
      isAuthenticated: true,
      stats: AsyncValue.data(stats),
      settings: const AppSettings(
        themeMode: AppThemeMode.starryBlue,
        displayCurrency: DisplayCurrency.cny,
      ),
      platformBrightness: Brightness.dark,
      now: now,
    );

    expect(result.state, HomeWidgetState.ready);
    expect(result.tokens, '1.26B');
    expect(result.cost, '¥1526.47');
    expect(result.usageUpdatedAtMs, isNot(result.limitsUpdatedAtMs));
    expect(result.theme, 'starryBlue');
  });

  test('智能选择最紧急的两个账户而不是固定厂商顺序', () {
    final limits = LimitsAgg(
      providers: [
        _provider('codex', 'codex-account', usedPercent: 53),
        _provider('cursor', 'cursor-account', usedPercent: 58),
        _provider('opencode', 'opencode-account', usedPercent: 100),
      ],
    );

    final items = selectHomeWidgetQuotaItems(limits, now: now);

    expect(items.map((item) => item.providerId), ['opencode', 'cursor']);
    expect(items.first.value, '剩余 0%');
    expect(items.first.tone, HomeWidgetQuotaTone.critical);
    expect(items.first.meterPercent, 100);
  });

  test('固定账户优先展示并用智能项补足第二行', () {
    final limits = LimitsAgg(
      providers: [
        _provider('codex', 'codex-account', usedPercent: 53),
        _provider('cursor', 'cursor-account', usedPercent: 58),
        _provider('opencode', 'opencode-account', usedPercent: 100),
      ],
    );

    final items = selectHomeWidgetQuotaItems(
      limits,
      pinnedEntries: const ['codex|codex-account'],
      now: now,
    );

    expect(items.map((item) => item.providerId), ['codex', 'opencode']);
  });

  test('小组件配额文案支持已用模式,进度条继续表示已用填充', () {
    final limits = LimitsAgg(
      providers: [_provider('codex', 'codex-account', usedPercent: 53)],
    );

    final item = selectHomeWidgetQuotaItems(
      limits,
      displayMode: LimitDisplayMode.used,
      now: now,
    ).single;

    expect(item.value, '已用 53%');
    expect(item.meterPercent, 53);
  });

  test('余额型额度显示金额语义且不绘制百分比进度条', () {
    final limits = LimitsAgg(
      providers: [
        LimitsProvider(
          provider: 'claude',
          status: 'ok',
          accountKey: 'credit-account',
          windows: const [
            LimitsWindow(
              kind: 'billing',
              label: 'Credits',
              metric: 'credits',
              remaining: 23.4,
              currency: 'USD',
            ),
          ],
        ),
      ],
    );

    final item = selectHomeWidgetQuotaItems(limits, now: now).single;

    expect(item.value, '余额 23.40 USD');
    expect(item.showMeter, false);
    expect(item.tone, HomeWidgetQuotaTone.normal);
  });

  test('已认证但首次拉取失败时显示错误态而不是伪造零数据', () {
    final result = buildHomeWidgetSnapshot(
      isAuthenticated: true,
      stats: AsyncValue.error('offline', StackTrace.empty),
      settings: const AppSettings(),
      platformBrightness: Brightness.dark,
      now: now,
    );

    expect(result.state, HomeWidgetState.error);
    expect(result.hasUsage, false);
  });
}

LimitsProvider _provider(
  String id,
  String accountKey, {
  required int usedPercent,
}) {
  return LimitsProvider(
    provider: id,
    status: 'ok',
    accountKey: accountKey,
    windows: [
      LimitsWindow(
        kind: 'weekly',
        label: '每周',
        usedPercent: usedPercent,
        resetsAt: '2026-08-16T07:00:00Z',
      ),
    ],
  );
}
