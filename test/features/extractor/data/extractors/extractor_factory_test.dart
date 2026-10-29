import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/extractor/data/extractor_factory.dart';
import 'package:mediagrab/features/extractor/data/extractors/base_extractor.dart';
import 'package:mediagrab/features/extractor/data/extractors/facebook_extractor.dart';
import 'package:mediagrab/features/extractor/data/extractors/instagram_extractor.dart';
import 'package:mediagrab/features/extractor/data/extractors/youtube_extractor.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';

class _FakeExtractor extends BaseExtractor {
  final bool Function(String) handlePredicate;
  bool isClosed = false;

  _FakeExtractor(this.handlePredicate);

  @override
  bool canHandle(String url) => handlePredicate(url);

  @override
  Future<MediaInfo> extractInfo(String url) async {
    return const MediaInfo(
      id: 'fake',
      title: 'Fake Title',
      thumbnailUrl: '',
      duration: Duration.zero,
      uploader: 'Fake Uploader',
      platform: PlatformType.unknown,
    );
  }

  @override
  Future<List<StreamInfo>> getStreams(String url) async => [];

  @override
  void close() {
    isClosed = true;
  }
}

void main() {
  group('ExtractorFactory - Multi-Platform Resolution', () {
    late ExtractorFactory factory;

    setUp(() {
      factory = ExtractorFactory();
    });

    tearDown(() {
      factory.close();
    });

    test('resolves YoutubeExtractor for all YouTube URL variants', () {
      final youtubeUrls = [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtu.be/dQw4w9WgXcQ',
        'https://www.youtube.com/shorts/dQw4w9WgXcQ?si=abc',
        'https://www.youtube.com/live/dQw4w9WgXcQ',
        'https://www.youtube.com/playlist?list=PL12345',
      ];

      for (final url in youtubeUrls) {
        final extractor = factory.getExtractor(url);
        expect(extractor, isNotNull, reason: 'Failed for $url');
        expect(extractor, isA<YoutubeExtractor>(), reason: 'Failed for $url');
      }
    });

    test('resolves FacebookExtractor for Facebook reels, watch, and share URLs', () {
      final fbUrls = [
        'https://www.facebook.com/reel/1234567890/',
        'https://facebook.com/reels/1234567890/?mibextid=123',
        'https://www.facebook.com/watch/?v=1234567890',
        'https://fb.watch/mXz817_oLk/',
        'https://fb.com/watch?v=123',
        'https://www.facebook.com/share/r/1234567890/',
      ];

      for (final url in fbUrls) {
        final extractor = factory.getExtractor(url);
        expect(extractor, isNotNull, reason: 'Failed for $url');
        expect(extractor, isA<FacebookExtractor>(), reason: 'Failed for $url');
      }
    });

    test('resolves InstagramExtractor for Instagram reel, post, and tv URLs', () {
      final igUrls = [
        'https://www.instagram.com/reel/DA12345/',
        'https://instagram.com/reel/DA12345?igsh=MXFjMzg1NQ==',
        'https://www.instagram.com/reels/DA12345/',
        'https://www.instagram.com/p/Cxyz123/',
        'https://www.instagram.com/p/Cxyz123/?utm_source=ig_web_copy_link',
        'https://www.instagram.com/tv/Cxyz123/',
        'https://instagr.am/p/Cxyz123/',
      ];

      for (final url in igUrls) {
        final extractor = factory.getExtractor(url);
        expect(extractor, isNotNull, reason: 'Failed for $url');
        expect(extractor, isA<InstagramExtractor>(), reason: 'Failed for $url');
      }
    });

    test('returns null for unsupported URLs', () {
      expect(factory.getExtractor('https://example.com/video.mp4'), isNull);
      expect(factory.getExtractor('https://twitter.com/i/status/123'), isNull);
      expect(factory.getExtractor(''), isNull);
    });

    test('getExtractorOrThrow throws UnsupportedError for unsupported URLs', () {
      expect(
        () => factory.getExtractorOrThrow('https://example.com/unsupported'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('supports custom extractors and closes all registered extractors', () {
      final fake1 = _FakeExtractor((url) => url.contains('service1.com'));
      final fake2 = _FakeExtractor((url) => url.contains('service2.com'));

      final customFactory = ExtractorFactory(extractors: [fake1, fake2]);

      expect(customFactory.getExtractor('https://service1.com/v'), equals(fake1));
      expect(customFactory.getExtractor('https://service2.com/v'), equals(fake2));
      expect(customFactory.getExtractor('https://youtube.com/watch?v=123'), isNull);

      customFactory.close();
      expect(fake1.isClosed, isTrue);
      expect(fake2.isClosed, isTrue);
    });
  });
}
