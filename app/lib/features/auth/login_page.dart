import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/auth_mode.dart';
import '../../core/network/dio_client.dart';
import '../../core/router.dart';
import '../../core/storage/prefs_storage.dart';
import '../../theme/glass_material.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_field.dart';
import '../../widgets/app_segmented.dart';
import 'legal_documents.dart';

// ============================================================
// 登录 / 注册页(原型 ①)。
// 对照 GOAL.md §5.0、saas-hub /api/auth/{login,register}、/api/health。
//
// 顶部:logo(72×72)+ 标题 + 副标题。
// AppSegmented(登录/注册)→ 邮箱 field → 密码 field → 主按钮。
// 服务器卡:默认 token-hub.zneox.com;展开高级选项可改自建 Hub 地址 + 共享密钥。
// 健康指示:GET /api/health(不鉴权)测延迟,green dot + "服务正常 · 86ms"。
//
// 提交:
//  SaaS 模式 → POST /api/auth/login|register → 存 token → 进总览。
//  自建 Hub 模式(填了密钥)→ 不登录,存 hubSecret → 校验 GET /api/stats 200 → 进总览。
// ============================================================

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _hubUrlCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();

  int _mode = 0; // 0=登录 1=注册
  bool _advanced = false; // 高级选项展开
  bool _loading = false;
  String? _error; // 错误提示(红字,按钮上方)
  bool _remember = true; // 记住账号密码(默认勾选,登录态保持便利)

  // 健康检查状态
  bool _healthChecking = false;
  bool _healthOk = false;
  int? _healthLatencyMs;

  @override
  void initState() {
    super.initState();
    // 预填默认 Hub 地址
    _hubUrlCtrl.text = ref.read(hubUrlProvider);
    // 预填记住的账号密码(rememberCredentials=true 时才有值)
    final s = ref.read(settingsProvider);
    _remember = s.rememberCredentials;
    if (s.rememberCredentials) {
      _emailCtrl.text = s.savedEmail;
      _passwordCtrl.text = s.savedPassword;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkHealth());
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _hubUrlCtrl.dispose();
    _secretCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Header(),
                AppSegmented(
                  labels: const ['登录', '注册'],
                  selectedIndex: _mode,
                  onChanged: (i) => setState(() {
                    _mode = i;
                    _error = null;
                  }),
                ),
                AppField(
                  label: '邮箱',
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  placeholder: 'you@example.com',
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                ),
                AppField(
                  label: '密码',
                  controller: _passwordCtrl,
                  obscureText: true,
                  placeholder: '至少 8 位',
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                ),
                // 记住账号密码:勾选则本地保存邮箱+密码(明文,同 OS 用户可读),
                // 下次进登录页预填。仅 SaaS 模式有意义;自建模式用 hubSecret 不存密码。
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: GestureDetector(
                    onTap: () => setState(() => _remember = !_remember),
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: _remember,
                            onChanged: (v) => setState(() => _remember = v ?? false),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text('记住账号密码', style: TextStyle(fontSize: 12, color: t.muted)),
                      ],
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      _error!,
                      style: TextStyle(fontSize: 12, color: t.red),
                    ),
                  ),
                AppButton(
                  label: _mode == 0 ? '登录并连接' : '注册并连接',
                  loading: _loading,
                  onPressed: _submit,
                ),
                const SizedBox(height: 12),
                const _LegalNotice(),
                const SizedBox(height: 16),
                _ServerCard(
                  hubUrlCtrl: _hubUrlCtrl,
                  secretCtrl: _secretCtrl,
                  advanced: _advanced,
                  onToggleAdvanced: () => setState(() => _advanced = !_advanced),
                ),
                const SizedBox(height: 18),
                _HealthIndicator(
                  checking: _healthChecking,
                  ok: _healthOk,
                  latencyMs: _healthLatencyMs,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 健康检查:GET /api/health(不鉴权),测往返延迟。
  // 用全局 dioProvider(baseUrl = settings.hubUrl)。改地址后用户手动重新检测。
  Future<void> _checkHealth() async {
    if (!mounted) return;
    setState(() {
      _healthChecking = true;
      _healthOk = false;
      _healthLatencyMs = null;
    });
    final sw = Stopwatch()..start();
    try {
      final resp = await ref.read(dioProvider).get<dynamic>('/api/health');
      sw.stop();
      final data = resp.data;
      final ok = data is Map && data['ok'] == true;
      if (!mounted) return;
      setState(() {
        _healthChecking = false;
        _healthOk = ok;
        _healthLatencyMs = ok ? sw.elapsedMilliseconds : null;
      });
    } catch (_) {
      sw.stop();
      if (!mounted) return;
      setState(() {
        _healthChecking = false;
        _healthOk = false;
      });
    }
  }

  // 提交:自建 Hub 模式(填了密钥)校验 stats;否则 SaaS 登录/注册。
  // ① 改了 Hub 地址 → 先持久化到 settings(后续全局 dio 用新 baseUrl)。
  // ② 自建模式:存 hubSecret → onSelfHostedConfigured → 校验 GET /api/stats 200。
  // ③ SaaS 模式:POST /api/auth/{login,register} → onSaasLogin → 进总览。
  Future<void> _submit() async {
    final secret = _secretCtrl.text.trim();
    final hubUrl = _hubUrlCtrl.text.trim();
    final defaultUrl = ref.read(hubUrlProvider);

    // 地址变了 → 持久化(自建/SaaS 切换都依赖此)
    if (hubUrl.isNotEmpty && hubUrl != defaultUrl) {
      await ref.read(settingsProvider.notifier).setHubUrl(hubUrl);
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (secret.isNotEmpty) {
        await _submitSelfHosted(secret);
      } else {
        await _submitSaas();
      }
      if (!mounted) return;
      // 登录成功:按"记住账号密码"开关持久化邮箱+密码(仅 SaaS 模式存密码;
      // 自建模式用 hubSecret,不存账号密码)。开关状态也写盘,下次进登录页据此预填。
      final email = _emailCtrl.text.trim().toLowerCase();
      final password = _passwordCtrl.text;
      await ref.read(settingsProvider.notifier).setRememberCredentials(_remember);
      if (_remember) {
        await ref.read(settingsProvider.notifier).saveCredentials(email: email, password: password);
      }
      // 登录成功 → 路由守卫 redirect 会把 /login 转 /home;显式 go 兜底
      context.go(AppRoutes.home);
    } on _AuthFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e, st) {
      // 兜底:任何未预期异常(如 secure_storage 写入 PlatformException)都给 UI 反馈,
      // 不静默吞。debugPrint 便于 hilog 定位。
      debugPrint('[login] _submit 异常: $e\n$st');
      if (!mounted) return;
      setState(() => _error = '登录失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // 自建 Hub:存密钥 + 校验 stats 接口能通。
  Future<void> _submitSelfHosted(String secret) async {
    await ref.read(authProvider.notifier).onSelfHostedConfigured(secret);
    try {
      // 用刚写入的 authState(自建模式)发 stats,401 = 密钥错
      await ref.read(dioProvider).get<dynamic>('/api/stats');
    } on DioException catch (e) {
      // 校验失败:回滚凭证,抛可读错误
      await ref.read(authProvider.notifier).clearSession();
      if (e.response?.statusCode == 401) {
        throw const _AuthFailure('共享密钥无效');
      }
      throw _AuthFailure('无法连接 Hub: ${e.message ?? e.type.name}');
    }
  }

  // SaaS:POST /api/auth/login 或 /api/auth/register。
  Future<void> _submitSaas() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      throw const _AuthFailure('请填写邮箱和密码');
    }
    final endpoint = _mode == 0 ? '/api/auth/login' : '/api/auth/register';
    try {
      final resp = await ref.read(dioProvider).post<dynamic>(
            endpoint,
            data: {'email': email, 'password': password},
          );
      // 对齐桌面端 main.js saas:login:判成功只看 data.token 是否非空,
      // 不查 data.ok / data.user(服务端虽返回 user,但客户端不依赖它,
      // 邮箱用用户输入,userId 留空 —— 续期/数据接口都用 token 不用 userId)。
      final data = resp.data is Map ? (resp.data as Map).cast<String, dynamic>() : const <String, dynamic>{};
      final accessToken = data['token'] as String?;
      final refreshToken = data['refreshToken'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        // 服务端 200 但缺 token:极少,按桌面端兜底映射
        final msg = data['message'] as String? ?? '登录失败(服务端未返回 token)';
        throw _AuthFailure(msg);
      }
      await ref.read(authProvider.notifier).onSaasLogin(
            accessToken: accessToken,
            refreshToken: refreshToken ?? '',
            userId: '',
            userEmail: email,
          );
    } on DioException catch (e) {
      // 401/400 带可读 message;其他网络错误
      final code = e.response?.data;
      String msg;
      if (code is Map && code['message'] is String) {
        msg = code['message'] as String;
      } else if (e.response?.statusCode == 401) {
        msg = _mode == 0 ? '邮箱或密码错误' : '注册失败';
      } else if (e.response?.statusCode == 409) {
        // 409 邮箱已注册(注册流程):提示直接登录
        msg = '该邮箱已注册,请直接登录';
      } else {
        msg = '网络错误: ${e.message ?? e.type.name}';
      }
      throw _AuthFailure(msg);
    }
  }
}

