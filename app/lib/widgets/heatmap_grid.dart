import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/format/formatters.dart';
import '../theme/theme_extension.dart';
import 'popup_placement.dart';
import 'year_heatmap.dart';

// ============================================================
// HeatmapGrid —— 全年热力图,对照原型 .heatmap。
// 单击格子弹出详情(Overlay 定位,避免被卡片/滚动区域裁切),
// 点击其他区域关闭。月份轴用 Stack 定位,避免列宽过窄只显示数字。
// ============================================================

class HeatmapGrid extends StatefulWidget {
  const HeatmapGrid({
    super.key,
    required this.levels,
    required this.monthLabels,
    this.cells = const [],
    this.cellSize = 11,
    this.gap = 3,
    this.initialScrollToEnd = true,
  });

  final List<List<int>> levels;
  final List<String> monthLabels;
  final List<List<HeatmapCellMeta?>> cells;
  final double cellSize;
  final double gap;
  final bool initialScrollToEnd;

  @override
  State<HeatmapGrid> createState() => _HeatmapGridState();
}

class _CellSelection {
  const _CellSelection(this.column, this.row);
  final int column;
  final int row;
}

class _HeatmapGridState extends State<HeatmapGrid> {
  final _scrollController = ScrollController();
  final _gridKey = GlobalKey();
  final _popupKey = GlobalKey();
  var _didInitialScroll = false;
  _CellSelection? _selected;
  OverlayEntry? _overlayEntry;
  ScrollPosition? _ancestorScrollPosition;

