import 'sse_stream_io.dart'
    if (dart.library.html) 'sse_stream_web.dart' as impl;

// 平台 SSE 字节流:移动端走 Dio,Web 走 fetch ReadableStream(支持 Authorization)。
typedef SseStreamHandle = impl.SseStreamHandle;

Future<SseStreamHandle> openSseStream({
  required String url,
  required Map<String, String> headers,
}) =>
    impl.openSseStream(url: url, headers: headers);
