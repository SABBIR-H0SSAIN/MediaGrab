import 'dart:async';
import 'dart:io';
import 'package:background_downloader/background_downloader.dart' as bg;
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/downloads/data/services/download_engine.dart';
import 'package:mediagrab/features/downloads/domain/entities/download_task.dart';
import 'package:mediagrab/features/downloads/domain/enums/download_status.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';

// Only the native boundary is replaced. Queue, path selection, callback handling
// and direct fallback execute the production engine implementation.
class _Downloader implements bg.FileDownloader {
  late bg.TaskStatusCallback status;
  final enqueued = Completer<bg.Task>();
  bool accept = true;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #registerCallbacks:
        status =
            invocation.namedArguments[#taskStatusCallback]
                as bg.TaskStatusCallback;
        return this;
      case #configureNotification:
        return this;
      case #enqueue:
        enqueued.complete(invocation.positionalArguments.single as bg.Task);
        return Future<bool>.value(accept);
      default:
        return super.noSuchMethod(invocation);
    }
  }
}

class _FailingHttp implements HttpClientAdapter {
  int requests = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    return ResponseBody.fromString('Unavailable', 404);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const media = MediaInfo(
    id: 'social',
    title: 'Social',
    thumbnailUrl: '',
    duration: Duration.zero,
    uploader: '',
    platform: PlatformType.facebook,
  );
  const stream = StreamInfo(
    url: 'https://example.com/video.mp4',
    qualityLabel: '360p',
    codec: 'avc1',
    container: 'mp4',
  );

  for (final terminal in [
    DownloadStatus.completed,
    DownloadStatus.failed,
    DownloadStatus.cancelled,
    DownloadStatus.paused,
  ]) {
    test('late native callbacks preserve ${terminal.name}', () async {
      final downloader = _Downloader();
      final engine = DownloadEngine(fileDownloader: downloader);
      addTearDown(engine.dispose);
      final task = DownloadTask(
        id: 'existing',
        mediaInfo: media,
        selectedStream: stream,
        status: terminal,
        createdAt: DateTime(2026),
      );
      engine.updateTaskDirectly(task);
      final native = bg.DownloadTask(taskId: task.id, url: stream.url);
      for (final status in [
        bg.TaskStatus.paused,
        bg.TaskStatus.canceled,
        bg.TaskStatus.failed,
        bg.TaskStatus.complete,
      ]) {
        downloader.status(bg.TaskStatusUpdate(native, status));
        await Future<void>.delayed(Duration.zero);
        expect(engine.getTask(task.id), task);
      }
    });
  }

  test(
    'native enqueue rejection enters direct fallback and releases slot',
    () async {
      final dir = await Directory.systemTemp.createTemp('enqueue_rejected_');
      addTearDown(() => dir.delete(recursive: true));
      final downloader = _Downloader()..accept = false;
      final http = _FailingHttp();
      final dio = Dio()..httpClientAdapter = http;
      final engine = DownloadEngine(fileDownloader: downloader, dio: dio);
      addTearDown(engine.dispose);
      final failed = engine.onTaskUpdated.firstWhere((t) => t.status.isFailed);
      await engine.startDownload(media, stream, '${dir.path}/video.mp4');
      final result = await failed.timeout(const Duration(seconds: 5));
      expect(result.errorMessage, contains('not found'));
      expect(http.requests, greaterThan(0));
      expect(engine.getActiveDownloads(), isEmpty);
    },
  );

  test(
    'restricted-folder fallback reserves a unique path without overwriting media',
    () async {
      final dir = await Directory.systemTemp.createTemp('fallback_collision_');
      addTearDown(() => dir.delete(recursive: true));
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => dir.path);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final existing = File('${dir.path}/MediaGrab/video.mp4');
      await existing.parent.create();
      await existing.writeAsBytes([1, 2, 3]);
      final downloader = _Downloader();
      final engine = DownloadEngine(fileDownloader: downloader);
      addTearDown(engine.dispose);
      final task = await engine.startDownload(
        media,
        stream,
        '/dev/null/video.mp4',
      );
      await downloader.enqueued.future.timeout(const Duration(seconds: 5));
      expect(
        engine.getTask(task.id)!.filePath,
        '${dir.path}/MediaGrab/video (1).mp4',
      );
      expect(await existing.readAsBytes(), [1, 2, 3]);
    },
  );
}
