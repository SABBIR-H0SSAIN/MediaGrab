/// Pure validation policy shared by production FFprobe and regression fixtures.
class YoutubeMediaValidation {
  static void validate({
    required Map<dynamic, dynamic> probe,
    required bool audioOnly,
    required int? width,
    required int? height,
    required String quality,
    required Duration expectedDuration,
  }) {
    final streams = (probe['streams'] as List? ?? []).cast<Map>();
    final video = streams.where((s) => s['codec_type'] == 'video').toList();
    final audio = streams.where((s) => s['codec_type'] == 'audio').toList();
    if (audio.isEmpty || (!audioOnly && video.isEmpty)) {
      throw StateError('YouTube output is missing required video or audio');
    }
    for (final s in [if (!audioOnly) video.first, audio.first]) {
      if (s['codec_name'] == null || s['codec_name'] == 'unknown') {
        throw StateError('YouTube output codec could not be verified');
      }
    }
    if (!audioOnly) {
      final v = video.first;
      if (height == null ||
          v['height'] != height ||
          (width != null && v['width'] != width)) {
        throw StateError(
          'YouTube quality verification failed: expected $quality (${width}x$height), received ${v['width']}x${v['height']}',
        );
      }
      final fpsMatch = RegExp(r'p(\d{2,3})').firstMatch(quality);
      if (fpsMatch != null) {
        final parts = '${v['avg_frame_rate'] ?? v['r_frame_rate']}'.split('/');
        final fps =
            (double.tryParse(parts.first) ?? 0) /
            (parts.length == 2 ? double.tryParse(parts.last) ?? 1 : 1);
        if (!fps.isFinite || fps < int.parse(fpsMatch[1]!) * .98) {
          throw StateError(
            'YouTube frame rate verification failed: expected $quality',
          );
        }
      }
    }
    final format = probe['format'] as Map? ?? {};
    final duration = double.tryParse('${format['duration']}') ?? 0;
    if (!duration.isFinite || duration <= 0) {
      throw StateError('YouTube output duration is invalid');
    }
    if (expectedDuration > Duration.zero) {
      final expected = expectedDuration.inMilliseconds / 1000;
      final tolerance = expected * .01 > 2 ? expected * .01 : 2.0;
      if ((duration - expected).abs() > tolerance) {
        throw StateError(
          'YouTube output duration differs from source ($duration / $expected seconds)',
        );
      }
    }
    // Individual durations catch a truncated track hidden by the other stream.
    for (final s in [if (!audioOnly) video.first, audio.first]) {
      final trackDuration = double.tryParse('${s['duration']}');
      if (trackDuration != null &&
          (trackDuration - duration).abs() >
              (duration * .01 > 2 ? duration * .01 : 2)) {
        throw StateError('YouTube audio/video track duration is incomplete');
      }
    }
  }
}
