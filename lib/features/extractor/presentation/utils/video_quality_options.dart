import '../../domain/entities/stream_info.dart';

/// Display resolution, including portrait media and human-readable aliases.
int? videoResolution(StreamInfo stream) {
  final width = stream.videoWidth;
  final height = stream.videoHeight;
  if (width != null && width > 0 && height != null && height > 0) {
    return width < height ? width : height;
  }
  final label = stream.qualityLabel.toLowerCase();
  final numeric = RegExp(r'(\d{3,4})\s*p').firstMatch(label);
  if (numeric != null) return int.parse(numeric.group(1)!);
  if (label.contains('8k')) return 4320;
  if (label.contains('4k')) return 2160;
  if (label.contains('2k')) return 1440;
  return height != null && height > 0 ? height : null;
}

int _frameRate(StreamInfo stream) {
  final label = stream.qualityLabel.toLowerCase();
  final match = RegExp(r'p\s*(\d{2,3})|\b(\d{2,3})\s*fps').firstMatch(label);
  return match == null ? 0 : int.parse(match.group(1) ?? match.group(2)!);
}

int _compatibility(StreamInfo stream) {
  final codec = stream.codec.toLowerCase();
  return (stream.container.toLowerCase() == 'mp4' ? 2 : 0) +
      (codec.contains('avc') ||
              codec.contains('h264') ||
              codec.contains('h.264')
          ? 1
          : 0);
}

bool _better(StreamInfo candidate, StreamInfo current) {
  // Progressive 360p is more reliable and avoids an unnecessary merge.
  if (videoResolution(candidate) == 360 &&
      candidate.isVideoOnly != current.isVideoOnly) {
    return !candidate.isVideoOnly;
  }
  final frameRate = _frameRate(candidate).compareTo(_frameRate(current));
  if (frameRate != 0) return frameRate > 0;
  final bitrate = (candidate.bitrate ?? 0).compareTo(current.bitrate ?? 0);
  if (bitrate != 0) return bitrate > 0;
  final compatibility = _compatibility(
    candidate,
  ).compareTo(_compatibility(current));
  if (compatibility != 0) return compatibility > 0;
  if (candidate.isVideoOnly != current.isVideoOnly) {
    return !candidate.isVideoOnly;
  }
  return false; // Keep the extractor's order when quality evidence is equal.
}

/// One original stream per resolution; extraction and download fallbacks retain
/// all variants. Unknown dimensions remain named categories, never invented HD.
List<StreamInfo> bestVideoQualityOptions(Iterable<StreamInfo> streams) {
  final options = <String, StreamInfo>{};
  for (final stream in streams.where((stream) => !stream.isAudioOnly)) {
    final resolution = videoResolution(stream);
    final label = stream.qualityLabel.trim().toLowerCase();
    final key =
        resolution?.toString() ??
        (label == 'best' || label.isEmpty ? 'original' : label);
    final current = options[key];
    if (current == null || _better(stream, current)) options[key] = stream;
  }
  return options.values.toList()..sort((a, b) {
    final resolution = (videoResolution(b) ?? 0).compareTo(
      videoResolution(a) ?? 0,
    );
    return resolution != 0
        ? resolution
        : a.qualityLabel.compareTo(b.qualityLabel);
  });
}
