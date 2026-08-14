import '../format/formatters.dart';
import '../models/stats.dart';
import 'limit_display_mode.dart';

bool isConfiguredLimitProvider(LimitsProvider provider) {
  final status = provider.status.trim().toLowerCase();
  final hasKey = (provider.accountKey ?? '').isNotEmpty;
  return hasKey && status != 'notconfigured' && status != 'disabled';
}

String limitProviderDisplayName(String id) {
  const labels = {
    'claude': 'Claude',
    'codex': 'Codex',
    'cursor': 'Cursor',
    'copilot': 'Copilot',
    'deepseek': 'DeepSeek',
    'antigravity': 'Antigravity',
    'opencode': 'OpenCode',
    'kimi': 'Kimi',
    'qwen': 'Qwen',
    'openrouter': 'OpenRouter',
    'minimax': 'MiniMax',
    'mimo': 'MiMo',
    'grok': 'Grok',
    'kiro': 'Kiro',
    'zai': 'Z.ai',
    'zaiteam': 'Z.ai Team',
    'volcengine': '火山引擎',
    'qoder': 'Qoder',
    'ollama': 'Ollama',
    'thirdparty': '第三方',
  };
  if (id.isEmpty) return '?';
  return labels[id] ?? id[0].toUpperCase() + id.substring(1);
}

String limitAccountLine(LimitsProvider provider) {
  final name = provider.accountName;
  if (name != null && name.isNotEmpty) return name;
  final email = provider.accountEmail;
  if (email != null && email.isNotEmpty) return maskLimitEmail(email);
  // accountLabel 是套餐名(Plus/Express),对照桌面 accountTitleLabel 不放在账户行。
  return '—';
}

// 对照桌面 limitProviderDisplayLabel:首字母大写,邮箱原样保留。
String limitProviderDisplayLabel(String value) {
  final label = value.trim();
  if (label.isEmpty || label.contains('@')) return label;
  return label[0].toUpperCase() + label.substring(1);
}

String _cursorPlanFromWindows(List<LimitsWindow> windows) {
  for (final window in windows) {
    final desc = (window.resetDescription ?? '').trim();
    final lower = desc.toLowerCase();
    if (lower.startsWith('cursor ')) {
      final raw = desc.substring(7).trim().replaceAll('_', ' ');
      if (raw.isNotEmpty) return limitProviderDisplayLabel(raw);
    }
  }
  return '';
}

// 对照桌面 limitProviderPlan + thirdPartyPlanText,配额行右侧套餐/状态文案。
String limitProviderPlanText(LimitsProvider provider) {
  final status = provider.status.trim().toLowerCase();
  if (status.isNotEmpty && status != 'ok') {
    return limitStatusLabel(provider);
  }
  final id = provider.provider.trim().toLowerCase();
  if (id == 'thirdparty') {
    final plan = (provider.planLabel ?? '').trim().toLowerCase();
    if (plan == 'account') return 'Account';
    if (plan == 'api key') return 'API key';
    if (plan == 'custom') return 'Custom';
    return '';
  }
  final explicit = (provider.planLabel ?? provider.accountLabel ?? '').trim();
  if (explicit.isNotEmpty) return limitProviderDisplayLabel(explicit);

  final name = (provider.accountName ?? '').trim();
  if (name.isNotEmpty && !name.contains('@')) {
    return limitProviderDisplayLabel(name);
  }
  if (id == 'cursor') {
    final fromWindow = _cursorPlanFromWindows(provider.windows);
    if (fromWindow.isNotEmpty) return fromWindow;
  }
  return '';
}

String limitProviderMetaLine(LimitsProvider provider) {
  final parts = <String>[];
  final updated = formatLimitUpdatedAge(provider.updatedAt);
  if (updated.isNotEmpty) parts.add(updated);
  final source = limitSourceLabel(
    provider.source,
    providerId: provider.provider,
  );
  if (source.isNotEmpty) parts.add(source);
  return parts.join(' · ');
}

String maskLimitEmail(String email) {
  final at = email.indexOf('@');
  if (at <= 1) return email;
  return '${email[0]}***${email.substring(at)}';
}

String limitSourceLabel(String? source, {String providerId = ''}) {
  const common = {
    'oauth': 'OAuth',
    'cli': 'CLI',
    'web': 'Web',
    'rpc': 'RPC',
    'local': '本地',
    'api': 'API',
  };
  return common[source?.toLowerCase()] ?? source ?? '';
}

String limitStatusLabel(LimitsProvider provider) {
  final id = provider.provider.trim().toLowerCase();
  final status = provider.status.trim().toLowerCase();
  if (status == 'ok') {
    if (id == 'cursor' ||
        id == 'claude' ||
        id == 'copilot' ||
        id == 'opencode' ||
        id == 'mimo') {
      return '已连接';
    }
    return '正常';
  }
  if (status == 'notconfigured') {
    if (id == 'cursor' || id == 'copilot' || id == 'qoder' || id == 'ollama') {
      return '请登录';
    }
    if (id == 'antigravity') return '请打开应用';
    return '未配置';
  }
  if (status == 'noSyncedData') return '无同步数据';
  if (status == 'unauthorized') return '请重新登录';
  if (status == 'rateLimited' || status == 'sourceRateLimited') return '受限';
  if (status == 'unavailable') return '不可用';
  const labels = {
    'warning': '警告',
    'exceeded': '已超限',
    'unknown': '未知',
    'error': '错误',
    'disabled': '已禁用',
  };
  return labels[status] ?? status;
}

