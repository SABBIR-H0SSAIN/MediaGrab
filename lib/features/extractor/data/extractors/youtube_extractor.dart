import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../../../core/utils/url_parser.dart';
import '../../domain/entities/media_info.dart';
import '../../domain/entities/playlist_info.dart';
import '../../domain/entities/stream_info.dart' as entity;
import 'base_extractor.dart';
import 'youtube_stream_selection.dart';

class _CachedManifest {
  final StreamManifest manifest;
  final DateTime timestamp;

  _CachedManifest(this.manifest, this.timestamp);
}

/// YouTube implementation of [BaseExtractor] using `youtube_explode_dart`
/// with resilient fallback using oEmbed and multi-client stream manifests.
class YoutubeExtractor extends BaseExtractor {
  static final Map<String, _CachedManifest> _manifestCache = {};

  /// Clears the in-memory manifest cache. Useful for test isolation.
  static void clearCache() {
    _manifestCache.clear();
  }

  /// Instance method helper to clear the manifest cache.
  void clearManifestCache() => clearCache();

  final YoutubeExplode _yt;
  final Dio _dio;
  final bool _shouldCloseYt;
  final bool _shouldCloseDio;

  YoutubeExtractor({YoutubeExplode? youtubeExplode, Dio? dio})
    : _yt = youtubeExplode ?? YoutubeExplode(),
      _dio = dio ?? Dio(),
      _shouldCloseYt = youtubeExplode == null,
      _shouldCloseDio = dio == null;

  @override
  bool canHandle(String url) {
    return detectPlatform(url) == PlatformType.youtube;
  }

