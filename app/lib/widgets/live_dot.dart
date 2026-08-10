import 'package:flutter/material.dart';

import '../theme/theme_extension.dart';

// ============================================================
// LiveDot —— 实时指示灯,对照原型 .live-dot。
// 7×7 绿点 + 8px glow 阴影 + 2s 脉冲(opacity 100%↔45%)。
// 文字 11 色 green(对照 .live-dot)。降级轮询场景由调用方改色/改文案。
// ============================================================

class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.text = '实时', this.color});
  final String text;
  final Color? color; // 默认 green,轮询降级时外部传 muted/amber

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 1.0, end: 0.45).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final color = widget.color ?? t.green;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            return Opacity(
              opacity: _pulse.value,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  // 8px glow(对照 box-shadow: 0 0 8px rgba(34,197,94,.8))
                  boxShadow: [
                    BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: 8),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 6),
        Text(
          widget.text,
          style: TextStyle(fontSize: 11, color: color),
        ),
      ],
    );
  }
}
