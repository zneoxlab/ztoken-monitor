import '../models/stats.dart';
import 'limit_presentation.dart';
import 'limit_provider_ids.dart';

// 单条配额账户的稳定排序键(provider + accountKey)。
String limitEntryKey(LimitsProvider provider) =>
    '${provider.provider.trim().toLowerCase()}|${provider.accountKey ?? ''}';

List<String> parseLimitProviderOrder(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  return raw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

String serializeLimitProviderOrder(List<String> order) => order.join(',');

// 归一化用户顺序:保留已知项、去重、追加未出现的当前项。
List<String> normalizeLimitProviderOrder(
  List<String> savedOrder,
  List<LimitsProvider> providers,
) {
  final known = providers.map(limitEntryKey).toList();
  final knownSet = known.toSet();
  final seen = <String>{};
  final order = <String>[];

  for (final item in savedOrder) {
    final key = item.trim();
    if (!knownSet.contains(key) || seen.contains(key)) continue;
    seen.add(key);
    order.add(key);
  }
  for (final key in known) {
    if (seen.contains(key)) continue;
    seen.add(key);
    order.add(key);
  }
  return order;
}

int _defaultCompare(LimitsProvider a, LimitsProvider b) {
  final configuredDiff = (isConfiguredLimitProvider(b) ? 1 : 0) -
      (isConfiguredLimitProvider(a) ? 1 : 0);
  if (configuredDiff != 0) return configuredDiff;
  final rankDiff = limitProviderRank(a.provider) - limitProviderRank(b.provider);
  if (rankDiff != 0) return rankDiff;
  return (a.accountKey ?? '').compareTo(b.accountKey ?? '');
}

// 有用户顺序时严格按用户顺序;否则 configured 在前 + 默认 provider 序。
List<LimitsProvider> orderedLimitProviders(
  List<LimitsProvider> providers, {
  List<String> savedOrder = const [],
}) {
  if (providers.isEmpty) return const [];
  final byKey = {for (final p in providers) limitEntryKey(p): p};

  if (savedOrder.isEmpty) {
    final copy = providers.toList()..sort(_defaultCompare);
    return copy;
  }

  final order = normalizeLimitProviderOrder(savedOrder, providers);
  final sorted = <LimitsProvider>[];
  for (final key in order) {
    final p = byKey[key];
    if (p != null) sorted.add(p);
  }
  return sorted;
}

List<String> reorderLimitProviderEntry(
  List<String> savedOrder,
  List<LimitsProvider> providers,
  int oldIndex,
  int newIndex,
) {
  final order = normalizeLimitProviderOrder(savedOrder, providers);
  if (oldIndex < 0 || oldIndex >= order.length) return order;
  final target = newIndex.clamp(0, order.length - 1);
  if (oldIndex == target) return order;
  final item = order.removeAt(oldIndex);
  order.insert(target, item);
  return order;
}
