import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/extractor/data/extractors/instagram_extractor.dart';

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

void main() {
  late InstagramExtractor extractor;

  setUp(() {
    extractor = InstagramExtractor();
  });

  tearDown(() {
    extractor.close();
  });

  group('InstagramExtractor - URL Detection & Shortcode Extraction', () {
    test('canHandle identifies Instagram URLs accurately', () {
      expect(
        extractor.canHandle('https://www.instagram.com/reel/DA12345/'),
        isTrue,
      );
      expect(
        extractor.canHandle(
          'https://instagram.com/reel/DA12345?igsh=MXFjMzg1NQ==',
        ),
        isTrue,
      );
      expect(
        extractor.canHandle('https://www.instagram.com/reels/DA12345/'),
        isTrue,
      );
      expect(
        extractor.canHandle('https://www.instagram.com/p/Cxyz123/'),
        isTrue,
      );
      expect(
        extractor.canHandle(
          'https://www.instagram.com/p/Cxyz123/?utm_source=ig_web_copy_link',
        ),
        isTrue,
      );
      expect(
        extractor.canHandle('https://www.instagram.com/tv/Cxyz123/'),
        isTrue,
      );
      expect(extractor.canHandle('https://instagr.am/p/Cxyz123/'), isTrue);

      // Non-Instagram URLs
      expect(
        extractor.canHandle('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        isFalse,
      );
      expect(
        extractor.canHandle('https://www.facebook.com/reel/1234567890/'),
        isFalse,
      );
      expect(extractor.canHandle('https://example.com/video.mp4'), isFalse);
    });

    test(
      'extractShortcode extracts shortcode across Instagram URL variations',
      () {
        expect(
          extractor.extractShortcode('https://www.instagram.com/reel/DA12345/'),
          'DA12345',
        );
        expect(
          extractor.extractShortcode(
            'https://www.instagram.com/reels/DA12345/?igsh=abc123xyz',
          ),
          'DA12345',
        );
        expect(
          extractor.extractShortcode(
            'https://www.instagram.com/p/Cxyz123/?utm_source=ig_web_copy_link',
          ),
          'Cxyz123',
        );
        expect(
          extractor.extractShortcode('https://instagram.com/tv/Cxyz123/'),
          'Cxyz123',
        );
        expect(extractor.extractShortcode('DA12345678'), 'DA12345678');
        expect(extractor.extractShortcode(''), isNull);
      },
    );
  });

  group('InstagramExtractor - MediaInfo & Streams Extraction', () {
    test(
      'extractInfo extracts caption, uploader, thumbnail, and duration from embed HTML',
      () async {
        const mockEmbedHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta property="og:title" content="Creator on Instagram: &quot;Behind the scenes of our new project!&quot;" />
  <meta property="og:image" content="https://scontent.cdninstagram.com/v/thumb.jpg" />
  <meta property="og:description" content="Behind the scenes of our new project!" />
</head>
<body>
  <div class="Caption">Behind the scenes of our new project!</div>
  <a class="CaptionUsername">project_creator</a>
  <img class="EmbeddedMediaImage" src="https://scontent.cdninstagram.com/v/thumb.jpg" />
  <script>
    var payload = {"video_duration": 18.2};
  </script>
</body>
</html>
''';

        final dio =
            Dio()
              ..httpClientAdapter = _MockHttpClientAdapter((options) async {
                expect(options.path, contains('/embed/captioned/'));
                return ResponseBody.fromString(
                  mockEmbedHtml,
                  200,
                  headers: {
                    Headers.contentTypeHeader: [Headers.textPlainContentType],
                  },
                );
              });

        final igExtractor = InstagramExtractor(dio: dio);
        final info = await igExtractor.extractInfo(
          'https://www.instagram.com/reel/DA12345/?igsh=abc',
        );

        expect(info.id, 'DA12345');
        expect(info.title, 'Behind the scenes of our new project!');
        expect(
          info.thumbnailUrl,
          'https://scontent.cdninstagram.com/v/thumb.jpg',
        );
        expect(info.uploader, 'project_creator');
        expect(info.duration.inSeconds, 18);
        expect(info.platform, PlatformType.instagram);

        igExtractor.close();
      },
    );

    test(
      'getStreams extracts HD MP4 and Audio streams with clean unescaped URLs',
      () async {
        const mockEmbedHtml = '''
<!DOCTYPE html>
<html>
<head></head>
<body>
<script>
  window.__additionalDataLoaded('/p/DA12345/', {
    "shortcode_media": {
      "video_url": "https:\\/\\/scontent.cdninstagram.com\\/v\\/t50.2886-16\\/reel_video.mp4?oh=abc\\u0026oe=def"
    }
  });
</script>
</body>
</html>
''';

        final dio =
            Dio()
              ..httpClientAdapter = _MockHttpClientAdapter((options) async {
                return ResponseBody.fromString(
                  mockEmbedHtml,
                  200,
                  headers: {
                    Headers.contentTypeHeader: [Headers.textPlainContentType],
                  },
                );
              });

        final igExtractor = InstagramExtractor(dio: dio);
        final streams = await igExtractor.getStreams(
          'https://www.instagram.com/reel/DA12345/',
        );

        expect(streams.length, 2);

        final videoStream = streams.firstWhere((s) => !s.isAudioOnly);
        expect(
          videoStream.url,
          'https://scontent.cdninstagram.com/v/t50.2886-16/reel_video.mp4?oh=abc&oe=def',
        );
        expect(videoStream.qualityLabel, 'Original');
        expect(videoStream.videoHeight, isNull);
        expect(videoStream.container, 'mp4');

        final audioStream = streams.firstWhere((s) => s.isAudioOnly);
        expect(audioStream.qualityLabel, 'Extract audio');
        expect(audioStream.url, videoStream.url);

        igExtractor.close();
      },
    );

    test(
      'getStreams falls back to og:video tag if JSON payload is missing',
      () async {
        const mockHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta property="og:video" content="https://scontent.cdninstagram.com/v/t50/fallback_reel.mp4" />
</head>
<body></body>
</html>
''';

        final dio =
            Dio()
              ..httpClientAdapter = _MockHttpClientAdapter((options) async {
                return ResponseBody.fromString(
                  mockHtml,
                  200,
                  headers: {
                    Headers.contentTypeHeader: [Headers.textPlainContentType],
                  },
                );
              });

        final igExtractor = InstagramExtractor(dio: dio);
        final streams = await igExtractor.getStreams(
          'https://www.instagram.com/p/Cxyz123/',
        );

        expect(streams.isNotEmpty, isTrue);
        expect(
          streams.first.url,
          'https://scontent.cdninstagram.com/v/t50/fallback_reel.mp4',
        );

        igExtractor.close();
      },
    );

    test(
      'getStreams throws StateError when no stream is found in embed or direct page',
      () async {
        const mockEmptyHtml =
            '<html><body><div>No media found</div></body></html>';

        final dio =
            Dio()
              ..httpClientAdapter = _MockHttpClientAdapter((options) async {
                return ResponseBody.fromString(
                  mockEmptyHtml,
                  200,
                  headers: {
                    Headers.contentTypeHeader: [Headers.textPlainContentType],
                  },
                );
              });

        final igExtractor = InstagramExtractor(dio: dio);

        expect(
          () =>
              igExtractor.getStreams('https://www.instagram.com/reel/DA12345/'),
          throwsA(isA<StateError>()),
        );

        igExtractor.close();
      },
    );
  });
}
