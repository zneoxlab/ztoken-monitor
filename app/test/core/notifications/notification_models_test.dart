import 'package:flutter_test/flutter_test.dart';
import 'package:ztoken_monitor/core/notifications/notification_models.dart';

void main() {
  test('规则文档解析服务端目标，并以剩余百分比保存规则', () {
    final targets = NotificationTargetsDocument.fromJson({
      'targets': [
        {
          'id': 'codex:account-a',
          'provider': 'codex',
          'accountKey': 'account-a',
          'accountLabel': '个人账户',
          'windows': [
            {'id': 'session', 'label': '5 小时', 'kind': 'session'},
            {'id': 'weekly', 'label': '每周', 'kind': 'weekly'},
          ],
        },
      ],
    });
    final rules = NotificationRulesDocument.fromJson({
      'updatedAt': '2026-08-12T00:00:00.000Z',
      'rules': [
        {
          'id': 'rule-codex-a',
          'targetId': 'codex:account-a',
          'enabled': true,
          'refreshEnabled': true,
          'warningEnabled': true,
          'thresholdPercent': 20,
          'windowIds': ['session', 'weekly'],
        },
      ],
    });

    expect(targets.targets.single.windows.map((item) => item.id), [
      'session',
      'weekly',
    ]);
    expect(rules.ruleForTarget('codex:account-a')!.thresholdPercent, 20);
    expect(rules.toPutBody()['baseUpdatedAt'], '2026-08-12T00:00:00.000Z');
    expect((rules.toPutBody()['rules'] as List).single['thresholdPercent'], 20);
  });

  test('目标兼容 targetId/windowId 与旧字段', () {
    final targets = NotificationTargetsDocument.fromJson({
      'items': [
        {
          'targetId': 'cursor:a',
          'providerId': 'cursor',
          'accountIdentity': 'a',
          'windowTargets': [
            {'windowId': 'five-hour', 'displayLabel': '5 小时'},
          ],
        },
      ],
    });

    final target = targets.targets.single;
    expect(target.id, 'cursor:a');
    expect(target.provider, 'cursor');
    expect(target.accountIdentity, 'a');
    expect(target.windows.single.id, 'five-hour');
    expect(target.windows.single.label, '5 小时');
  });

  test('旧目标规则可匹配并在保存时迁移到匿名目标 ID', () {
    final target = NotificationTarget.fromJson({
      'id': 'codex:opaque-id',
      'provider': 'codex',
      'legacy': {
        'targetId': 'codex:old-account-identity',
        'targetIds': ['codex:old-account-identity', 'codex:old-account-key'],
      },
      'windows': [
        {'id': 'session', 'label': '5 小时'},
      ],
    });
    final document = NotificationRulesDocument.fromJson({
      'updatedAt': '2026-08-12T00:00:00.000Z',
      'rules': [
        {
          'id': 'rule-old',
          'targetId': 'codex:old-account-identity',
          'enabled': true,
          'refreshEnabled': true,
          'warningEnabled': true,
          'thresholdPercent': 20,
          'windowIds': ['session'],
        },
      ],
    });

    final oldRule = document.ruleForTarget(
      target.id,
      legacyTargetIds: target.legacyTargetIds,
    );
    expect(oldRule?.id, 'rule-old');

    final migrated = document.withRule(
      oldRule!.copyWith(targetId: target.id),
      replaceTargetIds: target.legacyTargetIds,
    );
    expect(migrated.rules, hasLength(1));
    expect(migrated.rules.single.targetId, 'codex:opaque-id');
  });

  test('账户键生成的旧匿名 ID 也会在保存时被替换', () {
    final target = NotificationTarget.fromJson({
      'id': 'codex:new-opaque-id',
      'provider': 'codex',
      'legacy': {
        'targetIds': ['codex:old-opaque-id'],
      },
      'windows': [
        {'id': 'weekly', 'label': '每周'},
      ],
    });
    const rule = QuotaNotificationRule(
      id: 'rule-old-opaque',
      targetId: 'codex:old-opaque-id',
      enabled: true,
      windowIds: ['weekly'],
    );
    const document = NotificationRulesDocument(rules: [rule]);

    final migrated = document.withRule(
      document
          .ruleForTarget(target.id, legacyTargetIds: target.legacyTargetIds)!
          .copyWith(targetId: target.id),
      replaceTargetIds: target.legacyTargetIds,
    );

    expect(migrated.rules, hasLength(1));
    expect(migrated.rules.single.targetId, target.id);
  });
}
