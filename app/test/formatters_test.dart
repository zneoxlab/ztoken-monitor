// 格式化器测试:tokens 紧凑 / amountMinor / 货币换算 / 日期。
import 'package:flutter_test/flutter_test.dart';
import 'package:ztoken_monitor/core/format/formatters.dart';

void main() {
  group('DisplayCurrency', () {
    test('fromCode 正确反查', () {
      expect(DisplayCurrency.fromCode('USD'), DisplayCurrency.usd);
      expect(DisplayCurrency.fromCode('CNY'), DisplayCurrency.cny);
      expect(DisplayCurrency.fromCode('HKD'), DisplayCurrency.hkd);
      expect(DisplayCurrency.fromCode('TWD'), DisplayCurrency.twd);
    });

    test('fromCode 未知/缺失回落 USD', () {
      expect(DisplayCurrency.fromCode(null), DisplayCurrency.usd);
      expect(DisplayCurrency.fromCode('EUR'), DisplayCurrency.usd);
      expect(DisplayCurrency.fromCode(''), DisplayCurrency.usd);
    });

    test('4 种货币均带符号', () {
      expect(DisplayCurrency.usd.symbol, '\$');
      expect(DisplayCurrency.cny.symbol, '¥');
    });
  });

  group('formatTokensCompact', () {
    test('0 → "0"', () {
      expect(formatTokensCompact(0), '0');
    });

    test('千级 → K', () {
      expect(formatTokensCompact(1234), contains('K'));
    });

    test('百万级 → M', () {
      expect(formatTokensCompact(1200000), contains('M'));
    });

    test('十亿级 → B', () {
      expect(formatTokensCompact(2300000000), contains('B'));
    });
  });

  group('formatTokensFull', () {
    test('千分位整数', () {
      expect(formatTokensFull(1234567), '1,234,567');
    });

    test('0 → "0"', () {
      expect(formatTokensFull(0), '0');
    });
  });

  group('formatTokensApproxZh', () {
    test('大数显示约等于紧凑格式', () {
      expect(formatTokensApproxZh(190000000), '≈ 190M tokens');
    });

    test('0', () {
      expect(formatTokensApproxZh(0), '≈ 0 tokens');
    });
  });

  group('formatTokensApproxInline', () {
    test('inline suffix without tokens word', () {
      expect(formatTokensApproxInline(190000000), '≈ 190M');
    });
  });

  group('金额格式化', () {
    test('amountMinor 除以 100', () {
      expect(amountMinorToUsd(9000), 90.0);
      expect(amountMinorToUsd(0), 0.0);
      expect(amountMinorToUsd(105), 1.05);
    });

    test('USD 不换算,2 位小数', () {
      expect(formatMoney(8.36, DisplayCurrency.usd), '\$8.36');
    });

    test('CNY 按汇率换算', () {
      // 8.36 USD × 7.18 = 60.0248 → "¥60.02"
      expect(formatMoney(8.36, DisplayCurrency.cny), '¥60.02');
    });

    test('负值带负号', () {
      expect(formatMoney(-8.36, DisplayCurrency.usd), '-\$8.36');
    });

    test('amountMinor 一步格式化', () {
      // 9000 分 = 90 USD = ¥646.20
      expect(
        formatAmountMinor(9000, DisplayCurrency.cny),
        '¥${(90 * 7.18).toStringAsFixed(2)}',
      );
    });
  });

  group('汇率更新', () {
    test('setExchangeRates 覆盖快照但保留 USD 基准', () {
      setExchangeRates({DisplayCurrency.cny: 7.5});
      expect(rateOf(DisplayCurrency.cny), 7.5);
      expect(rateOf(DisplayCurrency.usd), 1.0); // 基准不变
      expect(rateOf(DisplayCurrency.hkd), 7.80); // 未更新项保留快照
    });

    test('非法汇率被忽略', () {
      setExchangeRates({DisplayCurrency.hkd: -1, DisplayCurrency.twd: 0});
      expect(rateOf(DisplayCurrency.hkd), greaterThan(0));
      expect(rateOf(DisplayCurrency.twd), greaterThan(0));
    });

    tearDown(() {
      // 复位回快照,避免污染其它测试
      setExchangeRates({});
    });
  });

  group('日期格式化', () {
    final now = DateTime(2026, 8, 6, 12, 0);

    test('formatDateShort 本地化', () {
      expect(formatDateShort(DateTime(2026, 8, 6)), '8月6日');
    });

    test('formatRelative 刚刚', () {
      expect(formatRelative(now.add(const Duration(seconds: 30)), now), '刚刚');
    });

    test('formatRelative 分钟', () {
      expect(
        formatRelative(now.subtract(const Duration(minutes: 5)), now),
        '5分钟前',
      );
    });

    test('formatRelative 小时', () {
      expect(
        formatRelative(now.subtract(const Duration(hours: 2)), now),
        '2小时前',
      );
    });

    test('formatRelative 昨天', () {
      expect(
        formatRelative(now.subtract(const Duration(days: 1)), now),
        '昨天',
      );
    });
  });
}
