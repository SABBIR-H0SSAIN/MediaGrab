import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';

void main() {
  group('MediaInfo Entity', () {
    test('supports value equality via Equatable', () {
      final uploadDate = DateTime(2025, 5, 20);
      final media1 = MediaInfo(
        id: 'dQw4w9WgXcQ',
        title: 'Rick Astley - Never Gonna Give You Up',
        thumbnailUrl: 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        duration: const Duration(minutes: 3, seconds: 32),
        uploader: 'Rick Astley',
        platform: PlatformType.youtube,
        uploadDate: uploadDate,
        viewCount: 1500000000,
        description: 'The official music video',
      );

      final media2 = MediaInfo(
        id: 'dQw4w9WgXcQ',
        title: 'Rick Astley - Never Gonna Give You Up',
        thumbnailUrl: 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        duration: const Duration(minutes: 3, seconds: 32),
        uploader: 'Rick Astley',
        platform: PlatformType.youtube,
        uploadDate: uploadDate,
        viewCount: 1500000000,
        description: 'The official music video',
      );

      expect(media1, equals(media2));
    });

    test('formats duration correctly for short and long media', () {
      const shortMedia = MediaInfo(
        id: '1',
        title: 'Short',
        thumbnailUrl: 'http://img.com',
        duration: Duration(minutes: 4, seconds: 7),
        uploader: 'User',
        platform: PlatformType.youtube,
      );
      expect(shortMedia.formattedDuration, '4:07');

      const secondsOnlyMedia = MediaInfo(
        id: '2',
        title: 'Seconds',
        thumbnailUrl: 'http://img.com',
        duration: Duration(seconds: 45),
        uploader: 'User',
        platform: PlatformType.youtube,
      );
      expect(secondsOnlyMedia.formattedDuration, '0:45');

      const longMedia = MediaInfo(
        id: '3',
        title: 'Long',
        thumbnailUrl: 'http://img.com',
        duration: Duration(hours: 2, minutes: 15, seconds: 30),
        uploader: 'User',
        platform: PlatformType.youtube,
      );
      expect(longMedia.formattedDuration, '2:15:30');
    });

    test('formats view counts into readable human strings', () {
      const billionViews = MediaInfo(
        id: '1',
        title: '1',
        thumbnailUrl: '',
        duration: Duration.zero,
        uploader: '',
        platform: PlatformType.youtube,
        viewCount: 1500000000,
      );
      expect(billionViews.formattedViews, '1.5B views');

      const millionViews = MediaInfo(
        id: '2',
        title: '2',
        thumbnailUrl: '',
        duration: Duration.zero,
        uploader: '',
        platform: PlatformType.youtube,
        viewCount: 4200000,
      );
      expect(millionViews.formattedViews, '4.2M views');

      const thousandViews = MediaInfo(
        id: '3',
        title: '3',
        thumbnailUrl: '',
        duration: Duration.zero,
        uploader: '',
        platform: PlatformType.youtube,
        viewCount: 35000,
      );
      expect(thousandViews.formattedViews, '35K views');

      const smallViews = MediaInfo(
        id: '4',
        title: '4',
        thumbnailUrl: '',
        duration: Duration.zero,
        uploader: '',
        platform: PlatformType.youtube,
        viewCount: 850,
      );
      expect(smallViews.formattedViews, '850 views');

      const nullViews = MediaInfo(
        id: '5',
        title: '5',
        thumbnailUrl: '',
        duration: Duration.zero,
        uploader: '',
        platform: PlatformType.youtube,
      );
      expect(nullViews.formattedViews, '');
    });
  });
}
