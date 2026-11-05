// Run with: flutter test test/benchmarks/batch_sync_benchmark.dart --reporter expanded
// Host CPU benchmark; no network, files, Android timings or download claims.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/downloads/domain/entities/download_task.dart';
import 'package:mediagrab/features/downloads/domain/enums/download_status.dart';
import 'package:mediagrab/features/extractor/data/extractor_factory.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';
import 'package:mediagrab/features/extractor/presentation/providers/batch_preparation_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('linked batch progress synchronization: 1000 rows, 100 updates', () {
    SharedPreferences.setMockInitialValues({});
    final controller = BatchPreparationController(
      ExtractorFactory(extractors: []),
    );
    const media = MediaInfo(
      id: 'sample',
      title: 'Sample',
      thumbnailUrl: '',
      duration: Duration.zero,
      uploader: '',
      platform: PlatformType.youtube,
    );
    const stream = StreamInfo(
      url: 'https://example.com/media',
      qualityLabel: '360p',
      codec: 'avc1',
      container: 'mp4',
    );
    final tasks = [
      for (var i = 0; i < 1000; i++)
        DownloadTask(
          id: 'task-$i',
          mediaInfo: media,
          selectedStream: stream,
          status: DownloadStatus.downloading,
          createdAt: DateTime(2026),
        ),
    ];
    for (var i = 0; i < tasks.length; i++) {
      if (i > 0) controller.add('https://example.com/$i');
      controller.attachTask(i, tasks[i]);
    }
    for (var i = 0; i < 10; i++) {
      controller.syncTasks(tasks, (_) async => false);
    }
    final measurements = <int>[];
    for (var round = 0; round < 5; round++) {
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        controller.syncTasks(tasks, (_) async => false);
      }
      measurements.add(stopwatch.elapsedMicroseconds);
    }
    // Deliberately no timing assertion: correctness belongs in regression tests.
    debugPrint('BATCH_SYNC_MICROSECONDS $measurements');
    expect(controller.state.items.length, 1000);
    controller.dispose();
  });
}
