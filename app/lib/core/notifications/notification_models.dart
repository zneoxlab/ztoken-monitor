import 'package:flutter/foundation.dart';

/// SaaS Hub 下发的、可配置的一个百分比额度窗口。
@immutable
class NotificationWindowTarget {
  const NotificationWindowTarget({
    required this.id,
    required this.label,
    this.kind = '',
  });

  final String id;
  final String label;
  final String kind;

  factory NotificationWindowTarget.fromJson(dynamic value) {
    final json = _asMap(value);
    return NotificationWindowTarget(
      id: _string(json['id'] ?? json['windowId'] ?? json['window_id']),
      label: _string(
        json['label'] ?? json['displayLabel'] ?? json['title'] ?? json['id'],
      ),
      kind: _string(json['kind']),
    );
  }
}

/// 一个账户的可通知目标。target id 和 window id 都由 Hub 定义，客户端不猜测。
@immutable
class NotificationTarget {
  const NotificationTarget({
    required this.id,
    required this.provider,
    this.legacyTargetIds = const [],
    this.accountKey = '',
    this.accountIdentity = '',
    this.accountLabel = '',
    this.windows = const [],
  });

  final String id;
  final String provider;

  /// 仅用于把升级前的旧规则 ID 迁移到匿名 target id；不会写入推送负载。
  final List<String> legacyTargetIds;
  final String accountKey;
  final String accountIdentity;
  final String accountLabel;
  final List<NotificationWindowTarget> windows;

  factory NotificationTarget.fromJson(dynamic value) {
    final json = _asMap(value);
    final legacy = _asMap(json['legacy']);
    final legacyTargetIds = <String>{
      ..._asList(legacy['targetIds']).map(_string),
      _string(
        legacy['targetId'] ??
            json['legacyTargetId'] ??
            json['legacy_target_id'],
      ),
    }..removeWhere((id) => id.isEmpty);
    final windowValues =
        json['windows'] ?? json['windowTargets'] ?? json['window_targets'];
    return NotificationTarget(
      id: _string(json['id'] ?? json['targetId'] ?? json['target_id']),
      provider: _string(
        json['provider'] ?? json['providerId'] ?? json['provider_id'],
      ),
      legacyTargetIds: legacyTargetIds.toList(growable: false),
      accountKey: _string(json['accountKey'] ?? json['account_key']),
      accountIdentity: _string(
        json['accountIdentity'] ?? json['account_identity'],
      ),
      accountLabel: _string(
        json['accountLabel'] ?? json['accountName'] ?? json['accountEmail'],
      ),
      windows: _asList(windowValues)
          .map(NotificationWindowTarget.fromJson)
          .where((window) => window.id.isNotEmpty)
          .toList(growable: false),
    );
  }
}

@immutable
class NotificationTargetsDocument {
  const NotificationTargetsDocument({this.targets = const []});

  final List<NotificationTarget> targets;

  factory NotificationTargetsDocument.fromJson(dynamic value) {
    final json = _asMap(value);
    final values = json['targets'] ?? json['items'] ?? const [];
    return NotificationTargetsDocument(
      targets: _asList(values)
          .map(NotificationTarget.fromJson)
          .where((target) => target.id.isNotEmpty)
          .toList(growable: false),
    );
  }
}

/// 一条账户级规则。阈值永远是「剩余百分比」，不受界面显示剩余/已用影响。
@immutable
class QuotaNotificationRule {
  const QuotaNotificationRule({
    required this.id,
    required this.targetId,
    this.enabled = false,
    this.refreshEnabled = true,
    this.warningEnabled = true,
    this.thresholdPercent = 20,
    this.windowIds = const [],
  });

  final String id;
  final String targetId;
  final bool enabled;
  final bool refreshEnabled;
  final bool warningEnabled;
  final int thresholdPercent;
  final List<String> windowIds;

  QuotaNotificationRule copyWith({
    String? id,
    String? targetId,
    bool? enabled,
    bool? refreshEnabled,
    bool? warningEnabled,
    int? thresholdPercent,
    List<String>? windowIds,
  }) {
    return QuotaNotificationRule(
      id: id ?? this.id,
      targetId: targetId ?? this.targetId,
      enabled: enabled ?? this.enabled,
      refreshEnabled: refreshEnabled ?? this.refreshEnabled,
      warningEnabled: warningEnabled ?? this.warningEnabled,
      thresholdPercent: (thresholdPercent ?? this.thresholdPercent).clamp(
        1,
        100,
      ),
      windowIds: windowIds ?? this.windowIds,
    );
  }

  factory QuotaNotificationRule.fromJson(dynamic value) {
    final json = _asMap(value);
    return QuotaNotificationRule(
      id: _string(json['id']),
      targetId: _string(json['targetId'] ?? json['target_id']),
      enabled: _bool(json['enabled']),
      refreshEnabled: _bool(
        json['refreshEnabled'] ?? json['refresh_enabled'],
        true,
      ),
      warningEnabled: _bool(
        json['warningEnabled'] ?? json['warning_enabled'],
        true,
      ),
      thresholdPercent: _int(
        json['thresholdPercent'] ?? json['threshold_percent'],
        20,
      ).clamp(1, 100),
      windowIds: _asList(json['windowIds'] ?? json['window_ids'])
          .map(_string)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'targetId': targetId,
    'enabled': enabled,
    'refreshEnabled': refreshEnabled,
    'warningEnabled': warningEnabled,
    'thresholdPercent': thresholdPercent,
    'windowIds': windowIds,
  };
}

@immutable
class NotificationRulesDocument {
  const NotificationRulesDocument({this.updatedAt = '', this.rules = const []});

  final String updatedAt;
  final List<QuotaNotificationRule> rules;

  QuotaNotificationRule? ruleForTarget(
    String targetId, {
    Iterable<String> legacyTargetIds = const [],
  }) {
    final legacyIds = legacyTargetIds.toSet();
    for (final rule in rules) {
      if (rule.targetId == targetId || legacyIds.contains(rule.targetId)) {
        return rule;
      }
    }
    return null;
  }

  NotificationRulesDocument withRule(
    QuotaNotificationRule rule, {
    Iterable<String> replaceTargetIds = const [],
  }) {
    final replacedIds = <String>{rule.targetId, ...replaceTargetIds}
      ..removeWhere((id) => id.isEmpty);
    final next = [
      for (final item in rules)
        if (!replacedIds.contains(item.targetId)) item,
      rule,
    ];
    return NotificationRulesDocument(updatedAt: updatedAt, rules: next);
  }

  factory NotificationRulesDocument.fromJson(dynamic value) {
    final json = _asMap(value);
    return NotificationRulesDocument(
      updatedAt: _string(json['updatedAt'] ?? json['updated_at']),
      rules: _asList(json['rules'])
          .map(QuotaNotificationRule.fromJson)
          .where((rule) => rule.id.isNotEmpty && rule.targetId.isNotEmpty)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toPutBody() => {
    'baseUpdatedAt': updatedAt,
    'rules': rules.map((rule) => rule.toJson()).toList(growable: false),
  };
}

/// 同一账户首次创建规则时使用的稳定客户端规则 id。
String notificationRuleIdForTarget(String targetId) {
  final normalized = targetId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return 'quota_${normalized.isEmpty ? 'target' : normalized.substring(0, normalized.length.clamp(0, 96))}';
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return const {};
}

List<dynamic> _asList(dynamic value) => value is List ? value : const [];

String _string(dynamic value) =>
    value is String ? value : value?.toString() ?? '';

bool _bool(dynamic value, [bool fallback = false]) =>
    value is bool ? value : fallback;

int _int(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}
