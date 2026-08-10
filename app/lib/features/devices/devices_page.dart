import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/view_period.dart';
import '../../core/format/formatters.dart';
import '../../core/models/stats.dart';
import '../../core/network/stats_repository.dart';
import '../../core/storage/prefs_storage.dart';
import '../../theme/glass_material.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/app_page_header.dart';
import '../../widgets/period_toggle.dart';
import '../../widgets/platform_icon.dart';

// ============================================================
// 设备页(原型 ⑥)——接真实数据。
// 数据源:statsProvider 的 snapshot.devices[]。
// stale 字段已由 hub 按 staleAfterMs 判好(API.md),客户端直接用:
//   stale=true → 灰显 + "已过期" 标 + 降透明度。
// 行:平台图标 + hostname + 在线标 + osName osVersion + 今日 tokens/花费。
// 点击展开:今日/本月 tokens、今日花费、在用工具(today.clients 键)、
//   上报方式(syncUploadIntervalMs:0/缺省=实时,否则"每 N 分钟")、
//   agentVersion/agentRuntime。
// 空态:0 台设备同总览空态。
// ============================================================

class DevicesPage extends ConsumerWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(statsProvider);
    final currency = ref.watch(settingsProvider).displayCurrency;
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: async.when(
            loading: () => const _Loading(),
            error: (e, st) => _Error(onRetry: () => ref.read(statsProvider.notifier).refresh()),
            data: (snapshot) {
              final devices = snapshot.devices;
              final viewPeriod = ref.watch(viewPeriodProvider);
              if (devices.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    const AppPageHeader(title: '设备', subtitle: '0 台设备', trailing: PeriodToggle()),
                    const SizedBox(height: 40),
                    const _EmptyState(),
                  ],
                );
              }
              final active = devices.where((d) => !d.stale).length;
              final sorted = _sortedDevices(devices);
              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  AppPageHeader(title: '设备', subtitle: '${devices.length} 台 · $active 台活跃', trailing: const PeriodToggle()),
                  const SizedBox(height: 6),
                  for (var i = 0; i < sorted.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    _DeviceCard(
                      device: sorted[i],
                      currency: currency,
                      viewPeriod: viewPeriod,
                      aggregatePeriods: snapshot.periods,
                      history: snapshot.historyPreview,
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

List<DeviceRecord> _sortedDevices(List<DeviceRecord> devices) {
  final copy = devices.toList();
  copy.sort((a, b) {
    if (a.stale != b.stale) return a.stale ? 1 : -1;
    final at = DateTime.tryParse(a.updatedAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bt = DateTime.tryParse(b.updatedAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
    final byTime = bt.compareTo(at);
    if (byTime != 0) return byTime;
    return (b.periods?.today?.totalTokens ?? 0).compareTo(a.periods?.today?.totalTokens ?? 0);
  });
  return copy;
}

String _deviceTitle(DeviceRecord d) {
  if (d.deviceId.isNotEmpty) return d.deviceId;
  if (d.hostname.isNotEmpty) return d.hostname;
  return '未命名设备';
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
          Text('无法加载设备列表', style: TextStyle(fontSize: 13, color: t.muted)),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Column(
      children: [
        Icon(Icons.devices_other_outlined, size: 48, color: t.faint),
        const SizedBox(height: 12),
        Text('暂无设备', style: TextStyle(fontSize: 14, color: t.muted)),
        const SizedBox(height: 6),
        Text('请在桌面端配置采集器并上报到 Hub', style: TextStyle(fontSize: 12, color: t.faint)),
      ],
    );
  }
}

// 单设备卡:可展开。stale 整卡降透明 + "已过期"标。
class _DeviceCard extends StatefulWidget {
  const _DeviceCard({
    required this.device,
    required this.currency,
    required this.viewPeriod,
    required this.aggregatePeriods,
    required this.history,
  });
  final DeviceRecord device;
  final DisplayCurrency currency;
  final ViewPeriod viewPeriod;
  final Periods? aggregatePeriods;
  final HistoryPreview? history;

  @override
  State<_DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<_DeviceCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final d = widget.device;
    final period = resolveDevicePeriod(widget.viewPeriod, d, widget.aggregatePeriods, widget.history);
    final today = d.periods?.today;

    return Opacity(
      opacity: d.stale ? 0.55 : 1.0,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                // 平台图标:按 platform/osName 选 Material 图标
                PlatformIcon(platform: d.platform, osName: d.osName),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _deviceTitle(d),
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: t.text),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 在线/过期标
                          _StatusTag(stale: d.stale),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _subLine(d),
                        style: TextStyle(fontSize: 11, color: t.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 当前周期 tokens/花费
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatTokensCompact(period?.totalTokens ?? 0),
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: t.text, fontFamily: 'Menlo', fontFamilyFallback: const ['monospace']),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatMoney(period?.costUsd ?? 0, widget.currency),
                      style: TextStyle(fontSize: 11, color: t.accent),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: t.muted),
              ],
            ),
          ),
          // 展开详情
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            sizeCurve: Curves.easeInOut,
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _detailRows(d, period, today, widget.viewPeriod, t),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  // 副标题:osName osVersion · 上报时间。
  String _subLine(DeviceRecord d) {
    final parts = <String>[];
    final os = [d.osName, d.osVersion].where((s) => s != null && s.isNotEmpty).join(' ');
    if (os.isNotEmpty) parts.add(os);
    final dt = DateTime.tryParse(d.updatedAt);
    if (dt != null) parts.add(formatRelative(dt, DateTime.now()));
    return parts.isEmpty ? d.platform : parts.join(' · ');
  }

  // 展开详情 kv 行。
  List<Widget> _detailRows(DeviceRecord d, Period? period, Period? today, ViewPeriod viewPeriod, AppThemeTokens t) {
    final rows = <({String k, String v})>[];
    final periodLabel = viewPeriod.shortLabel;
    rows.add((k: '$periodLabel tokens', v: formatTokensCompact(period?.totalTokens ?? 0)));
    rows.add((k: '$periodLabel 花费', v: formatMoney(period?.costUsd ?? 0, widget.currency)));
    if (viewPeriod == ViewPeriod.today) {
      rows.add((k: '本月 tokens', v: formatTokensCompact(d.periods?.month?.totalTokens ?? 0)));
    }
    // 在用工具:today.clients 的键
    final clients = today?.clients.keys.toList() ?? const [];
    rows.add((k: '在用工具', v: clients.isEmpty ? '—' : clients.join(', ')));
    // 上报方式:syncUploadIntervalMs 0/缺省=实时,否则每 N 分钟
    final interval = d.syncUploadIntervalMs;
    final mode = (interval == null || interval == 0) ? '实时' : '每 ${(interval / 60000).round()} 分钟';
    rows.add((k: '上报方式', v: mode));
    if (d.agentVersion != null && d.agentVersion!.isNotEmpty) {
      rows.add((k: '采集器', v: [d.agentRuntime, d.agentVersion].where((s) => s != null && s.isNotEmpty).join(' ')));
    }
    rows.add((k: '设备 ID', v: d.deviceId.isEmpty ? '—' : d.deviceId));

    return [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(rows[i].k, style: TextStyle(fontSize: 11.5, color: t.muted)),
            const SizedBox(width: 12),
            Expanded(
              child: SelectableText(
                rows[i].v,
                style: TextStyle(fontSize: 11.5, color: t.text, fontFamily: 'Menlo', fontFamilyFallback: const ['monospace']),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ],
    ];
  }
}

// 在线/过期小标签。
class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.stale});
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final (label, color) = stale ? ('已过期', t.faint) : ('在线', t.green);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
