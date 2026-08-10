import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_version.dart';
import '../../core/format/formatters.dart' show DisplayCurrency;
import '../../core/logging/app_log.dart';
import '../../core/limits/limit_presentation.dart';
import '../../core/limits/limit_provider_order.dart';
import '../../core/models/stats.dart';
import '../../core/network/auth_mode.dart';
import '../../core/network/stats_repository.dart';
import '../../core/network/sse_client.dart';
import '../../core/router.dart';
import '../../core/storage/prefs_storage.dart';
import '../../core/update/app_update_dialog.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass_material.dart';
import '../../theme/theme_extension.dart';
import '../../theme/theme_mode.dart' show AppMaterial;
import '../../widgets/app_page_header.dart';
import '../../widgets/provider_icon.dart';
import '../auth/legal_documents.dart';

// ============================================================
// 我的页(原型 ⑨)——设置中心。
// 账户卡:邮箱头像字母 + 连接状态(SSE/轮询/离线)+ 退出登录。
// 连接组:服务器地址(展示)+ 实时推送开关(SSE on/off,off 走轮询)。
// 显示组:货币(USD/CNY/HKD/TWD)+ 主题(4 色 + 跟随系统)+ 材质(实色/玻璃)。
// 关于:版本号。通知/语言/开源仓库等入口 alpha 阶段暂不展示。
// ============================================================

