import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_parser/http_parser.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/extractor/data/extractors/youtube_extractor.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class _FakeStreamClient extends StreamClient {
  int getManifestCallCount = 0;
  final Future<StreamManifest> Function(dynamic videoId)? getManifestHandler;

  _FakeStreamClient({this.getManifestHandler}) : super(YoutubeHttpClient());

  @override
  Future<StreamManifest> getManifest(
    dynamic videoId, {
    bool fullManifest = false,
    List<YoutubeApiClient>? ytClients,
    bool requireWatchPage = true,
  }) async {
    getManifestCallCount++;
    if (getManifestHandler != null) {
      return getManifestHandler!(videoId);
    }
    return StreamManifest([]);
  }
}

class _FakeVideoClient extends VideoClient {
  final Future<Video> Function(dynamic videoId)? getHandler;
  final StreamClient? _mockStreams;

  _FakeVideoClient({this.getHandler, StreamClient? streamsClient})
      : _mockStreams = streamsClient,
        super(YoutubeHttpClient());

  @override
  StreamClient get streamsClient => _mockStreams ?? super.streamsClient;

  @override
  StreamClient get streams => streamsClient;

  @override
  Future<Video> get(dynamic videoId) async {
    if (getHandler != null) {
      return getHandler!(videoId);
    }
    throw VideoUnavailableException('Video "$videoId" is private or unavailable');
  }
}

class _FakeYoutubeExplode extends YoutubeExplode {
  final VideoClient _mockVideos;

  _FakeYoutubeExplode({required VideoClient videos})
      : _mockVideos = videos,
        super();

  @override
  VideoClient get videos => _mockVideos;
}

class _MockHttpClientAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;

  _MockHttpClientAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}

StreamManifest _createTestManifest({
  String videoId = 'dQw4w9WgXcQ',
  String url = 'https://example.com/stream.mp4',
  String qualityLabel = '720p',
  int width = 1280,
  int height = 720,
}) {
  final stream = MuxedStreamInfo(
    VideoId(videoId),
    22,
    Uri.parse(url),
    StreamContainer.mp4,
    const FileSize(15000000),
    const Bitrate(2500000),
    'mp4a.40.2',
    'avc1.64001F',
    qualityLabel,
    VideoQuality.high720,
    VideoResolution(width, height),
    const Framerate(30),
    MediaType('video', 'mp4'),
  );
  return StreamManifest([stream]);
}

