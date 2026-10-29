import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import '../../../../core/utils/url_parser.dart';
import '../../domain/entities/media_info.dart';
import '../../domain/entities/stream_info.dart';
import 'base_extractor.dart';
import 'social_stream_parser.dart';

/// Instagram implementation of [BaseExtractor] capable of extracting reels,
/// posts, and IGTV videos using embed and public page scraping.
class InstagramExtractor extends BaseExtractor {
  final Dio _dio;
  final bool _shouldCloseDio;

  // Simple in-memory cache of last fetched HTML payload
  String? _cachedUrl;
  String? _cachedHtml;

  InstagramExtractor({Dio? dio})
    : _dio = dio ?? Dio(),
      _shouldCloseDio = dio == null;

  @override
  bool canHandle(String url) {
    return detectPlatform(url) == PlatformType.instagram;
  }

  /// Extracts Instagram shortcode (e.g. "Cxyz123") from URL.
  String? extractShortcode(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    final match = RegExp(
      r'(?:/p/|/reel/|/reels/|/tv/)([a-zA-Z0-9_-]+)',
      caseSensitive: false,
    ).firstMatch(trimmed);

    if (match != null) return match.group(1);

    // Check if directly a shortcode (e.g. 9-15 alphanumeric characters)
    if (RegExp(r'^[a-zA-Z0-9_-]{9,15}$').hasMatch(trimmed)) {
      return trimmed;
    }

    return null;
  }

  @override
  Future<MediaInfo> extractInfo(String url) async {
    final shortcode = extractShortcode(url);
    if (shortcode == null) {
      throw ArgumentError('Invalid Instagram URL: $url');
    }

    final html = await _fetchPageHtml(url, shortcode);
    final document = html_parser.parse(html);

    // 1. Caption / Title
    String? title;
    final captionElem =
        document.querySelector('div.Caption') ??
        document.querySelector('a.Caption');
    if (captionElem != null && captionElem.text.trim().isNotEmpty) {
      title = captionElem.text.trim();
    }
    if (title == null || title.isEmpty) {
      title =
          document
              .querySelector('meta[property="og:title"]')
              ?.attributes['content'];
    }
    if (title == null || title.isEmpty) {
      title =
          document
              .querySelector('meta[property="og:description"]')
              ?.attributes['content'];
    }
    if (title == null || title.isEmpty) {
      final captionMatch = RegExp(
        r'''["']caption["']\s*:\s*\{[^}]*?["']text["']\s*:\s*["']([^"']+)["']''',
      ).firstMatch(html);
      if (captionMatch != null) {
        title = _cleanText(captionMatch.group(1)!);
      }
    }
    if (title == null ||
        title.trim().isEmpty ||
        title.trim() == 'Instagram' ||
        title.toLowerCase().contains('log in')) {
      title = 'Instagram Reel ($shortcode)';
    } else {
      title = _cleanText(title);
    }

    // 2. Thumbnail
    String? thumb =
        document
            .querySelector('meta[property="og:image"]')
            ?.attributes['content'];
    if (thumb == null || thumb.isEmpty) {
      thumb =
          document.querySelector('img.EmbeddedMediaImage')?.attributes['src'];
    }
    if (thumb == null || thumb.isEmpty) {
      final thumbMatch = RegExp(
        r'''["'](?:thumbnail_src|display_url)["']\s*:\s*["']([^"']+)["']''',
      ).firstMatch(html);
      if (thumbMatch != null) {
        thumb = _cleanUrl(thumbMatch.group(1)!);
      }
    }
    if (thumb == null || thumb.isEmpty) {
      thumb = 'https://instagram.com/p/$shortcode/media/?size=l';
    } else {
      thumb = _cleanUrl(thumb);
    }

    // 3. Uploader
    String uploader = 'Instagram User';
    final userElem =
        document.querySelector('a.CaptionUsername') ??
        document.querySelector('.Username');
    if (userElem != null && userElem.text.trim().isNotEmpty) {
      uploader = userElem.text.trim();
    } else {
      final userMatch = RegExp(
        r'''["']owner["']\s*:\s*\{[^}]*?["']username["']\s*:\s*["']([^"']+)["']''',
      ).firstMatch(html);
      if (userMatch != null) {
        uploader = userMatch.group(1)!;
      } else {
        // e.g. "Name (@username) on Instagram: ..."
        final ogTitle =
            document
                .querySelector('meta[property="og:title"]')
                ?.attributes['content'];
        if (ogTitle != null) {
          final authorMatch = RegExp(
            r'^(.*?)\s+on Instagram',
          ).firstMatch(ogTitle);
          if (authorMatch != null) {
            uploader = authorMatch.group(1)!.trim();
          }
        }
      }
    }

    // 4. Duration
    Duration duration = Duration.zero;
    final durMatch = RegExp(
      r'''["']video_duration["']\s*:\s*([0-9.]+)''',
    ).firstMatch(html);
    if (durMatch != null) {
      final sec = double.tryParse(durMatch.group(1)!);
      if (sec != null) {
        duration = Duration(milliseconds: (sec * 1000).round());
      }
    }

    // 5. Description
    final description =
        document
            .querySelector('meta[property="og:description"]')
            ?.attributes['content'];

    return MediaInfo(
      id: shortcode,
      title: title,
      thumbnailUrl: thumb,
      duration: duration,
      uploader: uploader,
      platform: PlatformType.instagram,
      description: description,
    );
  }

