// SSE 帧解析器测试:分帧 / 事件类型 / 心跳忽略 / 多行 data / 增量拼接。
import 'package:flutter_test/flutter_test.dart';
import 'package:ztoken_monitor/core/network/sse_parser.dart';

void main() {
  group('parseSseChunk 单帧', () {
    test('stats 事件', () {
      const input = 'event: stats\ndata: {"type":"stats","reason":"update","stats":{"x":1},"at":"t"}\n\n';
      final r = parseSseChunk(input);
      expect(r.consumed, input.length);
      expect(r.events.length, 1);
      expect(r.events[0].event, 'stats');
      expect(r.events[0].data, contains('"reason":"update"'));
    });

    test('snapshot 事件', () {
      const input = 'event: snapshot\ndata: {"type":"stats","reason":"snapshot","stats":{}}\n\n';
      final r = parseSseChunk(input);
      expect(r.events.single.event, 'snapshot');
    });

    test('心跳注释行忽略', () {
      const input = ': hb\n\n';
      final r = parseSseChunk(input);
      expect(r.consumed, input.length);
      expect(r.events, isEmpty);
    });

    test('data: 后前导空格去掉(SSE 规范)', () {
      const input = 'event: stats\ndata: {"a":1}\n\n';
      final r = parseSseChunk(input);
      expect(r.events.single.data, '{"a":1}');
    });

    test('多行 data: 拼接(\\n 连接)', () {
      const input = 'event: stats\ndata: {"a":\ndata: 1}\n\n';
      final r = parseSseChunk(input);
      expect(r.events.single.data, '{"a":\n1}');
    });
  });

  group('parseSseChunk 多帧', () {
    test('连续两帧都解析', () {
      const input =
          'event: snapshot\ndata: {"i":1}\n\nevent: stats\ndata: {"i":2}\n\n';
      final r = parseSseChunk(input);
      expect(r.consumed, input.length);
      expect(r.events.length, 2);
      expect(r.events[0].event, 'snapshot');
      expect(r.events[1].event, 'stats');
    });

    test('帧间夹心跳仍正确分帧', () {
      const input =
          'event: stats\ndata: {"i":1}\n\n: hb\n\nevent: stats\ndata: {"i":2}\n\n';
      final r = parseSseChunk(input);
      expect(r.events.length, 2);
      expect(r.events[0].data, '{"i":1}');
      expect(r.events[1].data, '{"i":2}');
    });
  });

  group('parseSseChunk 增量(不完整帧)', () {
    test('无分隔符 → 0 consumed,0 events', () {
      const input = 'event: stats\ndata: {"a":1}';
      final r = parseSseChunk(input);
      expect(r.consumed, 0);
      expect(r.events, isEmpty);
    });

    test('一完整 + 一不完整 → 只解析完整帧,余量保留', () {
      const input = 'event: stats\ndata: {"a":1}\n\nevent: stats\ndata: {"b":2}';
      const firstFrame = 'event: stats\ndata: {"a":1}\n\n';
      final r = parseSseChunk(input);
      // 只消费第一帧(含 \n\n),第二帧不完整留着
      expect(r.events.length, 1);
      expect(r.events[0].data, '{"a":1}');
      expect(r.consumed, firstFrame.length);
      // 余量应是第二帧的未完成部分
      expect(input.substring(r.consumed), 'event: stats\ndata: {"b":2}');
    });
  });

  group('parseSseChunk 无 data 行的帧', () {
    test('纯 event 无 data → 忽略', () {
      const input = 'event: ping\n\n';
      final r = parseSseChunk(input);
      expect(r.events, isEmpty);
    });
  });
}
