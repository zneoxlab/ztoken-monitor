import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/auth_mode.dart';
import '../network/dio_client.dart';
import 'notification_models.dart';

class NotificationRulesConflict implements Exception {
  const NotificationRulesConflict();
}

class NotificationRulesRepository {
  NotificationRulesRepository(this._dio);

  final Dio _dio;

  Future<NotificationTargetsDocument> fetchTargets() async {
    final response = await _dio.get<dynamic>('/api/notification-targets');
    return NotificationTargetsDocument.fromJson(response.data);
  }

  Future<NotificationRulesDocument> fetchRules() async {
    final response = await _dio.get<dynamic>('/api/notification-rules');
    return NotificationRulesDocument.fromJson(response.data);
  }

  Future<NotificationRulesDocument> save(
    NotificationRulesDocument document,
  ) async {
    try {
      final response = await _dio.put<dynamic>(
        '/api/notification-rules',
        data: document.toPutBody(),
      );
      return NotificationRulesDocument.fromJson(response.data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 409) {
        throw const NotificationRulesConflict();
      }
      rethrow;
    }
  }

  Future<void> registerInstallation({
    required String installationId,
    required String platform,
    required String provider,
    required String environment,
    required String appVersion,
    required String token,
  }) {
    return _dio.put<void>(
      '/api/push/installations/$installationId',
      data: {
        'platform': platform,
        'provider': provider,
        'environment': environment,
        'appVersion': appVersion,
        'token': token,
      },
    );
  }

  Future<void> revokeInstallation(String installationId) {
    return _dio.delete<void>('/api/push/installations/$installationId');
  }
}

final notificationRulesRepositoryProvider =
    Provider<NotificationRulesRepository>(
      (ref) => NotificationRulesRepository(ref.watch(dioProvider)),
    );

@immutable
class NotificationRulesData {
  const NotificationRulesData({
    this.targets = const NotificationTargetsDocument(),
    this.rules = const NotificationRulesDocument(),
  });

  final NotificationTargetsDocument targets;
  final NotificationRulesDocument rules;

  NotificationRulesData copyWith({
    NotificationTargetsDocument? targets,
    NotificationRulesDocument? rules,
  }) => NotificationRulesData(
    targets: targets ?? this.targets,
    rules: rules ?? this.rules,
  );
}

/// Hub 文档的唯一读写入口。只有 SaaS 会话才访问这些端点。
class NotificationRulesNotifier
    extends StateNotifier<AsyncValue<NotificationRulesData>> {
  NotificationRulesNotifier(this._ref) : super(const AsyncValue.loading());

  final Ref _ref;

  bool get _isSaas => _ref.read(authProvider).mode == AuthMode.saas;

  Future<void> load() async {
    if (!_isSaas) {
      state = const AsyncValue.data(NotificationRulesData());
      return;
    }
    final previous = state.valueOrNull;
    if (previous == null) state = const AsyncValue.loading();
    try {
      final repository = _ref.read(notificationRulesRepositoryProvider);
      final values = await Future.wait<dynamic>([
        repository.fetchTargets(),
        repository.fetchRules(),
      ]);
      if (!mounted) return;
      state = AsyncValue.data(
        NotificationRulesData(
          targets: values[0] as NotificationTargetsDocument,
          rules: values[1] as NotificationRulesDocument,
        ),
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> saveRule(
    QuotaNotificationRule rule, {
    Iterable<String> replaceTargetIds = const [],
  }) async {
    final current = state.valueOrNull;
    if (!_isSaas || current == null) {
      throw StateError('当前不是可保存通知规则的 SaaS 会话');
    }
    final saved = await _ref
        .read(notificationRulesRepositoryProvider)
        .save(current.rules.withRule(rule, replaceTargetIds: replaceTargetIds));
    if (!mounted) return;
    state = AsyncValue.data(current.copyWith(rules: saved));
  }
}

final notificationRulesProvider =
    StateNotifierProvider<
      NotificationRulesNotifier,
      AsyncValue<NotificationRulesData>
    >((ref) => NotificationRulesNotifier(ref));

/// 登录、切换账号时重新读取目标和规则；自建 Hub 不调用 SaaS 端点。
final notificationRulesLifecycleProvider = Provider<void>((ref) {
  ref.listen<AuthMode>(authProvider.select((auth) => auth.mode), (
    previous,
    next,
  ) {
    if (next == AuthMode.saas) {
      ref.read(notificationRulesProvider.notifier).load();
    } else {
      ref.invalidate(notificationRulesProvider);
    }
  });
  if (ref.read(authProvider).mode == AuthMode.saas) {
    Future<void>.microtask(
      () => ref.read(notificationRulesProvider.notifier).load(),
    );
  }
});