// 登录流程内部错误:带可读 message 给 UI。
class _AuthFailure implements Exception {
  const _AuthFailure(this.message);
  final String message;
}

// 顶部 logo + 标题 + 副标题(原型 ① 顶部块)。
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(top: 56, bottom: 26),
      child: Column(
        children: [
          // logo 72×72 radius 18
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              'assets/icons/app.png',
              width: 72,
              height: 72,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 14),
          Text('ZT助手', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: t.text)),
          const SizedBox(height: 5),
          Text('所有 AI 工具的用量,一处总览', style: TextStyle(fontSize: 12.5, color: t.muted)),
        ],
      ),
    );
  }
}

// 服务器卡:展示当前 Hub 地址 + 高级选项(展开后可改地址 + 自建密钥)。
// 填了密钥 → 自建 Hub 模式(不登录,用 Bearer secret)。
class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.hubUrlCtrl,
    required this.secretCtrl,
    required this.advanced,
    required this.onToggleAdvanced,
  });

  final TextEditingController hubUrlCtrl;
  final TextEditingController secretCtrl;
  final bool advanced;
  final VoidCallback onToggleAdvanced;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onToggleAdvanced,
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('服务器', style: TextStyle(fontSize: 12.5, color: t.muted)),
                Expanded(
                  child: Text(
                    _hostOf(hubUrlCtrl.text),
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12, color: t.accent, fontFamily: 'Menlo', fontFamilyFallback: const ['monospace']),
                  ),
                ),
                Icon(advanced ? Icons.expand_less : Icons.expand_more, size: 18, color: t.muted),
              ],
            ),
          ),
          if (advanced) ...[
            const SizedBox(height: 10),
            AppField(label: 'Hub 地址', controller: hubUrlCtrl, placeholder: 'https://your-hub.com'),
            AppField(label: '共享密钥(自建 Hub,留空用 SaaS 登录)', controller: secretCtrl, obscureText: true),
          ] else ...[
            const SizedBox(height: 7),
            Text(
              '高级选项:自定义云端 / 自建 Hub 地址 + 共享密钥(Bearer Secret)',
              style: TextStyle(fontSize: 10.5, color: t.faint),
            ),
          ],
        ],
      ),
    );
  }

  // 从完整 URL 取 host 展示(原型只显示域名)。
  String _hostOf(String url) {
    final u = Uri.tryParse(url);
    return u?.host.isNotEmpty == true ? u!.host : url;
  }
}

