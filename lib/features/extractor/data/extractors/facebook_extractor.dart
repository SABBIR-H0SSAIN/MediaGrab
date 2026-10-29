import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import '../../../../core/utils/url_parser.dart';
import '../../domain/entities/media_info.dart';
import '../../domain/entities/stream_info.dart';
import 'base_extractor.dart';
import 'social_stream_parser.dart';

/// Facebook implementation of [BaseExtractor] capable of extracting reels,
/// watch videos, and public shared posts with SD/HD streams.
class FacebookExtractor extends BaseExtractor {
  final Dio _dio;
  final bool _shouldCloseDio;

  // Simple in-memory cache of last fetched HTML payload to avoid duplicate requests
  String? _cachedUrl;
  String? _cachedHtml;

  FacebookExtractor({Dio? dio})
    : _dio = dio ?? Dio(),
      _shouldCloseDio = dio == null;

  @override
  bool canHandle(String url) {
    return detectPlatform(url) == PlatformType.facebook;
  }

  /// Extracts Facebook video or reel ID from URL.
  String extractVideoId(String url) {
    final trimmed = url.trim();

    // /reel/123456789 or /reels/123456789
    final reelMatch = RegExp(r'/reels?/([0-9]+)').firstMatch(trimmed);
    if (reelMatch != null) return reelMatch.group(1)!;

    // watch?v=123456789 or watch/?v=123456789
    final watchMatch = RegExp(r'[?&]v=([0-9]+)').firstMatch(trimmed);
    if (watchMatch != null) return watchMatch.group(1)!;

    // /videos/123456789
    final videoMatch = RegExp(r'/videos/([0-9]+)').firstMatch(trimmed);
    if (videoMatch != null) return videoMatch.group(1)!;

    // fb.watch/abc123_xyz
    final fbWatchMatch = RegExp(
      r'fb\.watch/([a-zA-Z0-9_-]+)',
    ).firstMatch(trimmed);
    if (fbWatchMatch != null) return fbWatchMatch.group(1)!;

    // /share/r/12345 or /share/v/12345
    final shareMatch = RegExp(
      r'/share/[rv]/([a-zA-Z0-9_-]+)',
    ).firstMatch(trimmed);
    if (shareMatch != null) return shareMatch.group(1)!;

    // Generic numeric ID in URL
    final genericNum = RegExp(r'(\d{10,20})').firstMatch(trimmed);
    if (genericNum != null) return genericNum.group(1)!;

    // Fallback: MD5 hash of the URL string
    return md5.convert(utf8.encode(trimmed)).toString().substring(0, 12);
  }

