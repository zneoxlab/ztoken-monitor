import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import '../theme/theme_extension.dart';
import '../theme/theme_mode.dart';

// ============================================================
// AppTabBar —— 自绘底部标签栏,对照原型 .tabbar。
// 为什么不用 M3 NavigationBar:它有指示器药丸、最小高度 80、
// label 行为不可控,无法还原原型(58px 高、无指示器、10px 文字)。
// 本组件是 UI-IMPL.md §0"库存组件禁用表"的参考实现样板。
// ============================================================

class AppTabItem {
  const AppTabItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

class AppTabBar extends ConsumerWidget {
  const AppTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<AppTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final isGlass = ref.watch(effectiveMaterialProvider) != AppMaterial.solid;

    // 内容区:58px 高,5 个等分 tab;底部间距交给 SafeArea
    final content = Container(
      height: 58,
      decoration: BoxDecoration(
        // 实色材质用 tabbarBg(带 92% 透明);玻璃材质降到 40% 透出模糊
        color: isGlass ? t.tabbarBg.withValues(alpha: 0.40) : t.tabbarBg,
        border: Border(top: BorderSide(color: t.line, width: 1)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: _Tab(
                item: items[i],
                active: i == currentIndex,
                onTap: () => onTap(i),
              ),
            ),
        ],
      ),
    );

    // 玻璃材质:整栏 BackdropFilter 模糊(与 GlassCard 同 sigma 22)
    final blurred = isGlass
        ? ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: content,
            ),
          )
        : content;

    return SafeArea(top: false, child: blurred);
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.item, required this.active, required this.onTap});

  final AppTabItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final color = active ? t.accent : t.faint;

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, size: 23, color: color),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: TextStyle(fontSize: 10, color: color),
          ),
        ],
      ),
    );
  }
}
