import 'package:mediagrab/features/extractor/data/extractor_factory.dart';
import 'package:mediagrab/features/extractor/data/extractors/base_extractor.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/downloads/data/services/download_engine.dart';
import 'package:mediagrab/features/downloads/presentation/providers/download_manager_provider.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/playlist_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';
import 'package:mediagrab/features/extractor/presentation/providers/extractor_provider.dart';
import 'package:mediagrab/features/extractor/presentation/screens/media_info_screen.dart';
import 'package:mediagrab/features/extractor/presentation/widgets/playlist_selector_sheet.dart';
import 'package:mediagrab/features/extractor/presentation/widgets/quality_selector_sheet.dart';
import 'package:mediagrab/features/extractor/presentation/widgets/video_preview_card.dart';
import 'package:shimmer/shimmer.dart';

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
  const testUrl = 'https://youtube.com/watch?v=sample123';

  final sampleMedia = MediaInfo(
    id: 'sample123',
    title: 'Sample Video Title',
    thumbnailUrl: 'https://img.youtube.com/vi/sample123/hqdefault.jpg',
    duration: const Duration(minutes: 5, seconds: 12),
    uploader: 'Sample Creator',
    platform: PlatformType.youtube,
    description: 'This is a test description.',
  );

  const sampleStream = StreamInfo(
    url: 'https://example.com/sample123.mp4',
    container: 'mp4',
    qualityLabel: '1080p',
    codec: 'h264',
    isVideoOnly: false,
    isAudioOnly: false,
    bitrate: 5000000,
    sizeInBytes: 15000000,
  );

  const sampleAudioStream = StreamInfo(
    url: 'https://example.com/sample123.m4a',
    container: 'm4a',
    qualityLabel: '128 kbps',
    codec: 'mp4a',
    isAudioOnly: true,
    bitrate: 128000,
    sizeInBytes: 4000000,
  );

  final samplePlaylist = PlaylistInfo(
    id: 'list123',
    title: 'Best of Lo-Fi Beats',
    author: 'ChillHop Music',
    videoCount: 2,
    videos: [
      sampleMedia,
      MediaInfo(
        id: 'sample456',
        title: 'Track 2 in Playlist',
        thumbnailUrl: 'https://img.youtube.com/vi/sample456/hqdefault.jpg',
        duration: const Duration(minutes: 3),
        uploader: 'ChillHop Music',
        platform: PlatformType.youtube,
      ),
    ],
  );

  for (final allFail in [false, true]) {
    testWidgets(
      'download entire playlist reports ${allFail ? 'zero' : 'partial'} queue',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            mediaInfoProvider(testUrl).overrideWith((ref) async => sampleMedia),
            streamsProvider(
              testUrl,
            ).overrideWith((ref) async => [sampleStream]),
            playlistProvider(
              testUrl,
            ).overrideWith((ref) async => samplePlaylist),
            extractorFactoryProvider.overrideWithValue(
              ExtractorFactory(
                extractors: [
                  _BatchExtractor(
                    allFail ? {'sample123', 'sample456'} : {'sample456'},
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
            child: const MaterialApp(home: MediaInfoScreen(url: testUrl)),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final button = find.widgetWithText(
          FilledButton,
          'Download Entire Playlist',
        );
        await tester.ensureVisible(button);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(button);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(container.read(downloadManagerProvider).length, allFail ? 0 : 1);
        expect(
          find.textContaining(
            allFail ? 'No downloads could be queued.' : 'Queued 1 of 2',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('MediaInfoScreen shows shimmer skeleton while loading', (
    tester,
  ) async {
    final completer = Completer<MediaInfo>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          extractorFactoryProvider.overrideWithValue(
            ExtractorFactory(extractors: [_BatchExtractor()]),
          ),
          mediaInfoProvider(testUrl).overrideWith((ref) => completer.future),
        ],
        child: const MaterialApp(home: MediaInfoScreen(url: testUrl)),
      ),
    );
    await tester.pump();

    expect(find.byType(Shimmer), findsOneWidget);
  });

  testWidgets('MediaInfoScreen shows error view and retry button on failure', (
    tester,
  ) async {
    var retried = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          extractorFactoryProvider.overrideWithValue(
            ExtractorFactory(extractors: [_BatchExtractor()]),
          ),
          mediaInfoProvider(testUrl).overrideWith((ref) {
            if (!retried) {
              throw Exception('Network timeout occurred');
            }
            return sampleMedia;
          }),
        ],
        child: const MaterialApp(home: MediaInfoScreen(url: testUrl)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Extraction Failed'), findsOneWidget);
    expect(find.textContaining('Network timeout'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Try Again'), findsOneWidget);

    retried = true;
    await tester.tap(find.widgetWithText(FilledButton, 'Try Again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(VideoPreviewCard), findsOneWidget);
    expect(find.text('Sample Video Title'), findsOneWidget);
  });

  testWidgets(
    'MediaInfoScreen shows media info, opens quality sheet, and triggers download',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          extractorFactoryProvider.overrideWithValue(
            ExtractorFactory(extractors: [_BatchExtractor()]),
          ),
          mediaInfoProvider(
            testUrl,
          ).overrideWith((ref) => Future.value(sampleMedia)),
          streamsProvider(
            testUrl,
          ).overrideWith((ref) => Future.value([sampleStream])),
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
          child: const MaterialApp(home: MediaInfoScreen(url: testUrl)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(VideoPreviewCard), findsOneWidget);
      expect(find.text('Sample Video Title'), findsOneWidget);
      expect(find.text('Download Options'), findsOneWidget);
      expect(find.text('This is a test description.'), findsOneWidget);

      // Verify action buttons exist
      expect(find.widgetWithText(FilledButton, 'Download'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Audio Only'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Open in Browser'),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, 'Share'), findsOneWidget);

      // Ensure "Download" button is scrolled into view before tapping
      final downloadButtonFinder = find.widgetWithText(
        FilledButton,
        'Download',
      );
      await tester.ensureVisible(downloadButtonFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap "Download" button
      await tester.tap(downloadButtonFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify QualitySelectorSheet opens
      expect(find.byType(QualitySelectorSheet), findsOneWidget);

      // Tap "Download Selected (1080p)" button in quality sheet
      final downloadSelectedFinder = find.widgetWithText(
        FilledButton,
        'Download Selected (1080p)',
      );
      expect(downloadSelectedFinder, findsOneWidget);
      await tester.tap(downloadSelectedFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify download is queued/active in downloadManagerProvider
      final tasks = container.read(downloadManagerProvider);
      expect(tasks, isNotEmpty);
      expect(tasks.first.mediaInfo.title, 'Sample Video Title');
      expect(tasks.first.selectedStream.qualityLabel, '1080p');

      // Verify snackbar is shown confirming download started
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Download started · 1080p'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping Audio Only button opens QualitySelectorSheet with Audio tab active',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            extractorFactoryProvider.overrideWithValue(
              ExtractorFactory(extractors: [_BatchExtractor()]),
            ),
            mediaInfoProvider(
              testUrl,
            ).overrideWith((ref) => Future.value(sampleMedia)),
            streamsProvider(testUrl).overrideWith(
              (ref) => Future.value([sampleStream, sampleAudioStream]),
            ),
          ],
          child: const MaterialApp(home: MediaInfoScreen(url: testUrl)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final audioOnlyFinder = find.widgetWithText(FilledButton, 'Audio Only');
      await tester.ensureVisible(audioOnlyFinder);
      await tester.tap(audioOnlyFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify QualitySelectorSheet opens and has audio stream preselected
      expect(find.byType(QualitySelectorSheet), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Download Selected (128 kbps)'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'MediaInfoScreen displays prominent Playlist Header Card and "Select Videos to Download" opens PlaylistSelectorSheet',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            extractorFactoryProvider.overrideWithValue(
              ExtractorFactory(extractors: [_BatchExtractor()]),
            ),
            mediaInfoProvider(
              testUrl,
            ).overrideWith((ref) => Future.value(sampleMedia)),
            streamsProvider(
              testUrl,
            ).overrideWith((ref) => Future.value([sampleStream])),
            playlistProvider(
              testUrl,
            ).overrideWith((ref) => Future.value(samplePlaylist)),
          ],
          child: const MaterialApp(home: MediaInfoScreen(url: testUrl)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify Playlist card
      expect(find.text('PLAYLIST'), findsOneWidget);
      expect(find.text('Best of Lo-Fi Beats'), findsOneWidget);
      expect(find.text('2 videos • ChillHop Music'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Select Videos to Download'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Download Entire Playlist'),
        findsOneWidget,
      );

      // Tap "Select Videos to Download"
      final selectVideosBtn = find.widgetWithText(
        FilledButton,
        'Select Videos to Download',
      );
      await tester.ensureVisible(selectVideosBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(selectVideosBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify PlaylistSelectorSheet opens
      expect(find.byType(PlaylistSelectorSheet), findsOneWidget);
      expect(find.text('Track 2 in Playlist'), findsOneWidget);
    },
  );

  testWidgets(
    'MediaInfoScreen "Download Entire Playlist" directly enqueues all videos without opening sheet',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          extractorFactoryProvider.overrideWithValue(
            ExtractorFactory(extractors: [_BatchExtractor()]),
          ),
          mediaInfoProvider(
            testUrl,
          ).overrideWith((ref) => Future.value(sampleMedia)),
          streamsProvider(
            testUrl,
          ).overrideWith((ref) => Future.value([sampleStream])),
          playlistProvider(
            testUrl,
          ).overrideWith((ref) => Future.value(samplePlaylist)),
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
          child: const MaterialApp(home: MediaInfoScreen(url: testUrl)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap "Download Entire Playlist"
      final downloadAllBtn = find.widgetWithText(
        FilledButton,
        'Download Entire Playlist',
      );
      await tester.ensureVisible(downloadAllBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(downloadAllBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Should NOT open PlaylistSelectorSheet
      expect(find.byType(PlaylistSelectorSheet), findsNothing);

      // Should have enqueued both videos into downloadManagerProvider
      final tasks = container.read(downloadManagerProvider);
      expect(tasks.length, 2);
      expect(tasks[0].mediaInfo.title, 'Sample Video Title');
      expect(tasks[1].mediaInfo.title, 'Track 2 in Playlist');

      // Verify snackbar confirmation
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.textContaining('Starting download for 2 videos from playlist'),
        findsOneWidget,
      );
    },
  );

  testWidgets('expandable description toggles on tap when text is long', (
    tester,
  ) async {
    final longDescMedia = MediaInfo(
      id: 'longDesc',
      title: 'Video with Long Description',
      thumbnailUrl: 'https://img.youtube.com/vi/longDesc/hqdefault.jpg',
      duration: const Duration(minutes: 10),
      uploader: 'Detailed Creator',
      platform: PlatformType.youtube,
      description:
          'This is a comprehensive description that contains a lot of detailed information '
          'spanning across multiple sentences and paragraphs to explain everything about this video, '
          'its background, the production techniques, tools used, and acknowledgments to everyone involved.',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          extractorFactoryProvider.overrideWithValue(
            ExtractorFactory(extractors: [_BatchExtractor()]),
          ),
          mediaInfoProvider(
            testUrl,
          ).overrideWith((ref) => Future.value(longDescMedia)),
          streamsProvider(testUrl).overrideWith((ref) => Future.value([])),
        ],
        child: const MaterialApp(home: MediaInfoScreen(url: testUrl)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Ensure description card is visible
    final showMoreFinder = find.text('Show more');
    await tester.ensureVisible(showMoreFinder);
    expect(showMoreFinder, findsOneWidget);

    // Tap Show more
    await tester.tap(showMoreFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Show less'), findsOneWidget);

    // Tap Show less to collapse
    await tester.tap(find.text('Show less'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Show more'), findsOneWidget);
  });
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
