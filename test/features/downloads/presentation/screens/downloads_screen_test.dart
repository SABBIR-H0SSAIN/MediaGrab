import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/downloads/data/services/download_engine.dart';
import 'package:mediagrab/features/downloads/domain/entities/download_task.dart';
import 'package:mediagrab/features/downloads/domain/enums/download_status.dart';
import 'package:mediagrab/features/downloads/presentation/providers/download_manager_provider.dart';
import 'package:mediagrab/features/downloads/presentation/screens/downloads_screen.dart';
import 'package:mediagrab/features/downloads/presentation/widgets/download_tile.dart';
import 'package:mediagrab/features/downloads/presentation/widgets/empty_downloads_view.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';

void main() {
  group('DownloadsScreen', () {
    const testMediaInfo = MediaInfo(
      id: 'abc12345678',
      title: 'Advanced Flutter Architecture',
      thumbnailUrl: '',
      duration: Duration(minutes: 15),
      uploader: 'Flutter Ninja',
      platform: PlatformType.youtube,
    );

    const testMediaInfo2 = MediaInfo(
      id: 'xyz98765432',
      title: 'Queued Video 2',
      thumbnailUrl: '',
      duration: Duration(minutes: 8),
      uploader: 'Flutter Ninja',
      platform: PlatformType.youtube,
    );

    const testStreamInfo = StreamInfo(
      url: 'https://example.com/video.mp4',
      qualityLabel: '1080p',
      codec: 'avc1',
      container: 'mp4',
      sizeInBytes: 150000000,
    );

    late DownloadEngine engine;

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
    });

    tearDown(() {
      engine.dispose();
    });

    testWidgets('renders AppBar and 2 tabs (Active and Completed)', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [downloadEngineProvider.overrideWithValue(engine)],
          child: const MaterialApp(home: DownloadsScreen()),
        ),
      );

      expect(find.text('Downloads'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);

      // Verify empty view is displayed when no tasks
      expect(find.byType(EmptyDownloadsView), findsOneWidget);
      expect(find.text('No active downloads'), findsOneWidget);
    });

    testWidgets(
      'displays active and queued tasks in Active tab with badge count',
      (tester) async {
        final activeTask = DownloadTask(
          id: 'task-active-1',
          mediaInfo: testMediaInfo,
          selectedStream: testStreamInfo,
          status: DownloadStatus.downloading,
          progress: 0.4,
          createdAt: DateTime.now(),
        );

        final queuedTask = DownloadTask(
          id: 'task-queued-1',
          mediaInfo: testMediaInfo2,
          selectedStream: testStreamInfo,
          status: DownloadStatus.queued,
          createdAt: DateTime.now(),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              downloadEngineProvider.overrideWithValue(engine),
              downloadManagerProvider.overrideWith((ref) {
                final notifier = DownloadManagerNotifier(engine);
                notifier.setTasks([activeTask, queuedTask]);
                return notifier;
              }),
            ],
            child: const MaterialApp(home: DownloadsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(DownloadTile), findsNWidgets(2));
        expect(find.text('Advanced Flutter Architecture'), findsOneWidget);
        expect(find.text('Queued Video 2'), findsOneWidget);
        expect(find.text('2'), findsWidgets); // Active badge count
        expect(find.byType(EmptyDownloadsView), findsNothing);
      },
    );

    testWidgets('switches to Completed tab and displays completed tasks', (
      tester,
    ) async {
      final completedTask = DownloadTask(
        id: 'task-comp-1',
        mediaInfo: testMediaInfo,
        selectedStream: testStreamInfo,
        status: DownloadStatus.completed,
        progress: 1.0,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            downloadEngineProvider.overrideWithValue(engine),
            downloadManagerProvider.overrideWith((ref) {
              final notifier = DownloadManagerNotifier(engine);
              notifier.setTasks([completedTask]);
              return notifier;
            }),
          ],
          child: const MaterialApp(home: DownloadsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Active tab is empty
      expect(find.byType(EmptyDownloadsView), findsOneWidget);

      // Tap Completed tab
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();

      expect(find.byType(DownloadTile), findsOneWidget);
      expect(find.byTooltip('Play'), findsNothing);
      expect(find.text('1'), findsNothing);
      expect(
        find.descendant(
          of: find.widgetWithText(Tab, 'Completed'),
          matching: find.byType(Badge),
        ),
        findsNothing,
      );
    });

    testWidgets(
      'displays paused download in Active tab and triggers resume when tapped',
      (tester) async {
        final pausedTask = DownloadTask(
          id: 'task-paused-1',
          mediaInfo: testMediaInfo,
          selectedStream: testStreamInfo,
          status: DownloadStatus.paused,
          progress: 0.45,
          createdAt: DateTime.now(),
        );

        engine.updateTaskDirectly(pausedTask);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              downloadEngineProvider.overrideWithValue(engine),
              downloadManagerProvider.overrideWith((ref) {
                final notifier = DownloadManagerNotifier(engine);
                notifier.setTasks([pausedTask]);
                return notifier;
              }),
            ],
            child: const MaterialApp(home: DownloadsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Paused task must be visible in the initial "Active" tab
        expect(find.byType(DownloadTile), findsOneWidget);
        expect(find.byType(EmptyDownloadsView), findsNothing);
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

        // Tap Resume button
        await tester.tap(find.byIcon(Icons.play_arrow_rounded));
        await tester.pumpAndSettle();

        expect(
          engine.getTask('task-paused-1')?.status,
          DownloadStatus.downloading,
        );
      },
    );

    testWidgets(
      'displays failed download in Active tab and triggers retry when tapped',
      (tester) async {
        final failedTask = DownloadTask(
          id: 'task-failed-1',
          mediaInfo: testMediaInfo,
          selectedStream: testStreamInfo,
          status: DownloadStatus.failed,
          errorMessage: 'Server disconnected',
          createdAt: DateTime.now(),
        );

        engine.updateTaskDirectly(failedTask);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              downloadEngineProvider.overrideWithValue(engine),
              downloadManagerProvider.overrideWith((ref) {
                final notifier = DownloadManagerNotifier(engine);
                notifier.setTasks([failedTask]);
                return notifier;
              }),
            ],
            child: const MaterialApp(home: DownloadsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Failed task must be visible in the initial "Active" tab
        expect(find.byType(DownloadTile), findsOneWidget);
        expect(find.byType(EmptyDownloadsView), findsNothing);
        expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
        expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

        // Tap Retry button
        await tester.tap(find.byIcon(Icons.refresh_rounded));
        await tester.pumpAndSettle();

        expect(
          engine.getTask('task-failed-1')?.status,
          DownloadStatus.downloading,
        );
      },
    );

    testWidgets('triggers Pause All and Resume All actions', (tester) async {
      final activeTask = DownloadTask(
        id: 'task-act-1',
        mediaInfo: testMediaInfo,
        selectedStream: testStreamInfo,
        status: DownloadStatus.downloading,
        createdAt: DateTime.now(),
      );

      engine.updateTaskDirectly(activeTask);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            downloadEngineProvider.overrideWithValue(engine),
            downloadManagerProvider.overrideWith((ref) {
              final notifier = DownloadManagerNotifier(engine);
              notifier.setTasks([activeTask]);
              return notifier;
            }),
          ],
          child: const MaterialApp(home: DownloadsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Pause All button is visible in header/AppBar
      expect(find.text('Pause All'), findsWidgets);
      await tester.tap(find.text('Pause All').first);
      await tester.pumpAndSettle();

      expect(engine.getTask('task-act-1')?.status, DownloadStatus.paused);

      // Now Resume All button is visible
      expect(find.text('Resume All'), findsWidgets);
      await tester.tap(find.text('Resume All').first);
      await tester.pumpAndSettle();

      expect(engine.getTask('task-act-1')?.status, DownloadStatus.downloading);
    });

    testWidgets(
      'triggers Clear All with confirmation dialog on Completed tab',
      (tester) async {
        final completedTask = DownloadTask(
          id: 'task-comp-2',
          mediaInfo: testMediaInfo,
          selectedStream: testStreamInfo,
          status: DownloadStatus.completed,
          progress: 1.0,
          createdAt: DateTime.now(),
        );

        engine.updateTaskDirectly(completedTask);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              downloadEngineProvider.overrideWithValue(engine),
              downloadManagerProvider.overrideWith((ref) {
                final notifier = DownloadManagerNotifier(engine);
                notifier.setTasks([completedTask]);
                return notifier;
              }),
            ],
            child: const MaterialApp(home: DownloadsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Switch to Completed tab
        await tester.tap(find.text('Completed'));
        await tester.pumpAndSettle();

        expect(find.text('Clear All'), findsWidgets);

        // Tap Clear All
        await tester.tap(find.text('Clear All').first);
        await tester.pumpAndSettle();

        // Confirmation dialog appears
        expect(find.text('Clear Completed Downloads'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);

        // Confirm clearing
        await tester.tap(find.widgetWithText(FilledButton, 'Clear All'));
        await tester.pumpAndSettle();

        expect(engine.getTask('task-comp-2'), isNull);
        expect(find.byType(EmptyDownloadsView), findsOneWidget);
      },
    );

    testWidgets('shows snackbar when openMediaFile fails', (tester) async {
      final completedTask = DownloadTask(
        id: 'task-open-1',
        mediaInfo: testMediaInfo,
        selectedStream: testStreamInfo,
        status: DownloadStatus.completed,
        filePath: '/non/existent/path/video.mp4',
        progress: 1.0,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            downloadEngineProvider.overrideWithValue(engine),
            downloadManagerProvider.overrideWith((ref) {
              final notifier = DownloadManagerNotifier(engine);
              notifier.setTasks([completedTask]);
              return notifier;
            }),
          ],
          child: const MaterialApp(home: DownloadsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Completed tab
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(DownloadTile),
          matching: find.byIcon(Icons.more_vert_rounded),
        ),
      );
      await tester.pumpAndSettle();
      // External playback is explicitly selected from the menu.
      await tester.tap(find.text('Open with'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      // Verify SnackBar appears
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.textContaining('Could not open file: File not found'),
        findsOneWidget,
      );
    });

    testWidgets('filters downloads in real time via search action', (
      tester,
    ) async {
      final task1 = DownloadTask(
        id: 'task-search-1',
        mediaInfo: const MediaInfo(
          id: 'vid1',
          title: 'Flutter Clean Architecture',
          thumbnailUrl: 'https://example.com/thumb1.jpg',
          platform: PlatformType.youtube,
          duration: Duration(minutes: 10),
          uploader: 'Flutter Dev',
        ),
        selectedStream: testStreamInfo,
        status: DownloadStatus.downloading,
        progress: 0.5,
        createdAt: DateTime.now(),
      );

      final task2 = DownloadTask(
        id: 'task-search-2',
        mediaInfo: const MediaInfo(
          id: 'vid2',
          title: 'Dart 3 Patterns',
          thumbnailUrl: 'https://example.com/thumb2.jpg',
          platform: PlatformType.youtube,
          duration: Duration(minutes: 5),
          uploader: 'Dart Team',
        ),
        selectedStream: testStreamInfo,
        status: DownloadStatus.downloading,
        progress: 0.3,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            downloadEngineProvider.overrideWithValue(engine),
            downloadManagerProvider.overrideWith((ref) {
              final notifier = DownloadManagerNotifier(engine);
              notifier.setTasks([task1, task2]);
              return notifier;
            }),
          ],
          child: const MaterialApp(home: DownloadsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Flutter Clean Architecture'), findsOneWidget);
      expect(find.text('Dart 3 Patterns'), findsOneWidget);

      // Tap search icon
      await tester.tap(find.byKey(const ValueKey('downloads_search_action')));
      await tester.pumpAndSettle();

      // Enter search query
      await tester.enterText(find.byType(TextField), 'Clean');
      await tester.pumpAndSettle();

      expect(find.text('Flutter Clean Architecture'), findsOneWidget);
      expect(find.text('Dart 3 Patterns'), findsNothing);
    });

    testWidgets('DownloadsScreen respects initialTab: completed', (
      tester,
    ) async {
      final completedTask = DownloadTask(
        id: 'c1',
        mediaInfo: testMediaInfo,
        selectedStream: testStreamInfo,
        status: DownloadStatus.completed,
        progress: 1.0,
        createdAt: DateTime.now(),
        completedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            downloadEngineProvider.overrideWithValue(engine),
            downloadManagerProvider.overrideWith((ref) {
              final notifier = DownloadManagerNotifier(engine);
              notifier.setTasks([completedTask]);
              return notifier;
            }),
          ],
          child: const MaterialApp(
            home: DownloadsScreen(initialTab: 'completed'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Clear All'), findsOneWidget);
    });

    testWidgets(
      'DownloadsScreen updates tab when downloadsSelectedTabProvider changes',
      (tester) async {
        late WidgetRef refHolder;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [downloadEngineProvider.overrideWithValue(engine)],
            child: Consumer(
              builder: (context, ref, _) {
                refHolder = ref;
                return const MaterialApp(home: DownloadsScreen());
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Switch provider to 1 (Completed tab)
        refHolder.read(downloadsSelectedTabProvider.notifier).state = 1;
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('tab_completed_downloads')),
          findsOneWidget,
        );
      },
    );
  });
}