void main() {
  late YoutubeExtractor extractor;

  setUp(() {
    YoutubeExtractor.clearCache();
    extractor = YoutubeExtractor();
  });

  tearDown(() {
    YoutubeExtractor.clearCache();
    extractor.close();
  });

  group('YoutubeExtractor - URL Handling & ID Extraction', () {
    test('canHandle identifies YouTube URLs accurately', () {
      expect(
        extractor.canHandle('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        isTrue,
      );
      expect(extractor.canHandle('https://youtu.be/dQw4w9WgXcQ'), isTrue);
      expect(
        extractor.canHandle('https://www.youtube.com/shorts/dQw4w9WgXcQ'),
        isTrue,
      );
      expect(
        extractor.canHandle('https://www.youtube.com/live/dQw4w9WgXcQ'),
        isTrue,
      );
      expect(
        extractor.canHandle('https://www.youtube.com/playlist?list=PL123'),
        isTrue,
      );

      // Non-YouTube URLs
      expect(
        extractor.canHandle('https://www.instagram.com/reel/12345/'),
        isFalse,
      );
      expect(
        extractor.canHandle('https://www.facebook.com/watch/?v=123'),
        isFalse,
      );
      expect(extractor.canHandle('https://example.com/video.mp4'), isFalse);
    });

    test('extractVideoId handles all query parameter variations and shorts/live', () {
      const expectedId = 'dQw4w9WgXcQ';

      // Standard watch with query params
      expect(
        extractor.extractVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        expectedId,
      );
      expect(
        extractor.extractVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ&feature=shared'),
        expectedId,
      );
      expect(
        extractor.extractVideoId('https://www.youtube.com/watch?feature=shared&v=dQw4w9WgXcQ&t=42'),
        expectedId,
      );

      // youtu.be with tracking parameters
      expect(
        extractor.extractVideoId('https://youtu.be/dQw4w9WgXcQ'),
        expectedId,
      );
      expect(
        extractor.extractVideoId('https://youtu.be/dQw4w9WgXcQ?si=abcdef123'),
        expectedId,
      );
      expect(
        extractor.extractVideoId('https://youtu.be/dQw4w9WgXcQ?feature=share'),
        expectedId,
      );

      // Shorts with tracking parameters and trailing slashes
      expect(
        extractor.extractVideoId('https://www.youtube.com/shorts/dQw4w9WgXcQ'),
        expectedId,
      );
      expect(
        extractor.extractVideoId('https://www.youtube.com/shorts/dQw4w9WgXcQ/'),
        expectedId,
      );
      expect(
        extractor.extractVideoId('https://www.youtube.com/shorts/dQw4w9WgXcQ?si=tracking123'),
        expectedId,
      );
      expect(
        extractor.extractVideoId('https://m.youtube.com/shorts/dQw4w9WgXcQ?feature=share'),
        expectedId,
      );

      // Live streams with tracking parameters
      expect(
        extractor.extractVideoId('https://www.youtube.com/live/dQw4w9WgXcQ'),
        expectedId,
      );
      expect(
        extractor.extractVideoId('https://www.youtube.com/live/dQw4w9WgXcQ?si=xyz987'),
        expectedId,
      );

      // Embed and older URL formats
      expect(
        extractor.extractVideoId('https://www.youtube.com/embed/dQw4w9WgXcQ'),
        expectedId,
      );
      expect(
        extractor.extractVideoId('https://www.youtube.com/v/dQw4w9WgXcQ'),
        expectedId,
      );

      // Raw 11-char ID
      expect(extractor.extractVideoId('dQw4w9WgXcQ'), expectedId);

      // Negative cases
      expect(extractor.extractVideoId(''), isNull);
      expect(extractor.extractVideoId('https://google.com'), isNull);
      expect(extractor.extractVideoId('https://youtube.com'), isNull);
    });

    test('extractPlaylistId extracts playlist ID from playlist and watch URLs', () {
      const expectedList = 'PLrEnWoR732-DNXkZt3Rz-z2mF1u4nL123';

      expect(
        extractor.extractPlaylistId('https://www.youtube.com/playlist?list=$expectedList'),
        expectedList,
      );
      expect(
        extractor.extractPlaylistId('https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=$expectedList'),
        expectedList,
      );
      expect(
        extractor.extractPlaylistId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        isNull,
      );
    });
  });

  group('YoutubeExtractor - Resilient Fallback', () {
    test('falls back to oEmbed when _yt.videos.get throws VideoUnavailableException', () async {
      final fakeYt = _FakeYoutubeExplode(
        videos: _FakeVideoClient(
          getHandler: (id) => throw VideoUnavailableException('Video "$id" does not exist'),
        ),
      );

      final dio = Dio()
        ..httpClientAdapter = _MockHttpClientAdapter((options) async {
          expect(options.path, contains('youtube.com/oembed'));
          expect(options.path, contains('dQw4w9WgXcQ'));

          final responseJson = jsonEncode({
            'title': 'Rick Astley - Never Gonna Give You Up (Official Video)',
            'author_name': 'Rick Astley',
            'thumbnail_url': 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
          });

          return ResponseBody.fromString(
            responseJson,
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

      final fallbackExtractor = YoutubeExtractor(
        youtubeExplode: fakeYt,
        dio: dio,
      );

      final info = await fallbackExtractor.extractInfo('https://www.youtube.com/watch?v=dQw4w9WgXcQ');

      expect(info.id, 'dQw4w9WgXcQ');
      expect(info.title, 'Rick Astley - Never Gonna Give You Up (Official Video)');
      expect(info.uploader, 'Rick Astley');
      expect(info.thumbnailUrl, 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
      expect(info.platform, PlatformType.youtube);

      fallbackExtractor.close();
    });

    test('falls back to oEmbed on shorts when scraping fails', () async {
      final fakeYt = _FakeYoutubeExplode(
        videos: _FakeVideoClient(
          getHandler: (id) => throw YoutubeExplodeException('Watch page bot check blocked'),
        ),
      );

      final dio = Dio()
        ..httpClientAdapter = _MockHttpClientAdapter((options) async {
          final responseJson = jsonEncode({
            'title': 'Viral YouTube Short',
            'author_name': 'Popular Creator',
            'thumbnail_url': 'https://i.ytimg.com/vi/3i_b7Xp08kU/hqdefault.jpg',
          });

          return ResponseBody.fromString(
            responseJson,
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

      final fallbackExtractor = YoutubeExtractor(
        youtubeExplode: fakeYt,
        dio: dio,
      );

      final info = await fallbackExtractor.extractInfo('https://www.youtube.com/shorts/3i_b7Xp08kU?si=abc');

      expect(info.id, '3i_b7Xp08kU');
      expect(info.title, 'Viral YouTube Short');
      expect(info.uploader, 'Popular Creator');
      expect(info.platform, PlatformType.youtube);

      fallbackExtractor.close();
    });

    test('throws VideoUnavailableException when both _yt and oEmbed fail', () async {
      final fakeYt = _FakeYoutubeExplode(
        videos: _FakeVideoClient(
          getHandler: (id) => throw VideoUnavailableException('Private video'),
        ),
      );

      final dio = Dio()
        ..httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString(
            'Not Found',
            404,
            headers: {
              Headers.contentTypeHeader: [Headers.textPlainContentType],
            },
          );
        });

      final fallbackExtractor = YoutubeExtractor(
        youtubeExplode: fakeYt,
        dio: dio,
      );

      expect(
        () => fallbackExtractor.extractInfo('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        throwsA(isA<Exception>()),
      );

      fallbackExtractor.close();
    });
  });

  group('YoutubeExtractor - In-Memory Manifest Caching & Fast-Path', () {
    test('fetches manifest from network on first call and caches it', () async {
      final fakeStreams = _FakeStreamClient(
        getManifestHandler: (id) async => _createTestManifest(videoId: id.toString()),
      );
      final fakeYt = _FakeYoutubeExplode(
        videos: _FakeVideoClient(streamsClient: fakeStreams),
      );
      final cachedExtractor = YoutubeExtractor(youtubeExplode: fakeYt);

      final streams = await cachedExtractor.getStreams('https://www.youtube.com/watch?v=dQw4w9WgXcQ');

      expect(streams, isNotEmpty);
      expect(streams.first.qualityLabel, '720p');
      expect(fakeStreams.getManifestCallCount, equals(1));

      cachedExtractor.close();
    });

    test('repeated calls to getStreams return cached results without re-invoking network client', () async {
      final fakeStreams = _FakeStreamClient(
        getManifestHandler: (id) async => _createTestManifest(videoId: id.toString()),
      );
      final fakeYt = _FakeYoutubeExplode(
        videos: _FakeVideoClient(streamsClient: fakeStreams),
      );
      final cachedExtractor = YoutubeExtractor(youtubeExplode: fakeYt);

      // Call 1: Fetches from network
      final streams1 = await cachedExtractor.getStreams('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(fakeStreams.getManifestCallCount, equals(1));
      expect(streams1.first.url, 'https://example.com/stream.mp4');

      // Call 2: Standard watch URL (should hit cache)
      final streams2 = await cachedExtractor.getStreams('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(fakeStreams.getManifestCallCount, equals(1));
      expect(streams2.first.url, streams1.first.url);

      // Call 3: youtu.be short URL for same video ID (should hit cache)
      final streams3 = await cachedExtractor.getStreams('https://youtu.be/dQw4w9WgXcQ?feature=share');
      expect(fakeStreams.getManifestCallCount, equals(1));
      expect(streams3.first.url, streams1.first.url);

      // Call 4: /shorts/ URL for same video ID (should hit cache)
      final streams4 = await cachedExtractor.getStreams('https://www.youtube.com/shorts/dQw4w9WgXcQ');
      expect(fakeStreams.getManifestCallCount, equals(1));
      expect(streams4.first.url, streams1.first.url);

      cachedExtractor.close();
    });

    test('clearCache() invalidates cached manifest and triggers fresh network request', () async {
      final fakeStreams = _FakeStreamClient(
        getManifestHandler: (id) async => _createTestManifest(videoId: id.toString()),
      );
      final fakeYt = _FakeYoutubeExplode(
        videos: _FakeVideoClient(streamsClient: fakeStreams),
      );
      final cachedExtractor = YoutubeExtractor(youtubeExplode: fakeYt);

      await cachedExtractor.getStreams('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(fakeStreams.getManifestCallCount, equals(1));

      // Invalidate cache statically
      YoutubeExtractor.clearCache();

      // Next call should invoke network client again
      await cachedExtractor.getStreams('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(fakeStreams.getManifestCallCount, equals(2));

      // Invalidate cache via instance method
      cachedExtractor.clearManifestCache();

      // Next call should invoke network client a third time
      await cachedExtractor.getStreams('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(fakeStreams.getManifestCallCount, equals(3));

      cachedExtractor.close();
    });

    test('different video IDs are cached independently', () async {
      final fakeStreams = _FakeStreamClient(
        getManifestHandler: (id) async => _createTestManifest(
          videoId: id.toString(),
          url: 'https://example.com/$id.mp4',
        ),
      );
      final fakeYt = _FakeYoutubeExplode(
        videos: _FakeVideoClient(streamsClient: fakeStreams),
      );
      final cachedExtractor = YoutubeExtractor(youtubeExplode: fakeYt);

      // Video 1
      final v1Streams = await cachedExtractor.getStreams('https://www.youtube.com/watch?v=videoOne123');
      expect(fakeStreams.getManifestCallCount, equals(1));
      expect(v1Streams.first.url, 'https://example.com/videoOne123.mp4');

      // Video 2
      final v2Streams = await cachedExtractor.getStreams('https://www.youtube.com/watch?v=videoTwo456');
      expect(fakeStreams.getManifestCallCount, equals(2));
      expect(v2Streams.first.url, 'https://example.com/videoTwo456.mp4');

      // Video 1 again - must be served from cache
      final v1StreamsCached = await cachedExtractor.getStreams('https://youtu.be/videoOne123');
      expect(fakeStreams.getManifestCallCount, equals(2));
      expect(v1StreamsCached.first.url, 'https://example.com/videoOne123.mp4');

      cachedExtractor.close();
    });
  });
}
