// Controlled native-downloader boundary; production engine execution,
// FFmpeg/FFprobe completion and registry are not replaced.
import 'dart:async';
import 'dart:io';
import 'package:background_downloader/background_downloader.dart' as bg;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mediagrab/app.dart';
import 'package:mediagrab/core/services/download_notification_service.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/downloads/data/services/download_engine.dart';
import 'package:mediagrab/features/downloads/data/services/download_registry.dart';
import 'package:mediagrab/features/downloads/domain/enums/download_status.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';
import 'media_merge_device_probe.dart' as fixtures;

class _LocalDownloader implements bg.FileDownloader {
  final String prefix;
  late bg.TaskStatusCallback status;
  _LocalDownloader(this.prefix);

  Future<bool> _enqueue(bg.Task task) async {
    await File('$prefix.video').copy(await task.filePath());
    scheduleMicrotask(
      () => status(bg.TaskStatusUpdate(task, bg.TaskStatus.complete)),
    );
    return true;
  }

  Future<bg.TaskStatusUpdate> _download(bg.Task task) async {
    await File('$prefix.audio').copy(await task.filePath());
    return bg.TaskStatusUpdate(task, bg.TaskStatus.complete);
  }

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
        return _enqueue(invocation.positionalArguments.first as bg.Task);
      case #download:
        return _download(invocation.positionalArguments.first as bg.Task);
      default:
        return super.noSuchMethod(invocation);
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DownloadNotificationService.instance.init(requestPermission: false);
  runApp(const ProviderScope(child: MediaGrabApp()));
  unawaited(run());
}

Future<void> run() async {
  fixtures.root =
      '${(await getExternalStorageDirectory())!.path}/media-merge-tests';
  fixtures.evidence = File('${fixtures.root}/native-results.jsonl');
  await fixtures.evidence.writeAsString('');
  try {
    for (final platform in [
      PlatformType.facebook,
      PlatformType.instagram,
      PlatformType.unknown,
    ]) {
      final webm = platform == PlatformType.instagram;
      final prefix = '${fixtures.root}/${webm ? 'webm' : 'short'}';
      final selected = StreamInfo(
        url: 'https://example.com/controlled-native-video',
        qualityLabel: webm ? '1080p' : '480p',
        codec: webm ? 'vp9' : 'avc1',
        container: webm ? 'webm' : 'mp4',
        videoWidth: webm ? 1920 : 854,
        videoHeight: webm ? 1080 : 480,
        isVideoOnly: true,
      );
      final audio = StreamInfo(
        url: 'https://example.com/controlled-native-audio',
        qualityLabel: 'Audio',
        codec: webm ? 'opus' : 'aac',
        container: selected.container,
        isAudioOnly: true,
      );
      final registry = DownloadRegistry();
      final engine = DownloadEngine(
        fileDownloader: _LocalDownloader(prefix),
        downloadRegistry: registry,
      );
      final terminal = engine.onTaskUpdated.firstWhere(
        (t) =>
            t.status == DownloadStatus.completed ||
            t.status == DownloadStatus.failed,
      );
      final watch = Stopwatch()..start();
      final task = await engine.startDownload(
        MediaInfo(
          id: 'native-${platform.name}',
          title: 'Controlled native ${platform.name}',
          thumbnailUrl: '',
          duration: const Duration(seconds: 70),
          uploader: 'Native adapter fixture',
          platform: platform,
        ),
        selected,
        '${fixtures.root}/native-${platform.name}.${selected.container}',
        audioStream: audio,
      );
      final result = await terminal.timeout(const Duration(minutes: 1));
      if (result.status != DownloadStatus.completed) {
        throw StateError('Completion failed');
      }
      final proof = await fixtures.validate(
        result.filePath!,
        selected.videoWidth!,
        selected.videoHeight!,
        selected.qualityLabel,
        const Duration(seconds: 70),
      );
      final registered = (await registry.getCompletedRecords()).any(
        (r) => r.id == task.id,
      );
      if (!registered) throw StateError('Missing registered output');
      await fixtures.record({
        'case': 'native-adapter-route',
        'platform': platform.name,
        'status': 'VERIFIED',
        'elapsedMs': watch.elapsedMilliseconds,
        'registry': registered,
        'productionOutputProbe': true,
        'proof': proof,
      });
      engine.dispose();
    }
    debugPrint('MEDIA_MERGE_NATIVE_TEST_DONE');
  } catch (e) {
    await fixtures.record({
      'case': 'native-adapter-route',
      'status': 'FAILED',
      'type': e.runtimeType.toString(),
    });
  }
}
