import 'media_info.dart';
import 'stream_info.dart';

/// A reviewed selection. The source page URL is retained separately from CDN URLs.
class PreparedDownload {
  final String sourceUrl;
  final MediaInfo media;
  final StreamInfo stream;
  final StreamInfo? audioStream;

  const PreparedDownload({
    required this.sourceUrl,
    required this.media,
    required this.stream,
    this.audioStream,
  });
}
