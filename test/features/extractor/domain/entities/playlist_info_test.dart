import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/playlist_info.dart';

void main() {
  group('PlaylistInfo Entity', () {
    test('supports value equality via Equatable', () {
      const video = MediaInfo(
        id: 'vid1',
        title: 'Video 1',
        thumbnailUrl: 'https://img.com/1.jpg',
        duration: Duration(minutes: 5),
        uploader: 'Artist',
        platform: PlatformType.youtube,
      );

      const playlist1 = PlaylistInfo(
        id: 'PL12345',
        title: 'My Favorite Playlist',
        thumbnailUrl: 'https://img.com/thumb.jpg',
        author: 'Artist',
        videoCount: 1,
        videos: [video],
      );

      const playlist2 = PlaylistInfo(
        id: 'PL12345',
        title: 'My Favorite Playlist',
        thumbnailUrl: 'https://img.com/thumb.jpg',
        author: 'Artist',
        videoCount: 1,
        videos: [video],
      );

      expect(playlist1, equals(playlist2));
      expect(playlist1.props, playlist2.props);
    });
  });
}
