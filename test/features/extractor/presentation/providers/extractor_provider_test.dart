import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/extractor/data/extractor_factory.dart';
import 'package:mediagrab/features/extractor/data/extractors/base_extractor.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/playlist_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';
import 'package:mediagrab/features/extractor/presentation/providers/extractor_provider.dart';

class _MockExtractor extends BaseExtractor {
  final MediaInfo mockMediaInfo;
  final List<StreamInfo> mockStreams;
  final PlaylistInfo? mockPlaylist;
  final bool shouldThrow;

  _MockExtractor({
    required this.mockMediaInfo,
    required this.mockStreams,
    this.mockPlaylist,
    this.shouldThrow = false,
  });

  @override
  bool canHandle(String url) => true;

  @override
  Future<MediaInfo> extractInfo(String url) async {
    if (shouldThrow) throw Exception('Extraction failed');
    return mockMediaInfo;
  }

  @override
  Future<List<StreamInfo>> getStreams(String url) async {
    if (shouldThrow) throw Exception('Stream extraction failed');
    return mockStreams;
  }

  @override
  Future<PlaylistInfo?> extractPlaylist(String url) async {
    return mockPlaylist;
  }
}

void main() {
  const sampleMedia = MediaInfo(
    id: 'test_id',
    title: 'Test Video',
    thumbnailUrl: 'https://example.com/thumb.jpg',
    duration: Duration(minutes: 3),
    uploader: 'Test Channel',
    platform: PlatformType.youtube,
  );

  const sampleStream = StreamInfo(
    url: 'https://example.com/video.mp4',
    qualityLabel: '1080p',
    codec: 'h264',
    container: 'mp4',
    sizeInBytes: 104857600,
  );

  const samplePlaylist = PlaylistInfo(
    id: 'PL123',
    title: 'Test Playlist',
    author: 'Test Creator',
    videoCount: 1,
    videos: [sampleMedia],
  );

  group('Extractor Providers', () {
    test('mediaInfoProvider returns MediaInfo on success', () async {
      final mockExtractor = _MockExtractor(
        mockMediaInfo: sampleMedia,
        mockStreams: [sampleStream],
      );
      final container = ProviderContainer(
        overrides: [
          extractorFactoryProvider.overrideWithValue(
            ExtractorFactory(extractors: [mockExtractor]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final mediaInfo = await container.read(
        mediaInfoProvider('https://youtube.com/watch?v=test_id').future,
      );

      expect(mediaInfo, equals(sampleMedia));
    });

    test('streamsProvider returns StreamInfo list on success', () async {
      final mockExtractor = _MockExtractor(
        mockMediaInfo: sampleMedia,
        mockStreams: [sampleStream],
      );
      final container = ProviderContainer(
        overrides: [
          extractorFactoryProvider.overrideWithValue(
            ExtractorFactory(extractors: [mockExtractor]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final streams = await container.read(
        streamsProvider('https://youtube.com/watch?v=test_id').future,
      );

      expect(streams, equals([sampleStream]));
    });

    test('playlistProvider returns PlaylistInfo on success', () async {
      final mockExtractor = _MockExtractor(
        mockMediaInfo: sampleMedia,
        mockStreams: [sampleStream],
        mockPlaylist: samplePlaylist,
      );
      final container = ProviderContainer(
        overrides: [
          extractorFactoryProvider.overrideWithValue(
            ExtractorFactory(extractors: [mockExtractor]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final playlist = await container.read(
        playlistProvider('https://youtube.com/playlist?list=PL123').future,
      );

      expect(playlist, equals(samplePlaylist));
    });

    test('mediaInfoProvider emits error when extraction fails', () async {
      final mockExtractor = _MockExtractor(
        mockMediaInfo: sampleMedia,
        mockStreams: [],
        shouldThrow: true,
      );
      final container = ProviderContainer(
        overrides: [
          extractorFactoryProvider.overrideWithValue(
            ExtractorFactory(extractors: [mockExtractor]),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        () => container.read(
          mediaInfoProvider('https://youtube.com/watch?v=test_id').future,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
