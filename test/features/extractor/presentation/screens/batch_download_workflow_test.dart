import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediagrab/core/theme/app_theme.dart';
import 'package:mediagrab/features/downloads/data/services/download_engine.dart';
import 'package:mediagrab/features/downloads/data/services/download_registry.dart';
import 'package:mediagrab/features/downloads/domain/enums/download_status.dart';
import 'package:mediagrab/features/downloads/presentation/providers/download_manager_provider.dart';
import 'package:mediagrab/features/extractor/data/extractor_factory.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';
import 'package:mediagrab/features/extractor/presentation/providers/batch_preparation_provider.dart';
import 'package:mediagrab/features/extractor/presentation/providers/extractor_provider.dart';
import 'package:mediagrab/features/extractor/presentation/screens/batch_download_screen.dart';
import '../../batch_test_support.dart';
import 'package:mediagrab/features/settings/presentation/providers/settings_provider.dart';

const _stream = StreamInfo(
  url: 'https://cdn.example/video',
  qualityLabel: '360p',
  codec: 'h264',
  container: 'mp4',
  sizeInBytes: 1000,
  videoHeight: 360,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final width in [360.0, 393.0]) {
    testWidgets(
      'batch engine events, scoped controls and verified cleanup at ${width}dp',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final directory =
            (await tester.runAsync(
              () => Directory.systemTemp.createTemp('batch-flow'),
            ))!;
        addTearDown(() => directory.deleteSync(recursive: true));
        final progress = <String, void Function(double, int, int, double)>{};
        final complete = <String, Future<void> Function()>{};
        final registry = DownloadRegistry();
        final engine = DownloadEngine(
          maxConcurrentDownloads: 3,
          downloadRegistry: registry,
          customDownloadExecution: ({
            required task,
            required stream,
            required targetPath,
            required onProgress,
            required onComplete,
            required onError,
          }) async {
            progress[task.id] = onProgress;
            complete[task.id] = onComplete;
          },
        );
        addTearDown(engine.dispose);
        final extractor = BatchTestExtractor()..streams = [_stream];
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
            .setDownloadDirectory(directory.path);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.dark(),
              home: const BatchDownloadScreen(),
            ),
          ),
        );
        final controller = container.read(batchPreparationProvider.notifier);
        controller.paste(
          'https://youtube.com/watch?v=video000000,https://youtube.com/watch?v=video111111',
        );
        await controller.check();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Download 2 videos'));

        await tester.pumpAndSettle();

        expect(find.byType(BatchDownloadScreen), findsOneWidget);
        expect(find.text('Pause All'), findsOneWidget);
        final tasks = engine.getAllDownloads();
        expect(tasks, hasLength(2));
        final heading = tester.widget(find.text('Videos (2)'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 220)),
        );
        progress[tasks.first.id]!(.25, 250, 1000, 512);
        await tester.pump();
        await tester.scrollUntilVisible(
          find.textContaining('25.0%'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('25.0%'), findsOneWidget);
        expect(
          identical(heading, tester.widget(find.text('Videos (2)'))),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        final outside = await engine.startDownload(
          tasks.first.mediaInfo,
          _stream,
          '${directory.path}/outside.mp4',
        );
        await tester.tap(find.text('Pause All'));
        await tester.pumpAndSettle();
        expect(
          engine.getTask(outside.id)!.status,
          isNot(DownloadStatus.paused),
        );
        expect(engine.getTask(tasks.first.id)!.status, DownloadStatus.paused);
        expect(find.text('Resume All'), findsOneWidget);
        await tester.tap(find.text('Resume All'));
        await tester.pumpAndSettle();
        expect(
          engine.getTask(tasks.first.id)!.status,
          DownloadStatus.downloading,
        );
        // Transfer reaches 100% before finalization; the item must remain visible.
        progress[tasks.first.id]!(1, 1000, 1000, 0);
        await tester.pump();
        expect(
          controller.state.items.where((i) => i.taskId == tasks.first.id),
          hasLength(1),
        );
        await tester.runAsync(
          () => File(tasks.first.filePath!).writeAsBytes(List.filled(1000, 1)),
        );
        var finalized = false;
        unawaited(complete[tasks.first.id]!().then((_) => finalized = true));
        for (var attempt = 0; attempt < 10; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(finalized, isTrue);
        await tester.pumpAndSettle();
        expect(
          controller.state.items.where((i) => i.taskId == tasks.first.id),
          isEmpty,
        );
        expect(
          await tester.runAsync(() => File(tasks.first.filePath!).exists()),
          isTrue,
        );
        expect(
          container.read(completedDownloadsProvider).map((t) => t.id),
          contains(tasks.first.id),
        );
        expect(
          (await tester.runAsync(
            () => registry.getCompletedRecords(),
          ))!.map((r) => r.id),
          contains(tasks.first.id),
        );
        await tester.tap(find.text('Cancel All'));
        await tester.pumpAndSettle();
        expect(
          engine.getTask(tasks.last.id)!.status,
          isNot(DownloadStatus.cancelled),
        );
        await tester.tap(find.text('Cancel all'));
        await tester.pumpAndSettle();
        expect(engine.getTask(tasks.last.id)!.status, DownloadStatus.cancelled);
        // Failed entries can be dismissed from this batch without deleting the
        // saved file or touching another job or the Downloads history.
        engine.updateTaskDirectly(
          engine
              .getTask(tasks.last.id)!
              .copyWith(
                status: DownloadStatus.failed,
                errorMessage: 'Network unavailable.',
              ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Remove'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Retry'), findsOneWidget);
        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();
        expect(
          controller.state.items.where((i) => i.taskId == tasks.last.id),
          isEmpty,
        );
        await tester.pump(const Duration(seconds: 5));
        expect(engine.getTask(tasks.last.id)!.status, DownloadStatus.failed);
        expect(
          await tester.runAsync(() => File(tasks.first.filePath!).exists()),
          isTrue,
        );

        expect(
          engine.getTask(outside.id)!.status,
          isNot(DownloadStatus.cancelled),
        );
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(milliseconds: 300));
      },
    );
  }
}
