import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/url_parser.dart';

void main() {
  group('url_parser - detectPlatform', () {
    test('returns unknown for empty or whitespace strings', () {
      expect(detectPlatform(''), PlatformType.unknown);
      expect(detectPlatform('   '), PlatformType.unknown);
    });

    test('returns unknown for non-media URLs or invalid text', () {
      expect(detectPlatform('hello world'), PlatformType.unknown);
      expect(detectPlatform('https://google.com'), PlatformType.unknown);
      expect(detectPlatform('https://vimeo.com/123456'), PlatformType.unknown);
      expect(
        detectPlatform('https://notfacebook.com/watch'),
        PlatformType.unknown,
      );
      expect(
        detectPlatform('https://notyoutube.com/watch?v=123'),
        PlatformType.unknown,
      );
      expect(
        detectPlatform('https://instagram.com/privacy'),
        PlatformType.unknown,
      );
      expect(
        detectPlatform('https://instagram.com/explore'),
        PlatformType.unknown,
      );
    });

    test('detects YouTube URLs correctly', () {
      final youtubeUrls = [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'http://youtube.com/watch?v=dQw4w9WgXcQ',
        'youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtu.be/dQw4w9WgXcQ',
        'youtu.be/dQw4w9WgXcQ',
        'https://www.youtube.com/shorts/3i_b7Xp08kU',
        'https://youtube.com/shorts/3i_b7Xp08kU?feature=share',
        'youtube.com/shorts/3i_b7Xp08kU',
        'https://www.youtube.com/playlist?list=PLrAXtmErZgOdP_8GztsuKi9nrraNbKKp4',
        'youtube.com/playlist?list=PL12345',
        'https://www.youtube.com/channel/UC_x5XG1OV2P6uZZ5FSM9Ttw',
        'youtube.com/channel/UC12345',
        'https://www.youtube.com/@mkbhd',
        'youtube.com/@mkbhd',
        'https://m.youtube.com',
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
        'm.youtube.com',
        'https://music.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtube.com/live/live_id_123',
        'https://www.youtube.com/live/live_id_123',
      ];

      for (final url in youtubeUrls) {
        expect(
          detectPlatform(url),
          PlatformType.youtube,
          reason: 'Failed for: $url',
        );
      }
    });

    test('detects Facebook URLs correctly', () {
      final facebookUrls = [
        'https://www.facebook.com/watch/?v=123456789',
        'https://facebook.com/reel/123456789',
        'facebook.com/watch?v=12345',
        'https://fb.watch/mXz817_oLk/',
        'fb.watch/mXz817_oLk',
        'https://fb.com/video/12345',
        'fb.com/watch?v=123',
        'https://m.facebook.com/story.php?story_fbid=123',
        'm.facebook.com/video',
        'https://web.facebook.com/watch/?v=123',
        'web.facebook.com/watch',
      ];

      for (final url in facebookUrls) {
        expect(
          detectPlatform(url),
          PlatformType.facebook,
          reason: 'Failed for: $url',
        );
      }
    });

    test('detects Instagram URLs correctly', () {
      final instagramUrls = [
        'https://www.instagram.com/p/Cxyz123/',
        'https://instagram.com/p/Cxyz123',
        'instagram.com/p/Cxyz123/',
        'https://www.instagram.com/reel/DA12345/',
        'https://instagram.com/reel/DA12345',
        'instagram.com/reel/DA12345/',
        'https://www.instagram.com/reels/DA12345/',
        'https://instagram.com/stories/username/1234567890/',
        'instagram.com/stories/username/1234567890/',
        'https://www.instagram.com/tv/Cxyz123/',
        'instagram.com/tv/Cxyz123/',
        'https://instagr.am/p/Cxyz123/',
        'https://instagr.am/reel/Cxyz123/',
      ];

      for (final url in instagramUrls) {
        expect(
          detectPlatform(url),
          PlatformType.instagram,
          reason: 'Failed for: $url',
        );
      }
    });

    test('PlatformTypeExtension properties work as expected', () {
      expect(PlatformType.youtube.displayName, 'YouTube');
      expect(PlatformType.facebook.displayName, 'Facebook');
      expect(PlatformType.instagram.displayName, 'Instagram');
      expect(PlatformType.unknown.displayName, 'Unknown');

      expect(PlatformType.youtube.isValid, isTrue);
      expect(PlatformType.facebook.isValid, isTrue);
      expect(PlatformType.instagram.isValid, isTrue);
      expect(PlatformType.unknown.isValid, isFalse);
    });
  });
}