String limitStatusDetail(String status) {
  switch (status.trim().toLowerCase()) {
    case 'exceeded':
      return '该账户已超出配额,请检查厂商控制台。';
    case 'warning':
      return '该账户配额接近上限。';
    case 'error':
    case 'unauthorized':
      return '凭证可能失效,请在桌面端重新登录该工具。';
    case 'notconfigured':
      return '在桌面端配置并同步后,这里会显示配额。';
    case 'noSyncedData':
      return '暂无设备同步该账户的配额数据。';
    default:
      return '配额状态异常。';
  }
}

String limitWindowLabel(LimitsWindow window) {
  final label = window.label?.trim();
  if (label != null && label.isNotEmpty) return label;
  final title = window.title?.trim();
  if (title != null && title.isNotEmpty) return title;

  final minutes = window.windowMinutes;
  if (window.kind == 'session' && minutes == 300) return '5 小时';
  if (window.kind == 'session' && minutes != null && minutes > 0) {
    if (minutes % 60 == 0 && minutes >= 60) return '${minutes ~/ 60} 小时';
    return '$minutes 分钟';
  }

  const kindLabels = {
    'session': '会话窗口',
    'weekly': '每周',
    'daily': '每日',
    'monthly': '每月',
    'billing': '计费周期',
  };
  return kindLabels[window.kind] ?? window.kind;
}

int? limitResetRemainingMs(String iso, {DateTime? now}) {
  if (iso.isEmpty) return null;
  final reset = DateTime.tryParse(iso);
  final current = now ?? DateTime.now();
  if (reset == null) return null;
  final remaining = reset.difference(current).inMilliseconds;
  if (remaining > 0) return remaining;
  // 60s 宽限内视为即将重置(对照桌面 limitResetRemainingMs)。
  return remaining >= -60000 ? 0 : null;
}

String formatLimitDurationZh(int ms) {
  final totalMinutes = (ms / 60000).round().clamp(0, 1 << 30);
  final days = totalMinutes ~/ 1440;
  final hours = (totalMinutes % 1440) ~/ 60;
  final minutes = totalMinutes % 60;
  if (days > 0) return '$days天 $hours小时';
  if (hours > 0) return '$hours小时 $minutes分';
  if (minutes > 0) return '$minutes分';
  return '不足 1 分';
}

String limitWindowResetText(LimitsWindow window, {DateTime? now}) {
  final remainingMs = limitResetRemainingMs(window.resetsAt, now: now);
  if (remainingMs != null) {
    if (remainingMs == 0) return '即将重置';
    final resetAt = DateTime.tryParse(window.resetsAt);
    if (resetAt != null) {
      final current = now ?? DateTime.now();
      final isToday =
          resetAt.year == current.year &&
          resetAt.month == current.month &&
          resetAt.day == current.day;
      final left = '还有 ${formatLimitDurationZh(remainingMs)}';
      if (isToday) {
        final hh = resetAt.hour.toString().padLeft(2, '0');
        final mm = resetAt.minute.toString().padLeft(2, '0');
        return '$hh:$mm 重置 · $left';
      }
      return '${formatDateShort(resetAt)} · $left';
    }
    return '还有 ${formatLimitDurationZh(remainingMs)}';
  }

  final desc = window.resetDescription?.trim();
  if (desc != null && desc.isNotEmpty) return desc;

  final minutes = window.windowMinutes;
  if (minutes != null && minutes > 0 && window.kind == 'session') {
    if (minutes == 300) return '5 小时滚动窗口';
    if (minutes % 60 == 0 && minutes >= 60) return '${minutes ~/ 60} 小时滚动窗口';
    return '$minutes 分钟滚动窗口';
  }
  return '';
}

String formatLimitUpdatedAge(String? iso, {DateTime? now}) {
  if (iso == null || iso.isEmpty) return '';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  final diff = (now ?? DateTime.now()).difference(dt);
  if (diff.inSeconds < 45) return '刚刚更新';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前更新';
  if (diff.inHours < 24) return '${diff.inHours} 小时前更新';
  return '${formatDateShort(dt)} 更新';
}

String limitHomeAccountTitle(LimitsProvider provider) {
  return limitProviderDisplayName(provider.provider);
}

int limitWindowSortKey(LimitsWindow window) {
  const priority = {'session': 0, 'weekly': 1, 'billing': 2, 'monthly': 3};
  return priority[window.kind] ?? 10;
}

