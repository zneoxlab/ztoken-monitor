import 'package:flutter/material.dart';

// ============================================================
// 主题色令牌 —— 与 app-prototype/themes.css + base.css 一一对应。
// 4 套主题:石墨薄荷(默认) / 星海蓝 / 黑曜 / 纸白(浅色)。
// 厂商色与桌面端 usageCharts.js clientColors 对齐。
// 这里只放纯数据(Color 常量 + 数据类),ThemeExtension 与 ThemeData
// 构建在 theme_extension.dart / app_theme.dart。
// ============================================================

// 单个主题的完整色令牌。字段名对应 CSS 变量,方便逐项核对。
// accentRgb 用于玻璃材质的极光渐变(需要透明度叠加)。
class AppColorTokens {
  const AppColorTokens({
    required this.brightness,
    required this.bg,
    required this.panel,
    required this.panel2,
    required this.line,
    required this.text,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.accentRgb,
    required this.green,
    required this.red,
    required this.amber,
    required this.blue,
    required this.tabbarBg,
  });

  final Brightness brightness; // 决定深浅色,纸白为 light
  final Color bg; // --bg 应用背景
  final Color panel; // --panel 卡片
  final Color panel2; // --panel-2 次级卡片 / 凹陷区
  final Color line; // --line 分隔线
  final Color text; // --text 主文字
  final Color muted; // --muted 次要文字
  final Color faint; // --faint 更弱文字 / 图标未选中
  final Color accent; // --accent 强调色
  final List<int> accentRgb; // --accent-rgb,用于玻璃渐变透明度
  final Color green; // --green 成功 / 在线
  final Color red; // --red 危险
  final Color amber; // --amber 警告
  final Color blue; // --blue 信息蓝
  final Color tabbarBg; // --tabbar-bg 底栏背景(带透明度)

  // 玻璃材质下卡片的填充色:以主背景色为底,避免 panel 色+饱和模糊染紫。
  Color get glassPanelFill {
    if (brightness == Brightness.light) {
      return const Color(0x8CFFFFFF); // 白 55%
    }
    return bg.withValues(alpha: 0.55);
  }

  // 玻璃材质卡片边框色:深色白 16%,浅色白 75%。
  Color get glassBorder {
    if (brightness == Brightness.light) {
      return const Color(0xBFFFFFFF); // 白 75%
    }
    return const Color(0x29FFFFFF); // 白 16%
  }

  // 玻璃材质顶部内高光:深色白 14%,浅色白 90%。
  Color get glassHighlight {
    if (brightness == Brightness.light) {
      return const Color(0xE6FFFFFF); // 白 90%
    }
    return const Color(0x24FFFFFF); // 白 14%
  }
}

// ---------- 石墨薄荷(默认,深色) ----------
// 源自 base.css :root,桌面默认主题压深一档。
const graphiteMint = AppColorTokens(
  brightness: Brightness.dark,
  bg: Color(0xFF1B1D20),
  panel: Color(0xFF23262A),
  panel2: Color(0xFF2A2E33),
  line: Color(0x12FFFFFF), // rgba(255,255,255,0.07)
  text: Color(0xFFEEF5FB),
  muted: Color(0xFFA3ADBB),
  faint: Color(0xFF6B7480),
  accent: Color(0xFFB7EAD4),
  accentRgb: [183, 234, 212],
  green: Color(0xFF22C55E),
  red: Color(0xFFE5534B),
  amber: Color(0xFFD4A04A),
  blue: Color(0xFF58A6FF),
  tabbarBg: Color(0xEB1B1D20), // rgba(27,29,32,0.92)
);

// ---------- 星海蓝(深色) ----------
const starryBlue = AppColorTokens(
  brightness: Brightness.dark,
  bg: Color(0xFF161C27),
  panel: Color(0xFF1D2532),
  panel2: Color(0xFF252F40),
  line: Color(0x1A94B2E4), // rgba(148,178,228,0.10)
  text: Color(0xFFEAF2FD),
  muted: Color(0xFF93A5C2),
  faint: Color(0xFF62708B),
  accent: Color(0xFF58A6FF),
  accentRgb: [88, 166, 255],
  green: Color(0xFF3FB68B),
  red: Color(0xFFE5534B),
  amber: Color(0xFFD4A04A),
  blue: Color(0xFF58A6FF),
  tabbarBg: Color(0xEB161C27), // rgba(22,28,39,0.92)
);

// ---------- 黑曜(深色,近黑) ----------
const obsidian = AppColorTokens(
  brightness: Brightness.dark,
  bg: Color(0xFF0B0C0E),
  panel: Color(0xFF14161A),
  panel2: Color(0xFF1C1F24),
  line: Color(0x14FFFFFF), // rgba(255,255,255,0.08)
  text: Color(0xFFECEEF2),
  muted: Color(0xFF8F949C),
  faint: Color(0xFF5C626B),
  accent: Color(0xFFE6E8EC),
  accentRgb: [230, 232, 236],
  green: Color(0xFF22C55E),
  red: Color(0xFFE5534B),
  amber: Color(0xFFD4A04A),
  blue: Color(0xFF58A6FF),
  tabbarBg: Color(0xF00B0C0E), // rgba(11,12,14,0.94)
);

// ---------- 纸白(浅色) ----------
const porcelain = AppColorTokens(
  brightness: Brightness.light,
  bg: Color(0xFFEEF0F3),
  panel: Color(0xFFFFFFFF),
  panel2: Color(0xFFE6E9EE),
  line: Color(0x1A181C24), // rgba(24,28,36,0.10)
  text: Color(0xFF1C1F26),
  muted: Color(0xFF5B626D),
  faint: Color(0xFF9AA2AD),
  accent: Color(0xFF2563EB),
  accentRgb: [37, 99, 235],
  green: Color(0xFF18794E),
  red: Color(0xFFE5534B),
  amber: Color(0xFFD4A04A),
  blue: Color(0xFF58A6FF),
  tabbarBg: Color(0xEBFFFFFF), // rgba(255,255,255,0.92)
);

// 全部主题,供枚举切换。顺序即设置页展示顺序。
const appColorTokensList = <AppColorTokens>[
  graphiteMint,
  starryBlue,
  obsidian,
  porcelain,
];

// ============================================================
// 厂商色 —— 图表 / 占比条 / 工具图标背景着色。
// 与桌面端 usageCharts.js clientColors 对齐;近黑厂商色在深色主题
// 下需提亮(任务7 图表层处理),此处存原始值。
// key 为 client id(与 assets/icons/<id>.png 文件名一致)。
// ============================================================
const vendorColors = <String, Color>{
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

// 备用调色板:未在 vendorColors 中列出的厂商按出现顺序取色。
// 来源 GOAL.md §7"未列出厂商走备用调色板"。
const fallbackPalette = <Color>[
  Color(0xFF6BB6FF),
  Color(0xFFE879A6),
  Color(0xFFF6B26B),
  Color(0xFF8DE05B),
  Color(0xFFC77DFF),
  Color(0xFF5DD3C8),
  Color(0xFFFFD56B),
  Color(0xFF7DA8E8),
];

// 圆角令牌:--radius 14 / --radius-s 10。
const kRadiusCard = 14.0;
const kRadiusSmall = 10.0;
