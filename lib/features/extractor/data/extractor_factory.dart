import 'extractors/base_extractor.dart';
import 'extractors/facebook_extractor.dart';
import 'extractors/instagram_extractor.dart';
import 'extractors/youtube_extractor.dart';

/// Registry and factory for resolving the appropriate [BaseExtractor] for a given media URL.
class ExtractorFactory {
  final List<BaseExtractor> _extractors;

  ExtractorFactory({List<BaseExtractor>? extractors})
    : _extractors =
          extractors ??
          [
            YoutubeExtractor(),
            FacebookExtractor(),
            InstagramExtractor(),
          ];

  /// Returns a matching [BaseExtractor] for the given [url], or null if unsupported.
  BaseExtractor? getExtractor(String url) {
    for (final extractor in _extractors) {
      if (extractor.canHandle(url)) {
        return extractor;
      }
    }
    return null;
  }

  /// Returns a matching [BaseExtractor] or throws [UnsupportedError] if unsupported.
  BaseExtractor getExtractorOrThrow(String url) {
    final extractor = getExtractor(url);
    if (extractor == null) {
      throw UnsupportedError('No extractor available for URL: $url');
    }
    return extractor;
  }

  /// Closes all managed extractors.
  void close() {
    for (final extractor in _extractors) {
      extractor.close();
    }
  }
}
