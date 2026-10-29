import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import '../../domain/entities/stream_info.dart';

String youtubeQuality(yt.VideoStreamInfo stream) {
  final fps = stream.framerate.framesPerSecond;
  return fps > 30 && !RegExp(r'p\d{2,3}').hasMatch(stream.qualityLabel)
      ? '${stream.qualityLabel}${fps.round()}'
      : stream.qualityLabel;
}

/// An itag is mandatory when originally supplied. Never replace it with a
/// different resolution, frame rate, codec or language track during recovery.
yt.StreamInfo selectYoutubeStream(
  yt.StreamManifest manifest,
  StreamInfo selected,
) {
  final query = Uri.tryParse(selected.url)?.queryParameters ?? {};
  final tag = int.tryParse(query['itag'] ?? '');
  for (final stream in manifest.streams) {
    if (tag != null && stream.tag != tag) continue;
    final freshQuery = stream.url.queryParameters;
    if (selected.isAudioOnly && stream is yt.AudioOnlyStreamInfo) {
      // Clients may expose DRC and original encodings of the same original
      // language. Allow a fresh encoding, but never substitute a dubbed track.
      // The transfer layer sees changed xtags/size and restarts its bytes.
      if (!sameYoutubeAudioTrack(query['xtags'], freshQuery['xtags'], stream)) {
        continue;
      }
    } else if (query['xtags'] != freshQuery['xtags']) {
      continue;
    }
    if (stream is yt.VideoStreamInfo &&
        RegExp(r'p\d{2,3}').hasMatch(selected.qualityLabel) &&
        youtubeQuality(stream) != selected.qualityLabel) {
      continue;
    }
    if (selected.isAudioOnly && stream is yt.AudioOnlyStreamInfo) {
      if (stream.container.name.toLowerCase() ==
              selected.container.toLowerCase() &&
          stream.audioCodec == selected.codec) {
        return stream;
      }
    } else if (selected.isVideoOnly && stream is yt.VideoOnlyStreamInfo) {
      if (stream.videoResolution.height == selected.videoHeight &&
          stream.videoResolution.width == selected.videoWidth &&
          stream.container.name == selected.container &&
          stream.videoCodec == selected.codec &&
          (tag != null || youtubeQuality(stream) == selected.qualityLabel)) {
        return stream;
      }
    } else if (!selected.isVideoOnly &&
        !selected.isAudioOnly &&
        stream is yt.MuxedStreamInfo) {
      if (stream.videoResolution.height == selected.videoHeight &&
          stream.videoResolution.width == selected.videoWidth &&
          stream.container.name == selected.container &&
          (tag != null || youtubeQuality(stream) == selected.qualityLabel)) {
        return stream;
      }
    }
    // Audio fallback entities can refer to the progressive stream from which
    // audio is extracted. Preserve that exact itag as well.
    if (selected.isAudioOnly &&
        stream is yt.MuxedStreamInfo &&
        tag == stream.tag) {
      return stream;
    }
  }
  throw StateError(
    'Selected YouTube format ${tag ?? selected.qualityLabel} is no longer available; quality was preserved.',
  );
}

bool sameYoutubeAudioTrack(
  String? oldTags,
  String? newTags,
  yt.AudioOnlyStreamInfo stream,
) {
  if (oldTags == newTags) {
    return oldTags != null || stream.audioTrack?.audioIsDefault != false;
  }
  if (newTags == null) return false;
  Map<String, String> parse(String text) => {
    for (final part in text.split(':'))
      if (part.contains('='))
        part.split('=').first: part.substring(part.indexOf('=') + 1),
  };
  final fresh = parse(newTags);
  if (oldTags == null) return fresh['acont'] == 'original';
  final old = parse(oldTags);
  return old['lang'] != null &&
      old['lang'] == fresh['lang'] &&
      old['acont'] == fresh['acont'];
}

StreamInfo refreshedYoutubeEntity(yt.StreamInfo stream, StreamInfo selected) =>
    StreamInfo(
      url: stream.url.toString(),
      qualityLabel: selected.qualityLabel,
      codec: selected.codec,
      container: selected.container,
      sizeInBytes: stream.size.totalBytes,
      isAudioOnly: selected.isAudioOnly,
      isVideoOnly: selected.isVideoOnly,
      bitrate: selected.bitrate,
      videoWidth: selected.videoWidth,
      videoHeight: selected.videoHeight,
    );