class MePage extends ConsumerWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final auth = ref.watch(authProvider);
    final stats = ref.watch(statsProvider).valueOrNull;
    final limitProviders = orderedLimitProviders(
      stats?.limits?.providers ?? const [],
      savedOrder: parseLimitProviderOrder(settings.limitProviderOrder),
    ).where(isConfiguredLimitProvider).toList();
    final connState =
        ref.watch(sseConnectionStateProvider).value ??
        ref.read(sseClientProvider).current;

    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              const AppPageHeader(title: '我的', subtitle: '账户与设置'),
              const SizedBox(height: 6),
              _AccountCard(auth: auth, connState: connState),
              const SizedBox(height: 10),
              _SectionCard(
                title: '连接',
                children: [
                  _Row(label: '服务器地址', value: settings.hubUrl, mono: true),
                  _Row(label: '连接方式', value: _connLabel(connState)),
                  _SwitchRow(
                    label: '实时推送(SSE)',
                    subtitle: '关闭后改为轮询(下次启动生效)',
                    value: settings.sseEnabled,
                    onChanged: (v) =>
                        ref.read(settingsProvider.notifier).setSseEnabled(v),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _SectionCard(
                title: '显示',
                children: [
                  _ChoiceRow(
                    label: '货币',
                    options: const ['USD', 'CNY', 'HKD', 'TWD'],
                    selectedIndex: settings.displayCurrency.index,
                    onSelected: (i) => ref
                        .read(settingsProvider.notifier)
                        .setDisplayCurrency(DisplayCurrency.values[i]),
                  ),
                  _ChoiceRow(
                    label: '主题',
                    options: [for (final o in themePickerOptions) o.$2],
                    selectedIndex: themePickerIndex(settings.themeMode),
                    onSelected: (i) => ref
                        .read(settingsProvider.notifier)
                        .setThemeMode(themeModeFromPickerIndex(i)),
                  ),
                  _ChoiceRow(
                    label: '材质',
                    options: const ['默认', '透明玻璃'],
                    selectedIndex: settings.material.index,
                    onSelected: (i) => ref
                        .read(settingsProvider.notifier)
                        .setMaterial(AppMaterial.values[i]),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _SectionCard(
                title: '桌面小组件',
                children: [
                  _WidgetQuotaPickerRow(
                    providers: limitProviders,
                    pinnedEntries: parseLimitProviderOrder(
                      settings.homeWidgetPinnedLimits,
                    ),
                    onChanged: (entries) => ref
                        .read(settingsProvider.notifier)
                        .setHomeWidgetPinnedLimits(entries.join(',')),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _SectionCard(
                title: '关于',
                children: [
                  const _VersionExportRow(),
                  const AppUpdateCheckRow(),
                  _LinkRow(
                    label: LegalDocuments.userAgreementTitle,
                    onTap: () => showLegalDocument(
                      context,
                      title: LegalDocuments.userAgreementTitle,
                      body: LegalDocuments.userAgreementBody,
                    ),
                  ),
                  _LinkRow(
                    label: LegalDocuments.privacyPolicyTitle,
                    onTap: () => showLegalDocument(
                      context,
                      title: LegalDocuments.privacyPolicyTitle,
                      body: LegalDocuments.privacyPolicyBody,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // 连接方式文案。
  String _connLabel(SseConnectionState s) {
    switch (s) {
      case SseConnectionState.connected:
        return '实时推送';
      case SseConnectionState.connecting:
        return '连接中…';
      case SseConnectionState.polling:
        return '轮询中';
      case SseConnectionState.disconnected:
        return '离线';
    }
  }
}

class _WidgetQuotaPickerRow extends StatelessWidget {
  const _WidgetQuotaPickerRow({
    required this.providers,
    required this.pinnedEntries,
    required this.onChanged,
  });

  final List<LimitsProvider> providers;
  final List<String> pinnedEntries;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final byKey = {
      for (final provider in providers) limitEntryKey(provider): provider,
    };
    final pinnedNames = pinnedEntries
        .map((key) => byKey[key])
        .whereType<LimitsProvider>()
        .map((provider) => limitProviderDisplayName(provider.provider))
        .toList();
    final value = pinnedNames.isEmpty ? '智能选择' : pinnedNames.join('、');

    return GestureDetector(
      onTap: providers.isEmpty ? null : () => _showPicker(context),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('额度显示', style: TextStyle(fontSize: 12.5, color: t.text)),
                const SizedBox(height: 2),
                Text(
                  providers.isEmpty ? '暂无已配置额度账户' : '最多固定两个；留空时优先显示风险项',
                  style: TextStyle(fontSize: 10.5, color: t.faint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: t.muted),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right,
            size: 18,
            color: providers.isEmpty ? t.line : t.faint,
          ),
        ],
      ),
    );
  }

  Future<void> _showPicker(BuildContext context) async {
    final selected = pinnedEntries
        .where((key) {
          return providers.any((provider) => limitEntryKey(provider) == key);
        })
        .take(2)
        .toList();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final t = Theme.of(context).extension<AppThemeTokens>()!;
          return AlertDialog(
            backgroundColor: t.panel,
            title: Text('小组件额度显示', style: TextStyle(color: t.text)),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360, maxHeight: 420),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    '固定 1–2 个账户，或清空后按额度风险智能选择。',
                    style: TextStyle(fontSize: 12, color: t.muted),
                  ),
                  const SizedBox(height: 10),
                  for (final provider in providers)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: selected.contains(limitEntryKey(provider)),
                      activeColor: t.accent,
                      secondary: ProviderIcon(
                        providerId: provider.provider,
                        size: 28,
                        radius: 7,
                      ),
                      title: Text(
                        limitProviderDisplayName(provider.provider),
                        style: TextStyle(fontSize: 13, color: t.text),
                      ),
                      subtitle: Text(
                        limitAccountLine(provider),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: t.faint),
                      ),
                      onChanged: (checked) {
                        final key = limitEntryKey(provider);
                        setState(() {
                          if (checked == true) {
                            if (selected.length < 2 &&
                                !selected.contains(key)) {
                              selected.add(key);
                            }
                          } else {
                            selected.remove(key);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(const <String>[]),
                child: const Text('智能选择'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(selected),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    if (result != null) onChanged(result);
  }
}

// 连点版本号 10 次导出系统日志(含 SSE 诊断)到剪贴板。
class _VersionExportRow extends ConsumerStatefulWidget {
  const _VersionExportRow();

  @override
  ConsumerState<_VersionExportRow> createState() => _VersionExportRowState();
}

class _VersionExportRowState extends ConsumerState<_VersionExportRow> {
  static const _kVersion = kAppVersion;
  int _taps = 0;
  DateTime? _windowStart;

  void _onTap() {
    final now = DateTime.now();
    if (_windowStart == null ||
        now.difference(_windowStart!) > const Duration(seconds: 5)) {
      _taps = 0;
      _windowStart = now;
    }
    _taps++;
    if (_taps < 10) return;
    _taps = 0;
    _windowStart = null;
    _exportLogs();
  }

  Future<void> _exportLogs() async {
    final settings = ref.read(settingsProvider);
    final auth = ref.read(authProvider);
    final text = AppLog.export(hubUrl: settings.hubUrl, email: auth.userEmail);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('系统日志已复制到剪贴板')));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return GestureDetector(
      onTap: _onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('版本', style: TextStyle(fontSize: 12.5, color: t.muted)),
          Text(_kVersion, style: TextStyle(fontSize: 12.5, color: t.text)),
        ],
      ),
    );
  }
}

// 账户卡:头像字母 + 邮箱 + 连接状态 + 退出登录按钮。
class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.auth, required this.connState});
  final AuthState auth;
  final SseConnectionState connState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final email = auth.userEmail ?? '';
    final initial = email.isEmpty ? '?' : email[0].toUpperCase();

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          // 头像字母
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: t.accent,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  email.isEmpty ? '未登录' : email,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _ConnDot(state: connState),
                    const SizedBox(width: 5),
                    Text(
                      _connText(connState),
                      style: TextStyle(fontSize: 11, color: t.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 退出登录
          GestureDetector(
            onTap: () => _logout(ref, context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: t.red.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '退出',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: t.red,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _connText(SseConnectionState s) {
    switch (s) {
      case SseConnectionState.connected:
        return '已连接 · 实时';
      case SseConnectionState.connecting:
        return '连接中…';
      case SseConnectionState.polling:
        return '轮询中';
      case SseConnectionState.disconnected:
        return '离线';
    }
  }

  // 退出登录:清凭证(secure + prefs 降级)→ 路由守卫转 /login。
  Future<void> _logout(WidgetRef ref, BuildContext context) async {
    await ref.read(authProvider.notifier).clearSession();
    if (!context.mounted) return;
    context.go(AppRoutes.login);
  }
}

// 连接状态小圆点。
class _ConnDot extends StatelessWidget {
  const _ConnDot({required this.state});
  final SseConnectionState state;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final color = switch (state) {
      SseConnectionState.connected => t.green,
      SseConnectionState.connecting => t.amber,
      SseConnectionState.polling => t.muted,
      SseConnectionState.disconnected => t.faint,
    };
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// 分组卡:标题 + 子项列。
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: t.muted,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            children[i],
          ],
        ],
      ),
    );
  }
}

// 可点击行:左标签 + 右箭头(协议等)。
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12.5, color: t.text)),
          Icon(Icons.chevron_right, size: 18, color: t.faint),
        ],
      ),
    );
  }
}

