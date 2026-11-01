import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Bounded, secret-free logs, exportable through [pathForTask] or ADB run-as.
class YoutubeDiagnostics {
  static Future<String> pathForTask(String id) async =>
      '${(await getApplicationSupportDirectory()).path}/youtube-diagnostics/${id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.jsonl';

  final String taskId;
  int _records = 0;
  Future<void> _writes = Future.value();

  YoutubeDiagnostics(this.taskId);

  void record(String event, Map<String, Object?> values) {
    if (_records >= 380 && ['http', 'bytes'].contains(event)) return;
    if (_records++ >= 400) return;
    final firstRecord = _records == 1;
    // Callers supply diagnostic metadata, never exception messages/URLs/headers.
    final data = {
      'time': DateTime.now().toUtc().toIso8601String(),
      'taskId': taskId,
      'event': event,
      ...values,
    };
    debugPrint('YouTube ${jsonEncode(data)}');
    _writes = _writes
        .then((_) async {
          final path = await pathForTask(taskId);
          final directory = File(path).parent;
          await directory.create(recursive: true);
          if (firstRecord) {
            final files =
                await directory
                    .list()
                    .where((f) => f is File)
                    .cast<File>()
                    .toList();
            files.sort(
              (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
            );
            for (final old in files.take(
              (files.length - 19).clamp(0, files.length),
            )) {
              if (old.path != path) await old.delete();
            }
          }
          await File(path).writeAsString(
            '${jsonEncode(data)}\n',
            mode: FileMode.append,
            flush: true,
          );
        })
        .catchError((Object _) {});
  }

  Future<void> flush() => _writes;
}
