import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/downloads/data/services/download_engine.dart';
import 'package:mediagrab/features/downloads/domain/entities/download_task.dart';
import 'package:mediagrab/features/downloads/domain/enums/download_status.dart';
import 'package:mediagrab/features/downloads/presentation/providers/download_manager_provider.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';
import 'package:mediagrab/features/settings/presentation/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DownloadManagerProvider', () {
    const testMediaInfo = MediaInfo(
      id: 'abc12345678',
      title: 'State Management with Riverpod',
      thumbnailUrl: 'https://example.com/thumb.jpg',
      duration: Duration(minutes: 8),
      uploader: 'Flutter Dev',
      platform: PlatformType.youtube,
    );

    const testStreamInfo = StreamInfo(
      url: 'https://example.com/stream.mp4',
      qualityLabel: '1080p',
      codec: 'avc1',
      container: 'mp4',
      sizeInBytes: 80000000,
    );

    late DownloadEngine engine;
    late ProviderContainer container;

    setUp(() {
      engine = DownloadEngine(
        maxConcurrentDownloads: 2,
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

    test('starts with empty tasks list', () {
      final tasks = container.read(downloadManagerProvider);
      expect(tasks, isEmpty);
    });

    test('startDownload creates task and updates state', () async {
      final notifier = container.read(downloadManagerProvider.notifier);
      final task = await notifier.startDownload(
        testMediaInfo,
        testStreamInfo,
        '/tmp/download.mp4',
      );

      final state = container.read(downloadManagerProvider);
      expect(state.length, 1);
      expect(state.first.id, task.id);
      expect(state.first.status, DownloadStatus.downloading);
    });

    test('pauseDownload and resumeDownload update task state', () async {
      final notifier = container.read(downloadManagerProvider.notifier);
      final task = await notifier.startDownload(
        testMediaInfo,
        testStreamInfo,
        '/tmp/download.mp4',
      );

      final paused = await notifier.pauseDownload(task.id);
      expect(paused, isTrue);
      expect(
        container.read(downloadManagerProvider).first.status,
        DownloadStatus.paused,
      );

      final resumed = await notifier.resumeDownload(task.id);
      expect(resumed, isTrue);
      expect(
        container.read(downloadManagerProvider).first.status,
        DownloadStatus.downloading,
      );
    });

    test('cancelDownload updates task state to cancelled', () async {
      final notifier = container.read(downloadManagerProvider.notifier);
      final task = await notifier.startDownload(
        testMediaInfo,
        testStreamInfo,
        '/tmp/download.mp4',
      );

      final cancelled = await notifier.cancelDownload(task.id);
      expect(cancelled, isTrue);
      expect(
        container.read(downloadManagerProvider).first.status,
        DownloadStatus.cancelled,
      );
    });

    test('removeTask removes task from state', () async {
      final notifier = container.read(downloadManagerProvider.notifier);
      final task = await notifier.startDownload(
        testMediaInfo,
        testStreamInfo,
        '/tmp/download.mp4',
      );

      expect(container.read(downloadManagerProvider).length, 1);

      await notifier.removeTask(task.id);

      expect(container.read(downloadManagerProvider), isEmpty);
    });

    test('derived filtered providers group tasks accurately', () {
      final now = DateTime.now();
      final activeTask = DownloadTask(
        id: '1',
        mediaInfo: testMediaInfo,
        selectedStream: testStreamInfo,
        status: DownloadStatus.downloading,
        createdAt: now,
      );
      final queuedTask = DownloadTask(
        id: '2',
        mediaInfo: testMediaInfo,
        selectedStream: testStreamInfo,
        status: DownloadStatus.queued,
        createdAt: now,
      );
      final completedTask = DownloadTask(
        id: '3',
        mediaInfo: testMediaInfo,
        selectedStream: testStreamInfo,
        status: DownloadStatus.completed,
        createdAt: now,
      );
      final failedTask = DownloadTask(
        id: '4',
        mediaInfo: testMediaInfo,
        selectedStream: testStreamInfo,
        status: DownloadStatus.failed,
        createdAt: now,
      );
      final pausedTask = DownloadTask(
        id: '5',
        mediaInfo: testMediaInfo,
        selectedStream: testStreamInfo,
        status: DownloadStatus.paused,
        createdAt: now,
      );

      container.read(downloadManagerProvider.notifier).setTasks([
        activeTask,
        queuedTask,
        completedTask,
        failedTask,
        pausedTask,
      ]);

      expect(container.read(activeDownloadsProvider), [
        activeTask,
        queuedTask,
        failedTask,
        pausedTask,
      ]);
      expect(container.read(activeDownloadsCountProvider), 4);

      expect(container.read(queuedDownloadsProvider), [queuedTask]);
      expect(container.read(queuedDownloadsCountProvider), 1);

      expect(container.read(completedDownloadsProvider), [completedTask]);
      expect(container.read(completedDownloadsCountProvider), 1);

      expect(container.read(failedDownloadsProvider), [failedTask]);
    });

    test('pauseAll and resumeAll batch update all appropriate tasks', () async {
      final notifier = container.read(downloadManagerProvider.notifier);
      await notifier.startDownload(
        testMediaInfo,
        testStreamInfo,
        '/tmp/1.mp4',
      );
      await notifier.startDownload(
        testMediaInfo,
        testStreamInfo,
        '/tmp/2.mp4',
      );

      final initialTasks = container.read(downloadManagerProvider);
      expect(initialTasks.length, 2);
      expect(
        initialTasks.every((t) => t.status == DownloadStatus.downloading),
        isTrue,
      );

      await notifier.pauseAll();

      final pausedTasks = container.read(downloadManagerProvider);
      expect(
        pausedTasks.every((t) => t.status == DownloadStatus.paused),
        isTrue,
      );

      await notifier.resumeAll();

      final resumedTasks = container.read(downloadManagerProvider);
      expect(
        resumedTasks.every((t) => t.status == DownloadStatus.downloading),
        isTrue,
      );
    });

    test('clearCompleted removes only completed tasks', () async {
      final notifier = container.read(downloadManagerProvider.notifier);
      final activeTask = await notifier.startDownload(
        testMediaInfo,
        testStreamInfo,
        '/tmp/1.mp4',
      );
      final task2 = await notifier.startDownload(
        testMediaInfo,
        testStreamInfo,
        '/tmp/2.mp4',
      );
      final completedTask = task2.copyWith(status: DownloadStatus.completed);

      notifier.updateTask(completedTask);

      expect(container.read(downloadManagerProvider).length, 2);

      await notifier.clearCompleted();

      final remaining = container.read(downloadManagerProvider);
      expect(remaining.length, 1);
      expect(remaining.first.id, activeTask.id);
    });

    test(
      'startDownload resolves custom downloadDirectory from settings',
      () async {
        final customSettings = const SettingsState(
          downloadDirectory: '/custom/storage/dir',
        );
        final customContainer = ProviderContainer(
          overrides: [
            downloadEngineProvider.overrideWithValue(engine),
            settingsProvider.overrideWith(
              (ref) => SettingsNotifier()..state = customSettings,
            ),
          ],
        );
        addTearDown(customContainer.dispose);

        final notifier = customContainer.read(downloadManagerProvider.notifier);
        final task = await notifier.startDownload(
          testMediaInfo,
          testStreamInfo,
          '/old/path/video.mp4',
        );

        expect(task.filePath, '/custom/storage/dir/video.mp4');
      },
    );

    test(
      'startDownload throws CellularDownloadBlockedException when downloadOverCellular is false on cellular network',
      () async {
        final wifiOnlySettings = const SettingsState(
          downloadOverCellular: false,
        );
        final cellularEngine = DownloadEngine(
          maxConcurrentDownloads: 2,
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

        final cellularNotifier = DownloadManagerNotifier(
          cellularEngine,
          null,
          wifiOnlySettings,
          null,
          () async => true, // cellular checker reports true (cellular only)
        );

        expect(
          () => cellularNotifier.startDownload(
            testMediaInfo,
            testStreamInfo,
            '/tmp/test.mp4',
          ),
          throwsA(isA<CellularDownloadBlockedException>()),
        );
      },
    );

    test(
      'startDownload proceeds when downloadOverCellular is true on cellular network',
      () async {
        final allowCellularSettings = const SettingsState(
          downloadOverCellular: true,
        );
        final cellularEngine = DownloadEngine(
          maxConcurrentDownloads: 2,
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

        final cellularNotifier = DownloadManagerNotifier(
          cellularEngine,
          null,
          allowCellularSettings,
          null,
          () async => true, // cellular checker reports true
        );

        final task = await cellularNotifier.startDownload(
          testMediaInfo,
          testStreamInfo,
          '/tmp/test.mp4',
        );

        expect(task.status, DownloadStatus.downloading);
      },
    );

    test(
      'updateSettings updates engine maxConcurrentDownloads dynamically',
      () async {
        final notifier = container.read(downloadManagerProvider.notifier);
        expect(engine.maxConcurrentDownloads, 3);

        notifier.updateSettings(
          const SettingsState(maxConcurrentDownloads: 1),
        );
        expect(engine.maxConcurrentDownloads, 1);

        notifier.updateSettings(
          const SettingsState(maxConcurrentDownloads: 5),
        );
        expect(engine.maxConcurrentDownloads, 5);
      },
    );
  });
}
