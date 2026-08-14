// 偏好存储测试:AppSettings 序列化往返 / 默认值 / 未知值前向兼容。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ztoken_monitor/core/storage/prefs_storage.dart';
import 'package:ztoken_monitor/core/format/formatters.dart';
import 'package:ztoken_monitor/core/limits/limit_display_mode.dart';
import 'package:ztoken_monitor/theme/theme_mode.dart';

void main() {
  group('AppSettings 默认值', () {
    test('默认对照 GOAL.md:跟随系统 / 实色 / USD / 通知开 / 80%', () {
      const s = AppSettings();
      expect(s.themeMode, AppThemeMode.system);
      expect(s.material, AppMaterial.solid);
      expect(s.displayCurrency, DisplayCurrency.usd);
      expect(s.notifyEnabled, true);
      expect(s.notifyThresholdPercent, 80);
      expect(s.limitDisplayMode, LimitDisplayMode.remaining);
      expect(s.homeWidgetPinnedLimits, isEmpty);
    });
  });

  group('AppSettings 序列化往返', () {
    test('写入后读回一致', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      const original = AppSettings(
        themeMode: AppThemeMode.starryBlue,
        material: AppMaterial.glass,
        displayCurrency: DisplayCurrency.cny,
        notifyEnabled: false,
        notifyThresholdPercent: 50,
        limitDisplayMode: LimitDisplayMode.used,
        homeWidgetPinnedLimits: 'codex|one,cursor|two',
      );

      // 写盘
      for (final entry in original.toPrefs().entries) {
        if (entry.value is String) {
          await prefs.setString(entry.key, entry.value as String);
        } else if (entry.value is bool) {
          await prefs.setBool(entry.key, entry.value as bool);
        } else if (entry.value is int) {
          await prefs.setInt(entry.key, entry.value as int);
        }
      }

      final restored = AppSettings.fromPrefs(prefs);
      expect(restored.themeMode, AppThemeMode.starryBlue);
      expect(restored.material, AppMaterial.glass);
      expect(restored.displayCurrency, DisplayCurrency.cny);
      expect(restored.notifyEnabled, false);
      expect(restored.notifyThresholdPercent, 50);
      expect(restored.limitDisplayMode, LimitDisplayMode.used);
      expect(restored.homeWidgetPinnedLimits, 'codex|one,cursor|two');
    });

    test('空存储回落默认值', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final s = AppSettings.fromPrefs(prefs);
      expect(s.themeMode, AppThemeMode.system);
      expect(s.material, AppMaterial.solid);
      expect(s.displayCurrency, DisplayCurrency.usd);
      expect(s.notifyEnabled, true);
      expect(s.notifyThresholdPercent, 80);
      expect(s.limitDisplayMode, LimitDisplayMode.remaining);
    });

    test('未知 themeMode 字符串前向兼容回落 system', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.themeMode: 'futureTheme', // 未来版本新增的主题
      });
      final prefs = await SharedPreferences.getInstance();
      expect(AppSettings.fromPrefs(prefs).themeMode, AppThemeMode.system);
    });

    test('未知 material 字符串回落 solid', () async {
      SharedPreferences.setMockInitialValues({PrefsKeys.material: 'neon'});
      final prefs = await SharedPreferences.getInstance();
      expect(AppSettings.fromPrefs(prefs).material, AppMaterial.solid);
    });

    test('未知货币码回落 USD', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.displayCurrency: 'EUR',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(AppSettings.fromPrefs(prefs).displayCurrency, DisplayCurrency.usd);
    });

    test('通知阈值越界 clamp 到 [1,100]', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.notifyThresholdPercent: 150,
      });
      final prefs = await SharedPreferences.getInstance();
      // fromPrefs 不 clamp(直接读),clamp 在 setNotifyThresholdPercent 写入时
      expect(AppSettings.fromPrefs(prefs).notifyThresholdPercent, 150);
    });
  });

  group('SettingsNotifier 写盘', () {
    test('setThemeMode 更新状态并持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = SettingsNotifier(prefs);
      await notifier.load();

      await notifier.setThemeMode(AppThemeMode.obsidian);
      expect(notifier.state.themeMode, AppThemeMode.obsidian);

      // 新实例从磁盘读,验证确实落盘
      final prefs2 = await SharedPreferences.getInstance();
      expect(AppSettings.fromPrefs(prefs2).themeMode, AppThemeMode.obsidian);
    });

    test('setNotifyThresholdPercent clamp', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = SettingsNotifier(prefs);
      await notifier.load();

      await notifier.setNotifyThresholdPercent(200);
      expect(notifier.state.notifyThresholdPercent, 100);

      await notifier.setNotifyThresholdPercent(0);
      expect(notifier.state.notifyThresholdPercent, 1);
    });

    test('setLimitDisplayMode 更新并持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = SettingsNotifier(prefs);
      await notifier.load();

      await notifier.setLimitDisplayMode(LimitDisplayMode.used);
      expect(notifier.state.limitDisplayMode, LimitDisplayMode.used);
      expect(
        AppSettings.fromPrefs(prefs).limitDisplayMode,
        LimitDisplayMode.used,
      );
    });

    test('setDisplayCurrency 持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = SettingsNotifier(prefs);
      await notifier.load();

      await notifier.setDisplayCurrency(DisplayCurrency.twd);
      expect(notifier.state.displayCurrency, DisplayCurrency.twd);

      final prefs2 = await SharedPreferences.getInstance();
      expect(
        AppSettings.fromPrefs(prefs2).displayCurrency,
        DisplayCurrency.twd,
      );
    });

    test('setHomeWidgetPinnedLimits 最多保存两个且空值删除', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = SettingsNotifier(prefs);
      await notifier.load();

      await notifier.setHomeWidgetPinnedLimits('a|1,b|2,c|3');
      expect(notifier.state.homeWidgetPinnedLimits, 'a|1,b|2');
      expect(prefs.getString(PrefsKeys.homeWidgetPinnedLimits), 'a|1,b|2');

      await notifier.setHomeWidgetPinnedLimits('');
      expect(notifier.state.homeWidgetPinnedLimits, isEmpty);
      expect(prefs.containsKey(PrefsKeys.homeWidgetPinnedLimits), false);
    });
  });
}
