import 'package:equatable/equatable.dart';
import 'media_info.dart';

/// Immutable entity representing an extracted media playlist.
class PlaylistInfo extends Equatable {
  final String id;
  final String title;
  final String? thumbnailUrl;
  final String author;
  final int videoCount;
  final List<MediaInfo> videos;

  const PlaylistInfo({
    required this.id,
    required this.title,
    this.thumbnailUrl,
    required this.author,
    required this.videoCount,
    this.videos = const [],
  });

  @override
  List<Object?> get props => [
    id,
    title,
    thumbnailUrl,
    author,
    videoCount,
    videos,
  ];
}
