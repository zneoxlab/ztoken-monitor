// 主题系统测试:验证 4 主题令牌、ThemeExtension 挂载、玻璃材质切换。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ztoken_monitor/theme/app_colors.dart';
import 'package:ztoken_monitor/theme/app_theme.dart';
import 'package:ztoken_monitor/theme/glass_material.dart';
import 'package:ztoken_monitor/theme/theme_extension.dart';
import 'package:ztoken_monitor/theme/theme_mode.dart';

void main() {
  group('主题令牌', () {
    test('4 主题列表顺序与枚举一致', () {
      expect(appColorTokensList.length, 4);
      expect(appColorTokensList[0], graphiteMint);
      expect(appColorTokensList[3], porcelain);
    });

    test('纸白为浅色,其余为深色', () {
      expect(porcelain.brightness, Brightness.light);
      expect(graphiteMint.brightness, Brightness.dark);
      expect(starryBlue.brightness, Brightness.dark);
      expect(obsidian.brightness, Brightness.dark);
    });

    test('厂商色覆盖 GOAL.md §7 全部 10 个', () {
      expect(vendorColors.length, 10);
      expect(vendorColors['claude'], const Color(0xFFCC7C5E));
      expect(vendorColors['qwen'], const Color(0xFFA259E6));
    });
  });

  group('resolveTokens 跟随系统', () {
    test('system 深色→石墨薄荷', () {
      expect(
        resolveTokens(AppThemeMode.system, Brightness.dark),
        graphiteMint,
      );
    });

    test('system 浅色→纸白', () {
      expect(
        resolveTokens(AppThemeMode.system, Brightness.light),
        porcelain,
      );
    });

    test('强制主题忽略系统亮度', () {
      expect(
        resolveTokens(AppThemeMode.starryBlue, Brightness.light),
        starryBlue,
      );
    });
  });

  group('ThemeExtension 挂载', () {
    testWidgets('buildThemeData 携带 AppThemeTokens 扩展', (tester) async {
      final theme = buildThemeData(obsidian);
      final ext = theme.extension<AppThemeTokens>();
      expect(ext, isNotNull);
      expect(ext!.accent, obsidian.accent);
      expect(ext.bg, obsidian.bg);
    });
  });

  group('玻璃材质切换', () {
    // 直接 override effectiveMaterialProvider,绕过 settings 持久化链,
    // 专注验证 GlassCard 对材质的渲染分支。
    testWidgets('实色材质:GlassCard 无 BackdropFilter', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            effectiveMaterialProvider.overrideWithValue(AppMaterial.solid),
          ],
          child: MaterialApp(
            theme: buildThemeData(graphiteMint),
            home: const Scaffold(
              body: GlassCard(child: SizedBox(width: 50, height: 50)),
            ),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsNothing,
          reason: '实色材质不应有模糊层');
    });

    testWidgets('玻璃材质:GlassCard 含 BackdropFilter', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            effectiveMaterialProvider.overrideWithValue(AppMaterial.glass),
          ],
          child: MaterialApp(
            theme: buildThemeData(graphiteMint),
            home: const Scaffold(
              body: GlassCard(child: SizedBox(width: 50, height: 50)),
            ),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsOneWidget,
          reason: '玻璃材质应渲染模糊层');
    });
  });

  group('effectiveMaterial 降级', () {
    test('glass + glassDowngraded → solid', () {
      const s = ThemeSettings(
        material: AppMaterial.glass,
        glassDowngraded: true,
      );
      expect(effectiveMaterial(s), AppMaterial.solid);
    });

    test('glass 无降级 → glass', () {
      const s = ThemeSettings(material: AppMaterial.glass);
      expect(effectiveMaterial(s), AppMaterial.glass);
    });

    test('solid 不受降级影响', () {
      const s = ThemeSettings(
        material: AppMaterial.solid,
        glassDowngraded: true,
      );
      expect(effectiveMaterial(s), AppMaterial.solid);
    });
  });

  group('themePickerOptions', () {
    test('展示顺序与枚举 index 解耦', () {
      expect(themePickerIndex(AppThemeMode.system), 0);
      expect(themePickerIndex(AppThemeMode.graphiteMint), 1);
      expect(themePickerIndex(AppThemeMode.porcelain), 4);
      expect(themeModeFromPickerIndex(0), AppThemeMode.system);
      expect(themeModeFromPickerIndex(1), AppThemeMode.graphiteMint);
      expect(themeModeFromPickerIndex(4), AppThemeMode.porcelain);
      expect(themeModeFromPickerIndex(99), AppThemeMode.system);
    });
  });

  group('resolveMaterialThemeMode', () {
    test('system + 深色平台 → ThemeMode.dark', () {
      expect(
        resolveMaterialThemeMode(AppThemeMode.system, Brightness.dark),
        ThemeMode.dark,
      );
    });

    test('system + 浅色平台 → ThemeMode.light', () {
      expect(
        resolveMaterialThemeMode(AppThemeMode.system, Brightness.light),
        ThemeMode.light,
      );
    });

    test('强制深色主题忽略平台亮度', () {
      expect(
        resolveMaterialThemeMode(AppThemeMode.obsidian, Brightness.light),
        ThemeMode.dark,
      );
    });
  });

  group('themeModeFor', () {
    test('system → ThemeMode.system', () {
      expect(themeModeFor(AppThemeMode.system), ThemeMode.system);
    });

    test('深色主题 → ThemeMode.dark', () {
      expect(themeModeFor(AppThemeMode.obsidian), ThemeMode.dark);
      expect(themeModeFor(AppThemeMode.starryBlue), ThemeMode.dark);
    });

    test('纸白 → ThemeMode.light', () {
      expect(themeModeFor(AppThemeMode.porcelain), ThemeMode.light);
    });
  });
}
