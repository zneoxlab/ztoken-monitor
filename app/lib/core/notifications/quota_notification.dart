import '../limits/limit_presentation.dart';
import '../limits/limit_provider_order.dart';
import '../models/stats.dart';
import '../network/auth_mode.dart';

enum QuotaNotificationKind { low, refreshed }

/// SaaS 由服务端状态机投递；只有自建 Hub 保留移动端本地差分作为回退。
bool usesLocalQuotaNotificationFallback(AuthMode mode) =>
    mode == AuthMode.selfHosted;

class QuotaNotificationEvent {
  const QuotaNotificationEvent({
    required this.kind,
    required this.providerName,
    required this.windowLabel,
    required this.remainingPercent,
  });

  final QuotaNotificationKind kind;
  final String providerName;
  final String windowLabel;
  final int remainingPercent;
}

// 只在已有基线的配额发生“进入低额度”或“首次刷新到 100%”时提醒。
// 首次拉取只建立基线,避免登录/启动时把当前状态误报成刷新。
List<QuotaNotificationEvent> detectQuotaNotificationEvents({
  required LimitsAgg? previous,
  required LimitsAgg? current,
  required int thresholdPercent,
}) {
  if (previous == null || current == null) return const [];

  final threshold = thresholdPercent.clamp(1, 100);
  final previousProviders = {
    for (final provider in previous.providers)
      limitEntryKey(provider): provider,
  };
  final events = <QuotaNotificationEvent>[];

  for (final provider in current.providers) {
    final status = provider.status.trim().toLowerCase();
    if (status == 'notconfigured' || status == 'disabled') continue;

    final oldProvider = previousProviders[limitEntryKey(provider)];
    if (oldProvider == null) continue;
    final oldWindows = {
      for (final window in oldProvider.windows) _windowKey(window): window,
    };

    for (final window in provider.windows) {
      final currentRemaining = _remainingPercent(window);
      final oldWindow = oldWindows[_windowKey(window)];
      final oldRemaining = oldWindow == null
          ? null
          : _remainingPercent(oldWindow);
      if (currentRemaining == null || oldRemaining == null) continue;

      if (currentRemaining <= threshold && oldRemaining > threshold) {
        events.add(
          QuotaNotificationEvent(
            kind: QuotaNotificationKind.low,
            providerName: limitProviderDisplayName(provider.provider),
            windowLabel: limitWindowLabel(window),
            remainingPercent: currentRemaining,
          ),
        );
      } else if (oldRemaining < 100 && currentRemaining == 100) {
        events.add(
          QuotaNotificationEvent(
            kind: QuotaNotificationKind.refreshed,
            providerName: limitProviderDisplayName(provider.provider),
            windowLabel: limitWindowLabel(window),
            remainingPercent: currentRemaining,
          ),
        );
      }
    }
  }
  return events;
}

String quotaNotificationTitle(QuotaNotificationKind kind) {
  return switch (kind) {
    QuotaNotificationKind.low => '配额接近上限',
    QuotaNotificationKind.refreshed => '配额已刷新',
  };
}

String quotaNotificationBody(Iterable<QuotaNotificationEvent> events) {
  final items = events.toList();
  if (items.isEmpty) return '';
  final visible = items
      .take(3)
      .map((event) {
        return '${event.providerName} ${event.windowLabel} · 剩余 ${event.remainingPercent}%';
      })
      .join('、');
  final omitted = items.length - 3;
  return omitted > 0 ? '$visible 等 $omitted 项' : visible;
}

String _windowKey(LimitsWindow window) {
  final label = (window.label ?? window.title ?? '').trim().toLowerCase();
  return '${window.kind.trim().toLowerCase()}|$label|${window.windowMinutes ?? ''}';
}

int? _remainingPercent(LimitsWindow window) {
  // credits/spend 是金额口径,阈值通知只针对百分比配额,避免把金额误当百分比。
  if (window.isCredits || window.isSpend) return null;
  if (!limitHomeWindowHasData(window)) return null;
  return limitWindowRemainingPercent(window).clamp(0, 100);
}
