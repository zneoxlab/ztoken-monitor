// 鉴权状态测试:authorizationHeader 模式分支 / isAuthenticated / copyWith / load 判定。
import 'package:flutter_test/flutter_test.dart';
import 'package:ztoken_monitor/core/network/auth_mode.dart';

void main() {
  group('authorizationHeader', () {
    test('SaaS 模式:Bearer + accessToken', () {
      const s = AuthState(
        mode: AuthMode.saas,
        accessToken: 'jwt-xxx',
      );
      expect(s.authorizationHeader, 'Bearer jwt-xxx');
    });

    test('SaaS 模式但 accessToken 缺失 → null', () {
      const s = AuthState(mode: AuthMode.saas);
      expect(s.authorizationHeader, null);
    });

    test('自建 Hub 模式:Bearer + hubSecret', () {
      const s = AuthState(
        mode: AuthMode.selfHosted,
        hubSecret: 'shared-secret',
      );
      expect(s.authorizationHeader, 'Bearer shared-secret');
    });

    test('自建 Hub 模式但 hubSecret 缺失 → null', () {
      const s = AuthState(mode: AuthMode.selfHosted);
      expect(s.authorizationHeader, null);
    });

    test('未认证 → null', () {
      const s = AuthState();
      expect(s.authorizationHeader, null);
    });
  });

  group('isAuthenticated', () {
    test('saas/selfHosted 认证,unauthenticated 未认证', () {
      expect(const AuthState(mode: AuthMode.saas, accessToken: 'x').isAuthenticated, true);
      expect(const AuthState(mode: AuthMode.selfHosted, hubSecret: 'x').isAuthenticated, true);
      expect(const AuthState().isAuthenticated, false);
    });
  });

  group('copyWith', () {
    test('只改指定字段,其余保留', () {
      const s = AuthState(
        mode: AuthMode.saas,
        accessToken: 'a1',
        refreshToken: 'r1',
        userId: 'u1',
        userEmail: 'e@x',
      );
      final updated = s.copyWith(accessToken: 'a2', refreshToken: 'r2');
      expect(updated.mode, AuthMode.saas);
      expect(updated.accessToken, 'a2');
      expect(updated.refreshToken, 'r2');
      expect(updated.userId, 'u1'); // 未改,保留
      expect(updated.userEmail, 'e@x');
    });

    test('滚动续期场景:整体替换 token 对', () {
      const s = AuthState(
        mode: AuthMode.saas,
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        userId: 'u',
        userEmail: 'e',
      );
      final refreshed = s.copyWith(accessToken: 'new-access', refreshToken: 'new-refresh');
      expect(refreshed.accessToken, 'new-access');
      expect(refreshed.refreshToken, 'new-refresh');
      expect(refreshed.userId, 'u'); // 续期不改用户身份
    });
  });
}
