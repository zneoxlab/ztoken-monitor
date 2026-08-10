import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/theme_extension.dart';
import 'app_update_action.dart';
import 'app_update_policy.dart';
import 'app_update_service.dart';

export 'app_update_action.dart';

Future<AppUpdateCheckResult> performAppUpdateCheck(
  BuildContext context,
  WidgetRef ref, {
  required AppUpdateCheckTrigger trigger,
}) async {
  final result = await ref.read(appUpdateCheckerProvider)(trigger: trigger);
  if (!context.mounted) return result;

  if (result.shouldPrompt) {
    final policy = result.platformPolicy!;
    final available = await ref.read(appUpdateAvailabilityProvider)(policy);
    if (!context.mounted) return result;
    if (!available) {
      if (trigger == AppUpdateCheckTrigger.manual) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('发现新版本，但当前安装渠道暂无可用更新入口')));
      }
      return result;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: result.urgency != AppUpdateUrgency.required,
      builder: (dialogContext) => AppUpdatePromptDialog(
        result: result,
        action: ref.read(appUpdateActionProvider),
      ),
    );
  } else if (trigger == AppUpdateCheckTrigger.manual) {
    final message = switch (result.status) {
      AppUpdateCheckStatus.upToDate => '已是最新版本',
      AppUpdateCheckStatus.disabled => '更新检查尚未配置',
      AppUpdateCheckStatus.unsupported => '当前平台暂不支持应用内更新',
      AppUpdateCheckStatus.failed => '检查更新失败，请稍后重试',
      AppUpdateCheckStatus.throttled => '已完成近期检查',
      AppUpdateCheckStatus.updateAvailable => '',
    };
    if (message.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
  return result;
}

class AppUpdateCheckRow extends ConsumerStatefulWidget {
  const AppUpdateCheckRow({super.key});

  @override
  ConsumerState<AppUpdateCheckRow> createState() => _AppUpdateCheckRowState();
}

class _AppUpdateCheckRowState extends ConsumerState<AppUpdateCheckRow> {
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await performAppUpdateCheck(
        context,
        ref,
        trigger: AppUpdateCheckTrigger.manual,
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppThemeTokens>()!;
    return GestureDetector(
      onTap: _checking ? null : _check,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('检查更新', style: TextStyle(fontSize: 12.5, color: tokens.text)),
          if (_checking)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: tokens.accent,
              ),
            )
          else
            Icon(Icons.chevron_right, size: 18, color: tokens.faint),
        ],
      ),
    );
  }
}

class AppUpdatePromptDialog extends StatefulWidget {
  const AppUpdatePromptDialog({
    super.key,
    required this.result,
    required this.action,
  });

  final AppUpdateCheckResult result;
  final AppUpdateAction action;

  @override
  State<AppUpdatePromptDialog> createState() => _AppUpdatePromptDialogState();
}

class _AppUpdatePromptDialogState extends State<AppUpdatePromptDialog> {
  bool _launching = false;
  String _message = '';

  Future<void> _update() async {
    final policy = widget.result.platformPolicy;
    if (policy == null || _launching) return;
    setState(() {
      _launching = true;
      _message = '';
    });
    final actionResult = await widget.action(policy);
    if (!mounted) return;
    switch (actionResult.status) {
      case AppUpdateActionStatus.launched:
        if (widget.result.urgency == AppUpdateUrgency.optional) {
          Navigator.of(context).pop();
          return;
        }
        setState(
          () => _message = actionResult.message.isEmpty
              ? '已打开更新流程，请完成安装'
              : actionResult.message,
        );
      case AppUpdateActionStatus.permissionRequired:
        setState(
          () => _message = actionResult.message.isEmpty
              ? '请授权安装未知应用后再次点击更新'
              : actionResult.message,
        );
      case AppUpdateActionStatus.unavailable:
      case AppUpdateActionStatus.failed:
        setState(
          () => _message = actionResult.message.isEmpty
              ? '暂时无法启动更新，请稍后重试'
              : actionResult.message,
        );
    }
    if (mounted) setState(() => _launching = false);
  }

  @override
  Widget build(BuildContext context) {
    final policy = widget.result.platformPolicy!;
    final required = widget.result.urgency == AppUpdateUrgency.required;
    return PopScope(
      canPop: !required,
      child: AlertDialog(
        title: Text('发现新版本 v${policy.latestVersion}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (required) ...[
              const Text('此版本为必要更新，完成更新后才能继续使用。'),
              const SizedBox(height: 10),
            ],
            if (policy.releaseNotes.isNotEmpty) Text(policy.releaseNotes),
            if (_message.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_message, style: const TextStyle(fontSize: 12)),
            ],
          ],
        ),
        actions: [
          if (!required)
            TextButton(
              onPressed: _launching ? null : () => Navigator.of(context).pop(),
              child: const Text('稍后'),
            ),
          FilledButton(
            onPressed: _launching ? null : _update,
            child: _launching
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('立即更新'),
          ),
        ],
      ),
    );
  }
}
