import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/view_period.dart';
import '../../core/format/formatters.dart';
import '../../core/limits/limit_presentation.dart';
import '../../core/limits/limit_provider_order.dart';
import '../../core/models/stats.dart';
import '../../core/network/stats_repository.dart';
import '../../core/storage/prefs_storage.dart';
import '../../features/limits/widgets/limits_provider_card.dart';
import '../../theme/app_colors.dart';
import '../../theme/glass_material.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/app_page_header.dart';
import '../../widgets/heatmap_grid.dart';
import '../../widgets/live_dot.dart';
import '../../widgets/period_toggle.dart';
import '../../widgets/token_area_chart.dart';
import '../../widgets/year_heatmap.dart';

// 首页区块统一底间距(对照 .card margin-bottom:12)。
const _kHomeSectionGap = 12.0;
const _kMono = TextStyle(
  fontFamily: 'Menlo',
  fontFamilyFallback: ['monospace'],
);

Widget _homeSection(Widget child) => Padding(
  padding: const EdgeInsets.only(bottom: _kHomeSectionGap),
  child: child,
);
// 数据源:statsProvider(AsyncValue<StatsSnapshot>)。
//   冷启动 GET /api/stats 全量 → SSE/轮询增量刷新(GOAL.md §6.3)。
// 三态:loading(骨架)/ error(重试按钮)/ data(6 块渲染)。
// 6 块:AppPageHeader / hero 今日 / duo 本月+累计 / 额度 /
//      活动热力图(historyPreview.daily)/ 近 14 天趋势(daily 末14天)。
// ============================================================

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(statsProvider);
    final currency = ref.watch(settingsProvider).displayCurrency;
    // SSE 连接状态驱动头部 LiveDot 颜色(任务6 sseClientProvider)
    // 首版用 data 就绪判断实时性,后续接 sseClientProvider.connectionState
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: async.when(
            loading: () => const _Loading(),
            error: (e, st) => _Error(
              onRetry: () => ref.read(statsProvider.notifier).refresh(),
            ),
            data: (snapshot) => _StatsContent(
              snapshot: snapshot,
              currency: currency,
              settings: ref.watch(settingsProvider),
            ),
          ),
        ),
      ),
    );
  }
}

// 加载态:居中转圈 + 提示。
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

// 错误态:提示 + 重试按钮。
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
          Text('无法加载统计数据', style: TextStyle(fontSize: 13, color: t.muted)),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: t.accent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '重试',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF14201A),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 数据就绪:渲染 6 块。空数据(today.totalTokens=0 且无设备)显示空态。
class _StatsContent extends StatelessWidget {
  const _StatsContent({
    required this.snapshot,
    required this.currency,
    required this.settings,
  });
  final StatsSnapshot snapshot;
  final DisplayCurrency currency;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final today = snapshot.periods?.today;
    final isEmpty =
        (today == null || today.totalTokens == 0) && snapshot.devices.isEmpty;
    if (isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _Header(snapshot: snapshot),
          const SizedBox(height: 40),
          _EmptyState(),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _Header(snapshot: snapshot),
        _homeSection(
          _HeroCard(
            periods: snapshot.periods,
            currency: currency,
            history: snapshot.historyPreview,
          ),
        ),
        _homeSection(
          _DuoMonthAllTime(
            month: snapshot.periods?.month,
            allTime: snapshot.periods?.allTime,
            currency: currency,
          ),
        ),
        _QuotaAlertCard(limits: snapshot.limits, settings: settings),
        _homeSection(const _HeatmapCard()),
        _homeSection(_TrendCard(history: snapshot.historyPreview)),
        const SizedBox(height: 4),
      ],
    );
  }
}

// 头部:标题 + 副标题 + 周期切换 + LiveDot。
class _Header extends ConsumerWidget {
  const _Header({required this.snapshot});
  final StatsSnapshot snapshot;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceCount = snapshot.devices.length;
    final latest = _latestDeviceSync(snapshot.devices);
    return AppPageHeader(
      title: '总览',
      subtitle: formatDevicesSyncSubtitle(deviceCount, latest, DateTime.now()),
      titleTrailing: const LiveDot(text: '实时'),
      trailing: const PeriodToggle(),
    );
  }

  DateTime? _latestDeviceSync(List<DeviceRecord> devices) {
    DateTime? latest;
    for (final d in devices) {
      final dt = DateTime.tryParse(d.updatedAt);
      if (dt != null && (latest == null || dt.isAfter(latest))) latest = dt;
    }
    return latest;
  }
}

