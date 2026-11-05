// Explicit test entrypoint. The production entrypoint and UI are unchanged.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mediagrab/app.dart';
import 'package:mediagrab/core/services/download_notification_service.dart';
import 'package:mediagrab/features/downloads/data/services/download_engine.dart';
import 'package:mediagrab/features/downloads/data/services/youtube_diagnostics.dart';
import 'package:mediagrab/features/downloads/domain/enums/download_status.dart';
import 'package:mediagrab/features/extractor/data/extractors/youtube_extractor.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DownloadNotificationService.instance.init(requestPermission: false);
  runApp(const ProviderScope(child: MediaGrabApp()));
  unawaited(probe());
}

Future<void> probe() async {
  final directory = Directory(
    '${(await getExternalStorageDirectory())!.path}/youtube-mission-tests',
  );
  await directory.create(recursive: true);
  final results = File('${directory.path}/results.jsonl');
  final extractor = YoutubeExtractor();
  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 20)));
  final engine = DownloadEngine(maxConcurrentDownloads: 1, dio: dio);
  const cases = String.fromEnvironment(
    'YOUTUBE_TEST_CASES',
    defaultValue: 'aqz-KE-bpKQ|480p,aqz-KE-bpKQ|720p60,aqz-KE-bpKQ|1080p60',
  );
  for (final testCase in cases.split(',')) {
    final parts = testCase.split('|');
    final id = parts[0];
    final quality = parts[1];
    final mode = parts.length > 2 ? parts[2] : 'normal';
    final codec = parts.length > 3 ? parts[3] : 'avc';
    var injected = false;
    dio.interceptors.clear();
    if (mode == '403') {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (!injected &&
                '${options.headers['Range']}' != 'bytes=0-1048575') {
              injected = true;
              return handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response(requestOptions: options, statusCode: 403),
                ),
              );
            }
            handler.next(options);
          },
        ),
      );
    }
    final watch = Stopwatch()..start();
    try {
      final info = await extractor
          .extractInfo(id)
          .timeout(const Duration(seconds: 60));
      final streams = await extractor
          .getStreams(id)
          .timeout(const Duration(seconds: 90));
      StreamInfo? selected;
      for (final s in streams) {
        if (s.qualityLabel == quality &&
            !s.isAudioOnly &&
            (selected == null || s.codec.startsWith(codec))) {
          selected = s;
        }
      }
      if (selected == null) throw StateError('Requested quality unavailable');
      if (mode == 'expired') {
        final uri = Uri.parse(selected.url);
        selected = StreamInfo(
          url:
              uri
                  .replace(
                    queryParameters: {...uri.queryParameters, 'expire': '1'},
                  )
                  .toString(),
          qualityLabel: selected.qualityLabel,
          codec: selected.codec,
          container: selected.container,
          sizeInBytes: selected.sizeInBytes,
          isVideoOnly: selected.isVideoOnly,
          isAudioOnly: selected.isAudioOnly,
          videoWidth: selected.videoWidth,
          videoHeight: selected.videoHeight,
          bitrate: selected.bitrate,
        );
      }
      StreamInfo? audio;
      for (final s in streams.where((s) => s.isAudioOnly)) {
        if ((selected.container == 'webm' && s.codec == 'opus') ||
            (selected.container != 'webm' && s.codec == 'mp4a.40.2')) {
          audio = s;
          break;
        }
      }
      String? taskId;
      var controlled = false;
      var controlPass = !['pause', 'cancel'].contains(mode);
      final control = engine.onTaskUpdated.listen((t) async {
        if (t.id != taskId ||
            controlled ||
            (t.downloadedBytes ?? 0) < 1048576 ||
            !['pause', 'cancel'].contains(mode)) {
          return;
        }
        controlled = true;
        if (mode == 'cancel') {
          await engine.cancelDownload(t.id);
          controlPass =
              !await File('${t.filePath}_video.tmp').exists() &&
              !await File('${t.filePath}.youtube.part').exists();
          await engine.retryDownload(t.id);
          return;
        }
        await engine.pauseDownload(t.id);
        final before =
            engine
                .getAllDownloads()
                .firstWhere((v) => v.id == t.id)
                .downloadedBytes;
        await Future<void>.delayed(const Duration(milliseconds: 500));
        controlPass =
            before ==
            engine
                .getAllDownloads()
                .firstWhere((v) => v.id == t.id)
                .downloadedBytes;
        await engine.resumeDownload(t.id);
      });
      final task = await engine.startDownload(
        info,
        selected,
        '${directory.path}/${id}_$quality.${selected.container}',
        audioStream: audio,
      );
      taskId = task.id;
      final completed = await engine.onTaskUpdated
          .firstWhere(
            (t) =>
                t.id == task.id &&
                (t.status == DownloadStatus.completed ||
                    t.status == DownloadStatus.failed),
          )
          .timeout(const Duration(minutes: 20));
      await control.cancel();
      final logPath = await YoutubeDiagnostics.pathForTask(task.id);
      if (await File(logPath).exists()) {
        await File(logPath).copy('${directory.path}/${task.id}.jsonl');
      }
      final record = {
        'mode': mode,
        'controlPass': controlPass,
        'codec': selected.codec,
        'id': id,
        'quality': quality,
        'itag': Uri.parse(selected.url).queryParameters['itag'],
        'status': completed.status.name,
        'bytes': completed.downloadedBytes,
        'elapsedMs': watch.elapsedMilliseconds,
        'expectedDurationMs': info.duration.inMilliseconds,
        'path': completed.filePath,
        'error': completed.errorMessage,
      };
      await results.writeAsString(
        '${jsonEncode(record)}\n',
        mode: FileMode.append,
        flush: true,
      );
      debugPrint('YOUTUBE_MISSION_RESULT ${jsonEncode(record)}');
    } catch (e) {
      final record = {
        'id': id,
        'quality': quality,
        'status': 'FAILED',
        'type': e.runtimeType.toString(),
        'elapsedMs': watch.elapsedMilliseconds,
      };
      await results.writeAsString(
        '${jsonEncode(record)}\n',
        mode: FileMode.append,
        flush: true,
      );
      debugPrint('YOUTUBE_MISSION_RESULT ${jsonEncode(record)}');
    }
  }
  debugPrint('YOUTUBE_MISSION_DONE');
  extractor.close();
  engine.dispose();
  dio.close(force: true);
}