  static const _popupEstimate = Size(120, 40);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_refreshOverlay);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindAncestorScroll();
  }

  @override
  void dispose() {
    _removeOverlay();
    _ancestorScrollPosition?.removeListener(_refreshOverlay);
    _scrollController.removeListener(_refreshOverlay);
    _scrollController.dispose();
    super.dispose();
  }

  void _bindAncestorScroll() {
    final position = Scrollable.maybeOf(context)?.position;
    if (identical(position, _ancestorScrollPosition)) return;
    _ancestorScrollPosition?.removeListener(_refreshOverlay);
    _ancestorScrollPosition = position;
    _ancestorScrollPosition?.addListener(_refreshOverlay);
  }

  void _scrollToEndIfNeeded() {
    if (!widget.initialScrollToEnd || _didInitialScroll) return;
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    _scrollController.jumpTo(max);
    _didInitialScroll = true;
  }

  @override
  void didUpdateWidget(covariant HeatmapGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.levels.length != widget.levels.length) {
      _didInitialScroll = false;
      _dismiss();
      SchedulerBinding.instance.addPostFrameCallback((_) => _scrollToEndIfNeeded());
    }
  }

  HeatmapCellMeta? _metaAt(int col, int row) {
    if (widget.cells.length <= col || widget.cells[col].length <= row) return null;
    return widget.cells[col][row];
  }

  void _selectCell(int col, int row) {
    final meta = _metaAt(col, row);
    if (meta == null || meta.date.isEmpty) {
      _dismiss();
      return;
    }
    setState(() => _selected = _CellSelection(col, row));
    WidgetsBinding.instance.addPostFrameCallback((_) => _showOverlay());
  }

  void _dismiss() {
    _removeOverlay();
    if (_selected != null) setState(() => _selected = null);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _refreshOverlay() {
    _overlayEntry?.markNeedsBuild();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refineOverlayPlacement());
  }

  void _showOverlay() {
    _removeOverlay();
    final sel = _selected;
    if (sel == null || !mounted) return;
    final meta = _metaAt(sel.column, sel.row);
    if (meta == null || meta.date.isEmpty) return;

    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (overlayContext) => _buildOverlayPopup(overlayContext, sel, meta),
    );
    overlay.insert(_overlayEntry!);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refineOverlayPlacement());
  }

  void _refineOverlayPlacement() {
    if (_overlayEntry == null || !mounted) return;
    _overlayEntry!.markNeedsBuild();
  }

  Widget _buildOverlayPopup(BuildContext overlayContext, _CellSelection sel, HeatmapCellMeta meta) {
    final t = Theme.of(overlayContext).extension<AppThemeTokens>()!;
    final gridBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (gridBox == null || !gridBox.hasSize) return const SizedBox.shrink();

    final cellLocal = Offset(
      _columnLeft(sel.column),
      sel.row * (widget.cellSize + widget.gap),
    );
    final cellGlobal = gridBox.localToGlobal(cellLocal);
    final popupBox = _popupKey.currentContext?.findRenderObject() as RenderBox?;
    final popupSize = popupBox?.hasSize == true ? popupBox!.size : _popupEstimate;
    final topLeft = computePopupTopLeft(
      anchorTopLeft: cellGlobal,
      anchorSize: Size(widget.cellSize, widget.cellSize),
      popupSize: popupSize,
      viewport: popupViewport(overlayContext),
    );

    final dt = DateTime.tryParse(meta.date);
    final title = dt != null ? '${dt.month}月${dt.day}日' : meta.date;
    final detail = meta.tokens > 0 ? formatTokensCompact(meta.tokens) : '无活动';

    return Stack(
      children: [
        Positioned(
          left: topLeft.dx,
          top: topLeft.dy,
          child: Material(
            key: _popupKey,
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 120),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: t.panel,
                border: Border.all(color: t.line),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: t.text)),
                  Text(detail, style: TextStyle(fontSize: 10, color: t.muted)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _columnLeft(int col) => col * (widget.cellSize + widget.gap);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final columns = <Widget>[];
    for (var c = 0; c < widget.levels.length; c++) {
      if (c > 0) columns.add(SizedBox(width: widget.gap));
      columns.add(
        Column(
          children: [
            for (var r = 0; r < widget.levels[c].length; r++) ...[
              if (r > 0) SizedBox(height: widget.gap),
              _Cell(
                level: widget.levels[c][r],
                size: widget.cellSize,
                selected: _selected?.column == c && _selected?.row == r,
                onTap: () => _selectCell(c, r),
              ),
            ],
          ],
        ),
      );
    }

    final gridWidth = widget.levels.isEmpty
        ? 0.0
        : widget.levels.length * widget.cellSize + (widget.levels.length - 1) * widget.gap;
    final gridHeight = widget.levels.isEmpty
        ? 0.0
        : widget.levels.first.length * widget.cellSize +
            (widget.levels.first.length - 1) * widget.gap;

    final monthAxis = SizedBox(
      width: gridWidth,
      height: 14,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var c = 0; c < widget.monthLabels.length; c++)
            if (widget.monthLabels[c].isNotEmpty)
              Positioned(
                left: _columnLeft(c),
                bottom: 0,
                child: Text(
                  widget.monthLabels[c],
                  style: TextStyle(fontSize: 9, color: t.faint),
                ),
              ),
        ],
      ),
    );

    SchedulerBinding.instance.addPostFrameCallback((_) => _scrollToEndIfNeeded());

    return TapRegion(
      onTapOutside: (_) {
        if (_selected != null) _dismiss();
      },
      child: GestureDetector(
        onTap: _dismiss,
        behavior: HitTestBehavior.opaque,
        child: SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                key: _gridKey,
                width: gridWidth,
                height: gridHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: columns,
                ),
              ),
              SizedBox(height: widget.gap + 2),
              monthAxis,
            ],
          ),
        ),
      ),
    );
  }
}

/// 热力图图例:右对齐 "少 [5 格] 多"。
class HeatmapLegend extends StatelessWidget {
  const HeatmapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final colors = [
      t.panel2,
      t.accent.withValues(alpha: 0.25),
      t.accent.withValues(alpha: 0.45),
      t.accent.withValues(alpha: 0.70),
      t.accent,
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('少', style: TextStyle(fontSize: 10, color: t.faint)),
        const SizedBox(width: 4),
        for (final c in colors) ...[
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
          ),
        ],
        Text('多', style: TextStyle(fontSize: 10, color: t.faint)),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.level,
    required this.size,
    required this.onTap,
    this.selected = false,
  });

  final int level;
  final double size;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final color = switch (level) {
      0 => t.panel2,
      1 => t.accent.withValues(alpha: 0.25),
      2 => t.accent.withValues(alpha: 0.45),
      3 => t.accent.withValues(alpha: 0.70),
      _ => t.accent,
    };

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
          border: selected ? Border.all(color: t.text, width: 1.2) : null,
        ),
      ),
    );
  }
}
