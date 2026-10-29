import 'dart:convert';
import 'dart:math' as math;
import 'package:html/parser.dart' as html;
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
import '../../domain/entities/stream_info.dart';

/// Public-page rendition metadata shared by Facebook and Instagram.
/// Only complete-file DASH representations are returned: segmented manifests
/// require a different downloader and must never be saved as ordinary MP4 files.
class SocialStreamParser {
  static const _manifestKeys = {
    'dash_manifest',
    'dash_manifest_xml_string',
    'manifest_xml',
    'manifest_xml_string',
    'video_dash_manifest',
    'playlist',
  };
  static const _urlKeys = {
    'video_url',
    'playable_url',
    'playable_url_quality_hd',
    'browser_native_hd_url',
    'browser_native_sd_url',
    'hd_src',
    'sd_src',
    'hd_src_no_ratelimit',
    'sd_src_no_ratelimit',
    'progressive_url',
  };

  final List<StreamInfo> streams = [];
  final Set<String> manifestUrls = {};

  static String decode(String value) {
    return value
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u0026', '&')
        .replaceAll(r'\u003C', '<')
        .replaceAll(r'\u003c', '<')
        .replaceAll(r'\u003E', '>')
        .replaceAll(r'\u003e', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"');
  }

  static Iterable<dynamic> _jsonValues(String source) sync* {
    // Balanced scanning also handles JSON wrapped in a JS function call.
    var attempts = 0;
    for (var start = 0; start < source.length && attempts < 250; start++) {
      if (source[start] != '{' && source[start] != '[') continue;
      attempts++;
      var depth = 0;
      var quoted = false;
      var escaped = false;
      for (var end = start; end < source.length; end++) {
        final char = source[end];
        if (quoted) {
          if (escaped) {
            escaped = false;
          } else if (char == r'\') {
            escaped = true;
          } else if (char == '"') {
            quoted = false;
          }
        } else if (char == '"') {
          quoted = true;
        } else if (char == '{' || char == '[') {
          depth++;
        } else if (char == '}' || char == ']') {
          depth--;
          if (depth == 0) {
            try {
              yield jsonDecode(source.substring(start, end + 1));
              start = end;
            } catch (_) {
              /* Try an inner JSON object next. */
            }
            break;
          }
        }
      }
    }
  }

  static Iterable<Map<String, dynamic>> _maps(
    dynamic value, [
    int depth = 0,
  ]) sync* {
    if (depth > 40) return;
    if (value is Map<String, dynamic>) {
      yield value;
      for (final child in value.values) {
        yield* _maps(child, depth + 1);
      }
    } else if (value is List) {
      for (final child in value) {
        yield* _maps(child, depth + 1);
      }
    } else if (value is String &&
        (value.startsWith('{') || value.startsWith('['))) {
      try {
        yield* _maps(jsonDecode(value), depth + 1);
      } catch (_) {}
    }
  }

  static int? _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value');
  static bool _http(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  static String quality(
    int? width,
    int? height, {
    String fallback = 'Original',
  }) {
    if (width == null || height == null) {
      return height != null ? '${height}p' : fallback;
    }
    // A 1080x1920 reel is 1080p, while verification retains its actual height.
    return '${math.min(width, height)}p';
  }

  void add(StreamInfo stream) {
    if (!_http(stream.url)) return;
    final index = streams.indexWhere(
      (s) => s.url == stream.url && s.isAudioOnly == stream.isAudioOnly,
    );
    if (index < 0) {
      streams.add(stream);
    } else if (streams[index].videoHeight == null &&
        stream.videoHeight != null) {
      streams[index] = stream;
    }
  }

  void addProgressive(
    String url, {
    int? width,
    int? height,
    String label = 'Original',
  }) {
    final clean = decode(url);
    if (Uri.tryParse(clean)?.path.endsWith('.mpd') ?? false) {
      manifestUrls.add(clean);
      return;
    }
    if (Uri.tryParse(clean)?.path.endsWith('.m3u8') ?? false) return;
    add(
      StreamInfo(
        url: clean,
        qualityLabel: quality(width, height, fallback: label),
        codec: 'h264 / aac',
        container: 'mp4',
        videoWidth: width,
        videoHeight: height,
      ),
    );
  }

  void parsePage(String source, {String? mediaId}) {
    final document = html.parse(source);
    final roots = <dynamic>[];
    for (final script in document.querySelectorAll('script')) {
      roots.addAll(_jsonValues(script.text));
    }
    final maps = roots.expand((root) => _maps(root)).toList();
    final candidates =
        maps
            .where(
              (node) =>
                  [
                    'id',
                    'video_id',
                    'videoId',
                    'shortcode',
                    'code',
                  ].any(node.containsKey) &&
                  [
                    ..._manifestKeys,
                    ..._urlKeys,
                    'video_versions',
                    'videoDeliveryLegacyFields',
                    'videoDeliveryResponseFragment',
                  ].any(node.containsKey),
            )
            .toList();
    final matching =
        candidates
            .where(
              (node) => [
                'id',
                'video_id',
                'videoId',
                'shortcode',
                'code',
              ].any((key) => '${node[key]}' == mediaId),
            )
            .toList();
    final selected =
        matching.isNotEmpty
            ? _maps(matching.first)
            : candidates.isNotEmpty
            ? _maps(candidates.first)
            : maps;
    for (final node in selected) {
      for (final entry in node.entries) {
        final value = entry.value;
        if (_manifestKeys.contains(entry.key) && value is String) {
          parseDash(value);
        } else if ({
              'dash_manifest_url',
              'manifest_url',
              'playable_url_dash',
            }.contains(entry.key) &&
            value is String) {
          final clean = decode(value);
          if (_http(clean)) manifestUrls.add(clean);
        } else if (entry.key == 'video_versions' && value is List) {
          for (final version in value.whereType<Map<String, dynamic>>()) {
            if (version['url'] is String) {
              addProgressive(
                version['url'],
                width: _int(version['width']),
                height: _int(version['height']),
              );
            }
          }
        } else if (_urlKeys.contains(entry.key) && value is String) {
          final dimensions =
              node['dimensions'] is Map ? node['dimensions'] as Map : node;
          final metadata =
              node['metadata'] is Map ? node['metadata'] as Map : const {};
          final hasDimensions =
              entry.key == 'video_url' || entry.key == 'progressive_url';
          addProgressive(
            value,
            width:
                hasDimensions
                    ? _int(dimensions['width'] ?? metadata['width'])
                    : null,
            height:
                hasDimensions
                    ? _int(dimensions['height'] ?? metadata['height'])
                    : null,
            label:
                entry.key.contains('hd')
                    ? 'HD'
                    : entry.key.contains('sd') || entry.key == 'playable_url'
                    ? 'SD'
                    : 'Original',
          );
        }
      }
    }
    // Legacy JS payloads may not be valid JSON. Preserve their direct fallbacks.
    if (candidates.isEmpty && streams.isEmpty) {
      for (final key in _urlKeys) {
        final pattern = RegExp(
          '["\']$key["\']\\s*:\\s*("(?:\\\\.|[^"\\\\])*")',
        );
        for (final match in pattern.allMatches(source)) {
          try {
            addProgressive(
              jsonDecode(match.group(1)!) as String,
              label:
                  key.contains('hd')
                      ? 'HD'
                      : key.contains('sd') || key == 'playable_url'
                      ? 'SD'
                      : 'Original',
            );
          } catch (_) {}
        }
      }
    }
  }

  void parseDash(String raw, {String? manifestUrl}) {
    var decoded = decode(raw.trim());
    if (decoded.startsWith('%3C') || decoded.startsWith('%3c')) {
      try {
        decoded = Uri.decodeComponent(decoded);
      } catch (_) {}
    }
    if (!decoded.contains('<MPD')) return;
    try {
      final document = XmlDocument.parse(decoded);
      for (final rep in document.findAllElements('Representation')) {
        final parents = rep.ancestors.whereType<XmlElement>().toList();
        final levels = [rep, ...parents];
        // SegmentTemplate/List require downloading individual fragments.
        if (levels.any(
          (level) => level.childElements.any(
            (child) =>
                child.name.local == 'SegmentTemplate' ||
                child.name.local == 'SegmentList',
          ),
        )) {
          continue;
        }
        if (levels.any(
          (level) => level.childElements.any(
            (child) => child.name.local == 'ContentProtection',
          ),
        )) {
          continue;
        }
        String? attribute(String name) {
          for (final level in levels) {
            final value = level.getAttribute(name);
            if (value != null) return value;
          }
          return null;
        }

        Uri? base = manifestUrl == null ? null : Uri.tryParse(manifestUrl);
        var hasMediaBase = false;
        for (final level in levels.reversed) {
          final urls = level.childElements.where(
            (child) => child.name.local == 'BaseURL',
          );
          if (urls.isEmpty) continue;
          final text = urls.first.innerText.trim();
          final uri = Uri.tryParse(text);
          if (uri == null) continue;
          base = uri.hasScheme ? uri : base?.resolveUri(uri);
          if (level == rep) hasMediaBase = true;
        }
        if (base == null || !hasMediaBase || !_http(base.toString())) continue;
        final mime = attribute('mimeType') ?? '';
        final kind = attribute('contentType') ?? '';
        final width = _int(attribute('width'));
        final height = _int(attribute('height'));
        final audio = mime.startsWith('audio/') || kind == 'audio';
        if (!audio &&
            !(mime.startsWith('video/') || kind == 'video' || height != null)) {
          continue;
        }
        final bitrate = _int(attribute('bandwidth'));
        add(
          StreamInfo(
            url: base.toString(),
            qualityLabel:
                audio
                    ? bitrate == null
                        ? 'Audio'
                        : '${(bitrate / 1000).round()} kbps'
                    : quality(width, height),
            codec: attribute('codecs') ?? (audio ? 'aac' : 'h264'),
            container:
                mime.contains('webm')
                    ? 'webm'
                    : audio
                    ? 'm4a'
                    : 'mp4',
            isAudioOnly: audio,
            isVideoOnly: !audio,
            bitrate: bitrate,
            videoWidth: width,
            videoHeight: height,
          ),
        );
      }
    } catch (_) {
      /* A malformed optional manifest must not hide progressive streams. */
    }
  }

  Future<void> loadManifests(Dio dio) async {
    for (final url in manifestUrls.take(4).toList()) {
      try {
        final response = await dio.get<String>(
          url,
          options: Options(
            responseType: ResponseType.plain,
            receiveTimeout: const Duration(seconds: 10),
          ),
        );
        parseDash(response.data ?? '', manifestUrl: url);
      } catch (_) {
        /* Public progressive URLs remain available if DASH is restricted. */
      }
    }
  }

  List<StreamInfo> finish() {
    final audio = streams.where((s) => s.isAudioOnly).toList();
    final progressive =
        streams.where((s) => !s.isAudioOnly && !s.isVideoOnly).toList();
    if (audio.isEmpty && progressive.isNotEmpty) {
      add(
        StreamInfo(
          url: progressive.first.url,
          qualityLabel: 'Extract audio',
          codec: 'aac',
          container: 'mp4',
          isAudioOnly: true,
        ),
      );
    }
    // Never offer a silent adaptive track when no companion audio is available.
    if (!streams.any((s) => s.isAudioOnly)) {
      streams.removeWhere((s) => s.isVideoOnly);
    }
    streams.sort((a, b) {
      if (a.isAudioOnly != b.isAudioOnly) return a.isAudioOnly ? 1 : -1;
      final resolution = (b.videoHeight ?? 0).compareTo(a.videoHeight ?? 0);
      if (resolution != 0) return resolution;
      if (a.isVideoOnly != b.isVideoOnly) return a.isVideoOnly ? 1 : -1;
      return (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
    });
    return List.unmodifiable(streams);
  }
}
