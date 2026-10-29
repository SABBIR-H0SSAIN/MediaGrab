import '../../domain/entities/media_info.dart';
import '../../domain/entities/playlist_info.dart';
import '../../domain/entities/stream_info.dart';

/// Base contract for platform-specific media extractors.
abstract class BaseExtractor {
  /// Checks whether this extractor can handle the provided [url].
  bool canHandle(String url);

  /// Extracts media metadata from the given [url].
  Future<MediaInfo> extractInfo(String url);

  /// Retrieves all available downloadable streams for the media at [url].
  Future<List<StreamInfo>> getStreams(String url);

  /// Extracts playlist metadata and videos if the URL is a playlist.
  Future<PlaylistInfo?> extractPlaylist(String url) async => null;

  /// Releases any underlying network or system resources.
  void close() {}
}
