// 配额百分比展示口径。默认沿用移动端现有的“剩余”展示。
enum LimitDisplayMode { remaining, used }

LimitDisplayMode parseLimitDisplayMode(String? raw) {
  return switch (raw?.trim().toLowerCase()) {
    'used' => LimitDisplayMode.used,
    _ => LimitDisplayMode.remaining,
  };
}

String limitDisplayModeLabel(LimitDisplayMode mode) {
  return switch (mode) {
    LimitDisplayMode.remaining => '剩余',
    LimitDisplayMode.used => '已用',
  };
}
