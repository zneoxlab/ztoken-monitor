import 'dart:async';

import 'package:dio/dio.dart';

import 'dio_client.dart';

// 非 Web:复用 Dio 流式 GET。
class SseStreamHandle {
  SseStreamHandle._(this._cancel);

  final Future<void> Function() _cancel;
  final StreamController<List<int>> controller = StreamController<List<int>>();
  StreamSubscription<List<int>>? _sub;

  Stream<List<int>> get stream => controller.stream;

  Future<void> close() async {
    await _sub?.cancel();
    await _cancel();
    await controller.close();
  }
}

Future<SseStreamHandle> openSseStream({
  required String url,
  required Map<String, String> headers,
}) async {
  final dio = Dio(BaseOptions(
    connectTimeout: kHubConnectTimeout,
    receiveTimeout: null,
    headers: headers,
  ));
  final resp = await dio.get<ResponseBody>(
    url,
    options: Options(
      responseType: ResponseType.stream,
      headers: {...headers, 'Accept': 'text/event-stream'},
    ),
  );
  final handle = SseStreamHandle._(() async => dio.close(force: true));
  handle._sub = resp.data!.stream.listen(
    handle.controller.add,
    onError: handle.controller.addError,
    onDone: handle.controller.close,
    cancelOnError: true,
  );
  return handle;
}