List<LimitsWindow> sortedLimitWindows(List<LimitsWindow> windows) {
  final copy = windows.toList()
    ..sort((a, b) => limitWindowSortKey(a).compareTo(limitWindowSortKey(b)));
  return copy;
}

// 首页配额窗口:对照桌面 homeLimitAccounts,按优先级排序后最多 2 个(Cursor 仅 Total+Auto)。
bool limitHomeWindowHasData(LimitsWindow window) {
  if (window.isCredits) {
    return window.remaining != null ||
        (window.detail?.trim().isNotEmpty ?? false);
  }
  if (window.isSpend) return window.used != null || window.limit != null;
  if (window.usedPercent > 0 || window.remainingPercent > 0) return true;
  if (window.resetsAt.isNotEmpty) return true;
  if (window.resetDescription?.trim().isNotEmpty ?? false) return true;
  final label = window.label?.trim();
  return label != null && label.isNotEmpty;
}

List<LimitsWindow> limitHomeWindows(List<LimitsWindow> windows) {
  return sortedLimitWindows(
    windows.where(limitHomeWindowHasData).toList(),
  ).take(2).toList();
}

int limitWindowRemainingPercent(LimitsWindow window) {
  if (window.remainingPercent > 0) return window.remainingPercent.clamp(0, 100);
  return (100 - window.usedPercent).clamp(0, 100);
}

// 首页配额格:对照桌面 formatHomeLimitWindowValue,显示剩余/已用百分比。
String limitHomeWindowValue(
  LimitsWindow window, {
  LimitDisplayMode displayMode = LimitDisplayMode.remaining,
}) {
  if (window.isCredits) {
    return limitWindowValueText(window, displayMode: displayMode);
  }
  if (window.isSpend) {
    return limitWindowValueText(window, displayMode: displayMode);
  }
  final remaining = limitWindowRemainingPercent(window);
  final value = displayMode == LimitDisplayMode.used
      ? 100 - remaining
      : remaining;
  return '${limitDisplayModeLabel(displayMode)} $value%';
}

// 首页重置文案:紧凑 "重置 1天 15小时"(对照桌面 formatReset)。
String limitHomeResetText(LimitsWindow window, {DateTime? now}) {
  final remainingMs = limitResetRemainingMs(window.resetsAt, now: now);
  if (remainingMs != null) {
    if (remainingMs == 0) return '即将重置';
    return '重置 ${formatLimitDurationZh(remainingMs)}';
  }
  final desc = window.resetDescription?.trim();
  if (desc != null && desc.isNotEmpty) return desc;

  final minutes = window.windowMinutes;
  if (minutes != null && minutes > 0 && window.kind == 'session') {
    if (minutes == 300) return '5 小时滚动';
    if (minutes % 60 == 0 && minutes >= 60) return '${minutes ~/ 60} 小时滚动';
    return '$minutes 分钟滚动';
  }
  return '';
}

enum LimitHomeValueTone { normal, low, critical }

LimitHomeValueTone limitHomeValueTone(LimitsWindow window) {
  if (window.isCredits || window.isSpend) return LimitHomeValueTone.normal;
  final remaining = limitWindowRemainingPercent(window);
  if (remaining < 20) return LimitHomeValueTone.critical;
  if (remaining < 50) return LimitHomeValueTone.low;
  return LimitHomeValueTone.normal;
}

int limitWindowMeterPercent(LimitsWindow window) {
  if (window.isSpend &&
      window.limit != null &&
      window.limit! > 0 &&
      window.used != null) {
    return ((window.used! / window.limit!) * 100).round().clamp(0, 100);
  }
  return window.usedPercent;
}

bool limitWindowShouldShowMeter(LimitsWindow window) {
  if (!window.showMeter) return false;
  if (window.isSpend) return window.limit != null && window.limit! > 0;
  return !window.isCredits;
}

String limitWindowValueText(
  LimitsWindow window, {
  // 配额页历史上显示已用百分比,保留默认值以兼容直接调用方；页面会传入用户选择。
  LimitDisplayMode displayMode = LimitDisplayMode.used,
}) {
  if (window.isCredits) {
    if (window.remaining == null) return '—';
    final cur = (window.currency ?? '').trim();
    final suffix = cur.isEmpty ? '' : ' $cur';
    return '${window.remaining!.toStringAsFixed(2)}$suffix';
  }
  if (window.isSpend) {
    if (window.used == null) return '—';
    final cur = (window.currency ?? '').trim();
    final suffix = cur.isEmpty ? '' : ' $cur';
    if (displayMode == LimitDisplayMode.remaining &&
        window.limit != null &&
        window.limit! >= 0) {
      final left = (window.limit! - window.used!).clamp(0, window.limit!);
      return '剩余 ${left.toStringAsFixed(2)}$suffix';
    }
    return '已用 ${window.used!.toStringAsFixed(2)}$suffix';
  }
  final value = limitWindowRemainingPercent(window);
  final percent = displayMode == LimitDisplayMode.used ? 100 - value : value;
  return '${limitDisplayModeLabel(displayMode)} $percent%';
}
