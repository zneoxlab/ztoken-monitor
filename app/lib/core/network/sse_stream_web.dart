import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

// Web:fetch + ReadableStream,避免 Dio/XHR 流过早 onDone。
class SseStreamHandle {
  SseStreamHandle(this._abort, this.controller);

  final web.AbortController _abort;
  final StreamController<List<int>> controller;

  Stream<List<int>> get stream => controller.stream;

  Future<void> close() async {
    _abort.abort();
    await controller.close();
  }
}

Future<SseStreamHandle> openSseStream({
  required String url,
  required Map<String, String> headers,
}) async {
  final controller = StreamController<List<int>>();
  final abort = web.AbortController();

  final hdrs = web.Headers();
  for (final e in headers.entries) {
    hdrs.set(e.key, e.value);
  }

  final resp = await web.window
      .fetch(
        url.toJS,
        web.RequestInit(
          method: 'GET',
          headers: hdrs,
          signal: abort.signal,
        ),
      )
      .toDart;

  if (!resp.ok) {
    abort.abort();
  final err = 'HTTP ${resp.status}';
    await controller.close();
    throw StateError(err);
  }

  final body = resp.body;
  if (body == null) {
    abort.abort();
    await controller.close();
    throw StateError('SSE body 为空');
  }

  final handle = SseStreamHandle(abort, controller);
  unawaited(_readLoop(web.ReadableStreamDefaultReader(body), controller));
  return handle;
}

Future<void> _readLoop(
  web.ReadableStreamDefaultReader reader,
  StreamController<List<int>> controller,
) async {
  try {
    while (true) {
      final chunk = await reader.read().toDart;
      if (chunk.done) break;
      final bytes = chunk.value as JSUint8Array?;
      if (bytes != null) {
        controller.add(bytes.toDart);
      }
    }
    await controller.close();
  } catch (e) {
    if (!controller.isClosed) {
      controller.addError(e);
      await controller.close();
    }
  }
}
