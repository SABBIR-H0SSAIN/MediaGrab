import 'package:mediagrab/features/extractor/domain/entities/prepared_download.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/downloads/data/services/download_engine.dart';
import 'package:mediagrab/features/downloads/domain/entities/download_task.dart';
import 'package:mediagrab/features/downloads/presentation/providers/download_manager_provider.dart';
import 'package:mediagrab/features/extractor/data/extractor_factory.dart';
import 'package:mediagrab/features/extractor/data/extractors/base_extractor.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';
import 'package:mediagrab/features/extractor/presentation/providers/extractor_provider.dart';
import 'package:mediagrab/features/extractor/presentation/utils/batch_download_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Extractor extends BaseExtractor {
  final urls = <String>[];
  @override
  bool canHandle(String url) => true;
  @override
  Future<MediaInfo> extractInfo(String url) async {
    urls.add(url);
    return const MediaInfo(
      id: 'abcdefghijk',
      title: 'Actual title',
      thumbnailUrl: '',
      duration: Duration.zero,
      uploader: 'Uploader',
      platform: PlatformType.youtube,
    );
  }

  @override
  Future<List<StreamInfo>> getStreams(String url) async {
    urls.add(url);
    return const [
      StreamInfo(
        url: 'https://cdn.example/video',
        qualityLabel: '1080p',
        codec: 'h264',
        container: 'mp4',
        videoHeight: 1080,
        isVideoOnly: true,
      ),
      StreamInfo(
        url: 'https://cdn.example/audio',
        qualityLabel: '128 kbps',
        codec: 'aac',
        container: 'm4a',
        bitrate: 128000,
        isAudioOnly: true,
      ),
    ];
  }
}

void main() {
  for (final preparedMode in [false, true]) {
    testWidgets(
      preparedMode
          ? 'prepared selections skip extraction, retain audio, and report partial failure'
          : 'batch resolves a full page URL to real metadata and CDN stream',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final extractor = _Extractor();
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
        List<DownloadTask>? queued;
        final errors = <String>[];
        const url = 'https://www.youtube.com/watch?v=abcdefghijk';
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              extractorFactoryProvider.overrideWithValue(
                ExtractorFactory(extractors: [extractor]),
              ),
              downloadEngineProvider.overrideWithValue(engine),
              connectivityProvider.overrideWithValue(null),
            ],
            child: MaterialApp(
              home: Consumer(
                builder:
                    (context, ref, _) => TextButton(
                      onPressed: () async {
                        queued = await enqueueBatchMediaDownloads(
                          ref: ref,
                          targetDirectory: '/tmp',
                          onItemError: (url, error) => errors.add(url),
                          prepared:
                              !preparedMode
                                  ? const []
                                  : [
                                    const PreparedDownload(
                                      sourceUrl: url,
                                      media: MediaInfo(
                                        id: 'abcdefghijk',
                                        title: 'Actual title',
                                        thumbnailUrl: '',
                                        duration: Duration.zero,
                                        uploader: 'Uploader',
                                        platform: PlatformType.youtube,
                                      ),
                                      stream: StreamInfo(
                                        url: 'https://cdn.example/invalid',
                                        qualityLabel: '1080p',
                                        codec: 'h264',
                                        container: 'mp4',
                                        videoHeight: 1080,
                                        isVideoOnly: true,
                                      ),
                                    ),
                                    PreparedDownload(
                                      sourceUrl: url,
                                      media: const MediaInfo(
                                        id: 'abcdefghijk',
                                        title: 'Actual title',
                                        thumbnailUrl: '',
                                        duration: Duration.zero,
                                        uploader: 'Uploader',
                                        platform: PlatformType.youtube,
                                      ),
                                      stream:
                                          (await extractor.getStreams(
                                            url,
                                          )).first,
                                      audioStream:
                                          (await extractor.getStreams(
                                            url,
                                          )).last,
                                    ),
                                  ],
                          videos:
                              preparedMode
                                  ? const []
                                  : const [
                                    MediaInfo(
                                      id: url,
                                      title: 'Placeholder',
                                      thumbnailUrl: '',
                                      duration: Duration.zero,
                                      uploader: 'Batch',
                                      platform: PlatformType.youtube,
                                    ),
                                  ],
                        );
                      },
                      child: const Text('Queue'),
                    ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Queue'));
        await tester.pumpAndSettle();
        // Two test fixture calls construct the prepared streams; no metadata is fetched.
        expect(extractor.urls, [url, url]);
        expect(errors.length, preparedMode ? 1 : 0);
        expect(queued!.single.mediaInfo.title, 'Actual title');
        expect(queued!.single.selectedStream.url, 'https://cdn.example/video');
        expect(queued!.single.selectedStream.isVideoOnly, isTrue);
      },
    );
  }
}
