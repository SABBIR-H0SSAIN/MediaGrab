import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/downloads/data/services/download_engine.dart';
import 'package:mediagrab/features/downloads/domain/entities/download_task.dart';
import 'package:mediagrab/features/downloads/domain/enums/download_status.dart';
import 'package:mediagrab/features/downloads/presentation/providers/download_manager_provider.dart';
import 'package:mediagrab/features/downloads/presentation/widgets/download_tile.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';

void main() {
  group('DownloadTile Widget', () {
    const testMediaInfo = MediaInfo(
      id: 'abc12345678',
      title: 'Amazing Landscape 4K',
      thumbnailUrl: '', // empty to use fallback container in test
      duration: Duration(minutes: 4),
      uploader: 'Nature Channel',
      platform: PlatformType.youtube,
    );

    const testStreamInfo = StreamInfo(
      url: 'https://example.com/video.mp4',
      qualityLabel: '1080p',
      codec: 'avc1',
      container: 'mp4',
      sizeInBytes: 104857600, // 100 MB
    );

    final now = DateTime.now();

    testWidgets(
      'renders active downloading state with progress bar and speed/ETA',
      (tester) async {
        DownloadTask? pausedTask;
        DownloadTask? cancelledTask;

        final activeTask = DownloadTask(
          id: 'task-1',
          mediaInfo: testMediaInfo,
          selectedStream: testStreamInfo,
          status: DownloadStatus.downloading,
          progress: 0.5,
          downloadedBytes: 52428800,
          totalBytes: 104857600,
          speedBytesPerSecond: 2 * 1024 * 1024, // 2.0 MB/s
          createdAt: now,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DownloadTile(
                task: activeTask,
                animate: false,
                onPause: (t) => pausedTask = t,
                onCancel: (t) => cancelledTask = t,
              ),
            ),
          ),
        );

        expect(find.text('Amazing Landscape 4K'), findsOneWidget);
        expect(find.textContaining('1080p'), findsOneWidget);
        expect(find.textContaining('2.0 MB/s'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
        expect(find.byIcon(Icons.close_rounded), findsOneWidget);

        // Tap pause
        await tester.tap(find.byIcon(Icons.pause_rounded));
        expect(pausedTask?.id, 'task-1');

        // Tap cancel
        await tester.tap(find.byIcon(Icons.close_rounded));
        expect(cancelledTask?.id, 'task-1');
      },
    );

    testWidgets('renders paused state with play/resume button', (tester) async {
      DownloadTask? resumedTask;

      final pausedTask = DownloadTask(
        id: 'task-2',
        mediaInfo: testMediaInfo,
        selectedStream: testStreamInfo,
        status: DownloadStatus.paused,
        progress: 0.35,
        createdAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DownloadTile(
              task: pausedTask,
              animate: false,
              onResume: (t) => resumedTask = t,
            ),
          ),
        ),
      );

      expect(find.textContaining('Paused'), findsWidgets);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      expect(resumedTask?.id, 'task-2');
    });

    testWidgets('renders queued state with Queued chip and cancel button', (
      tester,
    ) async {
      final queuedTask = DownloadTask(
        id: 'task-3',
        mediaInfo: testMediaInfo,
        selectedStream: testStreamInfo,
        status: DownloadStatus.queued,
        createdAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DownloadTile(task: queuedTask, animate: false)),
        ),
      );

      expect(find.text('Queued'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets(
      'completed card opens on tap and keeps secondary actions in its menu',
      (tester) async {
        DownloadTask? openedTask;
        DownloadTask? sharedTask;
        DownloadTask? deletedTask;

        final completedTask = DownloadTask(
          id: 'task-4',
          mediaInfo: testMediaInfo,
          selectedStream: testStreamInfo,
          status: DownloadStatus.completed,
          progress: 1.0,
          createdAt: now,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DownloadTile(
                task: completedTask,
                animate: false,
                onOpen: (t) => openedTask = t,
                onShare: (t) => sharedTask = t,
                onDelete: (t) => deletedTask = t,
              ),
            ),
          ),
        );

        // Header and metadata
        expect(find.text('Amazing Landscape 4K'), findsOneWidget);
        expect(find.textContaining('1080p • MP4'), findsOneWidget);
        expect(find.textContaining('100 MB'), findsOneWidget);
        // Verify NO duplicate container chip
        expect(find.text('MP4'), findsNothing);

        expect(find.text('Completed'), findsNothing);
        expect(find.byTooltip('Play'), findsNothing);
        expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
        expect(find.text('4:00'), findsOneWidget);
        await tester.tap(find.text('Amazing Landscape 4K'));
        expect(openedTask?.id, 'task-4');
        await tester.tap(find.byIcon(Icons.more_vert_rounded));
        await tester.pumpAndSettle();
        expect(find.text('Open with'), findsOneWidget);
        await tester.tap(find.text('Share'));
        await tester.pumpAndSettle();
        expect(sharedTask?.id, 'task-4');
        await tester.tap(find.byIcon(Icons.more_vert_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        expect(deletedTask?.id, 'task-4');
      },
    );

    testWidgets('omits redundant completion labels from the completed list', (
      tester,
    ) async {
      final completedTaskWithTime = DownloadTask(
        id: 'task-4-time',
        mediaInfo: testMediaInfo,
        selectedStream: testStreamInfo,
        status: DownloadStatus.completed,
        progress: 1.0,
        createdAt: now.subtract(const Duration(hours: 1)),
        completedAt: now.subtract(const Duration(minutes: 30)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DownloadTile(task: completedTaskWithTime, animate: false),
          ),
        ),
      );

      expect(find.textContaining('Completed'), findsNothing);
      expect(find.textContaining('1080p • MP4'), findsOneWidget);
      expect(find.textContaining('100 MB'), findsOneWidget);
      expect(find.text('MP4'), findsNothing);
    });

    testWidgets('tapping completed card inkwell triggers onOpen callback', (
      tester,
    ) async {
      DownloadTask? openedTask;

      final completedTask = DownloadTask(
        id: 'task-tap-card',
        mediaInfo: testMediaInfo,
        selectedStream: testStreamInfo,
        status: DownloadStatus.completed,
        progress: 1.0,
        createdAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DownloadTile(
              task: completedTask,
              animate: false,
              onOpen: (t) => openedTask = t,
            ),
          ),
        ),
      );

      // Tap the title text on the card
      await tester.tap(find.text('Amazing Landscape 4K'));
      expect(openedTask?.id, 'task-tap-card');
    });

    testWidgets('renders failed state with error tooltip and retry button', (
      tester,
    ) async {
      DownloadTask? retriedTask;

      final failedTask = DownloadTask(
        id: 'task-5',
        mediaInfo: testMediaInfo,
        selectedStream: testStreamInfo,
        status: DownloadStatus.failed,
        errorMessage: 'Connection timeout',
        createdAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DownloadTile(
              task: failedTask,
              animate: false,
              onRetry: (t) => retriedTask = t,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      expect(find.textContaining('Connection timeout'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.refresh_rounded));
      expect(retriedTask?.id, 'task-5');
    });

    testWidgets(
      'consumes downloadProgressProvider to update progress and speed reactively',
      (tester) async {
        final engine = DownloadEngine(
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

        final initialTask = DownloadTask(
          id: 'reactive-task-1',
          mediaInfo: testMediaInfo,
          selectedStream: testStreamInfo,
          status: DownloadStatus.downloading,
          progress: 0.1,
          downloadedBytes: 10485760,
          totalBytes: 104857600,
          speedBytesPerSecond: 1024 * 1024,
          createdAt: now,
        );

        late DownloadManagerNotifier notifier;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              downloadEngineProvider.overrideWithValue(engine),
              downloadManagerProvider.overrideWith((ref) {
                notifier = DownloadManagerNotifier(engine);
                notifier.setTasks([initialTask]);
                return notifier;
              }),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: DownloadTile(task: initialTask, animate: false),
              ),
            ),
          ),
        );

        // Verify initial progress
        var progressFinder = find.byType(LinearProgressIndicator);
        expect(progressFinder, findsOneWidget);
        var indicator = tester.widget<LinearProgressIndicator>(progressFinder);
        expect(indicator.value, closeTo(0.1, 0.01));
        expect(find.textContaining('1.0 MB/s'), findsOneWidget);

        // Update task progress via notifier
        final updatedTask = initialTask.copyWith(
          progress: 0.75,
          downloadedBytes: 78643200,
          speedBytesPerSecond: 4.5 * 1024 * 1024,
        );
        notifier.updateTask(updatedTask);
        await tester.pump();

        // Verify updated progress without rebuilding the whole tile
        indicator = tester.widget<LinearProgressIndicator>(progressFinder);
        expect(indicator.value, closeTo(0.75, 0.01));
        expect(find.textContaining('4.5 MB/s'), findsOneWidget);
        expect(find.textContaining('75.0%'), findsOneWidget);

        engine.dispose();
      },
    );
  });
}