  @override
  Future<List<StreamInfo>> getStreams(String url) async {
    final shortcode = extractShortcode(url);
    if (shortcode == null) {
      throw ArgumentError('Invalid Instagram URL: $url');
    }

    final source = await _fetchPageHtml(url, shortcode);
    final parser = SocialStreamParser();
    void parse(String page) {
      parser.parsePage(page, mediaId: shortcode);
      if (!parser.streams.any((stream) => !stream.isAudioOnly)) {
        final fallback = _findVideoStreamUrl(page);
        if (fallback != null) {
          final document = html_parser.parse(page);
          parser.addProgressive(
            _cleanUrl(fallback),
            width: int.tryParse(
              document
                      .querySelector('meta[property="og:video:width"]')
                      ?.attributes['content'] ??
                  '',
            ),
            height: int.tryParse(
              document
                      .querySelector('meta[property="og:video:height"]')
                      ?.attributes['content'] ??
                  '',
            ),
          );
        }
      }
    }

    parse(source);
    // Embed pages often expose only one rendition. The public page can include
    // video_versions and video_dash_manifest with higher-resolution tracks.
    try {
      parse(await _fetchDirectPage(shortcode));
    } catch (_) {}
    await parser.loadManifests(_dio);
    final streams = parser.finish();
    if (!streams.any((stream) => !stream.isAudioOnly)) {
      throw StateError(
        'No playable video stream found for Instagram URL: $url',
      );
    }
    return streams;
  }

  String? _findVideoStreamUrl(String html) {
    final patterns = [
      RegExp(r'''["']video_url["']\s*:\s*["']([^"']+)["']'''),
      RegExp(r'''["']browser_native_hd_url["']\s*:\s*["']([^"']+)["']'''),
      RegExp(r'''["']browser_native_sd_url["']\s*:\s*["']([^"']+)["']'''),
      RegExp(
        r'''["']video_versions["']\s*:\s*\[\s*\{[^}]*?["']url["']\s*:\s*["']([^"']+)["']''',
      ),
      RegExp(r'''<video[^>]+src=["']([^"']+)["']'''),
      RegExp(r'''<source[^>]+src=["']([^"']+)["']'''),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null) {
        return match.group(1);
      }
    }

    final document = html_parser.parse(html);
    final ogVideo =
        document
            .querySelector('meta[property="og:video"]')
            ?.attributes['content'] ??
        document
            .querySelector('meta[property="og:video:url"]')
            ?.attributes['content'] ??
        document
            .querySelector('meta[property="og:video:secure_url"]')
            ?.attributes['content'];

    if (ogVideo != null && ogVideo.isNotEmpty) {
      return ogVideo;
    }

    return null;
  }

  Future<String> _fetchPageHtml(String url, String shortcode) async {
    if (_cachedUrl == url && _cachedHtml != null) {
      return _cachedHtml!;
    }

    final embedUrl = 'https://www.instagram.com/p/$shortcode/embed/captioned/';
    try {
      final html = await _getHtml(embedUrl);
      _cachedUrl = url;
      _cachedHtml = html;
      return html;
    } catch (_) {
      // Fallback to direct page if embed fails
      final directHtml = await _fetchDirectPage(shortcode);
      _cachedUrl = url;
      _cachedHtml = directHtml;
      return directHtml;
    }
  }

  Future<String> _fetchDirectPage(String shortcode) async {
    final directUrl = 'https://www.instagram.com/reel/$shortcode/';
    return _getHtml(directUrl);
  }

  Future<String> _getHtml(String url) async {
    final response = await _dio.get<String>(
      url,
      options: Options(
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
          'Sec-Fetch-Mode': 'navigate',
        },
        followRedirects: true,
        maxRedirects: 5,
        responseType: ResponseType.plain,
      ),
    );

    return response.data ?? '';
  }

  String _cleanUrl(String raw) {
    return raw
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u0026', '&')
        .replaceAll('&amp;', '&');
  }

  String _cleanText(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  @override
  void close() {
    if (_shouldCloseDio) {
      _dio.close();
    }
  }
}