// 空态:无数据时提示。
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Column(
      children: [
        Icon(Icons.inbox_outlined, size: 48, color: t.faint),
        const SizedBox(height: 12),
        Text('暂无用量数据', style: TextStyle(fontSize: 14, color: t.muted)),
        const SizedBox(height: 6),
        Text(
          '请在桌面端配置采集器并上报到 Hub',
          style: TextStyle(fontSize: 12, color: t.faint),
        ),
      ],
    );
  }
}

// Hero 大卡:跟随全局 viewPeriodProvider。
class _HeroCard extends ConsumerWidget {
  const _HeroCard({
    required this.periods,
    required this.currency,
    required this.history,
  });
  final Periods? periods;
  final DisplayCurrency currency;
  final HistoryPreview? history;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final viewPeriod = ref.watch(viewPeriodProvider);
    final period = resolvePeriod(viewPeriod, periods, history);
    final tokens = period?.totalTokens ?? 0;
    final cost = period?.costUsd ?? 0;
    final stats = heroStatsForPeriod(viewPeriod, period, history);
    final accent14 = Color.fromARGB(
      36,
      t.accentRgb[0],
      t.accentRgb[1],
      t.accentRgb[2],
    );
    final accent3 = Color.fromARGB(
      8,
      t.accentRgb[0],
      t.accentRgb[1],
      t.accentRgb[2],
    );

    return GlassCard(
      isHero: true,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kRadiusCard),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent14, accent3],
              stops: const [0.0, 0.55],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  viewPeriodSubtitle(viewPeriod),
                  style: TextStyle(fontSize: 12, color: t.muted),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        formatTokensFull(tokens),
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: t.text,
                          fontFamily: 'Menlo',
                          fontFamilyFallback: const ['monospace'],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatTokensApproxInline(tokens),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  formatMoney(cost, currency),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.accent,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _HeroMetaItem(label: '缓存命中', value: stats.cacheHit),
                    const SizedBox(width: 14),
                    _HeroMetaItem(label: '输出', value: stats.output),
                    const SizedBox(width: 14),
                    _HeroMetaItem(label: '活跃时长', value: stats.activeTime),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// hero meta 项:11 muted 标签 + 13 text 值。
class _HeroMetaItem extends StatelessWidget {
  const _HeroMetaItem({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: t.muted)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: t.text,
            ).merge(_kMono),
          ),
        ],
      ),
    );
  }
}

// 本月 / 累计 双小卡:单张玻璃卡内分栏,避免并排 BackdropFilter 裁切异常。
class _DuoMonthAllTime extends StatelessWidget {
  const _DuoMonthAllTime({
    required this.month,
    required this.allTime,
    required this.currency,
  });
  final Period? month;
  final Period? allTime;
  final DisplayCurrency currency;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _MiniCardContent(
                label: '本月',
                value: formatTokensCompact(month?.totalTokens ?? 0),
                cost: formatMoney(month?.costUsd ?? 0, currency),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: VerticalDivider(
                width: 1,
                thickness: 1,
                color: t.line.withValues(alpha: 0.45),
              ),
            ),
            Expanded(
              child: _MiniCardContent(
                label: '累计',
                value: formatTokensCompact(allTime?.totalTokens ?? 0),
                cost: formatMoney(allTime?.costUsd ?? 0, currency),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniCardContent extends StatelessWidget {
  const _MiniCardContent({
    required this.label,
    required this.value,
    required this.cost,
  });
  final String label;
  final String value;
  final String cost;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: t.muted)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: t.text,
          ).merge(_kMono),
        ),
        const SizedBox(height: 2),
        Text(
          cost,
          style: TextStyle(fontSize: 11, color: t.accent).merge(_kMono),
        ),
      ],
    );
  }
}

// 额度:与配额页同序,仅展示已配置账户的全部窗口。
class _QuotaAlertCard extends StatelessWidget {
  const _QuotaAlertCard({required this.limits, required this.settings});
  final LimitsAgg? limits;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    if (limits == null || limits!.providers.isEmpty) {
      return const SizedBox.shrink();
    }

    final savedOrder = parseLimitProviderOrder(settings.limitProviderOrder);
    final providers =
        orderedLimitProviders(limits!.providers, savedOrder: savedOrder)
            .where((p) => isConfiguredLimitProvider(p) && p.windows.isNotEmpty)
            .toList();

