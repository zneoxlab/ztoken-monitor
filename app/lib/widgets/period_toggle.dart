import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/view_period.dart';
import '../theme/theme_extension.dart';

// 头部周期切换:今日 → 本月 → 本年 → 累计。
class PeriodToggle extends ConsumerWidget {
  const PeriodToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final period = ref.watch(viewPeriodProvider);

    return GestureDetector(
      onTap: () => ref.read(viewPeriodProvider.notifier).state = period.next,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: t.faint.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(period.shortLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.text)),
            const SizedBox(width: 3),
            Icon(Icons.swap_horiz, size: 14, color: t.muted),
          ],
        ),
      ),
    );
  }
}
