// stats 模型 fromJson 测试:正常解析 + 脏数据容错(缺字段/类型不符/null)。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ztoken_monitor/core/models/stats.dart';

void main() {
  group('Period.fromJson', () {
    test('正常解析', () {
      const json = {
        'totalTokens': 1234,
        'costUsd': 0.01,
        'clients': {'codex': 1000, 'claude': 234},
        'clientCosts': {'codex': 0.008, 'claude': 0.002},
        'models': {'gpt-4': 1234},
        'modelCosts': {'gpt-4': 0.01},
      };
      final p = Period.fromJson(json);
      expect(p.totalTokens, 1234);
      expect(p.costUsd, 0.01);
      expect(p.clients['codex'], 1000);
      expect(p.clientCosts['claude'], 0.002);
    });

    test('数字字段是字符串也能解析(tokscale 偶发)', () {
      const json = {'totalTokens': '5678', 'costUsd': '1.5'};
      final p = Period.fromJson(json);
      expect(p.totalTokens, 5678);
      expect(p.costUsd, 1.5);
    });

    test('缺字段回落默认(不抛)', () {
      final p = Period.fromJson({});
      expect(p.totalTokens, 0);
      expect(p.costUsd, 0);
      expect(p.clients, isEmpty);
    });

    test('null 输入不抛', () {
      final p = Period.fromJson(null);
      expect(p.totalTokens, 0);
    });

    test('clients 值为 null 回落 0', () {
      const json = {'clients': {'codex': null, 'claude': 5}};
      final p = Period.fromJson(json);
      expect(p.clients['codex'], 0);
      expect(p.clients['claude'], 5);
    });
  });

  group('LimitsWindow.fromJson', () {
    test('百分比型', () {
      const json = {
        'kind': 'session',
        'usedPercent': 42,
        'remainingPercent': 58,
        'resetsAt': '2026-05-18T05:00:00.000Z',
      };
      final w = LimitsWindow.fromJson(json);
      expect(w.kind, 'session');
      expect(w.usedPercent, 42);
      expect(w.isCredits, false);
    });

    test('信用型(metric=credits)', () {
      const json = {
        'kind': 'monthly',
        'metric': 'credits',
        'remaining': 12.5,
        'currency': 'USD',
      };
      final w = LimitsWindow.fromJson(json);
      expect(w.isCredits, true);
      expect(w.remaining, 12.5);
      expect(w.currency, 'USD');
    });
  });

  group('HistoryPreview.fromJson', () {
    test('daily/monthly 数组解析', () {
      const json = {
        'daily': [
          {'date': '2026-08-05', 'tokens': 100, 'cost': 0.5, 'activeTimeMs': 12000},
          {'date': '2026-08-06', 'tokens': 200, 'cost': 1.0},
        ],
        'monthly': [
          {'month': '2026-08', 'tokens': 5000, 'cost': 30.0},
        ],
      };
      final h = HistoryPreview.fromJson(json);
      expect(h.daily.length, 2);
      expect(h.daily[0].date, '2026-08-05');
      expect(h.daily[0].activeTimeMs, 12000);
      expect(h.daily[1].activeTimeMs, 0); // 缺字段回落 0
      expect(h.monthly.single.month, '2026-08');
    });

    test('daily 为 null 回落空数组', () {
      final h = HistoryPreview.fromJson({});
      expect(h.daily, isEmpty);
      expect(h.monthly, isEmpty);
      expect(h.summary, isNull);
    });
  });

  group('StatsSnapshot.fromJson', () {
    test('完整结构嵌套解析', () {
      const json = {
        'staleAfterMs': 600000,
        'subscriptionsUpdatedAt': '2026-08-06T00:00:00.000Z',
        'periods': {
          'today': {'totalTokens': 100, 'costUsd': 1.0, 'clients': {'codex': 100}},
          'month': {'totalTokens': 3000, 'costUsd': 30.0},
          'allTime': {'totalTokens': 50000, 'costUsd': 500.0},
        },
        'devices': [
          {
            'deviceId': 'macbook',
            'hostname': 'macbook.local',
            'platform': 'darwin-arm64',
            'receivedAt': '2026-08-06T10:00:00.000Z',
            'stale': false,
          }
        ],
        'historyPreview': {
          'daily': [{'date': '2026-08-06', 'tokens': 100}],
        },
        'limits': {
          'providers': [
            {
              'provider': 'claude',
              'status': 'ok',
              'windows': [
                {'kind': 'session', 'usedPercent': 64, 'resetsAt': '2026-08-06T17:00:00.000Z'}
              ],
            }
          ],
        },
      };
      final s = StatsSnapshot.fromJson(json);
      expect(s.staleAfterMs, 600000);
      expect(s.subscriptionsUpdatedAt, isNotEmpty);
      expect(s.periods!.today!.totalTokens, 100);
      expect(s.periods!.allTime!.totalTokens, 50000);
      expect(s.devices.single.deviceId, 'macbook');
      expect(s.devices.single.stale, false);
      expect(s.historyPreview!.daily.single.tokens, 100);
      expect(s.limits!.providers.single.provider, 'claude');
      expect(s.limits!.providers.single.windows.single.usedPercent, 64);
    });

    test('极简响应(只有 today)不抛', () {
      const json = {
        'periods': {'today': {'totalTokens': 5}},
      };
      final s = StatsSnapshot.fromJson(json);
      expect(s.periods!.today!.totalTokens, 5);
      expect(s.periods!.month, isNull);
      expect(s.devices, isEmpty);
      expect(s.limits, isNull);
      expect(s.staleAfterMs, 600000); // 缺省默认
    });

    test('空对象不抛,全默认', () {
      final s = StatsSnapshot.fromJson({});
      expect(s.staleAfterMs, 600000);
      expect(s.subscriptionsUpdatedAt, '');
      expect(s.periods, isNull);
      expect(s.devices, isEmpty);
    });

    test('从真实 JSON 字符串解析(模拟 GET /api/stats 响应)', () {
      const raw = '''
      {"staleAfterMs":300000,"periods":{"today":{"totalTokens":12400000,"costUsd":8.36,"clients":{"claude":8000000,"codex":4400000}},"month":{"totalTokens":186000000,"costUsd":124.5},"allTime":{"totalTokens":1280000000,"costUsd":862.1}},"devices":[],"historyPreview":{"daily":[{"date":"2026-08-06","tokens":12400000,"cost":8.36}]},"limits":{"providers":[{"provider":"claude","status":"ok","windows":[{"kind":"session","usedPercent":64,"resetsAt":"2026-08-06T17:00:00.000Z"}]}]},"subscriptionsUpdatedAt":""}
      ''';
      final s = StatsSnapshot.fromJson(jsonDecode(raw));
      expect(s.periods!.today!.totalTokens, 12400000);
      expect(s.limits!.providers.single.windows.single.usedPercent, 64);
    });
  });
}
