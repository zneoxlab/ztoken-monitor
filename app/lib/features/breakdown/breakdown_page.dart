import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/view_period.dart';
import '../../core/format/formatters.dart';
import '../../core/models/stats.dart';
import '../../core/network/stats_repository.dart';
import '../../core/storage/prefs_storage.dart';
import '../../theme/app_colors.dart';
import '../../theme/glass_material.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/app_page_header.dart';
import '../../widgets/app_segmented.dart';
import '../../widgets/breakdown_usage_row.dart';
import '../../widgets/period_toggle.dart';

// ============================================================
// 明细页 —— 工具 / 模型拆解(会话/项目待后续版本)。
// ============================================================

class BreakdownPage extends ConsumerStatefulWidget {
  const BreakdownPage({super.key});

  @override
  ConsumerState<BreakdownPage> createState() => _BreakdownPageState();
}

class _BreakdownPageState extends ConsumerState<BreakdownPage> {
  int _dim = 0; // 0=工具 1=模型

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(statsProvider);
    final currency = ref.watch(settingsProvider).displayCurrency;
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: async.when(
            loading: () => const _Loading(),
            error: (e, st) => _Error(onRetry: () => ref.read(statsProvider.notifier).refresh()),
            data: (snapshot) => _Content(
              snapshot: snapshot,
              currency: currency,
              dim: _dim,
              onDim: (i) => setState(() => _dim = i),
            ),
          ),
        ),
      ),
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
          Text('无法加载明细', style: TextStyle(fontSize: 13, color: t.muted)),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(10)),
              child: Text('重试', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF14201A))),
            ),
          ),
        ],
      ),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({
    required this.snapshot,
    required this.currency,
    required this.dim,
    required this.onDim,
  });
  final StatsSnapshot snapshot;
  final DisplayCurrency currency;
  final int dim;
  final ValueChanged<int> onDim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewPeriod = ref.watch(viewPeriodProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const AppPageHeader(
          title: '明细',
          subtitle: '按工具 / 模型拆解',
          trailing: PeriodToggle(),
        ),
        const SizedBox(height: 6),
        AppSegmented(
          labels: const ['工具', '模型'],
          selectedIndex: dim,
          onChanged: onDim,
        ),
        _Body(
          snapshot: snapshot,
          currency: currency,
          dim: dim,
          viewPeriod: viewPeriod,
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

// 主体:按 dim 分发工具/模型列表。
class _Body extends StatelessWidget {
  const _Body({required this.snapshot, required this.currency, required this.dim, required this.viewPeriod});
  final StatsSnapshot snapshot;
  final DisplayCurrency currency;
  final int dim;
  final ViewPeriod viewPeriod;

  Period? _period() => resolvePeriod(viewPeriod, snapshot.periods, snapshot.historyPreview);

  @override
  Widget build(BuildContext context) {
    final period = _period();
    if (dim == 0) return _ClientList(period: period, currency: currency);
    return _ModelList(period: period, currency: currency);
  }
}

// 工具列表:与模型同款布局(全量数值 + 工具图标 + 缓存展开 + 主力模型)。
class _ClientList extends StatelessWidget {
  const _ClientList({required this.period, required this.currency});
  final Period? period;
  final DisplayCurrency currency;

  @override
  Widget build(BuildContext context) {
    if (period == null || period!.clients.isEmpty) return const _EmptySegment();
    final entries = period!.clients.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxTok = entries.first.value;
    final rows = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final id = e.key;
      final tokens = e.value;
      final cost = period!.clientCosts[id] ?? 0;
      final share = maxTok == 0 ? 0.0 : tokens / maxTok;
      final color = vendorColors[id] ?? _fallbackColor(i);
      final topModels = (period!.clientModels[id]?.entries.toList() ?? [])
        ..sort((a, b) => b.value.compareTo(a.value));
      final topModelRows = topModels
          .take(3)
          .map((m) => (name: m.key, tokens: m.value))
          .toList();
      rows.add(ToolBreakdownRow(
        showTopDivider: i != 0,
        clientId: id,
        name: _clientLabel(id),
        tokens: tokens,
        cost: cost,
        currency: currency,
        share: share,
        color: color,
        cacheReads: period!.clientCacheReads[id] ?? 0,
        cacheWrites: period!.clientCacheWrites[id] ?? 0,
        outputs: period!.clientOutputs[id] ?? 0,
        topModels: topModelRows,
      ));
    }
    return GlassCard(padding: const EdgeInsets.fromLTRB(14, 4, 14, 6), child: Column(children: rows));
  }
}

// 模型列表:桌面端同款布局(全量数值 + 厂商图标/色点 + 缓存展开)。
class _ModelList extends StatelessWidget {
  const _ModelList({required this.period, required this.currency});
  final Period? period;
  final DisplayCurrency currency;

  @override
  Widget build(BuildContext context) {
    if (period == null || period!.models.isEmpty) return const _EmptySegment();
    final entries = period!.models.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxTok = entries.first.value;
    final rows = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final model = e.key;
      final tokens = e.value;
      final cost = period!.modelCosts[model] ?? 0;
      final share = maxTok == 0 ? 0.0 : tokens / maxTok;
      rows.add(ModelBreakdownRow(
        showTopDivider: i != 0,
        model: model,
        tokens: tokens,
        cost: cost,
        currency: currency,
        share: share,
        cacheReads: period!.modelCacheReads[model] ?? 0,
        cacheWrites: period!.modelCacheWrites[model] ?? 0,
        outputs: period!.modelOutputs[model] ?? 0,
      ));
    }
    return GlassCard(padding: const EdgeInsets.fromLTRB(14, 4, 14, 6), child: Column(children: rows));
  }
}

// 空段:"该周期暂无记录"。
class _EmptySegment extends StatelessWidget {
  const _EmptySegment();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(child: Text('该周期暂无记录', style: TextStyle(fontSize: 13, color: t.faint))),
    );
  }
}

// client id → 展示名(与首页额度卡同源,精简版)。
String _clientLabel(String id) {
  const labels = {
    'claude': 'Claude', 'codex': 'Codex', 'cursor': 'Cursor', 'copilot': 'Copilot',
    'deepseek': 'DeepSeek', 'antigravity': 'Antigravity', 'opencode': 'OpenCode',
    'kimi': 'Kimi', 'qwen': 'Qwen', 'openrouter': 'OpenRouter', 'cline': 'Cline',
    'zcode': 'ZCode', 'qoder': 'Qoder',
  };
  if (id.isEmpty) return '?';
  return labels[id] ?? id[0].toUpperCase() + id.substring(1);
}

// 备用调色板取色(模型行/无厂商色 client)。
Color _fallbackColor(int index) {
  const palette = fallbackPalette;
  if (palette.isEmpty) return const Color(0xFF6BB6FF);
  return palette[index % palette.length];
}