  /// Parses YouTube video ID from various URL patterns including shorts, live,
  /// youtu.be, and URLs with tracking query parameters.
  String? extractVideoId(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    if (VideoId.validateVideoId(trimmed)) return trimmed;

    final parsed = VideoId.parseVideoId(trimmed);
    if (parsed != null && VideoId.validateVideoId(parsed)) return parsed;

    // Shorts: /shorts/<id> with query parameters, hashes, or trailing slashes
    final shortsMatch = RegExp(
      r'(?:youtube\.com|youtu\.be)/shorts/([a-zA-Z0-9_-]{11})(?:[/?&#]|$)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (shortsMatch != null) return shortsMatch.group(1);

    // Live: /live/<id> with query parameters or trailing slashes
    final liveMatch = RegExp(
      r'(?:youtube\.com|youtu\.be)/live/([a-zA-Z0-9_-]{11})(?:[/?&#]|$)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (liveMatch != null) return liveMatch.group(1);

    // youtu.be/<id>
    final youtuBeMatch = RegExp(
      r'youtu\.be/([a-zA-Z0-9_-]{11})(?:[/?&#]|$)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (youtuBeMatch != null) return youtuBeMatch.group(1);

    // Standard watch: ?v=<id> or &v=<id>
    final watchMatch = RegExp(
      r'[?&]v=([a-zA-Z0-9_-]{11})(?:[&#]|$)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (watchMatch != null) return watchMatch.group(1);

    // Embed, /v/, /e/
    final embedMatch = RegExp(
      r'(?:/embed/|/v/|/e/)([a-zA-Z0-9_-]{11})(?:[/?&#]|$)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (embedMatch != null) return embedMatch.group(1);

    return null;
  }

  /// Parses YouTube playlist ID from URLs.
  String? extractPlaylistId(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    if (PlaylistId.validatePlaylistId(trimmed)) return trimmed;

    final parsed = PlaylistId.parsePlaylistId(trimmed);
    if (parsed != null) return parsed;

    final match = RegExp(r'[?&]list=([a-zA-Z0-9_-]+)').firstMatch(trimmed);
    if (match != null) return match.group(1);

    return null;
  }

  @override
  Future<MediaInfo> extractInfo(String url) async {
    final videoIdStr = extractVideoId(url);

    if (videoIdStr != null) {
      try {
        final video = await _yt.videos.get(videoIdStr);
        return _mapVideoToMediaInfo(video);
      } on VideoUnavailableException {
        return await _fetchOEmbedFallback(videoIdStr);
      } catch (e) {
        // Fallback for scraping/network blocks on watch page
        try {
          return await _fetchOEmbedFallback(videoIdStr);
        } catch (_) {
          rethrow;
        }
      }
    }

    // Check if it is a playlist URL
    final playlistIdStr = extractPlaylistId(url);
    if (playlistIdStr != null) {
      final playlist = await _yt.playlists.get(playlistIdStr);
      final firstVideo = await _firstOrNull(
        _yt.playlists.getVideos(playlistIdStr),
      );
      if (firstVideo != null) {
        return _mapVideoToMediaInfo(firstVideo);
      }
      return MediaInfo(
        id: playlist.id.value,
        title: playlist.title,
        thumbnailUrl: playlist.thumbnails.highResUrl,
        duration: Duration.zero,
        uploader: playlist.author,
        platform: PlatformType.youtube,
        description: playlist.description,
      );
    }

    throw ArgumentError('Invalid or unsupported YouTube URL: $url');
  }

  Future<MediaInfo> _fetchOEmbedFallback(String videoId) async {
    final oembedUrl =
        'https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$videoId&format=json';
    final response = await _dio.get(oembedUrl);
    if (response.statusCode == 200) {
      final data =
          response.data is Map<String, dynamic>
              ? response.data as Map<String, dynamic>
              : jsonDecode(response.data.toString()) as Map<String, dynamic>;

      final title = data['title'] as String? ?? 'YouTube Video';
      final author = data['author_name'] as String? ?? 'YouTube Creator';
      final thumb =
          data['thumbnail_url'] as String? ??
          'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

      return MediaInfo(
        id: videoId,
        title: title,
        thumbnailUrl: thumb,
        duration: Duration.zero,
        uploader: author,
        platform: PlatformType.youtube,
        description: null,
      );
    }
    throw VideoUnavailableException('Video "$videoId" is unavailable.');
  }

  @override
  Future<List<entity.StreamInfo>> getStreams(String url) async {
    var videoIdStr = extractVideoId(url);

    if (videoIdStr == null) {
      final playlistIdStr = extractPlaylistId(url);
      if (playlistIdStr != null) {
        final firstVideo = await _firstOrNull(
          _yt.playlists.getVideos(playlistIdStr),
        );
        if (firstVideo != null) {
          videoIdStr = firstVideo.id.value;
        }
      }
    }

    if (videoIdStr == null) {
      throw ArgumentError('Could not find video ID for URL: $url');
    }

    // Check in-memory manifest cache with 10-minute TTL
    final cached = _manifestCache[videoIdStr];
    if (cached != null) {
      if (DateTime.now().difference(cached.timestamp) <
          const Duration(minutes: 10)) {
        return _parseManifest(cached.manifest);
      } else {
        _manifestCache.remove(videoIdStr);
      }
    }

    StreamManifest manifest;
    try {
      manifest = await _yt.videos.streamsClient.getManifest(videoIdStr);
    } catch (_) {
      try {
        manifest = await _yt.videos.streamsClient.getManifest(
          videoIdStr,
          ytClients: [
            YoutubeApiClient.androidSdkless,
            YoutubeApiClient.android,
            YoutubeApiClient.ios,
            YoutubeApiClient.tv,
          ],
          requireWatchPage: false,
        );
      } catch (_) {
        try {
          manifest = await _yt.videos.streamsClient.getManifest(
            videoIdStr,
            ytClients: [
              YoutubeApiClient.androidSdkless,
              YoutubeApiClient.android,
              YoutubeApiClient.ios,
              YoutubeApiClient.tv,
            ],
          );
        } catch (_) {
          manifest = await _yt.videos.streamsClient.getManifest(videoIdStr);
        }
      }
    }

    // Cache successfully fetched manifest
    // Keep memory bounded when processing long playlists.
    if (_manifestCache.length >= 100) {
      _manifestCache.remove(_manifestCache.keys.first);
    }
    _manifestCache[videoIdStr] = _CachedManifest(manifest, DateTime.now());

    return _parseManifest(manifest);
  }

  /// Returns a byte stream directly from `youtube_explode_dart` for a video ID and stream entity.
  Future<Stream<List<int>>?> getByteStream(
    String videoId,
    entity.StreamInfo streamEntity,
  ) async {
    final videoIdStr = extractVideoId(videoId) ?? videoId;
    try {
      StreamManifest? manifest;
      final cached = _manifestCache[videoIdStr];
      if (cached != null) {
        manifest = cached.manifest;
      } else {
        manifest = await _yt.videos.streamsClient.getManifest(
          videoIdStr,
          ytClients: [
            YoutubeApiClient.androidSdkless,
            YoutubeApiClient.android,
            YoutubeApiClient.ios,
            YoutubeApiClient.tv,
          ],
        );
      }

      final targetStream = selectYoutubeStream(manifest, streamEntity);
      return _yt.videos.streamsClient.get(targetStream);
    } catch (_) {}
    return null;
  }

  List<entity.StreamInfo> _parseManifest(StreamManifest manifest) {
    // 1. Muxed streams (both video + audio)
    final muxedStreams =
        manifest.muxed.map((m) {
          final codec =
              m.videoCodec.isNotEmpty && m.audioCodec.isNotEmpty
                  ? '${m.videoCodec} / ${m.audioCodec}'
                  : (m.videoCodec.isNotEmpty ? m.videoCodec : m.container.name);

          return entity.StreamInfo(
            url: m.url.toString(),
            qualityLabel: youtubeQuality(m),
            codec: codec,
            container: m.container.name,
            sizeInBytes: m.size.totalBytes,
            isAudioOnly: false,
            bitrate: m.bitrate.bitsPerSecond,
            videoWidth: m.videoResolution.width,
            videoHeight: m.videoResolution.height,
            isVideoOnly: false,
          );
        }).toList();

    // 2. Video-only streams (require merging with audio)
    // Filter out 144p and 240p streams that YouTube blocks with 403 on Android client range requests.
    // Also deduplicate: if a progressive muxed stream already provides this resolution (e.g. 360p),
    // prefer the pristine muxed stream which has ratebypass=yes and does not require FFmpeg merging!
    final muxedHeights = muxedStreams.map((m) => m.videoHeight ?? 0).toSet();
    final filteredVideoOnly =
        manifest.videoOnly.where((v) {
          final h = v.videoResolution.height;
          if (muxedHeights.contains(h)) return false;
          return h >= 360;
        }).toList();
    final effectiveVideoOnly = filteredVideoOnly;

    final videoOnlyStreams =
        effectiveVideoOnly.map((v) {
          return entity.StreamInfo(
            url: v.url.toString(),
            qualityLabel: youtubeQuality(v),
            codec: v.videoCodec.isNotEmpty ? v.videoCodec : v.container.name,
            container: v.container.name,
            sizeInBytes: v.size.totalBytes,
            isAudioOnly: false,
            bitrate: v.bitrate.bitsPerSecond,
            videoWidth: v.videoResolution.width,
            videoHeight: v.videoResolution.height,
            isVideoOnly: true,
          );
        }).toList();

    // 3. Audio-only streams (prefer >= 100 kbps non-throttled original audio tracks)
    final highBitrateAudio =
        manifest.audioOnly.where((a) {
          final kbps = a.bitrate.kiloBitsPerSecond;
          return kbps >= 100;
        }).toList();
    final audioPool =
        highBitrateAudio.isNotEmpty
            ? highBitrateAudio
            : manifest.audioOnly.toList();

    final validAudio =
        audioPool.where((a) {
          final track = a.audioTrack;
          if (track == null) return true;
          return track.audioIsDefault;
        }).toList();
    final effectiveAudio = validAudio.isNotEmpty ? validAudio : audioPool;

    final audioOnlyStreams =
        effectiveAudio.map((a) {
          final kbps = (a.bitrate.kiloBitsPerSecond).round();
          return entity.StreamInfo(
            url: a.url.toString(),
            qualityLabel: '$kbps kbps',
            codec: a.audioCodec.isNotEmpty ? a.audioCodec : a.container.name,
            container: a.container.name,
            sizeInBytes: a.size.totalBytes,
            isAudioOnly: true,
            bitrate: a.bitrate.bitsPerSecond,
            videoWidth: null,
            videoHeight: null,
            isVideoOnly: false,
          );
        }).toList();

    // Always ensure a pristine high-quality AAC audio option is available from muxed stream
    if (audioOnlyStreams.isEmpty && muxedStreams.isNotEmpty) {
      final m = muxedStreams.first;
      audioOnlyStreams.add(
        entity.StreamInfo(
          url: m.url,
          qualityLabel: '128 kbps',
          codec: 'mp4a.40.2',
          container: 'm4a',
          sizeInBytes: m.sizeInBytes,
          isAudioOnly: true,
          bitrate: 128000,
          videoWidth: null,
          videoHeight: null,
          isVideoOnly: false,
        ),
      );
    }

    // Sort video streams: quality descending (height, then bitrate)
    final allVideoStreams = [...muxedStreams, ...videoOnlyStreams];
    allVideoStreams.sort((a, b) {
      final heightA = a.videoHeight ?? 0;
      final heightB = b.videoHeight ?? 0;
      if (heightA != heightB) {
        return heightB.compareTo(heightA);
      }
      if (a.isVideoOnly != b.isVideoOnly) {
        return a.isVideoOnly ? 1 : -1;
      }
      final bitA = a.bitrate ?? 0;
      final bitB = b.bitrate ?? 0;
      return bitB.compareTo(bitA);
    });

    // Sort audio streams: bitrate descending
    audioOnlyStreams.sort((a, b) {
      final bitA = a.bitrate ?? 0;
      final bitB = b.bitrate ?? 0;
      return bitB.compareTo(bitA);
    });

    return [...allVideoStreams, ...audioOnlyStreams];
  }

  @override
  Future<PlaylistInfo?> extractPlaylist(String url) async {
    final playlistIdStr = extractPlaylistId(url);
    if (playlistIdStr == null) return null;

    final playlist = await _yt.playlists.get(playlistIdStr);
    final videos = <MediaInfo>[];

    try {
      await for (final video in _yt.playlists.getVideos(playlistIdStr)) {
        videos.add(_mapVideoToMediaInfo(video));
      }
    } catch (_) {
      // Retain successfully parsed videos if stream breaks
    }

    return PlaylistInfo(
      id: playlist.id.value,
      title: playlist.title,
      thumbnailUrl: playlist.thumbnails.highResUrl,
      author: playlist.author,
      videoCount: playlist.videoCount ?? videos.length,
      videos: videos,
    );
  }

  MediaInfo _mapVideoToMediaInfo(Video video) {
    return MediaInfo(
      id: video.id.value,
      title: video.title,
      thumbnailUrl: video.thumbnails.highResUrl,
      duration: video.duration ?? Duration.zero,
      uploader: video.author,
      platform: PlatformType.youtube,
      uploadDate: video.uploadDate ?? video.publishDate,
      viewCount: video.engagement.viewCount,
      description: video.description,
    );
  }

  static Future<T?> _firstOrNull<T>(Stream<T> stream) async {
    await for (final item in stream) {
      return item;
    }
    return null;
  }

  @override
  void close() {
    if (_shouldCloseYt) {
      _yt.close();
    }
    if (_shouldCloseDio) {
      _dio.close();
    }
  }
}
