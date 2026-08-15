import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_models.dart';
import '../../../core/notifications/notification_rules_repository.dart';
import '../../../core/notifications/push_lifecycle.dart';
import '../../../core/notifications/quota_notification_service.dart';
import '../../../theme/theme_extension.dart';
import '../../../widgets/app_button.dart';

/// 配额卡片内的账户级通知入口。卡片只展示状态摘要，完整配置统一放在
/// 底部弹层中，避免把一组表单控件直接塞进额度卡片。
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
    final rule = document.ruleForTarget(
      target.id,
      legacyTargetIds: target.legacyTargetIds,
    );
    final enabled = rule?.enabled ?? false;
    final summary = _notificationSummary(rule);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: t.panel2,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          key: const Key('quota-notification-settings-entry'),
          borderRadius: BorderRadius.circular(11),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: false,
            backgroundColor: Colors.transparent,
            barrierColor: Colors.black.withValues(alpha: 0.46),
            builder: (_) => QuotaNotificationSettingsSheet(
              target: target,
              document: document,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: t.line),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: enabled ? t.accent.withValues(alpha: 0.14) : t.panel,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    enabled
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_none_outlined,
                    size: 19,
                    color: enabled ? t.accent : t.muted,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '配额通知',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: t.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: t.faint),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, size: 20, color: t.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _notificationSummary(QuotaNotificationRule? rule) {
    if (rule == null || !rule.enabled) return '设置刷新提醒、额度预警和通知范围';
    final types = <String>[
      if (rule.refreshEnabled) '刷新提醒',
      if (rule.warningEnabled) '低于 ${rule.thresholdPercent}%',
    ];
    final range = rule.windowIds.length == 1
        ? '1 个范围'
        : '${rule.windowIds.length} 个范围';
    return '${types.join(' · ')} · $range';
  }
}

class QuotaNotificationSettingsSheet extends ConsumerStatefulWidget {
  const QuotaNotificationSettingsSheet({
    super.key,
    required this.target,
    required this.document,
  });

  final NotificationTarget target;
  final NotificationRulesDocument document;

  @override
  ConsumerState<QuotaNotificationSettingsSheet> createState() =>
      _QuotaNotificationSettingsSheetState();
}

