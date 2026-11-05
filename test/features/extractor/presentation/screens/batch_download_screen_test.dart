import 'package:mediagrab/features/downloads/domain/entities/download_task.dart';
import 'package:mediagrab/features/downloads/domain/enums/download_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mediagrab/features/downloads/data/services/download_engine.dart';
import 'package:mediagrab/features/downloads/presentation/providers/download_manager_provider.dart';
import 'package:mediagrab/features/extractor/data/extractor_factory.dart';
import 'package:mediagrab/features/extractor/presentation/providers/extractor_provider.dart';
import 'package:mediagrab/features/extractor/presentation/providers/batch_preparation_provider.dart';
import 'package:mediagrab/features/extractor/presentation/screens/batch_download_screen.dart';
import 'package:mediagrab/features/settings/presentation/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../batch_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('resume reports Wi-Fi-only restriction instead of throwing', (
    tester,
  ) async {
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
    addTearDown(engine.dispose);
    final container = ProviderContainer(
      overrides: [
        extractorFactoryProvider.overrideWithValue(
          ExtractorFactory(extractors: [BatchTestExtractor()]),
        ),
        downloadEngineProvider.overrideWithValue(engine),
        downloadManagerProvider.overrideWith(
          (ref) => DownloadManagerNotifier(
            engine,
            [],
            const SettingsState(downloadOverCellular: false),
            null,
            () async => true,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BatchDownloadScreen()),
      ),
    );
    final controller = container.read(batchPreparationProvider.notifier);
    controller.edit(0, 'https://youtu.be/video0');
    await controller.check();
    final item = controller.state.items.first;
    controller.attachTask(
      0,
      DownloadTask(
        id: 'paused',
        mediaInfo: item.media!,
        selectedStream: batchVideo,
        status: DownloadStatus.paused,
        createdAt: DateTime.now(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Resume'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Cellular downloading is disabled'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('small screen and keyboard keep the download action reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final container = ProviderContainer(
      overrides: [
        extractorFactoryProvider.overrideWithValue(
          ExtractorFactory(extractors: [BatchTestExtractor()]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BatchDownloadScreen()),
      ),
    );
    final controller = container.read(batchPreparationProvider.notifier);
    controller.paste(
      'https://youtu.be/video0 https://youtube.com/watch?v=video0 not-a-url https://youtu.be/video1',
    );
    await controller.check();
    await tester.pumpAndSettle();
    expect(controller.state.items.length, 3);
    expect(find.text('Check links'), findsNothing);
    final button = find.widgetWithText(FilledButton, 'Download 2 videos');
    expect(tester.getRect(button).bottom, lessThanOrEqualTo(450));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets(
    'single-link preparation, optional quality, narrow layout and in-place downloading',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final extractor = BatchTestExtractor();
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
      addTearDown(engine.dispose);
      final container = ProviderContainer(
        overrides: [
          extractorFactoryProvider.overrideWithValue(
            ExtractorFactory(extractors: [extractor]),
          ),
          downloadEngineProvider.overrideWithValue(engine),
          connectivityProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(settingsProvider.notifier)
          .setDownloadDirectory('/tmp');
      final router = GoRouter(
        initialLocation: '/batch-download',
        routes: [
          GoRoute(
            path: '/batch-download',
            builder: (_, _) => const BatchDownloadScreen(),
          ),
          GoRoute(
            path: '/downloads',
            builder: (_, _) => const Scaffold(body: Text('Active downloads')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Download 0 videos'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byType(TextField).first,
        'https://youtube.com/watch?v=video000000',
      );
      await tester.pump();
      // Typing does not rebuild the text field with a new identity or lose focus.
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        contains('video0'),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('Video video000000'), findsOneWidget);
      expect(find.text('Download 1 video'), findsOneWidget);
      expect(engine.getAllDownloads(), isEmpty);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('1080p'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('1080p'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1080p').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use quality'));
      await tester.pumpAndSettle();
      expect(find.text('1080p · Custom'), findsOneWidget);
      expect(extractor.metadataCalls.length, 1);
      expect(extractor.streamCalls.length, 1);
      expect(engine.getAllDownloads(), isEmpty);
      final download = find.text('Download 1 video');
      await tester.tap(download);
      await tester.tap(download, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Active downloads'), findsNothing);
      expect(router.routeInformationProvider.value.uri.path, '/batch-download');
      expect(
        find.byKey(const ValueKey('batch_progress_summary')),
        findsOneWidget,
      );
      expect(find.text('Pause All'), findsOneWidget);
      expect(engine.getAllDownloads().length, 1);
      expect(find.byTooltip('Default quality'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Add more videos'),
        -150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Add more videos'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byTooltip('Default quality'), findsOneWidget);
      expect(find.byKey(const ValueKey('batch_auto_add')), findsOneWidget);
      expect(container.read(downloadsSelectedTabProvider), 0);
      expect(extractor.metadataCalls.length, 1);
      expect(extractor.streamCalls.length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selection count and batch preference respect individual override',
    (tester) async {
      final extractor = BatchTestExtractor();
      final container = ProviderContainer(
        overrides: [
          extractorFactoryProvider.overrideWithValue(
            ExtractorFactory(extractors: [extractor]),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: BatchDownloadScreen()),
        ),
      );
      final controller = container.read(batchPreparationProvider.notifier);
      controller.paste(
        'https://youtube.com/watch?v=video0 https://youtube.com/watch?v=video1',
      );
      await controller.check();
      await tester.pumpAndSettle();
      expect(find.text('Download 2 videos'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.descendant(
          of: find.byKey(const ValueKey('batch_item_0')),
          matching: find.byType(Checkbox),
        ),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      expect(find.text('Download 1 video'), findsOneWidget);
      controller.choose(0, batchVideo, null);
      controller.setQuality('Audio');
      await tester.pump();
      expect(find.text('720p · Custom'), findsOneWidget);
      expect(controller.state.items.last.selected, batchAudio);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    },
  );
}
