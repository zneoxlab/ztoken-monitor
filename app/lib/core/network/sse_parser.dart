// ============================================================
// SSE 帧解析器 —— 纯函数,对照 saas-hub/src/sse.js 的 sseFormat。
//
// 帧格式(服务端 sseFormat):
//   event: <event>\n
//   data: <json>\n
//   \n              ← 空行分帧
// 心跳:": hb\n\n"(注释行,以 : 开头,忽略)。
// 规范:一个事件可跨多行 data:,本服务端只发单行 data,但解析器按规范
//   把同一事件的多行 data: 拼接(\n 连接)再 JSON 解码,前向兼容。
//
// 输入:已积累的字节解码文本;输出:消费掉的字数 + 解析出的帧(可能多个)。
// 流式解析:调用方喂入增量文本,本函数返回 {consumed, frames},
//   调用方截掉 consumed 前缀保留余量,下次再追加。
// ============================================================

// 一个解析出的 SSE 事件。
class SseEvent {
  const SseEvent({required this.event, required this.data});
  final String event; // 'stats' / 'snapshot' / ''(默认 message)
  final String data; // data: 行拼接后的原始字符串(JSON 文本)
}

// 解析结果:本次消费的字符数 + 解析出的完整事件列表。
class SseParseResult {
  const SseParseResult({required this.consumed, required this.events});
  final int consumed;
  final List<SseEvent> events;
}

// 帧分隔符:空行(\n\n)。服务端每帧以 \n\n 结尾。
// 找到第一个 \n\n 之前的内容为一帧;找不到说明数据不完整,等下次。
SseParseResult parseSseChunk(String input) {
  final events = <SseEvent>[];
  var consumed = 0;
  var start = 0;

  while (true) {
    final sep = input.indexOf('\n\n', start);
    if (sep < 0) break; // 剩余不构成完整帧,留待下次

    final block = input.substring(start, sep);
    consumed = sep + 2; // 含分隔符
    start = sep + 2;

    final event = _parseBlock(block);
    if (event != null) events.add(event);
  }

  return SseParseResult(consumed: consumed, events: events);
}

// 解析单个帧块(不含尾随 \n\n)。返回 null = 注释行/心跳/空帧,忽略。
SseEvent? _parseBlock(String block) {
  if (block.isEmpty) return null;

  String? event;
  final dataParts = <String>[];

  for (final line in block.split('\n')) {
    if (line.isEmpty) continue;
    // 注释行(心跳 ": hb"):忽略
    if (line.startsWith(':')) continue;
    if (line.startsWith('event:')) {
      event = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      // data: 后可能有一个前导空格(SSE 规范),去掉
      var d = line.substring(5);
      if (d.startsWith(' ')) d = d.substring(1);
      dataParts.add(d);
    }
    // 其他字段(id: / retry:)本协议不用,忽略
  }

  // 无 data 行的帧(纯注释/纯 event)对 stats 无意义,忽略
  if (dataParts.isEmpty) return null;

  return SseEvent(event: event ?? '', data: dataParts.join('\n'));
}
