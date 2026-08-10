import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/breakdown/breakdown_page.dart';
import '../features/devices/devices_page.dart';
import '../features/home/home_page.dart';
import '../features/home/trend_page.dart';
import '../features/limits/limits_page.dart';
import '../features/me/me_page.dart';
import 'network/auth_mode.dart';
import '../widgets/app_tabbar.dart';

// 路由名常量,避免散落字符串。二级页带返回箭头、无底部标签栏。
class AppRoutes {
  static const login = '/login';
  static const home = '/home';
  static const breakdown = '/breakdown';
  static const limits = '/limits';
  static const devices = '/devices';
  static const me = '/me';
  // 二级页
  static const trend = '/home/trend';
  static const subscriptions = '/limits/subscriptions';
}

// 全局路由配置。认证守卫:未认证只能进 /login,已认证访问 /login 转 /home。
// redirect 每次 navigate 求值,冷启动 / 深链 / 手动 go 都会被拦;
// 登录/登出的跳转由 LoginPage / MePage 在改完 AuthState 后显式 context.go 触发。
final routerProvider = Provider<GoRouter>((ref) {
  bool isAuthed() => ref.read(authProvider).isAuthenticated;

  return GoRouter(
    initialLocation: AppRoutes.home,
    redirect: (context, state) {
      final authed = isAuthed();
      final onLogin = state.matchedLocation == AppRoutes.login;
      // 未认证且不在登录页 → 登录页
      if (!authed && !onLogin) return AppRoutes.login;
      // 已认证却在登录页 → 总览
      if (authed && onLogin) return AppRoutes.home;
      return null;
    },
    routes: [
      // 登录页:独立全屏,不带底部标签栏
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginPage(),
      ),
      // 主壳:底部 5 tab,各 tab 状态独立保活
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            _AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) => const HomePage(),
              routes: [
                GoRoute(
                  path: 'trend',
                  builder: (context, state) => const TrendPage(),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.breakdown,
              builder: (context, state) => const BreakdownPage(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.devices,
              builder: (context, state) => const DevicesPage(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.limits,
              builder: (context, state) => const LimitsPage(),
              routes: [
                GoRoute(
                  path: 'subscriptions',
                  builder: (context, state) => const SizedBox(),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.me,
              builder: (context, state) => const MePage(),
            ),
          ]),
        ],
      ),
    ],
  );
});

// 主壳:承载底部标签栏与各 tab 的导航壳。
// 底部栏用自绘 AppTabBar(原型 .tabbar),不用 M3 NavigationBar——
// 后者的指示器药丸/最小高度/label 样式无法还原原型(UI-IMPL.md §0)。
class _AppShell extends StatelessWidget {
  const _AppShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: AppTabBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        items: const [
          AppTabItem(icon: Icons.home_outlined, label: '总览'),
          AppTabItem(icon: Icons.grid_view_rounded, label: '明细'),
          AppTabItem(icon: Icons.desktop_windows_outlined, label: '设备'),
          AppTabItem(icon: Icons.speed_outlined, label: '配额'),
          AppTabItem(icon: Icons.person_outline, label: '我的'),
        ],
      ),
    );
  }
}
