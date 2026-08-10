import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ztoken_monitor/widgets/popup_placement.dart';

void main() {
  test('computePopupTopLeft prefers above when space allows', () {
    const viewport = Rect.fromLTWH(0, 0, 400, 800);
    final pos = computePopupTopLeft(
      anchorTopLeft: const Offset(100, 200),
      anchorSize: const Size(11, 11),
      popupSize: const Size(120, 40),
      viewport: viewport,
    );
    expect(pos.dy, 200 - 4 - 40);
    expect(pos.dx, 100 + 11 / 2 - 60);
  });

  test('computePopupTopLeft flips below when top overflows', () {
    const viewport = Rect.fromLTWH(0, 0, 400, 800);
    final pos = computePopupTopLeft(
      anchorTopLeft: const Offset(100, 10),
      anchorSize: const Size(11, 11),
      popupSize: const Size(120, 40),
      viewport: viewport,
    );
    expect(pos.dy, 10 + 11 + 4);
  });

  test('computePopupTopLeft clamps horizontally inside viewport', () {
    const viewport = Rect.fromLTWH(0, 0, 200, 800);
    final pos = computePopupTopLeft(
      anchorTopLeft: const Offset(170, 200),
      anchorSize: const Size(11, 11),
      popupSize: const Size(120, 40),
      viewport: viewport,
    );
    expect(pos.dx, 80);
  });
}