class _QuotaNotificationSettingsSheetState
    extends ConsumerState<QuotaNotificationSettingsSheet> {
  static const _thresholdOptions = [5, 10, 20, 30, 50];
  late QuotaNotificationRule _rule;
  bool _saving = false;
  bool _testing = false;

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
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.9;
    final accountLabel = widget.target.accountLabel.trim().isEmpty
        ? '当前额度账户'
        : widget.target.accountLabel.trim();

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SizedBox(
          key: const Key('quota-notification-settings-sheet'),
          height: sheetHeight,
          child: Material(
            color: t.panel,
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  const SizedBox(height: 9),
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 13, 12, 14),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: t.accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(
                            Icons.notifications_active_outlined,
                            color: t.accent,
                            size: 21,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '配额通知',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: t.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                accountLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: t.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(),
                          icon: Icon(Icons.close_rounded, color: t.muted),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: t.line),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SettingsPanel(
                            child: _SettingToggle(
                              icon: Icons.notifications_none_rounded,
                              title: '启用配额通知',
                              subtitle: 'App 未打开时也可接收 SaaS Hub 推送',
                              value: _rule.enabled,
                              onChanged: _saving
                                  ? null
                                  : (value) => setState(
                                      () => _rule = _rule.copyWith(
                                        enabled: value,
                                      ),
                                    ),
                            ),
                          ),
                          if (_rule.enabled) ...[
                            const SizedBox(height: 18),
                            const _SectionLabel('通知类型'),
                            const SizedBox(height: 8),
                            _SettingsPanel(
                              child: Column(
                                children: [
                                  _SettingToggle(
                                    icon: Icons.refresh_rounded,
                                    title: '额度刷新通知',
                                    subtitle: '剩余额度首次回到 100% 时提醒',
                                    value: _rule.refreshEnabled,
                                    onChanged: _saving
                                        ? null
                                        : (value) => setState(
                                            () => _rule = _rule.copyWith(
                                              refreshEnabled: value,
                                            ),
                                          ),
                                  ),
                                  Divider(height: 1, color: t.line),
                                  _SettingToggle(
                                    icon: Icons.warning_amber_rounded,
                                    title: '额度预警',
                                    subtitle: '首次降到设定的剩余阈值时提醒',
                                    value: _rule.warningEnabled,
                                    onChanged: _saving
                                        ? null
                                        : (value) => setState(
                                            () => _rule = _rule.copyWith(
                                              warningEnabled: value,
                                            ),
                                          ),
                                  ),
                                  if (_rule.warningEnabled) ...[
                                    Divider(height: 1, color: t.line),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        12,
                                        12,
                                        13,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '剩余低于此值提醒',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: t.text,
                                            ),
                                          ),
                                          const SizedBox(height: 9),
                                          Wrap(
                                            spacing: 7,
                                            runSpacing: 7,
                                            children: [
                                              for (final value
                                                  in _thresholdOptions)
                                                ChoiceChip(
                                                  label: Text('$value%'),
                                                  selected:
                                                      _rule.thresholdPercent ==
                                                      value,
                                                  showCheckmark: false,
                                                  selectedColor: t.accent
                                                      .withValues(alpha: 0.16),
                                                  backgroundColor: t.panel,
                                                  side: BorderSide(
                                                    color:
                                                        _rule.thresholdPercent ==
                                                            value
                                                        ? t.accent.withValues(
                                                            alpha: 0.7,
                                                          )
                                                        : t.line,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          9,
                                                        ),
                                                  ),
                                                  labelStyle: TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w600,
                                                    color:
                                                        _rule.thresholdPercent ==
                                                            value
                                                        ? t.accent
                                                        : t.muted,
                                                  ),
                                                  onSelected: _saving
                                                      ? null
                                                      : (_) => setState(
                                                          () => _rule = _rule
                                                              .copyWith(
                                                                thresholdPercent:
                                                                    value,
                                                              ),
                                                        ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            const _SectionLabel(
                              '通知范围',
                              subtitle: '可多选，仅显示此账户当前支持的百分比额度',
                            ),
                            const SizedBox(height: 8),
                            _SettingsPanel(
                              child: Column(
                                children: [
                                  for (
                                    var index = 0;
                                    index < widget.target.windows.length;
                                    index++
                                  ) ...[
                                    if (index > 0)
                                      Divider(height: 1, color: t.line),
                                    _RangeRow(
                                      label: widget.target.windows[index].label,
                                      selected: _rule.windowIds.contains(
                                        widget.target.windows[index].id,
                                      ),
                                      onChanged: _saving
                                          ? null
                                          : (selected) => _setWindowSelected(
                                              widget.target.windows[index].id,
                                              selected,
                                            ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          const _SectionLabel('通知测试'),
                          const SizedBox(height: 8),
                          _TestNotificationButton(
                            loading: _testing,
                            enabled: !_saving && !_testing,
                            onPressed: _sendTestNotification,
                          ),
                          if (!_canSave) ...[
                            const SizedBox(height: 12),
                            Text(
                              '请至少选择一个通知范围，并开启一种通知。',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, color: t.red),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: BoxDecoration(
                      color: t.panel,
                      border: Border(top: BorderSide(color: t.line)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            label: '取消',
                            ghost: true,
                            onPressed: _saving
                                ? null
                                : () => Navigator.of(context).pop(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AppButton(
                            label: '保存',
                            loading: _saving,
                            onPressed: _saving || !_canSave ? null : _save,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setWindowSelected(String windowId, bool selected) {
    setState(() {
      final ids = [..._rule.windowIds];
      if (selected) {
        if (!ids.contains(windowId)) ids.add(windowId);
      } else {
        ids.remove(windowId);
      }
      _rule = _rule.copyWith(windowIds: ids);
    });
  }

  Future<void> _sendTestNotification() async {
    setState(() => _testing = true);
    final sent = await ref
        .read(quotaNotificationServiceProvider)
        .showTestNotification();
    if (!mounted) return;
    setState(() => _testing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(sent ? '测试通知已发送，请查看系统通知栏。' : '未能发送测试通知，请在系统设置中允许通知。'),
      ),
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
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        if (!permissionGranted) {
          messenger.showSnackBar(
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

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Material(
      color: t.panel2,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: t.line),
          borderRadius: BorderRadius.circular(13),
        ),
        child: child,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title, {this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: t.text,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: TextStyle(fontSize: 10.5, color: t.faint)),
        ],
      ],
    );
  }
}

class _SettingToggle extends StatelessWidget {
  const _SettingToggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: value ? t.accent.withValues(alpha: 0.13) : t.panel,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 18, color: value ? t.accent : t.muted),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: t.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 10.5, color: t.faint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch.adaptive(
              value: value,
              activeThumbColor: t.accent,
              activeTrackColor: t.accent.withValues(alpha: 0.34),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeRow extends StatelessWidget {
  const _RangeRow({
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!selected),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          children: [
            Checkbox(
              value: selected,
              activeColor: t.accent,
              side: BorderSide(color: t.muted),
              visualDensity: VisualDensity.compact,
              onChanged: onChanged == null
                  ? null
                  : (value) => onChanged!(value == true),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: t.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestNotificationButton extends StatelessWidget {
  const _TestNotificationButton({
    required this.loading,
    required this.enabled,
    required this.onPressed,
  });

  final bool loading;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Material(
      color: t.panel2,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        key: const Key('send-test-notification'),
        borderRadius: BorderRadius.circular(13),
        onTap: enabled ? onPressed : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(Icons.send_rounded, size: 17, color: t.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '发送测试通知',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '验证本机通知权限与系统展示效果',
                      style: TextStyle(fontSize: 10.5, color: t.faint),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (loading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: t.accent,
                  ),
                )
              else
                Icon(Icons.chevron_right_rounded, size: 20, color: t.faint),
            ],
          ),
        ),
      ),
    );
  }
}
