import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/limits/limit_provider_order.dart';
import '../../core/models/stats.dart';
import '../../core/network/stats_repository.dart';
import '../../core/storage/prefs_storage.dart';
import '../../theme/glass_material.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/app_page_header.dart';
import 'widgets/limits_provider_card.dart';

class LimitsPage extends ConsumerWidget {
  const LimitsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(statsProvider);
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: async.when(
            loading: () => const _Loading(),
            error: (e, st) => _Error(onRetry: () => ref.read(statsProvider.notifier).refresh()),
            data: (snapshot) {
              final limits = snapshot.limits;
              if (limits == null || limits.providers.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: const [
                    AppPageHeader(title: '配额', subtitle: 'AI 工具额度'),
                    SizedBox(height: 40),
                    _EmptyState(),
                  ],
                );
              }
              final savedOrder = parseLimitProviderOrder(ref.watch(settingsProvider).limitProviderOrder);
              final providers = orderedLimitProviders(
                limits.providers,
                savedOrder: savedOrder,
              );
              return _LimitsList(
                providers: providers,
                staleAfterMs: snapshot.staleAfterMs,
                limitsUpdatedAt: limits.updatedAt,
                onReorder: (oldIndex, newIndex) async {
                  final order = reorderLimitProviderEntry(
                    savedOrder,
                    limits.providers,
                    oldIndex,
                    newIndex,
                  );
                  await ref.read(settingsProvider.notifier).setLimitProviderOrder(
                        serializeLimitProviderOrder(order),
                      );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LimitsList extends StatelessWidget {
  const _LimitsList({
    required this.providers,
    required this.staleAfterMs,
    required this.limitsUpdatedAt,
    required this.onReorder,
  });

  final List<LimitsProvider> providers;
  final int staleAfterMs;
  final String limitsUpdatedAt;
  final Future<void> Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppPageHeader(title: '配额', subtitle: 'AI 工具额度 · 长按拖动排序'),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          sliver: SliverReorderableList(
            itemCount: providers.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex -= 1;
              onReorder(oldIndex, newIndex);
            },
            itemBuilder: (context, index) {
              final p = providers[index];
              final key = limitEntryKey(p);
              return ReorderableDelayedDragStartListener(
                key: ValueKey(key),
                index: index,
                child: Padding(
                  padding: EdgeInsets.only(bottom: index < providers.length - 1 ? 10 : 0),
                  child: LimitsProviderCard(
                    provider: p,
                    staleAfterMs: staleAfterMs,
                    limitsUpdatedAt: limitsUpdatedAt,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(height: 12),
          Text('加载中…', style: TextStyle(fontSize: 12, color: t.muted)),
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 40, color: t.faint),
          const SizedBox(height: 12),
          Text('无法加载配额', style: TextStyle(fontSize: 13, color: t.muted)),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(10)),
              child: const Text('重试', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF14201A))),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Column(
      children: [
        Icon(Icons.speed_outlined, size: 48, color: t.faint),
        const SizedBox(height: 12),
        Text('暂无配额数据', style: TextStyle(fontSize: 14, color: t.muted)),
        const SizedBox(height: 6),
        Text('在桌面端设置 → AI Tool Limits 配置', style: TextStyle(fontSize: 12, color: t.faint)),
      ],
    );
  }
}
