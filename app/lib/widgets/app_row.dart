import 'package:flutter/material.dart';

import '../theme/theme_extension.dart';
import 'share_bar.dart';

// ============================================================
// AppRow —— 列表行,对照原型 .row + 展开 .expand。
// 不用 M3 ListTile:默认 padding/字号不符(UI-IMPL.md §0/§5)。
// 结构:Row[ 图标 34×34(panel2,radius 9,内 Image 22×22),
//   SizedBox(11), Expanded(Column[名称 13.5/w600, 副标题 11 muted]),
//   Column[end][数值 13.5/w700 mono, 花费 11 accent mono] ]。
// 行分隔:除首行外顶部 1px line。点击 InkWell 展开 AnimatedCrossFade。
// ============================================================

class AppRowData {
  const AppRowData({
    required this.iconAsset,
    required this.name,
    this.subtitle,
    this.value,
    this.cost,
    this.shareColor, // 占比条色(厂商色),null 不显条
    this.share, // 0..1 占比,null 不显条
    this.expandKv = const [], // 展开面板 kv 行 [{k, v}]
    this.iconWidget, // 优先于 iconAsset(支持 ProviderIcon 等自绘图标)
  });

  final String iconAsset;
  final String name;
  final String? subtitle;
  final String? value;
  final String? cost;
  final Color? shareColor;
  final double? share;
  final List<({String k, String v})> expandKv;
  final Widget? iconWidget;
}

class AppRow extends StatefulWidget {
  const AppRow({
    super.key,
    required this.data,
    this.showTopDivider = false, // 首行 false,其余 true
    this.shareBar, // 可选外部占比条(ShareBar),null 不显
  });

  final AppRowData data;
  final bool showTopDivider;
  final Widget? shareBar;

  @override
  State<AppRow> createState() => _AppRowState();
}

class _AppRowState extends State<AppRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final d = widget.data;
    final hasExpand = d.expandKv.isNotEmpty;

    return Column(
      children: [
        // 行本体:顶部分隔线用 border.top(不用 Divider,它有默认缩进)
        Container(
          decoration: BoxDecoration(
            border: widget.showTopDivider
                ? Border(top: BorderSide(color: t.line, width: 1))
                : null,
          ),
          child: InkWell(
            onTap: hasExpand ? () => setState(() => _expanded = !_expanded) : null,
            child: Padding(
              // .row padding 11 2
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
              child: Row(
                children: [
                  // .ricon: 34×34 panel2 radius 9,内图标 22×22
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: t.panel2,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.center,
                    child: d.iconWidget ??
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: Image.asset(
                            d.iconAsset,
                            width: 22,
                            height: 22,
                            fit: BoxFit.contain,
                          ),
                        ),
                  ),
                  const SizedBox(width: 11),
                  // .rmain
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.name,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: t.text,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (d.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            d.subtitle!,
                            style: TextStyle(fontSize: 11, color: t.muted),
                          ),
                        ],
                        if (widget.shareBar == null && d.share != null && d.shareColor != null)
                          ShareBar(share: d.share!, color: d.shareColor!),
                      ],
                    ),
                  ),
                  // .rval: 右侧数值列
                  if (d.value != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // 数值 13.5 w700 等宽
                        Text(
                          d.value!,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: t.text,
                            fontFamily: 'Menlo',
                            fontFamilyFallback: const ['monospace'],
                          ),
                        ),
                        if (d.cost != null) ...[
                          const SizedBox(height: 2),
                          // 花费 11 等宽 accent
                          Text(
                            d.cost!,
                            style: TextStyle(
                              fontSize: 11,
                              color: t.accent,
                              fontFamily: 'Menlo',
                              fontFamilyFallback: const ['monospace'],
                            ),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        // 可选占比条(行内)
        if (widget.shareBar != null)
          Padding(
            padding: const EdgeInsets.only(left: 45, right: 2),
            child: widget.shareBar!,
          ),
        // 展开面板 .expand:AnimatedCrossFade
        if (hasExpand)
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            sizeCurve: Curves.easeOutCubic,
            crossFadeState:
                _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: _ExpandPanel(kv: d.expandKv),
          ),
      ],
    );
  }
}

// 展开面板 .expand:panel2 底,radius 10,内部 kv 两行 11.5 muted/b mono。
class _ExpandPanel extends StatelessWidget {
  const _ExpandPanel({required this.kv});
  final List<({String k, String v})> kv;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 0).copyWith(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.panel2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          for (var i = 0; i < kv.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    kv[i].k,
                    style: TextStyle(fontSize: 11.5, color: t.muted),
                  ),
                  Text(
                    kv[i].v,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: t.text,
                      fontFamily: 'Menlo',
                      fontFamilyFallback: const ['monospace'],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
