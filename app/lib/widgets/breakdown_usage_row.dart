import 'package:flutter/material.dart';

import '../core/format/formatters.dart';
import '../core/model_presentation.dart';
import '../theme/theme_extension.dart';
import 'provider_icon.dart';
import 'share_bar.dart';

/// 明细用量行(对齐桌面端 breakdown .row):图标/色点 + 名称 + 全量数值/花费 + 占比条 + 缓存展开。
class BreakdownUsageRow extends StatefulWidget {
  const BreakdownUsageRow({
    super.key,
    required this.name,
    required this.tokens,
    required this.cost,
    required this.currency,
    required this.share,
    required this.color,
    this.iconAssetId,
    this.cacheReads = 0,
    this.cacheWrites = 0,
    this.outputs = 0,
    this.topModels = const [],
    this.showTopDivider = false,
  });

  final String name;
  final int tokens;
  final double cost;
  final DisplayCurrency currency;
  final double share;
  final Color color;
  final String? iconAssetId;
  final int cacheReads;
  final int cacheWrites;
  final int outputs;
  final List<({String name, int tokens})> topModels;
  final bool showTopDivider;

  @override
  State<BreakdownUsageRow> createState() => _BreakdownUsageRowState();
}

class _BreakdownUsageRowState extends State<BreakdownUsageRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final canExpand = widget.tokens > 0;

    return Column(
      children: [
        if (widget.showTopDivider)
          Divider(height: 1, thickness: 1, color: t.line.withValues(alpha: 0.35)),
        InkWell(
          onTap: canExpand ? () => setState(() => _expanded = !_expanded) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LeadingMark(color: widget.color, iconAssetId: widget.iconAssetId),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.name,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: t.text),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatTokensFull(widget.tokens),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: t.text,
                            fontFamily: 'Menlo',
                            fontFamilyFallback: const ['monospace'],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatMoney(widget.cost, widget.currency),
                          style: TextStyle(
                            fontSize: 11,
                            color: t.muted,
                            fontFamily: 'Menlo',
                            fontFamilyFallback: const ['monospace'],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ShareBar(share: widget.share, color: widget.color),
              ],
            ),
          ),
        ),
        if (_expanded) _CacheExpandPanel(
          tokens: widget.tokens,
          cacheReads: widget.cacheReads,
          cacheWrites: widget.cacheWrites,
          outputs: widget.outputs,
          topModels: widget.topModels,
        ),
      ],
    );
  }
}

class ToolBreakdownRow extends StatelessWidget {
  const ToolBreakdownRow({
    super.key,
    required this.clientId,
    required this.name,
    required this.tokens,
    required this.cost,
    required this.currency,
    required this.share,
    required this.color,
    required this.cacheReads,
    required this.cacheWrites,
    required this.outputs,
    required this.topModels,
    this.showTopDivider = false,
  });

  final String clientId;
  final String name;
  final int tokens;
  final double cost;
  final DisplayCurrency currency;
  final double share;
  final Color color;
  final int cacheReads;
  final int cacheWrites;
  final int outputs;
  final List<({String name, int tokens})> topModels;
  final bool showTopDivider;

  @override
  Widget build(BuildContext context) {
    final iconId = knownProviderIconIds.contains(clientId) ? clientId : null;
    return BreakdownUsageRow(
      name: name,
      tokens: tokens,
      cost: cost,
      currency: currency,
      share: share,
      color: color,
      iconAssetId: iconId,
      cacheReads: cacheReads,
      cacheWrites: cacheWrites,
      outputs: outputs,
      topModels: topModels,
      showTopDivider: showTopDivider,
    );
  }
}

class ModelBreakdownRow extends StatelessWidget {
  const ModelBreakdownRow({
    super.key,
    required this.model,
    required this.tokens,
    required this.cost,
    required this.currency,
    required this.share,
    required this.cacheReads,
    required this.cacheWrites,
    required this.outputs,
    this.showTopDivider = false,
  });

  final String model;
  final int tokens;
  final double cost;
  final DisplayCurrency currency;
  final double share;
  final int cacheReads;
  final int cacheWrites;
  final int outputs;
  final bool showTopDivider;

  @override
  Widget build(BuildContext context) {
    final color = modelColor(model);
    return BreakdownUsageRow(
      name: model,
      tokens: tokens,
      cost: cost,
      currency: currency,
      share: share,
      color: color,
      iconAssetId: modelIconAssetId(model),
      cacheReads: cacheReads,
      cacheWrites: cacheWrites,
      outputs: outputs,
      showTopDivider: showTopDivider,
    );
  }
}

class _LeadingMark extends StatelessWidget {
  const _LeadingMark({required this.color, this.iconAssetId});
  final Color color;
  final String? iconAssetId;

  @override
  Widget build(BuildContext context) {
    if (iconAssetId != null) {
      return ProviderIcon(providerId: iconAssetId!, size: 22, radius: 6);
    }
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _CacheExpandPanel extends StatelessWidget {
  const _CacheExpandPanel({
    required this.tokens,
    required this.cacheReads,
    required this.cacheWrites,
    required this.outputs,
    this.topModels = const [],
  });
  final int tokens;
  final int cacheReads;
  final int cacheWrites;
  final int outputs;
  final List<({String name, int tokens})> topModels;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final cacheMiss = (tokens - cacheReads - outputs).clamp(0, tokens);
    final inputTokens = cacheReads + cacheMiss;
    final hitPct = inputTokens > 0 ? ((cacheReads * 100) / inputTokens).round() : 0;
    final missPct = inputTokens > 0 ? 100 - hitPct : 0;

    return Padding(
      padding: const EdgeInsets.only(left: 18, right: 2, bottom: 8),
      child: Column(
        children: [
          _AccordionRow(label: '输入（缓存命中）', percent: hitPct, value: formatTokensFull(cacheReads), tokens: t),
          const SizedBox(height: 6),
          _AccordionRow(label: '输入（缓存未命中）', percent: missPct, value: formatTokensFull(cacheMiss), tokens: t),
          const SizedBox(height: 6),
          _AccordionRow(label: '输出', value: formatTokensFull(outputs), tokens: t),
          if (cacheWrites > 0) ...[
            const SizedBox(height: 6),
            _AccordionRow(label: '缓存写入', value: formatTokensFull(cacheWrites), tokens: t),
          ],
          if (topModels.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (var i = 0; i < topModels.length && i < 3; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              _AccordionRow(
                label: topModels[i].name,
                percent: tokens > 0
                    ? ((topModels[i].tokens * 100) / tokens).round()
                    : null,
                value: formatTokensFull(topModels[i].tokens),
                tokens: t,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _AccordionRow extends StatelessWidget {
  const _AccordionRow({required this.label, required this.value, required this.tokens, this.percent});
  final String label;
  final String value;
  final AppThemeTokens tokens;
  final int? percent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: label, style: TextStyle(fontSize: 11, color: tokens.muted)),
                if (percent != null)
                  TextSpan(text: ' $percent%', style: TextStyle(fontSize: 11, color: tokens.faint)),
              ],
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: tokens.text,
            fontFamily: 'Menlo',
            fontFamilyFallback: const ['monospace'],
          ),
        ),
      ],
    );
  }
}
