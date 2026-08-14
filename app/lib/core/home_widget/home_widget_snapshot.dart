import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/theme_mode.dart';
import '../format/formatters.dart';
import '../limits/limit_display_mode.dart';
import '../limits/limit_presentation.dart';
import '../limits/limit_provider_order.dart';
import '../models/stats.dart';
import '../storage/prefs_storage.dart';

enum HomeWidgetState { disconnected, loading, ready, error }

enum HomeWidgetQuotaTone { normal, low, critical }

@immutable
class HomeWidgetQuotaItem {
  const HomeWidgetQuotaItem({
    required this.entryKey,
    required this.providerId,
    required this.iconId,
    required this.providerName,
    required this.windowLabel,
    required this.value,
    required this.resetText,
    required this.tone,
    required this.meterPercent,
    required this.showMeter,
  });

  final String entryKey;
  final String providerId;
  final String iconId;
  final String providerName;
  final String windowLabel;
  final String value;
  final String resetText;
  final HomeWidgetQuotaTone tone;
  final int meterPercent;
  final bool showMeter;

  Map<String, Object?> toChannelMap() => {
    'entryKey': entryKey,
    'providerId': providerId,
    'iconId': iconId,
    'providerName': providerName,
    'windowLabel': windowLabel,
    'value': value,
    'resetText': resetText,
    'tone': tone.name,
    'meterPercent': meterPercent,
    'showMeter': showMeter,
  };
}

@immutable
class HomeWidgetSnapshot {
  const HomeWidgetSnapshot({
    required this.state,
    required this.theme,
    this.hasUsage = false,
    this.periodLabel = '本月',
    this.tokens = '0',
    this.cost = '',
    this.usageUpdatedAtMs = 0,
    this.usageStale = false,
    this.limitsUpdatedAtMs = 0,
    this.limitsStale = false,
    this.quotas = const [],
  });

  final HomeWidgetState state;
  final String theme;
  final bool hasUsage;
  final String periodLabel;
  final String tokens;
  final String cost;
  final int usageUpdatedAtMs;
  final bool usageStale;
  final int limitsUpdatedAtMs;
  final bool limitsStale;
  final List<HomeWidgetQuotaItem> quotas;

  Map<String, Object?> toChannelMap() => {
    'state': state.name,
    'theme': theme,
    'hasUsage': hasUsage,
    'periodLabel': periodLabel,
    'tokens': tokens,
    'cost': cost,
    'usageUpdatedAtMs': usageUpdatedAtMs,
    'usageStale': usageStale,
    'limitsUpdatedAtMs': limitsUpdatedAtMs,
    'limitsStale': limitsStale,
    'quotas': quotas.map((e) => e.toChannelMap()).toList(),
  };
}

HomeWidgetSnapshot buildHomeWidgetSnapshot({
  required bool isAuthenticated,
  required AsyncValue<StatsSnapshot> stats,
  required AppSettings settings,
  required Brightness platformBrightness,
  DateTime? now,
}) {
  final theme = _widgetTheme(settings.themeMode, platformBrightness);
  if (!isAuthenticated) {
    return HomeWidgetSnapshot(
      state: HomeWidgetState.disconnected,
      theme: theme,
    );
  }

  if (stats.isLoading) {
    return HomeWidgetSnapshot(state: HomeWidgetState.loading, theme: theme);
  }
  if (stats.hasError || !stats.hasValue) {
    return HomeWidgetSnapshot(state: HomeWidgetState.error, theme: theme);
  }

  final snapshot = stats.requireValue;
  final current = now ?? DateTime.now();
  final month = snapshot.periods?.month;
  final latestUsage = _latestDate(snapshot.devices.map((d) => d.updatedAt));
  final hasUsage =
      month != null &&
      (month.totalTokens > 0 ||
          month.costUsd != 0 ||
          snapshot.devices.isNotEmpty);
  final limitsUpdated = _limitsUpdatedAt(snapshot.limits);
  final limitsStale =
      limitsUpdated != null &&
      current.difference(limitsUpdated).inMilliseconds > snapshot.staleAfterMs;

  return HomeWidgetSnapshot(
    state: HomeWidgetState.ready,
    theme: theme,
    hasUsage: hasUsage,
    tokens: hasUsage ? formatTokensCompact(month.totalTokens) : '0',
    cost: hasUsage ? formatMoney(month.costUsd, settings.displayCurrency) : '',
    usageUpdatedAtMs: latestUsage?.millisecondsSinceEpoch ?? 0,
    usageStale:
        snapshot.devices.isNotEmpty &&
        snapshot.devices.every((device) => device.stale),
    limitsUpdatedAtMs: limitsUpdated?.millisecondsSinceEpoch ?? 0,
    limitsStale: limitsStale,
    quotas: selectHomeWidgetQuotaItems(
      snapshot.limits,
      pinnedEntries: parseLimitProviderOrder(settings.homeWidgetPinnedLimits),
      savedProviderOrder: parseLimitProviderOrder(settings.limitProviderOrder),
      displayMode: settings.limitDisplayMode,
      now: current,
    ),
  );
}

