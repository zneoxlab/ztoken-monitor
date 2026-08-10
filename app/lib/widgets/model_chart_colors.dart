import 'package:flutter/material.dart';

import '../core/models/stats.dart';
import '../theme/app_colors.dart';

Color colorForModel(String model, int index) {
  if (model.isEmpty) return fallbackPalette[index % fallbackPalette.length];
  final hash = model.hashCode.abs();
  return fallbackPalette[(hash + index) % fallbackPalette.length];
}

List<String> topModelsFromDays(List<HistoryDay> days, {int limit = 5}) {
  final totals = _modelTotals(days.map((d) => d.perModel));
  if (totals.isEmpty) return const [];
  final sorted = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return sorted.take(limit).map((e) => e.key).toList();
}

List<String> topModelsFromMonths(List<HistoryMonth> months, {int limit = 5}) {
  final totals = _modelTotals(months.map((m) => m.perModel));
  if (totals.isEmpty) return const [];
  final sorted = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return sorted.take(limit).map((e) => e.key).toList();
}

Map<String, int> _modelTotals(Iterable<Map<String, HistoryBucket>> rows) {
  final totals = <String, int>{};
  for (final perModel in rows) {
    for (final e in perModel.entries) {
      totals[e.key] = (totals[e.key] ?? 0) + e.value.tokens;
    }
  }
  return totals;
}
