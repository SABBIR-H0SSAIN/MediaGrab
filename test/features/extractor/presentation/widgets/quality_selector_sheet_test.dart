import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';
import 'package:mediagrab/features/extractor/presentation/providers/extractor_provider.dart';
import 'package:mediagrab/features/extractor/presentation/widgets/quality_selector_sheet.dart';
import 'package:mediagrab/features/settings/presentation/providers/settings_provider.dart';

void main() {
  const videoStream1 = StreamInfo(
    url: 'https://example.com/1080.mp4',
    qualityLabel: '1080p',
    codec: 'avc1',
    container: 'mp4',
    sizeInBytes: 100 * 1024 * 1024,
    videoHeight: 1080,
    videoWidth: 1920,
    isVideoOnly: true,
  );

  const videoStream2 = StreamInfo(
    url: 'https://example.com/720.mp4',
    qualityLabel: '720p',
    codec: 'avc1',
    container: 'mp4',
    sizeInBytes: 50 * 1024 * 1024,
    videoHeight: 720,
    videoWidth: 1280,
  );

  const audioStream = StreamInfo(
    url: 'https://example.com/audio.m4a',
    qualityLabel: '128 kbps',
    codec: 'mp4a',
    container: 'm4a',
    sizeInBytes: 5 * 1024 * 1024,
    isAudioOnly: true,
    bitrate: 128000,
  );

  const audioStream2 = StreamInfo(
    url: 'https://example.com/audio2.opus',
    qualityLabel: '256 kbps',
    codec: 'opus',
    container: 'webm',
    sizeInBytes: 8 * 1024 * 1024,
    isAudioOnly: true,
    bitrate: 256000,
  );

  const testUrl = 'https://youtube.com/watch?v=sample';

  Widget buildSheetWidget({
    void Function(StreamInfo)? onDownload,
    void Function(StreamInfo, StreamInfo?)? onDownloadWithAudio,
    List<StreamInfo>? streams,
    bool initialIsAudio = false,
    SettingsState? settings,
  }) {
    return ProviderScope(
      overrides: [
        streamsProvider(testUrl).overrideWith(
          (ref) => Future.value(
            streams ?? [videoStream1, videoStream2, audioStream, audioStream2],
          ),
        ),
        if (settings != null)
          settingsProvider.overrideWith(
            (ref) => SettingsNotifier()..state = settings,
          ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: QualitySelectorSheet(
            url: testUrl,
            onDownload: onDownload,
            onDownloadWithAudio: onDownloadWithAudio,
            initialIsAudio: initialIsAudio,
          ),
        ),
      ),
    );
  }

  testWidgets(
    'one best video per resolution is shown and companion audio is retained',
    (tester) async {
      const best = StreamInfo(
        url: 'https://example.com/best1080.mp4',
        qualityLabel: '1080p',
        codec: 'avc1',
        container: 'mp4',
        videoHeight: 1080,
        bitrate: 4000000,
        isVideoOnly: true,
      );
      const alternate = StreamInfo(
        url: 'https://example.com/alternate1080.webm',
        qualityLabel: '1080p',
        codec: 'vp9',
        container: 'webm',
        videoHeight: 1080,
        bitrate: 2000000,
        isVideoOnly: true,
      );
      StreamInfo? downloaded;
      StreamInfo? companion;
      await tester.pumpWidget(
        buildSheetWidget(
          streams: [alternate, best, videoStream1, videoStream2, audioStream],
          onDownloadWithAudio: (video, audio) {
            downloaded = video;
            companion = audio;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1080p'), findsOneWidget);
      expect(find.text('720p'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Download Selected (1080p)'),
      );
      await tester.pumpAndSettle();
      expect(downloaded, best);
      expect(companion, audioStream);
    },
  );

  testWidgets(
    'QualitySelectorSheet displays tabs, streams, and allows selection and download',
    (tester) async {
      StreamInfo? downloadedStream;

      await tester.pumpWidget(
        buildSheetWidget(
          onDownload: (stream) {
            downloadedStream = stream;
          },
        ),
      );
      await tester.pumpAndSettle();

      // Check header and tabs
      expect(find.text('Download Options'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);
      expect(find.text('Audio'), findsOneWidget);

      // Verify video streams are present
      expect(find.text('1080p'), findsOneWidget);
      expect(find.text('720p'), findsOneWidget);

      // Tap on 720p tile
      await tester.tap(find.text('720p'));
      await tester.pumpAndSettle();

      // Tap Download Selected
      await tester.tap(
        find.widgetWithText(FilledButton, 'Download Selected (720p)'),
      );
      await tester.pumpAndSettle();

      expect(downloadedStream, equals(videoStream2));
    },
  );

  testWidgets('Audio tab displays audio streams', (tester) async {
    await tester.pumpWidget(buildSheetWidget());
    await tester.pumpAndSettle();

    // Switch to Audio tab
    await tester.tap(find.text('Audio'));
    await tester.pumpAndSettle();

    // Verify audio stream details
    expect(find.text('128 kbps'), findsOneWidget);
    expect(find.text('M4A'), findsOneWidget);
  });

  testWidgets(
    'switching to Audio tab updates stream selection, visual highlight, and download button without manual tile tap',
    (tester) async {
      StreamInfo? downloadedStream;

      await tester.pumpWidget(
        buildSheetWidget(
          onDownload: (stream) {
            downloadedStream = stream;
          },
        ),
      );
      await tester.pumpAndSettle();

      // Initially on Video tab: button reflects first video stream (1080p)
      expect(
        find.widgetWithText(FilledButton, 'Download Selected (1080p)'),
        findsOneWidget,
      );

      // Switch to Audio tab
      await tester.tap(find.text('Audio'));
      await tester.pumpAndSettle();

      // Button should now immediately reflect the default audio stream (128 kbps)
      expect(
        find.widgetWithText(FilledButton, 'Download Selected (128 kbps)'),
        findsOneWidget,
      );

      // Verify the 128 kbps tile is visually highlighted with primaryContainer
      final theme = Theme.of(tester.element(find.text('128 kbps')));
      final audioTileMaterial = tester.widget<Material>(
        find
            .ancestor(
              of: find.text('128 kbps'),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(
        audioTileMaterial.color,
        equals(theme.colorScheme.primaryContainer),
      );

      // Tap "Download Selected" button while on the Audio tab
      await tester.tap(
        find.widgetWithText(FilledButton, 'Download Selected (128 kbps)'),
      );
      await tester.pumpAndSettle();

      // Verify the audio stream was downloaded, not the video stream
      expect(downloadedStream, equals(audioStream));
    },
  );

  testWidgets(
    'tab switching preserves independent stream selections across Video and Audio tabs',
    (tester) async {
      StreamInfo? downloadedStream;

      await tester.pumpWidget(
        buildSheetWidget(
          onDownload: (stream) {
            downloadedStream = stream;
          },
        ),
      );
      await tester.pumpAndSettle();

      // Select 720p on Video tab
      await tester.tap(find.text('720p'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, 'Download Selected (720p)'),
        findsOneWidget,
      );

      // Switch to Audio tab
      await tester.tap(find.text('Audio'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, 'Download Selected (128 kbps)'),
        findsOneWidget,
      );

      // Select 256 kbps on Audio tab
      await tester.tap(find.text('256 kbps'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, 'Download Selected (256 kbps)'),
        findsOneWidget,
      );

      // Switch back to Video tab -> 720p selection is preserved
      await tester.tap(find.text('Video'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, 'Download Selected (720p)'),
        findsOneWidget,
      );

      // Switch back to Audio tab -> 256 kbps selection is preserved
      await tester.tap(find.text('Audio'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, 'Download Selected (256 kbps)'),
        findsOneWidget,
      );

      // Download from Audio tab triggers 256 kbps
      await tester.tap(
        find.widgetWithText(FilledButton, 'Download Selected (256 kbps)'),
      );
      await tester.pumpAndSettle();
      expect(downloadedStream, equals(audioStream2));
    },
  );

  testWidgets('initialIsAudio: true initializes with Audio tab selected', (
    tester,
  ) async {
    await tester.pumpWidget(buildSheetWidget(initialIsAudio: true));
    await tester.pumpAndSettle();

    // Directly displays audio stream button and details
    expect(
      find.widgetWithText(FilledButton, 'Download Selected (128 kbps)'),
      findsOneWidget,
    );
    expect(find.text('128 kbps'), findsOneWidget);
    expect(find.text('Standard'), findsOneWidget);
  });

  testWidgets(
    'QualitySelectorSheet displays quality tier badges and radio indicators',
    (tester) async {
      await tester.pumpWidget(buildSheetWidget());
      await tester.pumpAndSettle();

      // 1080p stream should have FHD tier badge
      expect(find.text('FHD'), findsOneWidget);
      // 720p stream should have HD tier badge
      expect(find.text('HD'), findsOneWidget);

      // Selected stream has check circle icon
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      // Unselected stream has radio button unchecked icon
      expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsOneWidget);
    },
  );

  testWidgets(
    'QualitySelectorSheet pre-selects 720p stream when defaultVideoQuality is 720p',
    (tester) async {
      await tester.pumpWidget(
        buildSheetWidget(
          settings: const SettingsState(defaultVideoQuality: '720p'),
        ),
      );
      await tester.pumpAndSettle();

      // Download button defaults directly to 720p without clicking
      expect(
        find.widgetWithText(FilledButton, 'Download Selected (720p)'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'QualitySelectorSheet defaults to Audio tab when defaultVideoQuality is Audio Only',
    (tester) async {
      await tester.pumpWidget(
        buildSheetWidget(
          settings: const SettingsState(defaultVideoQuality: 'Audio Only'),
        ),
      );
      await tester.pumpAndSettle();

      // Audio tab is pre-selected and button reflects default audio stream
      expect(
        find.widgetWithText(FilledButton, 'Download Selected (128 kbps)'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'QualitySelectorSheet does not display Video only badge and formats subtitle cleanly without raw codec hashes',
    (tester) async {
      await tester.pumpWidget(buildSheetWidget());
      await tester.pumpAndSettle();

      // "Video only" badge must NOT appear anywhere, even though videoStream1 is video-only
      expect(find.text('Video only'), findsNothing);

      // Raw codec hashes like "avc1" must not be displayed
      expect(find.textContaining('avc1'), findsNothing);

      // Clean subtitle format with size and uppercase container
      expect(find.text('~100.0 MB'), findsOneWidget);
      expect(find.text('~50.0 MB'), findsOneWidget);

      // Redundant trailing download button on ListTile should not exist
      expect(
        find.widgetWithIcon(IconButton, Icons.download_rounded),
        findsNothing,
      );

      // Switch to Audio tab
      await tester.tap(find.text('Audio'));
      await tester.pumpAndSettle();

      // Raw audio codecs like "mp4a" and "opus" must not be displayed
      expect(find.textContaining('mp4a'), findsNothing);
      expect(find.textContaining('opus'), findsNothing);

      // Clean audio subtitles
      expect(find.text('~5.0 MB'), findsOneWidget);
      expect(find.text('~8.0 MB'), findsOneWidget);
    },
  );

  testWidgets(
    'QualitySelectorSheet renders without overflow on narrow 320px viewport',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildSheetWidget());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Download Options'), findsOneWidget);
      expect(find.text('1080p'), findsOneWidget);
    },
  );

  testWidgets(
    'QualitySelectorSheet displays all video and audio tier badges correctly',
    (tester) async {
      const extraStreams = [
        StreamInfo(
          url: 'https://example.com/4k.mp4',
          qualityLabel: '4K',
          codec: 'vp9',
          container: 'webm',
          videoHeight: 2160,
        ),
        StreamInfo(
          url: 'https://example.com/1440.mp4',
          qualityLabel: '1440p',
          codec: 'vp9',
          container: 'webm',
          videoHeight: 1440,
        ),
        StreamInfo(
          url: 'https://example.com/480.mp4',
          qualityLabel: '480p',
          codec: 'avc1',
          container: 'mp4',
          videoHeight: 480,
        ),
        StreamInfo(
          url: 'https://example.com/audio_high.m4a',
          qualityLabel: '320 kbps',
          codec: 'aac',
          container: 'm4a',
          isAudioOnly: true,
          bitrate: 320000,
        ),
        StreamInfo(
          url: 'https://example.com/audio_basic.m4a',
          qualityLabel: '64 kbps',
          codec: 'aac',
          container: 'm4a',
          isAudioOnly: true,
          bitrate: 64000,
        ),
      ];

      await tester.pumpWidget(buildSheetWidget(streams: extraStreams));
      await tester.pumpAndSettle();

      // Video badges
      expect(find.text('4K UHD'), findsOneWidget);
      expect(find.text('QHD'), findsOneWidget);
      expect(find.text('SD'), findsOneWidget);

      // Switch to Audio tab
      await tester.tap(find.text('Audio'));
      await tester.pumpAndSettle();

      // Audio badges
      expect(find.text('High'), findsOneWidget);
      expect(find.text('Basic'), findsOneWidget);
    },
  );
}
