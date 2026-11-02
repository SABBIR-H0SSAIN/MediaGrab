import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/downloads/data/services/download_engine.dart';
import 'package:mediagrab/features/downloads/domain/entities/download_task.dart';
import 'package:mediagrab/features/downloads/domain/enums/download_status.dart';
import 'package:mediagrab/features/downloads/presentation/providers/download_manager_provider.dart';
import 'package:mediagrab/features/downloads/presentation/providers/download_progress_provider.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';

void main() {
  group('DownloadProgressProvider', () {
    const testMediaInfo = MediaInfo(
      id: 'abc12345678',
      title: 'Provider Family Testing',
      thumbnailUrl: 'https://example.com/thumb.jpg',
      duration: Duration(minutes: 6),
      uploader: 'Coder',
      platform: PlatformType.youtube,
    );

    const testStreamInfo = StreamInfo(
      url: 'https://example.com/stream.mp4',
      qualityLabel: '720p',
      codec: 'avc1',
      container: 'mp4',
      sizeInBytes: 50000000,
    );

    late DownloadEngine engine;
    late ProviderContainer container;

    setUp(() {
      engine = DownloadEngine(
        customDownloadExecution:
            ({
              required task,
              required stream,
              required targetPath,
              required onProgress,
              required onComplete,
              required onError,
            }) async {},
      );

      container = ProviderContainer(
        overrides: [downloadEngineProvider.overrideWithValue(engine)],
      );
    });

    tearDown(() {
      container.dispose();
      engine.dispose();
    });

    test('returns null and 0.0 for unknown taskId', () {
      final task = container.read(downloadProgressProvider('unknown_task'));
      expect(task, isNull);

      final progress = container.read(
        downloadTaskProgressValueProvider('unknown_task'),
      );
      expect(progress, 0.0);
    });

    test('returns correct task and progress value for existing task', () {
      final task = DownloadTask(
        id: 'task-42',
        mediaInfo: testMediaInfo,
        selectedStream: testStreamInfo,
        status: DownloadStatus.downloading,
        progress: 0.67,
        createdAt: DateTime.now(),
      );

      container.read(downloadManagerProvider.notifier).setTasks([task]);

      final found = container.read(downloadProgressProvider('task-42'));
      expect(found, equals(task));

      final progressVal = container.read(
        downloadTaskProgressValueProvider('task-42'),
      );
      expect(progressVal, 0.67);
    });
  });
}
