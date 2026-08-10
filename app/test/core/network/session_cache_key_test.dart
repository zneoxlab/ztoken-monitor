import 'package:flutter_test/flutter_test.dart';
import 'package:ztoken_monitor/core/network/auth_mode.dart';
import 'package:ztoken_monitor/core/network/stats_repository.dart';

void main() {
  group('sessionCacheKey', () {
    test('未认证返回空串', () {
      expect(sessionCacheKey(const AuthState()), '');
    });

    test('SaaS 登录后随 token/邮箱变化', () {
      const a = AuthState(
        mode: AuthMode.saas,
        accessToken: 'token-a',
        userEmail: 'a@example.com',
      );
      const b = AuthState(
        mode: AuthMode.saas,
        accessToken: 'token-b',
        userEmail: 'a@example.com',
      );
      const c = AuthState(
        mode: AuthMode.saas,
        accessToken: 'token-b',
        userEmail: 'b@example.com',
      );

      expect(sessionCacheKey(a), isNot(sessionCacheKey(b)));
      expect(sessionCacheKey(b), isNot(sessionCacheKey(c)));
    });

    test('自建 Hub 用 hubSecret 区分会话', () {
      const a = AuthState(mode: AuthMode.selfHosted, hubSecret: 'secret-a');
      const b = AuthState(mode: AuthMode.selfHosted, hubSecret: 'secret-b');
      expect(sessionCacheKey(a), isNot(sessionCacheKey(b)));
    });
  });
}
