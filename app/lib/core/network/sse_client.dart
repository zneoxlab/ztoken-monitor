import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_log.dart';
import 'auth_mode.dart';
import 'dio_client.dart';
import 'sse_parser.dart';
import 'sse_stream.dart';

// ============================================================
// SseClient —— SSE 长连接客户端 + 退避重连 + 轮询降级。
// ============================================================

enum SseConnectionState {
  connecting,
  connected,
  polling,
  disconnected,
}

const _kBackoffStart = Duration(seconds: 1);
const _kBackoffMax = Duration(seconds: 30);
const _kPollInterval = Duration(seconds: 30);
const _kMaxSseFailures = 3;
const _kSseRecoveryCooldown = Duration(seconds: 60);

class SseClient {
  SseClient({required this.ref});

  final Ref ref;

  final _statsController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get stats => _statsController.stream;

  final _stateController = StreamController<SseConnectionState>.broadcast();
  Stream<SseConnectionState> get connectionState => _stateController.stream;

  SseConnectionState current = SseConnectionState.disconnected;

  StreamSubscription<List<int>>? _byteSub;
  SseStreamHandle? _streamHandle;
  Timer? _reconnectTimer;
  Timer? _pollTimer;
  Duration _backoff = _kBackoffStart;
  int _sseFailures = 0;
  bool _disposed = false;
  bool _inPolling = false;
  bool _connectInFlight = false;
  DateTime? _lastSseRecoveryAt;
  String _buffer = '';

  Future<void> start() async {
    if (_disposed) return;
    _log('start');
    _setState(SseConnectionState.connecting);
    await _connectSse();
  }

  Future<void> onResume() async {
    _log('onResume');
    await _pollOnce(attemptSseRecovery: !_inPolling);
    if (!_inPolling) {
      _backoff = _kBackoffStart;
      await _connectSse();
    }
  }

  // 登出/切账号:断开 SSE 与轮询,避免旧会话帧继续写入 statsProvider。
  Future<void> stop() async {
    if (_disposed) return;
    _log('stop');
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _closeStream();
    _inPolling = false;
    _connectInFlight = false;
    _sseFailures = 0;
    _backoff = _kBackoffStart;
    _setState(SseConnectionState.disconnected);
  }

  void _log(String message) => AppLog.info('sse', message);

  void _setState(SseConnectionState s) {
    if (current == s) return;
    current = s;
    _log('state → ${s.name}');
    if (!_disposed) _stateController.add(s);
  }

  Future<void> _connectSse() async {
    if (_disposed || _connectInFlight) return;
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) {
      _setState(SseConnectionState.disconnected);
      return;
    }

    _connectInFlight = true;
    _setState(SseConnectionState.connecting);
    await _closeStream();

    final hubUrl = ref.read(hubUrlProvider);
    final url = '${hubUrl.replaceAll(RegExp(r'/$'), '')}/api/stats/stream';
    final headers = <String, String>{
      'Accept': 'text/event-stream',
      if (auth.authorizationHeader != null)
        'Authorization': auth.authorizationHeader!,
    };

    _log('connect $url');

    try {
      _streamHandle = await openSseStream(url: url, headers: headers);
      _onConnected();
      _byteSub = _streamHandle!.stream.listen(
        _onBytes,
        onError: (Object e) => _onStreamError('stream error: $e'),
        onDone: () => _onStreamError('SSE 流关闭'),
        cancelOnError: true,
      );
    } on DioException catch (e) {
      _onStreamError('SSE 连接失败: ${e.message} (status=${e.response?.statusCode})');
    } catch (e) {
      _onStreamError('SSE 连接异常: $e');
    } finally {
      _connectInFlight = false;
    }
  }

  Future<void> _closeStream() async {
    _byteSub?.cancel();
    _byteSub = null;
    final handle = _streamHandle;
    _streamHandle = null;
    if (handle != null) await handle.close();
    _buffer = '';
  }

  void _onConnected() {
    _sseFailures = 0;
    _backoff = _kBackoffStart;
    if (_inPolling) {
      _inPolling = false;
      _pollTimer?.cancel();
      _pollTimer = null;
      _log('SSE 恢复,退出轮询');
    }
    _setState(SseConnectionState.connected);
  }

  void _onBytes(List<int> bytes) {
    _buffer += utf8.decode(bytes);
    final r = parseSseChunk(_buffer);
    _buffer = _buffer.substring(r.consumed);
    for (final ev in r.events) {
      _dispatch(ev);
    }
  }

  void _dispatch(SseEvent ev) {
    try {
      final json = jsonDecode(ev.data) as Map<String, dynamic>;
      final stats = json['stats'];
      if (stats is Map<String, dynamic>) {
        _statsController.add(stats);
      }
    } catch (e) {
      _log('帧解析失败: $e');
    }
  }

  void _onStreamError(Object reason) {
    if (_disposed) return;
    AppLog.warn('sse', '$reason (failures=$_sseFailures, polling=$_inPolling)');
    unawaited(_closeStream());
    _sseFailures++;
    if (_sseFailures >= _kMaxSseFailures && !_inPolling) {
      _enterPolling();
      return;
    }
    _setState(SseConnectionState.connecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_backoff, () {
      final next = _backoff * 2;
      _backoff = next > _kBackoffMax ? _kBackoffMax : next;
      _connectSse();
    });
  }

  void _enterPolling() {
    if (_inPolling) return;
    _inPolling = true;
    _lastSseRecoveryAt = DateTime.now();
    unawaited(_closeStream());
    _reconnectTimer?.cancel();
    _setState(SseConnectionState.polling);
    _pollTimer?.cancel();
    _log('降级轮询(间隔 ${_kPollInterval.inSeconds}s)');
    _pollOnce();
    _pollTimer = Timer.periodic(_kPollInterval, (_) => _pollOnce());
  }

  Future<void> _pollOnce({bool attemptSseRecovery = true}) async {
    if (_disposed) return;
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) return;
    try {
      final resp = await ref.read(dioProvider).get<dynamic>(
            '/api/stats',
            options: Options(receiveTimeout: kHubDataReceiveTimeout),
          );
      if (resp.data is Map<String, dynamic>) {
        _statsController.add(resp.data as Map<String, dynamic>);
      }
      if (_inPolling && attemptSseRecovery && _shouldAttemptSseRecovery()) {
        _lastSseRecoveryAt = DateTime.now();
        _log('轮询成功,尝试恢复 SSE');
        await _connectSse();
      }
    } on DioException catch (e) {
      AppLog.warn('sse', '轮询失败: ${e.message}');
      if (!_inPolling) _enterPolling();
    } catch (e) {
      AppLog.warn('sse', '轮询异常: $e');
      if (!_inPolling) _enterPolling();
    }
  }

  bool _shouldAttemptSseRecovery() {
    final last = _lastSseRecoveryAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= _kSseRecoveryCooldown;
  }

  void dispose() {
    _disposed = true;
    _log('dispose');
    unawaited(_closeStream());
    _reconnectTimer?.cancel();
    _pollTimer?.cancel();
    _statsController.close();
    _stateController.close();
  }
}

final sseClientProvider = Provider<SseClient>((ref) {
  final client = SseClient(ref: ref);
  ref.onDispose(client.dispose);
  ref.listen<bool>(
    authProvider.select((auth) => auth.isAuthenticated),
    (previous, next) {
      if (previous == true && next == false) {
        client.stop();
      }
    },
  );
  return client;
});

final sseConnectionStateProvider = StreamProvider<SseConnectionState>((ref) async* {
  final client = ref.watch(sseClientProvider);
  yield client.current;
  yield* client.connectionState;
});
