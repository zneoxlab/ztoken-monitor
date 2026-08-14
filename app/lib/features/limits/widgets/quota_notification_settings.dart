import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_models.dart';
import '../../../core/notifications/notification_rules_repository.dart';
import '../../../core/notifications/push_lifecycle.dart';
import '../../../theme/theme_extension.dart';

/// 配额页内的账户级通知入口。只展示 Hub 当前声明支持的百分比窗口。
class QuotaNotificationSettings extends ConsumerWidget {
  const QuotaNotificationSettings({
    super.key,
    required this.target,
    required this.document,
  });

  final NotificationTarget target;
  final NotificationRulesDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (target.windows.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final enabled =
        document
            .ruleForTarget(target.id, legacyTargetIds: target.legacyTargetIds)
            ?.enabled ??
        false;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => QuotaNotificationSettingsDialog(
              target: target,
              document: document,
            ),
          ),
          icon: Icon(
            enabled
                ? Icons.notifications_active_outlined
                : Icons.notifications_none_outlined,
            size: 18,
          ),
          label: Text(enabled ? '通知已开启' : '通知设置'),
          style: TextButton.styleFrom(
            foregroundColor: enabled ? t.accent : t.muted,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }
}

class QuotaNotificationSettingsDialog extends ConsumerStatefulWidget {
  const QuotaNotificationSettingsDialog({
    super.key,
    required this.target,
    required this.document,
  });

  final NotificationTarget target;
  final NotificationRulesDocument document;

  @override
  ConsumerState<QuotaNotificationSettingsDialog> createState() =>
      _QuotaNotificationSettingsDialogState();
}

class _QuotaNotificationSettingsDialogState
    extends ConsumerState<QuotaNotificationSettingsDialog> {
  static const _thresholdOptions = [5, 10, 20, 30, 50];
  late QuotaNotificationRule _rule;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.document.ruleForTarget(
      widget.target.id,
      legacyTargetIds: widget.target.legacyTargetIds,
    );
    _rule =
        existing?.copyWith(targetId: widget.target.id) ??
        QuotaNotificationRule(
          id: notificationRuleIdForTarget(widget.target.id),
          targetId: widget.target.id,
          windowIds: widget.target.windows.map((window) => window.id).toList(),
        );
  }

  bool get _canSave {
    if (!_rule.enabled) return true;
    return _rule.windowIds.isNotEmpty &&
        (_rule.refreshEnabled || _rule.warningEnabled);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return AlertDialog(
      backgroundColor: t.panel,
      title: Text('配额通知', style: TextStyle(color: t.text)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390, maxHeight: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.target.accountLabel.isEmpty
                    ? '为此账户设置提醒'
                    : widget.target.accountLabel,
                style: TextStyle(fontSize: 12, color: t.muted),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用配额通知'),
                subtitle: const Text('系统推送将在 App 未打开时送达'),
                value: _rule.enabled,
                onChanged: _saving
                    ? null
                    : (value) => setState(
                        () => _rule = _rule.copyWith(enabled: value),
                      ),
              ),
              if (_rule.enabled) ...[
                const Divider(height: 18),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('额度刷新通知'),
                  subtitle: const Text('仅在剩余额度首次回到 100% 时提醒'),
                  value: _rule.refreshEnabled,
                  onChanged: _saving
                      ? null
                      : (value) => setState(
                          () => _rule = _rule.copyWith(refreshEnabled: value),
                        ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('额度预警'),
                  subtitle: const Text('剩余额度首次降到阈值及以下时提醒'),
                  value: _rule.warningEnabled,
                  onChanged: _saving
                      ? null
                      : (value) => setState(
                          () => _rule = _rule.copyWith(warningEnabled: value),
                        ),
                ),
                if (_rule.warningEnabled) ...[
                  const SizedBox(height: 8),
                  Text('剩余低于此值提醒', style: TextStyle(color: t.text)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final value in _thresholdOptions)
                        ChoiceChip(
                          label: Text('$value%'),
                          selected: _rule.thresholdPercent == value,
                          onSelected: _saving
                              ? null
                              : (_) => setState(
                                  () => _rule = _rule.copyWith(
                                    thresholdPercent: value,
                                  ),
                                ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Text('提醒范围', style: TextStyle(color: t.text)),
                const SizedBox(height: 3),
                Text(
                  '可多选，仅展示此账户当前支持的百分比额度。',
                  style: TextStyle(fontSize: 11, color: t.faint),
                ),
                const SizedBox(height: 4),
                for (final window in widget.target.windows)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(window.label),
                    value: _rule.windowIds.contains(window.id),
                    onChanged: _saving
                        ? null
                        : (selected) => setState(() {
                            final ids = [..._rule.windowIds];
                            if (selected == true) {
                              if (!ids.contains(window.id)) ids.add(window.id);
                            } else {
                              ids.remove(window.id);
                            }
                            _rule = _rule.copyWith(windowIds: ids);
                          }),
                  ),
              ],
              if (!_canSave) ...[
                const SizedBox(height: 6),
                Text(
                  '请至少选择一个提醒范围，并开启一种提醒。',
                  style: TextStyle(fontSize: 11, color: t.red),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving || !_canSave ? null : _save,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final wasEnabled =
        widget.document
            .ruleForTarget(
              widget.target.id,
              legacyTargetIds: widget.target.legacyTargetIds,
            )
            ?.enabled ??
        false;
    setState(() => _saving = true);
    try {
      await ref
          .read(notificationRulesProvider.notifier)
          .saveRule(_rule, replaceTargetIds: widget.target.legacyTargetIds);
      var permissionGranted = true;
      if (!wasEnabled && _rule.enabled) {
        permissionGranted = await ref
            .read(pushLifecycleProvider)
            .requestPermissionAndSync();
      }
      if (mounted) {
        Navigator.of(context).pop();
        if (!permissionGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('规则已保存；请在系统设置中允许通知后才能收到推送。')),
          );
        }
      }
    } on NotificationRulesConflict {
      await ref.read(notificationRulesProvider.notifier).load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('通知配置已在其他设备更新，请重新打开后保存。')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败，请检查网络后重试。')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