  @override
  Future<MediaInfo> extractInfo(String url) async {
    final html = await _fetchPageHtml(url);
    final videoId = extractVideoId(url);

    final document = html_parser.parse(html);

    // 1. Extract Title
    String? title =
        document
            .querySelector('meta[property="og:title"]')
            ?.attributes['content'];
    if (title == null || title.trim().isEmpty) {
      title =
          document
              .querySelector('meta[name="twitter:title"]')
              ?.attributes['content'];
    }
    if (title == null || title.trim().isEmpty) {
      title = document.querySelector('title')?.text;
    }
    if (title == null ||
        title.trim().isEmpty ||
        title.trim() == 'Facebook' ||
        title.toLowerCase().contains('log in')) {
      title = 'Facebook Video ($videoId)';
    } else {
      title = _cleanText(title);
    }

    // 2. Extract Thumbnail
    String? thumb =
        document
            .querySelector('meta[property="og:image"]')
            ?.attributes['content'];
    if (thumb == null || thumb.isEmpty) {
      thumb =
          document
              .querySelector('meta[property="og:image:url"]')
              ?.attributes['content'];
    }
    if (thumb == null || thumb.isEmpty) {
      thumb =
          document
              .querySelector('meta[name="twitter:image"]')
              ?.attributes['content'];
    }
    if (thumb == null || thumb.isEmpty) {
      final thumbMatch = RegExp(
        r'''["']preferred_thumbnail["']\s*:\s*\{["']image["']\s*:\s*\{["']uri["']\s*:\s*["']([^"']+)["']''',
      ).firstMatch(html);
      if (thumbMatch != null) {
        thumb = _cleanUrl(thumbMatch.group(1)!);
      }
    }

    // 3. Extract Uploader
    String uploader = 'Facebook User';
    final siteName =
        document
            .querySelector('meta[property="og:site_name"]')
            ?.attributes['content'];
    if (siteName != null &&
        siteName.isNotEmpty &&
        siteName.toLowerCase() != 'facebook') {
      uploader = siteName;
    }
    final ownerMatch = RegExp(
      r'''["']owner["']\s*:\s*\{[^}]*?["']name["']\s*:\s*["']([^"']+)["']''',
    ).firstMatch(html);
    if (ownerMatch != null) {
      uploader = _cleanText(ownerMatch.group(1)!);
    }

    // 4. Extract Duration
    Duration duration = Duration.zero;
    final ogDuration =
        document
            .querySelector('meta[property="og:video:duration"]')
            ?.attributes['content'];
    if (ogDuration != null) {
      final seconds = double.tryParse(ogDuration);
      if (seconds != null) {
        duration = Duration(milliseconds: (seconds * 1000).round());
      }
    }
    if (duration == Duration.zero) {
      final durMatch = RegExp(
        r'''["']playable_duration_in_ms["']\s*:\s*([0-9]+)''',
      ).firstMatch(html);
      if (durMatch != null) {
        final ms = int.tryParse(durMatch.group(1)!);
        if (ms != null) {
          duration = Duration(milliseconds: ms);
        }
      }
    }

    // 5. Description
    final description =
        document
            .querySelector('meta[property="og:description"]')
            ?.attributes['content'];

    return MediaInfo(
      id: videoId,
      title: title,
      thumbnailUrl: thumb ?? '',
      duration: duration,
      uploader: uploader,
      platform: PlatformType.facebook,
      description: description,
    );
  }

  @override
  Future<List<StreamInfo>> getStreams(String url) async {
    final source = await _fetchPageHtml(url);
    final parser =
        SocialStreamParser()..parsePage(source, mediaId: extractVideoId(url));
    // Preserve legacy public-page sources without inventing their resolution.
    if (!parser.streams.any((stream) => !stream.isAudioOnly)) {
      for (final key in [
        'playable_url_quality_hd',
        'browser_native_hd_url',
        'hd_src',
        'hd_src_no_ratelimit',
        'playable_url',
        'browser_native_sd_url',
        'sd_src',
        'sd_src_no_ratelimit',
      ]) {
        final pattern = RegExp('["\']?$key["\']?\\s*:\\s*["\']([^"\']+)["\']');
        final match = pattern.firstMatch(source);
        if (match != null) {
          parser.addProgressive(
            _cleanUrl(match.group(1)!),
            label: key.contains('hd') ? 'HD' : 'SD',
          );
        }
      }
    }
    if (!parser.streams.any((stream) => !stream.isAudioOnly)) {
      final document = html_parser.parse(source);
      final fallback =
          document
              .querySelector('meta[property="og:video"]')
              ?.attributes['content'] ??
          document
              .querySelector('meta[property="og:video:url"]')
              ?.attributes['content'] ??
          document
              .querySelector('meta[property="og:video:secure_url"]')
              ?.attributes['content'] ??
          document.querySelector('video')?.attributes['src'] ??
          document.querySelector('video source')?.attributes['src'];
      if (fallback != null) parser.addProgressive(_cleanUrl(fallback));
    }
    await parser.loadManifests(_dio);
    final streams = parser.finish();
    if (!streams.any((stream) => !stream.isAudioOnly)) {
      throw StateError('No playable streams found for Facebook video: $url');
    }
    return streams;
  }

  Future<String> _fetchPageHtml(String url) async {
    if (_cachedUrl == url && _cachedHtml != null) {
      return _cachedHtml!;
    }

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

    final html = response.data ?? '';
    _cachedUrl = url;
    _cachedHtml = html;
    return html;
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
