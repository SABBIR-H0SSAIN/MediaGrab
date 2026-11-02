import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/downloads/data/services/download_engine.dart';
import 'package:mediagrab/features/downloads/domain/enums/download_status.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('media_merge_lifecycle_');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  const video = StreamInfo(
    url: 'https://example.com/video',
    qualityLabel: 'HD',
    codec: 'avc1',
    container: 'mp4',
    isVideoOnly: true,
  );
  const audio = StreamInfo(
    url: 'https://example.com/audio',
    qualityLabel: 'Audio',
    codec: 'aac',
    container: 'mp4',
    isAudioOnly: true,
  );

  Future<
    ({
      DownloadEngine engine,
      String id,
      Future<void> Function() complete,
      String output,
    })
  >
  start(
    FFmpegMergeFunction merger, {
    PlatformType platform = PlatformType.facebook,
  }) async {
    final ready = Completer<void>();
    late Future<void> Function() complete;
    final engine = DownloadEngine(
      ffmpegMerger: merger,
      customDownloadExecution: ({
        required task,
        required stream,
        required targetPath,
        required onProgress,
        required onComplete,
        required onError,
      }) async {
        await File(targetPath).writeAsBytes([1, 2, 3]);
        if (stream.isVideoOnly) {
          complete = onComplete;
          if (!ready.isCompleted) ready.complete();
        } else {
          await onComplete();
        }
      },
    );
    addTearDown(engine.dispose);
    final output = '${dir.path}/result.mp4';
    final task = await engine.startDownload(
      MediaInfo(
        id: 'fixture',
        title: 'Fixture',
        thumbnailUrl: '',
        duration: Duration.zero,
        uploader: '',
        platform: platform,
      ),
      video,
      output,
      audioStream: audio,
    );
    await ready.future;
    return (
      engine: engine,
      id: task.id,
      complete: () => complete(),
      output: output,
    );
  }

  for (final platform in [
    PlatformType.facebook,
    PlatformType.instagram,
    PlatformType.unknown,
  ]) {
    test('${platform.name}: failed merge preserves source tracks', () async {
      final job = await start((v, a, o) async => false, platform: platform);
      await job.complete();
      expect(job.engine.getTask(job.id)?.status, DownloadStatus.failed);
      expect(await File('${job.output}_video.tmp').readAsBytes(), [1, 2, 3]);
      expect(await File('${job.output}_audio.tmp').readAsBytes(), [1, 2, 3]);
    });
  }

  test('validation failure preserves recoverable inputs', () async {
    final job = await start((v, a, o) async {
      await File(o).writeAsBytes([]);
      return true;
    });
    await job.complete();
    expect(job.engine.getTask(job.id)?.status, DownloadStatus.failed);
    expect(await File('${job.output}_video.tmp').exists(), isTrue);
    expect(await File('${job.output}_audio.tmp').exists(), isTrue);
  });

  test('successful completion cleans inputs only after finalization', () async {
    final job = await start((v, a, o) async {
      await File(o).writeAsBytes([4, 5, 6]);
      return true;
    });
    await job.complete();
    expect(job.engine.getTask(job.id)?.status, DownloadStatus.completed);
    expect(await File(job.output).readAsBytes(), [4, 5, 6]);
    expect(await File('${job.output}_video.tmp').exists(), isFalse);
    expect(await File('${job.output}_audio.tmp').exists(), isFalse);
  });

  test(
    'resume waits for the old merge writer and paused inputs survive',
    () async {
      final entered = Completer<void>();
      final exit = Completer<void>();
      var merges = 0;
      final job = await start((v, a, o) async {
        merges++;
        if (merges == 1) {
          entered.complete();
          await exit.future;
        }
        await File(o).writeAsBytes([4, 5, 6]);
        return true;
      });
      final old = job.complete();
      await entered.future;
      var resumed = false;
      final pause = job.engine.pauseDownload(job.id);
      final resume = job.engine.resumeDownload(job.id).then((value) {
        resumed = value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(job.engine.getTask(job.id)?.status, DownloadStatus.paused);
      expect(resumed, isFalse);
      expect(merges, 1);
      exit.complete();
      await old;
      await pause;
      await resume;
      expect(resumed, isTrue);
      expect(await File('${job.output}_video.tmp').exists(), isTrue);
      expect(await File('${job.output}_audio.tmp').exists(), isTrue);
    },
  );

  test('cancel joins the merge writer before cleaning owned files', () async {
    final entered = Completer<void>();
    final exit = Completer<void>();
    final job = await start((v, a, o) async {
      entered.complete();
      await exit.future;
      await File(o).writeAsBytes([4]);
      return true;
    });
    final old = job.complete();
    await entered.future;
    var stopped = false;
    final cancel = job.engine.cancelDownload(job.id).then((_) {
      stopped = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse);
    expect(job.engine.getTask(job.id)?.status, DownloadStatus.cancelled);
    exit.complete();
    await old;
    await cancel;
    expect(stopped, isTrue);
    for (final suffix in ['', '_video.tmp', '_audio.tmp']) {
      expect(await File('${job.output}$suffix').exists(), isFalse);
    }
    expect(job.engine.getActiveDownloads(), isEmpty);
  });
}
