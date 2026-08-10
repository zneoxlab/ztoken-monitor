// 鉴权路径判定测试:免鉴权端点清单 + query 处理。
import 'package:flutter_test/flutter_test.dart';
import 'package:ztoken_monitor/core/network/auth_paths.dart';

void main() {
  group('isNoAuthPath', () {
    test('鉴权端点 + 健康检查免鉴权', () {
      expect(isNoAuthPath('/api/auth/login'), true);
      expect(isNoAuthPath('/api/auth/register'), true);
      expect(isNoAuthPath('/api/auth/refresh'), true);
      expect(isNoAuthPath('/api/health'), true);
    });

    test('数据接口需鉴权', () {
      expect(isNoAuthPath('/api/stats'), false);
      expect(isNoAuthPath('/api/ingest'), false);
      expect(isNoAuthPath('/api/subscriptions'), false);
    });

    test('带 query 的路径只比较 pathname', () {
      expect(isNoAuthPath('/api/auth/login?next=/x'), true);
      expect(isNoAuthPath('/api/stats?since=2026-01-01'), false);
    });

    test('续期端点自身 401 不触发续期(免鉴权)', () {
      // /api/auth/refresh 是免鉴权路径 → 拦截器 onError 见到此路径直接抛,不递归
      expect(isNoAuthPath('/api/auth/refresh'), true);
    });
  });
}
