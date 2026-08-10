import 'package:flutter/material.dart';

import '../theme/theme_extension.dart';

// ============================================================
// ProviderIcon —— 厂商图标,对照 assets/icons/<id>.png。
// 优先用图标文件(Image.asset);文件缺失或加载失败时降级为首字母色块。
// 背景色用 vendorColors[id] 半透明;圆形 34×34 radius 9(与原型 ricon 一致)。
// ============================================================

// vendor 颜色表(与 theme/app_colors.dart 同步,但为避免循环依赖此处内联精简版;
// 完整色表以 app_colors.dart 为准,这里只放图标降级色块用的常用项 + 默认)。
const _providerColors = <String, Color>{
  'claude': Color(0xFFCC7C5E),
  'codex': Color(0xFF49A3B0),
  'cursor': Color(0xFF8FA3BF),
  'copilot': Color(0xFF9B8CF2),
  'kimi': Color(0xFF5B6B85),
  'deepseek': Color(0xFF4D6BFE),
  'openrouter': Color(0xFF6566F1),
  'antigravity': Color(0xFF4285F4),
  'opencode': Color(0xFF7D8590),
  'qwen': Color(0xFFA259E6),
};

class ProviderIcon extends StatelessWidget {
  const ProviderIcon({
    super.key,
    required this.providerId,
    this.size = 34,
    this.radius = 9,
  });

  /// 厂商 id(与 `assets/icons/<id>.png` 文件名一致)。
  final String providerId;

  /// 图标边长(像素)。
  final double size;

  /// 背景圆角(像素)。
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final color = _providerColors[providerId] ?? t.accent;
    final bg = color.withValues(alpha: 0.18);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      // 优先图标文件;加载失败(资产缺失/损坏)降级首字母。
      // builder 返回非空 widget 时跳过 fallback;抛错或返回 null 进 fallback。
      child: _IconImage(id: providerId, size: size, fallbackColor: color),
    );
  }
}

// 图标图片:文件存在用 Image.asset,缺失/解码失败降级首字母色块。
// 用 builder 模式捕获 Image.asset 的加载异常 AssetImage 同步解析失败场景。
// 已存在图标文件的 provider id 集合(与 assets/icons/*.png 同步)。
// 不在此集合的 provider 走首字母降级,避免 Image.asset 抛"资产缺失"。
// 新增图标文件时同步加到这里。
const knownProviderIconIds = <String>{
  'antigravity', 'app', 'claude', 'cline', 'codebuddy', 'codex', 'copilot',
  'cursor', 'deepseek', 'hermes-agent', 'kilocode', 'kimi', 'kiro', 'mimo-code',
  'minimax', 'newapi', 'ollama', 'openclaw', 'opencode', 'openrouter', 'os-apple',
  'os-linux', 'os-windows', 'pi', 'proma', 'qoder', 'qwen', 'volcengine', 'workbuddy',
  'xai', 'zcode', 'zed',
};

class _IconImage extends StatelessWidget {
  const _IconImage({required this.id, required this.size, required this.fallbackColor});
  final String id;
  final double size;
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    // 无 id 或无图标文件:直接首字母降级
    if (id.isEmpty || !knownProviderIconIds.contains(id)) {
      return Text(
        id.isNotEmpty ? id[0].toUpperCase() : '?',
        style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w700, color: fallbackColor),
      );
    }
    return Image.asset(
      'assets/icons/$id.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      // 文件存在但解码损坏时兜底
      errorBuilder: (context, error, stackTrace) => Text(
        id[0].toUpperCase(),
        style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w700, color: fallbackColor),
      ),
    );
  }
}