List<HomeWidgetQuotaItem> selectHomeWidgetQuotaItems(
  LimitsAgg? limits, {
  List<String> pinnedEntries = const [],
  List<String> savedProviderOrder = const [],
  LimitDisplayMode displayMode = LimitDisplayMode.remaining,
  DateTime? now,
}) {
  if (limits == null || limits.providers.isEmpty) return const [];
  final current = now ?? DateTime.now();
  final providers = orderedLimitProviders(
    limits.providers,
    savedOrder: savedProviderOrder,
  ).where(isConfiguredLimitProvider).toList();
  final providerOrder = <String, int>{
    for (var i = 0; i < providers.length; i++) limitEntryKey(providers[i]): i,
  };
  final providerCounts = <String, int>{};
  for (final provider in providers) {
    final id = provider.provider.trim().toLowerCase();
    providerCounts[id] = (providerCounts[id] ?? 0) + 1;
  }

  final candidates = <_QuotaCandidate>[];
  for (final provider in providers) {
    final candidate = _quotaCandidate(
      provider,
      duplicateProvider:
          (providerCounts[provider.provider.trim().toLowerCase()] ?? 0) > 1,
      providerOrder: providerOrder[limitEntryKey(provider)] ?? 1 << 20,
      displayMode: displayMode,
      now: current,
    );
    if (candidate != null) candidates.add(candidate);
  }
  if (candidates.isEmpty) return const [];

  candidates.sort(_compareQuotaCandidates);
  final byKey = {
    for (final candidate in candidates) candidate.item.entryKey: candidate,
  };
  final selected = <_QuotaCandidate>[];
  final seen = <String>{};
  for (final key in pinnedEntries) {
    final candidate = byKey[key];
    if (candidate == null || !seen.add(key)) continue;
    selected.add(candidate);
    if (selected.length == 2) break;
  }
  for (final candidate in candidates) {
    if (selected.length == 2) break;
    if (!seen.add(candidate.item.entryKey)) continue;
    selected.add(candidate);
  }
  return selected.map((candidate) => candidate.item).toList();
}

class _QuotaCandidate {
  const _QuotaCandidate({
    required this.item,
    required this.severity,
    required this.remaining,
    required this.providerOrder,
  });

  final HomeWidgetQuotaItem item;
  final int severity;
  final int remaining;
  final int providerOrder;
}

_QuotaCandidate? _quotaCandidate(
  LimitsProvider provider, {
  required bool duplicateProvider,
  required int providerOrder,
  required LimitDisplayMode displayMode,
  required DateTime now,
}) {
  final statusSeverity = _statusSeverity(provider.status);
  final windows = provider.windows.where(limitHomeWindowHasData).toList()
    ..sort(_compareWindowsByUrgency);
  final window = windows.isEmpty ? null : windows.first;
  if (window == null && statusSeverity >= 2) return null;

  final entryKey = limitEntryKey(provider);
  final statusAbnormal = statusSeverity < 2;
  final tone = statusAbnormal
      ? (statusSeverity == 0
            ? HomeWidgetQuotaTone.critical
            : HomeWidgetQuotaTone.low)
      : _quotaTone(window!);
  final windowLabel = window == null ? '状态' : limitWindowLabel(window);
  final accountLine = duplicateProvider ? limitAccountLine(provider) : '';
  final detailLabel = accountLine.isEmpty || accountLine == '—'
      ? windowLabel
      : '$windowLabel · $accountLine';
  final remaining = window == null ? 0 : _windowRemaining(window);

  return _QuotaCandidate(
    severity: statusAbnormal ? statusSeverity : _toneSeverity(tone),
    remaining: remaining,
    providerOrder: providerOrder,
    item: HomeWidgetQuotaItem(
      entryKey: entryKey,
      providerId: provider.provider.trim().toLowerCase(),
      iconId: _providerIconId(provider.provider),
      providerName: limitProviderDisplayName(provider.provider),
      windowLabel: detailLabel,
      value: statusAbnormal
          ? limitStatusLabel(provider)
          : _widgetWindowValue(window!, displayMode),
      resetText: statusAbnormal || window == null
          ? ''
          : limitHomeResetText(window, now: now),
      tone: tone,
      meterPercent: statusAbnormal || window == null
          ? 0
          : limitWindowMeterPercent(window).clamp(0, 100),
      showMeter:
          !statusAbnormal &&
          window != null &&
          limitWindowShouldShowMeter(window),
    ),
  );
}