class _LegalNotice extends StatelessWidget {
  const _LegalNotice();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final base = TextStyle(fontSize: 11, color: t.faint, height: 1.4);
    final link = TextStyle(fontSize: 11, color: t.accent, height: 1.4);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('登录即表示您同意', style: base),
        GestureDetector(
          onTap: () => showLegalDocument(
            context,
            title: LegalDocuments.userAgreementTitle,
            body: LegalDocuments.userAgreementBody,
          ),
          child: Text('《用户协议》', style: link),
        ),
        Text('和', style: base),
        GestureDetector(
          onTap: () => showLegalDocument(
            context,
            title: LegalDocuments.privacyPolicyTitle,
            body: LegalDocuments.privacyPolicyBody,
          ),
          child: Text('《隐私政策》', style: link),
        ),
      ],
    );
  }
}

// 健康指示器:green/red dot + "服务正常 · 86ms" / "服务异常" / "检测中"。
class _HealthIndicator extends StatelessWidget {
  const _HealthIndicator({
    required this.checking,
    required this.ok,
    required this.latencyMs,
  });

  final bool checking;
  final bool ok;
  final int? latencyMs;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final color = checking ? t.muted : (ok ? t.green : t.red);
    final text = checking
        ? '检测中…'
        : ok
            ? (latencyMs != null ? '服务正常 · ${latencyMs}ms' : '服务正常')
            : '服务异常';

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 11, color: t.faint)),
      ],
    );
  }
}
