import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/extractor/data/extractors/facebook_extractor.dart';

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
  late FacebookExtractor extractor;

  setUp(() {
    extractor = FacebookExtractor();
  });

  tearDown(() {
    extractor.close();
  });

  group('FacebookExtractor - URL Detection & ID Extraction', () {
    test('canHandle identifies Facebook URLs accurately', () {
      expect(
        extractor.canHandle('https://www.facebook.com/reel/1234567890/'),
        isTrue,
      );
      expect(
        extractor.canHandle(
          'https://facebook.com/reels/1234567890/?mibextid=123',
        ),
        isTrue,
      );
      expect(
        extractor.canHandle('https://www.facebook.com/watch/?v=1234567890'),
        isTrue,
      );
      expect(extractor.canHandle('https://fb.watch/mXz817_oLk/'), isTrue);
      expect(extractor.canHandle('https://fb.com/watch?v=1234567890'), isTrue);
      expect(
        extractor.canHandle('https://www.facebook.com/share/r/1234567890/'),
        isTrue,
      );
      expect(
        extractor.canHandle('https://www.facebook.com/share/v/1234567890/'),
        isTrue,
      );
      expect(
        extractor.canHandle(
          'https://m.facebook.com/story.php?story_fbid=1234567890',
        ),
        isTrue,
      );

      // Non-Facebook URLs
      expect(
        extractor.canHandle('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        isFalse,
      );
      expect(
        extractor.canHandle('https://www.instagram.com/reel/Cxyz123/'),
        isFalse,
      );
      expect(extractor.canHandle('https://example.com/video.mp4'), isFalse);
    });

    test(
      'extractVideoId extracts identifier across various Facebook URL patterns',
      () {
        expect(
          extractor.extractVideoId('https://www.facebook.com/reel/9876543210/'),
          '9876543210',
        );
        expect(
          extractor.extractVideoId(
            'https://facebook.com/reels/9876543210/?mibextid=abc',
          ),
          '9876543210',
        );
        expect(
          extractor.extractVideoId(
            'https://www.facebook.com/watch/?v=1122334455&ref=sharing',
          ),
          '1122334455',
        );
        expect(
          extractor.extractVideoId(
            'https://www.facebook.com/user/videos/5544332211/',
          ),
          '5544332211',
        );
        expect(
          extractor.extractVideoId('https://fb.watch/mXz817_oLk/'),
          'mXz817_oLk',
        );
        expect(
          extractor.extractVideoId(
            'https://www.facebook.com/share/r/rShared123/',
          ),
          'rShared123',
        );
      },
    );
  });

  group('FacebookExtractor - MediaInfo & Streams Extraction', () {
    test(
      'extractInfo extracts metadata from Facebook OpenGraph and JSON tags',
      () async {
        const mockHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta property="og:title" content="Awesome Facebook Reel Video" />
  <meta property="og:image" content="https://scontent.xx.fbcdn.net/v/t15/thumb.jpg" />
  <meta property="og:video:duration" content="45.5" />
  <meta property="og:description" content="Check out this viral Facebook reel video!" />
  <meta property="og:site_name" content="Facebook Page Creator" />
</head>
<body>
</body>
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

        final fbExtractor = FacebookExtractor(dio: dio);
        final info = await fbExtractor.extractInfo(
          'https://www.facebook.com/reel/1234567890/',
        );

        expect(info.id, '1234567890');
        expect(info.title, 'Awesome Facebook Reel Video');
        expect(
          info.thumbnailUrl,
          'https://scontent.xx.fbcdn.net/v/t15/thumb.jpg',
        );
        expect(info.duration.inSeconds, 45);
        expect(info.uploader, 'Facebook Page Creator');
        expect(info.platform, PlatformType.facebook);
        expect(info.description, 'Check out this viral Facebook reel video!');

        fbExtractor.close();
      },
    );

    test(
      'getStreams extracts HD, SD, and Audio streams with clean unescaped URLs',
      () async {
        const mockHtml = '''
<!DOCTYPE html>
<html>
<head></head>
<body>
<script>
  requireLazy(["ScheduledApplyEach"], function() {
    var payload = {
      "playable_url_quality_hd": "https:\\/\\/video.xx.fbcdn.net\\/v\\/hd_video.mp4?oh=123\\u0026oe=456",
      "playable_url": "https:\\/\\/video.xx.fbcdn.net\\/v\\/sd_video.mp4?oh=123\\u0026oe=456"
    };
  });
</script>
</body>
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

        final fbExtractor = FacebookExtractor(dio: dio);
        final streams = await fbExtractor.getStreams(
          'https://www.facebook.com/reel/1234567890/',
        );

        expect(streams.length, 3);

        final hdStream = streams.firstWhere((s) => s.qualityLabel == 'HD');
        expect(
          hdStream.url,
          'https://video.xx.fbcdn.net/v/hd_video.mp4?oh=123&oe=456',
        );
        expect(hdStream.container, 'mp4');
        expect(hdStream.isAudioOnly, isFalse);
        expect(hdStream.videoHeight, isNull);

        final sdStream = streams.firstWhere((s) => s.qualityLabel == 'SD');
        expect(
          sdStream.url,
          'https://video.xx.fbcdn.net/v/sd_video.mp4?oh=123&oe=456',
        );
        expect(sdStream.isAudioOnly, isFalse);
        expect(sdStream.videoHeight, isNull);

        final audioStream = streams.firstWhere((s) => s.isAudioOnly);
        expect(audioStream.qualityLabel, 'Extract audio');
        expect(audioStream.url, hdStream.url);

        fbExtractor.close();
      },
    );

    test(
      'getStreams falls back to og:video tag when JSON urls are absent',
      () async {
        const mockHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta property="og:video" content="https://video.xx.fbcdn.net/v/fallback.mp4" />
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

        final fbExtractor = FacebookExtractor(dio: dio);
        final streams = await fbExtractor.getStreams(
          'https://fb.watch/mXz817_oLk/',
        );

        expect(streams.isNotEmpty, isTrue);
        expect(streams.first.url, 'https://video.xx.fbcdn.net/v/fallback.mp4');

        fbExtractor.close();
      },
    );

    test(
      'getStreams throws StateError when no stream is present in HTML',
      () async {
        const mockHtml = '<html><body><p>Video unavailable</p></body></html>';

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

        final fbExtractor = FacebookExtractor(dio: dio);

        expect(
          () => fbExtractor.getStreams(
            'https://www.facebook.com/reel/1234567890/',
          ),
          throwsA(isA<StateError>()),
        );

        fbExtractor.close();
      },
    );
  });
}
