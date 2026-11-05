import 'package:mediagrab/features/extractor/presentation/providers/extractor_provider.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';
import 'package:mediagrab/features/extractor/data/extractor_factory.dart';
import 'package:mediagrab/features/extractor/data/extractors/base_extractor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/downloads/data/services/download_engine.dart';
import 'package:mediagrab/features/downloads/presentation/providers/download_manager_provider.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/playlist_info.dart';
import 'package:mediagrab/features/extractor/presentation/widgets/playlist_selector_sheet.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            return '/mock/app/docs';
          },
        );
  });

  final sampleVideo1 = MediaInfo(
    id: 'vid1',
    title: 'First Playlist Video',
    thumbnailUrl: 'https://img.youtube.com/vi/vid1/hqdefault.jpg',
    duration: const Duration(minutes: 3, seconds: 15),
    uploader: 'Cool Creator',
    platform: PlatformType.youtube,
  );

  final sampleVideo2 = MediaInfo(
    id: 'vid2',
    title: 'Second Playlist Video',
    thumbnailUrl: 'https://img.youtube.com/vi/vid2/hqdefault.jpg',
    duration: const Duration(minutes: 4, seconds: 45),
    uploader: 'Cool Creator',
    platform: PlatformType.youtube,
  );

  final sampleVideo3 = MediaInfo(
    id: 'vid3',
    title: 'Third Playlist Video',
    thumbnailUrl: 'https://img.youtube.com/vi/vid3/hqdefault.jpg',
    duration: const Duration(minutes: 1, seconds: 20),
    uploader: 'Cool Creator',
    platform: PlatformType.youtube,
  );

  final samplePlaylist = PlaylistInfo(
    id: 'playlist123',
    title: 'Awesome Album Tracks',
    author: 'Cool Creator',
    videoCount: 3,
    videos: [sampleVideo1, sampleVideo2, sampleVideo3],
  );

  Widget buildPlaylistSheetWidget({
    PlaylistInfo? playlist,
    void Function(List<MediaInfo>)? onDownloadBatch,
    ProviderContainer? container,
  }) {
    final sheet = PlaylistSelectorSheet(
      playlist: playlist ?? samplePlaylist,
      onDownloadBatch: onDownloadBatch,
    );

    if (container != null) {
      return UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: sheet)),
      );
    }

    return ProviderScope(
      overrides: [
        downloadEngineProvider.overrideWith(
          (ref) => DownloadEngine(
            customDownloadExecution:
                ({
                  required task,
                  required stream,
                  required targetPath,
                  required onProgress,
                  required onComplete,
                  required onError,
                }) async {},
          ),
        ),
      ],
      child: MaterialApp(home: Scaffold(body: sheet)),
    );
  }

  testWidgets(
    'PlaylistSelectorSheet displays header info, items, and pre-selects all items',
    (tester) async {
      await tester.pumpWidget(buildPlaylistSheetWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify playlist title and metadata
      expect(find.text('Awesome Album Tracks'), findsOneWidget);
      expect(find.textContaining('Cool Creator • 3 videos'), findsOneWidget);
      expect(find.text('Select All'), findsOneWidget);
      expect(find.text('3 / 3 selected'), findsOneWidget);

      // Verify individual video titles and index tags
      expect(find.text('First Playlist Video'), findsOneWidget);
      expect(find.text('Second Playlist Video'), findsOneWidget);
      expect(find.text('Third Playlist Video'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('#3'), findsOneWidget);

      // Verify duration badges
      expect(find.text('3:15'), findsOneWidget);
      expect(find.text('4:45'), findsOneWidget);
      expect(find.text('1:20'), findsOneWidget);

      // Verify bottom button has all 3 selected
      expect(
        find.widgetWithText(FilledButton, 'Download Selected (3 videos)'),
        findsOneWidget,
      );
    },
  );

  testWidgets('toggling individual checkboxes updates count and button label', (
    tester,
  ) async {
    await tester.pumpWidget(buildPlaylistSheetWidget());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Deselect the first video by tapping its title row
    await tester.tap(find.text('First Playlist Video'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('2 / 3 selected'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Download Selected (2 videos)'),
      findsOneWidget,
    );

    // Deselect the second video
    await tester.tap(find.text('Second Playlist Video'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('1 / 3 selected'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Download Selected (1 video)'),
      findsOneWidget,
    );

    // Deselect the third video
    await tester.tap(find.text('Third Playlist Video'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('0 / 3 selected'), findsOneWidget);
    final downloadBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Download Selected (0 videos)'),
    );
    // Button must be disabled when 0 items selected
    expect(downloadBtn.onPressed, isNull);

    // Re-select second video
    await tester.tap(find.text('Second Playlist Video'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('1 / 3 selected'), findsOneWidget);
    final enabledBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Download Selected (1 video)'),
    );
    expect(enabledBtn.onPressed, isNotNull);
  });

  testWidgets(
    'Select All toggle toggles all items off when all are selected, and on when some/none are selected',
    (tester) async {
      await tester.pumpWidget(buildPlaylistSheetWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Initially all 3 are selected -> tapping Select All should deselect all
      await tester.tap(find.text('Select All'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('0 / 3 selected'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Download Selected (0 videos)'),
        findsOneWidget,
      );

      // Tapping Select All again should select all 3
      await tester.tap(find.text('Select All'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('3 / 3 selected'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Download Selected (3 videos)'),
        findsOneWidget,
      );

      // Deselect one item -> 2 / 3 selected -> tapping Select All should select all
      await tester.tap(find.text('First Playlist Video'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('2 / 3 selected'), findsOneWidget);

      await tester.tap(find.text('Select All'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('3 / 3 selected'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping Download Selected invokes onDownloadBatch with selected media',
    (tester) async {
      List<MediaInfo>? batchResult;

      await tester.pumpWidget(
        buildPlaylistSheetWidget(
          onDownloadBatch: (selected) {
            batchResult = selected;
          },
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Deselect video 2
      await tester.tap(find.text('Second Playlist Video'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap download button
      await tester.tap(
        find.widgetWithText(FilledButton, 'Download Selected (2 videos)'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(batchResult, isNotNull);
      expect(batchResult!.length, 2);
      expect(batchResult![0].id, 'vid1');
      expect(batchResult![1].id, 'vid3');
    },
  );

  for (final allFail in [false, true]) {
    testWidgets(
      'playlist reports ${allFail ? 'zero' : 'partial'} queued items',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            extractorFactoryProvider.overrideWithValue(
              ExtractorFactory(
                extractors: [
                  _BatchExtractor(
                    allFail ? {'vid1', 'vid2', 'vid3'} : {'vid2', 'vid3'},
                  ),
                ],
              ),
            ),
            downloadEngineProvider.overrideWith(
              (ref) => DownloadEngine(
                customDownloadExecution:
                    ({
                      required task,
                      required stream,
                      required targetPath,
                      required onProgress,
                      required onComplete,
                      required onError,
                    }) async {},
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder:
                      (context) => TextButton(
                        onPressed:
                            () => PlaylistSelectorSheet.show(
                              context,
                              playlist: samplePlaylist,
                            ),
                        child: const Text('Open playlist'),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open playlist'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(
          find.widgetWithText(FilledButton, 'Download Selected (3 videos)'),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(container.read(downloadManagerProvider).length, allFail ? 0 : 1);
        if (allFail) {
          expect(
            find.textContaining('No downloads could be queued.'),
            findsOneWidget,
          );
          expect(find.byType(PlaylistSelectorSheet), findsOneWidget);
        } else {
          expect(find.text('Queued 1 of 3 videos'), findsOneWidget);
          expect(find.byType(PlaylistSelectorSheet), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Download Selected enqueues items into downloadManagerProvider when no callback is provided',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          extractorFactoryProvider.overrideWithValue(
            ExtractorFactory(extractors: [_BatchExtractor()]),
          ),
          downloadEngineProvider.overrideWith(
            (ref) => DownloadEngine(
              customDownloadExecution:
                  ({
                    required task,
                    required stream,
                    required targetPath,
                    required onProgress,
                    required onComplete,
                    required onError,
                  }) async {},
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildPlaylistSheetWidget(container: container));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap download selected (3 videos)
      await tester.tap(
        find.widgetWithText(FilledButton, 'Download Selected (3 videos)'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify tasks enqueued in downloadManagerProvider
      final tasks = container.read(downloadManagerProvider);
      expect(tasks.length, 3);
      expect(tasks[0].mediaInfo.title, 'First Playlist Video');
      expect(tasks[1].mediaInfo.title, 'Second Playlist Video');
      expect(tasks[2].mediaInfo.title, 'Third Playlist Video');
    },
  );
}

// Playlist enqueue must resolve actual downloadable streams, not page URLs.
class _BatchExtractor extends BaseExtractor {
  final Set<String> failedIds;
  _BatchExtractor([this.failedIds = const {}]);
  @override
  bool canHandle(String url) => true;
  @override
  Future<MediaInfo> extractInfo(String url) => throw UnimplementedError();
  @override
  Future<List<StreamInfo>> getStreams(String url) async {
    if (failedIds.any(url.contains)) throw StateError('Network unavailable');
    return const [
      StreamInfo(
        url: 'https://cdn.example/video.mp4',
        qualityLabel: '720p',
        container: 'mp4',
        codec: 'h264',
        videoHeight: 720,
      ),
    ];
  }
}
