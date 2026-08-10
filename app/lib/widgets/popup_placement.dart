import 'dart:ui';

import 'package:flutter/material.dart';

/// 计算悬浮层在视口内的位置:优先在锚点上方,空间不足则翻转到下方,并水平夹紧。
Offset computePopupTopLeft({
  required Offset anchorTopLeft,
  required Size anchorSize,
  required Size popupSize,
  required Rect viewport,
  double gap = 4,
  bool preferAbove = true,
}) {
  final anchorBottom = anchorTopLeft.dy + anchorSize.height;
  final anchorCenterX = anchorTopLeft.dx + anchorSize.width / 2;

  final aboveTop = anchorTopLeft.dy - gap - popupSize.height;
  final belowTop = anchorBottom + gap;
  final spaceAbove = anchorTopLeft.dy - viewport.top;
  final spaceBelow = viewport.bottom - anchorBottom;

  double top;
  if (preferAbove && aboveTop >= viewport.top) {
    top = aboveTop;
  } else if (belowTop + popupSize.height <= viewport.bottom) {
    top = belowTop;
  } else if (spaceAbove >= spaceBelow) {
    top = (aboveTop).clamp(viewport.top, viewport.bottom - popupSize.height);
  } else {
    top = (belowTop).clamp(viewport.top, viewport.bottom - popupSize.height);
  }

  var left = anchorCenterX - popupSize.width / 2;
  if (left < viewport.left) left = viewport.left;
  if (left + popupSize.width > viewport.right) {
    left = viewport.right - popupSize.width;
  }

  return Offset(left, top);
}

/// 屏幕安全区域内的悬浮层边界(留 [margin] 边距)。
Rect popupViewport(BuildContext context, {double margin = 8}) {
  final media = MediaQuery.of(context);
  return Rect.fromLTWH(
    margin,
    media.padding.top + margin,
    media.size.width - margin * 2,
    media.size.height - media.padding.top - media.padding.bottom - margin * 2,
  );
}
