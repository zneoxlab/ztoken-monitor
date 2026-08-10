import 'package:flutter/material.dart';

import '../../theme/glass_material.dart';
import '../../theme/theme_extension.dart';

class LegalDocuments {
  LegalDocuments._();

  static const userAgreementTitle = '用户协议';
  static const privacyPolicyTitle = '隐私政策';

  static const userAgreementBody = '''
欢迎使用 ZT助手（以下简称「本应用」）。在使用本应用前，请仔细阅读本协议。

一、服务说明
本应用用于汇总、展示您在本地设备上绑定的 AI 工具用量与配额信息，数据来源于您自行配置并授权的桌面端采集程序及同步服务。本应用不对第三方服务商的数据准确性、完整性或实时性作出保证。

二、免责声明
1. 本应用按「现状」提供，不提供任何明示或暗示的保证，包括但不限于适销性、特定用途适用性及不侵权保证。
2. 本应用展示的费用、用量、配额、趋势等数据仅供参考，不构成财务、投资或计费依据；因依赖上述数据所作出的任何决定，风险由您自行承担。
3. 因网络故障、第三方服务变更、设备离线、数据延迟或用户配置错误导致的数据缺失、偏差或服务中断，开发者不承担赔偿责任。
4. 您应妥善保管本应用及关联 Hub 的登录凭证；因凭证泄露、设备丢失或他人未经授权使用而产生的后果，由您自行承担。
5. 在法律允许的最大范围内，开发者对因使用或无法使用本应用而产生的任何直接、间接、附带或后果性损害不承担责任。

三、使用规范
您不得利用本应用从事违法活动，不得尝试未授权访问他人数据或干扰服务正常运行。

四、协议变更
我们可能适时更新本协议；更新后继续使用本应用，即视为接受修订后的协议。

最后更新：2026 年 8 月
''';

  static const privacyPolicyBody = '''
ZT助手 重视您的隐私。本政策说明我们如何收集、使用与保护您的信息。

一、我们收集的信息
1. 本应用登录：为连接云端 Hub，我们会处理您注册/登录本应用时提供的邮箱与密码（或自建 Hub 的共享密钥），用于身份验证与数据同步。
2. 用量数据：您设备上的桌面端采集程序上报的 token 用量、花费、配额状态、设备标识等统计信息，用于在移动端展示与多设备汇总。

二、我们不收集、不存储的信息
除本应用登录所需的账号与密码外，我们不在云端存储任何第三方 AI 服务（如 Cursor、Claude、OpenRouter 等）的账号密码、API 密钥、Cookie 或其他登录凭证。

上述第三方凭证仅保存在您电脑端已绑定账号的本地设备上，由桌面端程序在本地读取与使用，不会上传至我们的云端。

三、数据用途
同步至云端的数据仅用于为您记录、汇总与展示用量历史及多设备视图，不会用于广告投放，亦不会出售给第三方。

四、数据存储与安全
1. 本应用登录凭证在设备端采用系统提供的安全存储；云端传输使用 HTTPS。
2. 您可随时退出登录以清除本设备上的会话信息。

五、您的权利
您可停止使用本应用、退出登录，并联系我们在合理范围内删除与您 Hub 账号关联的云端账户数据（用量汇总记录）。

六、政策更新
我们可能更新本政策；重大变更时会在应用内提示。继续使用即表示您了解更新后的政策。

最后更新：2026 年 8 月
''';
}

void showLegalDocument(BuildContext context, {required String title, required String body}) {
  Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (ctx) => _LegalDocumentPage(title: title, body: body),
    ),
  );
}

class _LegalDocumentPage extends StatelessWidget {
  const _LegalDocumentPage({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.arrow_back_ios_new, size: 18, color: t.text),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: t.text),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Text(
                    body.trim(),
                    style: TextStyle(fontSize: 13, height: 1.55, color: t.muted),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