int _compareQuotaCandidates(_QuotaCandidate a, _QuotaCandidate b) {
  final severity = a.severity.compareTo(b.severity);
  if (severity != 0) return severity;
  final remaining = a.remaining.compareTo(b.remaining);
  if (remaining != 0) return remaining;
  return a.providerOrder.compareTo(b.providerOrder);
}

int _compareWindowsByUrgency(LimitsWindow a, LimitsWindow b) {
  final aTone = _toneSeverity(_quotaTone(a));
  final bTone = _toneSeverity(_quotaTone(b));
  final tone = aTone.compareTo(bTone);
  if (tone != 0) return tone;
  final remaining = _windowRemaining(a).compareTo(_windowRemaining(b));
  if (remaining != 0) return remaining;
  return limitWindowSortKey(a).compareTo(limitWindowSortKey(b));
}

int _windowRemaining(LimitsWindow window) {
  if (window.isCredits) return 101;
  if (window.isSpend &&
      window.limit != null &&
      window.limit! > 0 &&
      window.used != null) {
    return (100 - limitWindowMeterPercent(window)).clamp(0, 100);
  }
  return limitWindowRemainingPercent(window);
}

HomeWidgetQuotaTone _quotaTone(LimitsWindow window) {
  return switch (limitHomeValueTone(window)) {
    LimitHomeValueTone.normal => HomeWidgetQuotaTone.normal,
    LimitHomeValueTone.low => HomeWidgetQuotaTone.low,
    LimitHomeValueTone.critical => HomeWidgetQuotaTone.critical,
  };
}

int _toneSeverity(HomeWidgetQuotaTone tone) => switch (tone) {
  HomeWidgetQuotaTone.critical => 0,
  HomeWidgetQuotaTone.low => 1,
  HomeWidgetQuotaTone.normal => 2,
};

int _statusSeverity(String raw) {
  return switch (raw.trim().toLowerCase()) {
    'exceeded' || 'error' || 'unauthorized' || 'unavailable' => 0,
    'warning' || 'ratelimited' || 'sourceratelimited' || 'unknown' => 1,
    _ => 2,
  };
}

String _widgetWindowValue(LimitsWindow window, LimitDisplayMode displayMode) {
  if (window.isCredits) return '余额 ${limitWindowValueText(window)}';
  return limitHomeWindowValue(window, displayMode: displayMode);
}

String _providerIconId(String raw) {
  return switch (raw.trim().toLowerCase()) {
    'mimo' => 'mimo-code',
    'zai' || 'zaiteam' => 'zcode',
    final id when id.isNotEmpty => id,
    _ => 'app',
  };
}

DateTime? _limitsUpdatedAt(LimitsAgg? limits) {
  if (limits == null) return null;
  final aggregate = DateTime.tryParse(limits.updatedAt);
  if (aggregate != null) return aggregate;
  return _latestDate(
    limits.providers.map((provider) => provider.updatedAt ?? ''),
  );
}

DateTime? _latestDate(Iterable<String> values) {
  DateTime? latest;
  for (final value in values) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null && (latest == null || parsed.isAfter(latest))) {
      latest = parsed;
    }
  }
  return latest;
}

String _widgetTheme(AppThemeMode mode, Brightness brightness) {
  return switch (mode) {
    AppThemeMode.system =>
      brightness == Brightness.light ? 'porcelain' : 'graphiteMint',
    AppThemeMode.graphiteMint => 'graphiteMint',
    AppThemeMode.starryBlue => 'starryBlue',
    AppThemeMode.obsidian => 'obsidian',
    AppThemeMode.porcelain => 'porcelain',
  };
}
