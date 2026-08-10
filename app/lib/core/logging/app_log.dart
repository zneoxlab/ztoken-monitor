import 'package:flutter/foundation.dart';

import '../app_version.dart';

// 内存环形日志缓冲,供 SSE 诊断与「连点版本号导出」使用。
class AppLog {
  AppLog._();

  static const _maxEntries = 800;
  static final List<String> _lines = <String>[];

  static void info(String tag, String message) {
    _write('I', tag, message);
  }

  static void warn(String tag, String message) {
    _write('W', tag, message);
  }

  static void error(String tag, String message, [Object? err]) {
    final detail = err == null ? message : '$message · $err';
    _write('E', tag, detail);
  }

  static void _write(String level, String tag, String message) {
    final line =
        '${DateTime.now().toIso8601String()} [$level/$tag] $message';
    debugPrint(line);
    _lines.add(line);
    if (_lines.length > _maxEntries) {
      _lines.removeRange(0, _lines.length - _maxEntries);
    }
  }

  static String export({String? hubUrl, String? email}) {
    final buf = StringBuffer()
      ..writeln('ZT助手 system log')
      ..writeln('version: $kAppVersion')
      ..writeln('exportedAt: ${DateTime.now().toIso8601String()}')
      ..writeln('platform: ${defaultTargetPlatform.name}')
      ..writeln('hubUrl: ${hubUrl ?? '-'}')
      ..writeln('user: ${email ?? '-'}')
      ..writeln('entries: ${_lines.length}')
      ..writeln('---');
  for (final line in _lines) {
      buf.writeln(line);
    }
    return buf.toString();
  }

  @visibleForTesting
  static void clear() => _lines.clear();
}
