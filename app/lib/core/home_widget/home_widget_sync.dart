import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_theme.dart';
import '../network/auth_mode.dart';
import '../network/stats_repository.dart';
import '../router.dart';
import '../storage/prefs_storage.dart';
import 'home_widget_bridge.dart';
import 'home_widget_snapshot.dart';

final homeWidgetBridgeProvider = Provider<HomeWidgetBridge>((ref) {
  return HomeWidgetBridge();
});

final homeWidgetSnapshotProvider = Provider<HomeWidgetSnapshot>((ref) {
  return buildHomeWidgetSnapshot(
    isAuthenticated: ref.watch(authProvider).isAuthenticated,
    stats: ref.watch(statsProvider),
    settings: ref.watch(settingsProvider),
    platformBrightness: ref.watch(platformBrightnessProvider),
  );
});

class HomeWidgetSync extends ConsumerStatefulWidget {
  const HomeWidgetSync({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<HomeWidgetSync> createState() => _HomeWidgetSyncState();
}

class _HomeWidgetSyncState extends ConsumerState<HomeWidgetSync> {
  late final HomeWidgetBridge _bridge;
  late final ProviderSubscription<HomeWidgetSnapshot> _snapshotSubscription;

  @override
  void initState() {
    super.initState();
    _bridge = ref.read(homeWidgetBridgeProvider);
    _snapshotSubscription = ref.listenManual<HomeWidgetSnapshot>(
      homeWidgetSnapshotProvider,
      (_, next) => unawaited(_bridge.update(next)),
      fireImmediately: true,
    );
    unawaited(_bridge.startActionHandling(_handleAction));
  }

  Future<void> _handleAction(String rawRoute, bool refresh) async {
    final route = switch (rawRoute) {
      AppRoutes.limits => AppRoutes.limits,
      _ => AppRoutes.home,
    };
    if (refresh && ref.read(authProvider).isAuthenticated) {
      await ref.read(statsProvider.notifier).refresh();
    }
    if (!mounted) return;
    widget.router.go(route);
  }

  @override
  void dispose() {
    _snapshotSubscription.close();
    unawaited(_bridge.stopActionHandling());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