    final windowCount = providers.fold<int>(0, (n, p) => n + p.windows.length);
    if (windowCount == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CardHead(title: '额度'),
            const SizedBox(height: 8),
            for (var i = 0; i < providers.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Divider(
                    height: 1,
                    color: Theme.of(context)
                        .extension<AppThemeTokens>()!
                        .faint
                        .withValues(alpha: 0.35),
                  ),
                ),
              LimitsHomeAccountBlock(
                provider: providers[i],
                displayMode: settings.limitDisplayMode,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// 热力图卡:随全局周期切换布局(本月日历 / 本年 / 全部历史等)。
class _HeatmapCard extends ConsumerStatefulWidget {
  const _HeatmapCard();

  @override
  ConsumerState<_HeatmapCard> createState() => _HeatmapCardState();
}

class _HeatmapCardState extends ConsumerState<_HeatmapCard> {
  bool _showActiveDays = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(historyProvider);
    final viewPeriod = ref.watch(viewPeriodProvider);
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _CardHead(
            title: '活动',
            trailing: _heatmapTrailing(async, viewPeriod, t),
          ),
          const SizedBox(height: 10),
          async.when(
            loading: () => Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: t.muted,
                ),
              ),
            ),
            error: (e, st) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '历史加载失败',
                style: TextStyle(fontSize: 12, color: t.faint),
              ),
            ),
            data: (history) {
              final daily = history.daily;
              if (daily.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    '暂无历史数据',
                    style: TextStyle(fontSize: 12, color: t.faint),
                  ),
                );
              }
              final scoped = heatmapDailyForViewPeriod(daily, viewPeriod);
              final built = buildActivityHeatmapGrid(scoped, viewPeriod);
              return HeatmapGrid(
                levels: built.levels,
                monthLabels: built.monthLabels,
                cells: built.cells,
              );
            },
          ),
          const SizedBox(height: 8),
          const HeatmapLegend(),
        ],
      ),
    );
  }

  Widget? _heatmapTrailing(
    AsyncValue<HistoryPreview> async,
    ViewPeriod viewPeriod,
    AppThemeTokens t,
  ) {
    final scopeStyle = TextStyle(fontSize: 11, color: t.faint);
    final streakStyle = TextStyle(fontSize: 11, color: t.accent);
    final scope = Text(activityScopeLabel(viewPeriod), style: scopeStyle);
    final streakText = _streakText(async);
    if (streakText == null) return scope;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        scope,
        Text(' · ', style: scopeStyle),
        GestureDetector(
          onTap: () => setState(() => _showActiveDays = !_showActiveDays),
          behavior: HitTestBehavior.opaque,
          child: Text(streakText, style: streakStyle),
        ),
      ],
    );
  }

  String? _streakText(AsyncValue<HistoryPreview> async) {
    return async.maybeWhen(
      data: (history) => activityHeatmapStreakText(
        summary: history.summary,
        daily: history.daily,
        showActiveDays: _showActiveDays,
      ),
      orElse: () => null,
    );
  }
}
// 一年网格构建逻辑见 widgets/year_heatmap.dart(buildYearGrid),首页与趋势页共用。

// 近 14 天趋势卡:面积图 + 峰值 tokens(对照桌面 home-area-chart)。
class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.history});
  final HistoryPreview? history;

  @override
  Widget build(BuildContext context) {
    final daily = history?.daily ?? const [];
    if (daily.isEmpty) return const SizedBox.shrink();
    final last14 = daily.length > 14 ? daily.sublist(daily.length - 14) : daily;
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final values = last14.map((d) => d.tokens).toList();
    final peak = values.fold<int>(0, (m, v) => v > m ? v : m);
    final dateLabels = [
      for (var i = 0; i < last14.length; i++)
        _dayLabel(i, last14.length, last14),
    ];

    return GestureDetector(
      onTap: () => context.go('/home/trend'),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '近 ${last14.length} 天趋势',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.muted,
                    ),
                  ),
                ),
                if (peak > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '峰值 ${formatTokensCompact(peak)}',
                      style: TextStyle(fontSize: 10.5, color: t.faint),
                    ),
                  ),
                Text('趋势 ›', style: TextStyle(fontSize: 11, color: t.accent)),
              ],
            ),
            const SizedBox(height: 6),
            TokenAreaChart(values: values, dateLabels: dateLabels),
          ],
        ),
      ),
    );
  }

  String _dayLabel(int i, int total, List<HistoryDay> days) {
    if (i == 0 || i == total - 1 || i == total ~/ 2) {
      return _dayOfMonth(days[i].date);
    }
    return '';
  }

  String _dayOfMonth(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    return '${dt.day}';
  }
}

// 通用卡片头 .card-head:空间两端,标题 13/w600 muted + trailing 11。
class _CardHead extends StatelessWidget {
  const _CardHead({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: t.muted,
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
