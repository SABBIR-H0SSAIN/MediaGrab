import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/extractor/data/extractors/youtube_extractor.dart';

void main() {
  late YoutubeExtractor extractor;

  setUp(() {
    extractor = YoutubeExtractor();
  });

  tearDown(() {
    extractor.close();
  });

  group('YoutubeExtractor URL Handling & ID Extraction', () {
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

    test(
      'extractVideoId extracts 11-character video ID from varied URL formats',
      () {
        const expectedId = 'dQw4w9WgXcQ';

        expect(
          extractor.extractVideoId(
            'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
          ),
          expectedId,
        );
        expect(
          extractor.extractVideoId('https://youtu.be/dQw4w9WgXcQ'),
          expectedId,
        );
        expect(
          extractor.extractVideoId(
            'https://www.youtube.com/shorts/dQw4w9WgXcQ?si=abcdef123',
          ),
          expectedId,
        );
        expect(
          extractor.extractVideoId('https://www.youtube.com/embed/dQw4w9WgXcQ'),
          expectedId,
        );
        expect(extractor.extractVideoId('dQw4w9WgXcQ'), expectedId);
        expect(extractor.extractVideoId(''), isNull);
        expect(extractor.extractVideoId('https://google.com'), isNull);
      },
    );

    test(
      'extractPlaylistId extracts playlist ID from playlist and watch URLs',
      () {
        const expectedList = 'PLrEnWoR732-DNXkZt3Rz-z2mF1u4nL123';

        expect(
          extractor.extractPlaylistId(
            'https://www.youtube.com/playlist?list=$expectedList',
          ),
          expectedList,
        );
        expect(
          extractor.extractPlaylistId(
            'https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=$expectedList',
          ),
          expectedList,
        );
        expect(
          extractor.extractPlaylistId(
            'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
          ),
          isNull,
        );
      },
    );
  });
}