// 普通行:左标签 + 右值。
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.mono = false});
  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(label, style: TextStyle(fontSize: 12.5, color: t.muted)),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              color: t.text,
              fontFamily: mono ? 'Menlo' : null,
              fontFamilyFallback: mono ? const ['monospace'] : null,
            ),
          ),
        ),
      ],
    );
  }
}

// 开关行:左标签(+副标题)+ 右 Switch。
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12.5, color: t.text)),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 10.5, color: t.faint),
                ),
              ],
            ],
          ),
        ),
        Switch.adaptive(value: value, onChanged: onChanged),
      ],
    );
  }
}

// 选择行:左标签 + 右段控(选项)。
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
  });
  final String label;
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Row(
      children: [
        Text(label, style: TextStyle(fontSize: 12.5, color: t.text)),
        const Spacer(),
        // 紧凑选项条:每个选项一个可点 chip
        Row(
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              GestureDetector(
                onTap: () => onSelected(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: i == selectedIndex
                        ? t.accent.withValues(alpha: 0.18)
                        : t.panel2,
                    borderRadius: BorderRadius.circular(6),
                    border: i == selectedIndex
                        ? Border.all(color: t.accent.withValues(alpha: 0.5))
                        : null,
                  ),
                  child: Text(
                    options[i],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: i == selectedIndex
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: i == selectedIndex ? t.accent : t.muted,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
