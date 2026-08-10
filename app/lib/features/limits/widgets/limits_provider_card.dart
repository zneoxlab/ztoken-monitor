import 'package:flutter/material.dart';

import '../../../core/limits/limit_presentation.dart';
import '../../../core/models/stats.dart';
import '../../../theme/glass_material.dart';
import '../../../theme/theme_extension.dart';
import '../../../widgets/app_tag.dart';
import '../../../widgets/meter_bar.dart';
import '../../../widgets/provider_icon.dart';

// 配额 provider 卡 + 窗口行 + 首页扁平行,三处共用。

class LimitsProviderCard extends StatelessWidget {
  const LimitsProviderCard({
    super.key,
    required this.provider,
    required this.staleAfterMs,
    required this.limitsUpdatedAt,
  });

  final LimitsProvider provider;
  final int staleAfterMs;
  final String limitsUpdatedAt;

  bool get _stale {
    if (limitsUpdatedAt.isEmpty) return false;
    final dt = DateTime.tryParse(limitsUpdatedAt);
    if (dt == null) return false;
    return DateTime.now().difference(dt).inMilliseconds > staleAfterMs;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final p = provider;
    final notOk = p.status.isNotEmpty && p.status.toLowerCase() != 'ok';
    final planText = limitProviderPlanText(p);
    final metaLine = limitProviderMetaLine(p);

    return Opacity(
      opacity: _stale ? 0.6 : 1.0,
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProviderIcon(providerId: p.provider),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              limitProviderDisplayName(p.provider),
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.text),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (planText.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.42),
                              child: Text(
                                planText,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  height: 1.2,
                                  color: notOk ? t.amber : t.muted,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        limitAccountLine(p),
                        style: TextStyle(fontSize: 11, color: t.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (metaLine.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(metaLine, style: TextStyle(fontSize: 10, color: t.faint)),
                      ],
                    ],
                  ),
                ),
                if (_stale) ...[
                  const SizedBox(width: 6),
                  AppTag(text: '数据过期', variant: AppTagVariant.grey),
                ],
              ],
            ),
            if (notOk) ...[
              const SizedBox(height: 10),
              Text(limitStatusDetail(p.status), style: TextStyle(fontSize: 11.5, color: t.faint)),
            ] else ...[
              const SizedBox(height: 8),
              for (var i = 0; i < p.windows.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                LimitsWindowRow(window: p.windows[i]),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class LimitsWindowRow extends StatelessWidget {
  const LimitsWindowRow({super.key, required this.window});

  final LimitsWindow window;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final w = window;
    final title = limitWindowLabel(w);
    final resetText = limitWindowResetText(w);
    final percent = limitWindowMeterPercent(w);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                title,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: t.text),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              limitWindowValueText(w),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: _valueColor(w, t),
                fontFamily: 'Menlo',
                fontFamilyFallback: const ['monospace'],
              ),
            ),
          ],
        ),
        if (limitWindowShouldShowMeter(w)) ...[
          const SizedBox(height: 6),
          MeterBar(usedPercent: percent.toDouble()),
        ],
        if (resetText.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(resetText, style: TextStyle(fontSize: 10.5, color: t.faint)),
        ],
        if (w.detail != null && w.detail!.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(w.detail!, style: TextStyle(fontSize: 10.5, color: t.faint)),
        ],
      ],
    );
  }

  Color _valueColor(LimitsWindow w, AppThemeTokens t) {
    if (w.isCredits || w.isSpend) return t.accent;
    if (w.usedPercent >= 90) return t.red;
    if (w.usedPercent >= 60) return t.amber;
    return t.accent;
  }
}

class LimitsHomeAccountBlock extends StatelessWidget {
  const LimitsHomeAccountBlock({super.key, required this.provider});

  final LimitsProvider provider;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final windows = limitHomeWindows(provider.windows);
    if (windows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ProviderIcon(providerId: provider.provider, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                limitHomeAccountTitle(provider),
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: t.text),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 30),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cellWidth = windows.length == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  for (final w in windows)
                    SizedBox(
                      width: cellWidth,
                      child: _HomeLimitWindowCell(window: w),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HomeLimitWindowCell extends StatelessWidget {
  const _HomeLimitWindowCell({required this.window});

  final LimitsWindow window;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final value = limitHomeWindowValue(window);
    final reset = limitHomeResetText(window);
    final tone = limitHomeValueTone(window);
    final valueColor = switch (tone) {
      LimitHomeValueTone.critical => t.red,
      LimitHomeValueTone.low => t.amber,
      LimitHomeValueTone.normal => t.text,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                limitWindowLabel(window),
                style: TextStyle(fontSize: 10.5, color: t.muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: valueColor,
                fontFamily: 'Menlo',
                fontFamilyFallback: const ['monospace'],
              ),
            ),
          ],
        ),
        if (reset.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            reset,
            style: TextStyle(fontSize: 9.5, color: t.muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (limitWindowShouldShowMeter(window)) ...[
          const SizedBox(height: 4),
          MeterBar(usedPercent: limitWindowMeterPercent(window).toDouble(), compact: true),
        ],
      ],
    );
  }
}
