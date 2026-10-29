import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import '../../domain/entities/stream_info.dart';
import 'youtube_stream_selection.dart';

/// Current maintained, non-JS player profile. The old Android SDK-less profile
/// can expose playable headers but reject adaptive ranges partway through.
/// Source: yt-dlp 2026.10.26, extractor/youtube/_base.py, visionos profile.
/// Not all videos (notably made-for-kids media) are served by this client.
class YoutubeRecovery {
  /// Companion audio is automatic for a video request. Prefer the original
  /// format; if a client omits a surround/DRC variant, choose available original
  /// audio in the output container. Standalone audio requests stay exact.
  static yt.AudioOnlyStreamInfo selectCompanion(
    yt.StreamManifest manifest,
    StreamInfo preferred,
    String container,
  ) {
    try {
      final exact = selectYoutubeStream(manifest, preferred);
      if (exact is yt.AudioOnlyStreamInfo &&
          (container == 'webm'
              ? exact.audioCodec == 'opus'
              : exact.audioCodec.startsWith('mp4a'))) {
        return exact;
      }
    } on StateError {
      /* The automatically selected variant is unavailable. */
    }
    final oldTags = Uri.parse(preferred.url).queryParameters['xtags'];
    final candidates =
        manifest.audioOnly.where((s) {
            final tags = s.url.queryParameters['xtags'];
            final sameTrack = sameYoutubeAudioTrack(oldTags, tags, s);
            return sameTrack &&
                (container == 'webm'
                    ? s.audioCodec == 'opus'
                    : s.audioCodec.startsWith('mp4a'));
          }).toList()
          ..sort(
            (a, b) =>
                b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond),
          );
    if (candidates.isEmpty) {
      throw StateError(
        'No compatible original audio is available for this YouTube video',
      );
    }
    return candidates.first;
  }

  static Future<StreamInfo> companion(
    yt.YoutubeExplode client,
    String videoId,
    StreamInfo preferred,
    String container, {
    void Function(String, Map<String, Object?>)? diagnostic,
  }) async {
    final manifest = await client.videos.streamsClient.getManifest(
      videoId,
      ytClients: [visionOs],
      requireWatchPage: true,
    );
    final stream = selectCompanion(manifest, preferred, container);
    diagnostic?.call('companion_selected', {
      'requestedItag': Uri.parse(preferred.url).queryParameters['itag'],
      'itag': stream.tag,
      'bitrate': stream.bitrate.bitsPerSecond,
      'codec': stream.audioCodec,
    });
    return StreamInfo(
      url: stream.url.toString(),
      qualityLabel: '${stream.bitrate.kiloBitsPerSecond.round()} kbps',
      codec: stream.audioCodec,
      container: stream.container.name,
      sizeInBytes: stream.size.totalBytes,
      isAudioOnly: true,
      bitrate: stream.bitrate.bitsPerSecond,
    );
  }

  static const visionOs = yt.YoutubeApiClient({
    'context': {
      'client': {
        'clientName': 'VISIONOS',
        'clientVersion': '1.02',
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
        'userAgent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
      },
    },
  }, 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false');

  static Future<yt.StreamInfo> resolve(
    yt.YoutubeExplode client,
    String videoId,
    StreamInfo selected, {
    void Function(String, Map<String, Object?>)? diagnostic,
  }) async {
    try {
      final manifest = await client.videos.streamsClient.getManifest(
        videoId,
        ytClients: [visionOs],
        requireWatchPage: true,
      );
      final stream = selectYoutubeStream(manifest, selected);
      diagnostic?.call('extracted', {
        'method': 'visionos',
        'formats': manifest.streams.map((s) => s.tag).toSet().toList(),
      });
      return stream;
    } catch (error) {
      diagnostic?.call('extraction_fallback', {
        'method': 'visionos',
        'type': error.runtimeType.toString(),
      });
    }
    // Preserve the app's required legacy multi-client recovery for media that
    // the maintained profile does not serve. Never substitute another quality.
    final manifest = await client.videos.streamsClient.getManifest(
      videoId,
      ytClients: [
        yt.YoutubeApiClient.androidSdkless,
        yt.YoutubeApiClient.ios,
        yt.YoutubeApiClient.tv,
      ],
      requireWatchPage: false,
    );
    diagnostic?.call('extracted', {
      'method': 'legacy',
      'formats': manifest.streams.map((s) => s.tag).toSet().toList(),
    });
    return selectYoutubeStream(manifest, selected);
  }
}
