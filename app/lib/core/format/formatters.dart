import 'package:intl/intl.dart';

// ============================================================
// 格式化器 —— tokens 紧凑格式 / 金额(amountMinor)/ 货币换算。
// 对照 GOAL.md §6.4/§6.5:
//  - tokens 用 K/M/B 紧凑格式(NumberFormat.compact)
//  - amountMinor 是整数"分",除以 100
//  - 显示货币 USD/CNY/HKD/TWD,内置静态汇率快照,USD 为基准
//  - 所有 costUsd 先存 USD 原值,展示层换算
// ============================================================

// 显示货币:协议支持的 4 种(docs/API.md 校验范围)。
enum DisplayCurrency {
  usd('USD', '\$'),
  cny('CNY', '¥'),
  hkd('HKD', 'HK\$'),
  twd('TWD', 'NT\$');

  const DisplayCurrency(this.code, this.symbol);
  final String code; // ISO 4217,与协议 currency 字段一致
  final String symbol; // 展示符号

  // 由协议 currency code 反查;未知/缺失回落 USD(前向兼容)。
  static DisplayCurrency fromCode(String? code) {
    if (code == null) return DisplayCurrency.usd;
    for (final c in DisplayCurrency.values) {
      if (c.code == code) return c;
    }
    return DisplayCurrency.usd;
  }
}

// 静态汇率快照:1 USD 兑换目标货币(GOAL.md §6.5 内置快照)。
// 启动时若 hub 附带汇率或公开源可用则更新;无则沿用此快照。
// 数值为近似值,仅用于展示,非结算。
const _usdRateSnapshot = <DisplayCurrency, double>{
  DisplayCurrency.usd: 1.0,
  DisplayCurrency.cny: 7.18,
  DisplayCurrency.hkd: 7.80,
  DisplayCurrency.twd: 32.0,
};

// 可变汇率表:默认等于快照,启动后可被 setExchangeRates 更新。
Map<DisplayCurrency, double> _rates = Map.from(_usdRateSnapshot);

// 更新汇率(任务7 启动时从 hub 响应或公开源拉取后调用)。
void setExchangeRates(Map<DisplayCurrency, double> newRates) {
  // 始终保留 USD=1.0 基准,忽略非法值
  final merged = Map<DisplayCurrency, double>.from(_usdRateSnapshot);
  newRates.forEach((cur, rate) {
    if (rate > 0) merged[cur] = rate;
  });
  _rates = merged;
}

double rateOf(DisplayCurrency cur) => _rates[cur] ?? _usdRateSnapshot[cur]!;

// ============================================================
// tokens 格式化
// ============================================================

// 紧凑格式:1234 → 1.2K,1_200_000 → 1.2M。英文 locale 保证 K/M/B 后缀。
String formatTokensCompact(num tokens) {
  if (tokens == 0) return '0';
  return NumberFormat.compact(locale: 'en_US').format(tokens);
}

// 带单位全量格式:1234567 → "1.23M tokens"。明细页/大数字场景。
String formatTokensWithUnit(num tokens) {
  return '${formatTokensCompact(tokens)} tokens';
}

// 原始整数(千分位):1_234_567 → "1,234,567"。展开详情用。
String formatTokensFull(num tokens) {
  return NumberFormat.decimalPatternDigits(locale: 'en_US', decimalDigits: 0)
      .format(tokens);
}

// 约等于紧凑格式(独立行):190_000_000 → "≈ 190M tokens"。
String formatTokensApproxZh(num tokens) {
  if (tokens == 0) return '≈ 0 tokens';
  return '≈ ${formatTokensCompact(tokens)} tokens';
}

// 与完整数字同一行时的紧凑后缀:190_000_000 → "≈ 190M"。
String formatTokensApproxInline(num tokens) {
  if (tokens == 0) return '≈ 0';
  return '≈ ${formatTokensCompact(tokens)}';
}

// ============================================================
// 金额格式化(amountMinor / costUsd)
// ============================================================

// amountMinor(整数分)→ 美元小数。协议字段除以 100。
double amountMinorToUsd(int amountMinor) => amountMinor / 100.0;

// costUsd(美元小数)→ 目标显示货币小数,按当前汇率换算。
double usdTo(double usd, DisplayCurrency to) => usd * rateOf(to);

// 金额格式化:usd → 目标货币,带符号 + 2 位小数。
// 例:usd=8.36, to=CNY → "¥60.02";usd=-8.36 → "-¥60.02"。
String formatMoney(double usd, DisplayCurrency to) {
  final value = usdTo(usd, to);
  final sign = value < 0 ? '-' : '';
  return '$sign${to.symbol}${value.abs().toStringAsFixed(2)}';
}

// amountMinor → 直接格式化为目标货币(一步到位,订阅 topUps 等场景)。
String formatAmountMinor(int amountMinor, DisplayCurrency to) {
  return formatMoney(amountMinorToUsd(amountMinor), to);
}

// ============================================================
// 日期格式化(趋势/会话 lastUsedAt 等)
// ============================================================

// "2026-08-06" → "8月6日"(本地化短日期)。
// 用显式模式串(含中文字面量),不传 locale,避免运行时 locale 数据初始化依赖。
String formatDateShort(DateTime date) {
  return DateFormat('M月d日').format(date);
}

// "2026-08-06 14:30" → "08-06 14:30"(明细会话行用)。
String formatDateTimeShort(DateTime date) {
  return DateFormat('MM-dd HH:mm').format(date);
}

// 活跃时长:ms → "4h 12m" / "32m"(对照桌面 formatActiveDuration)。
String formatActiveDuration(int ms) {
  final totalMinutes = (ms / 60000).round().clamp(0, 1 << 30);
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m';
  return '0m';
}

// 相对时间:lastUsedAt → "3分钟前 / 2小时前 / 昨天 / 3天前"。
String formatRelative(DateTime time, DateTime now) {
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
  if (diff.inHours < 24) return '${diff.inHours}小时前';
  if (diff.inDays == 1) return '昨天';
  if (diff.inDays < 30) return '${diff.inDays}天前';
  return formatDateShort(time);
}

// 设备同步副标题:"3 台设备 · 刚刚同步"。
String formatDevicesSyncSubtitle(int deviceCount, DateTime? latestSync, DateTime now) {
  if (deviceCount <= 0) return '暂无设备';
  if (latestSync == null) return '$deviceCount 台设备';
  final rel = formatRelative(latestSync, now);
  if (rel == '刚刚') return '$deviceCount 台设备 · 刚刚同步';
  return '$deviceCount 台设备 · $rel同步';
}
