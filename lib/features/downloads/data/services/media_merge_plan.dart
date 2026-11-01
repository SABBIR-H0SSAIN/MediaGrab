/// Codec and synchronization policy shared by every platform.
/// Unknown timing keeps the original resampling path rather than guessing.
class MediaMergePlan {
  static List<String> audioCodecs({
    required bool webm,
    Map<dynamic, dynamic>? videoProbe,
    Map<dynamic, dynamic>? audioProbe,
  }) {
    if (webm) return const ['copy', 'libopus'];
    final video = _track(videoProbe, 'video');
    final audio = _track(audioProbe, 'audio');
    if (audio?['codec_name'] != 'aac') return const ['aac', 'copy'];
    final videoStart = _number(video?['start_time']);
    final audioStart = _number(audio?['start_time']);
    final videoDuration = _number(video?['duration']);
    final audioDuration = _number(audio?['duration']);
    final aligned =
        videoStart != null &&
        audioStart != null &&
        (videoStart - audioStart).abs() <= .05 &&
        videoDuration != null &&
        audioDuration != null &&
        videoDuration > 0 &&
        audioDuration > 0 &&
        (videoDuration - audioDuration).abs() <= .25;
    return aligned ? const ['copy', 'aac'] : const ['aac', 'copy'];
  }

  static Map? _track(Map? probe, String type) {
    for (final stream in probe?['streams'] as List? ?? const []) {
      if (stream is Map && stream['codec_type'] == type) return stream;
    }
    return null;
  }

  static double? _number(dynamic value) {
    final number = double.tryParse('$value');
    return number != null && number.isFinite ? number : null;
  }

  static List<String> arguments({
    required String video,
    required String audio,
    required String output,
    required String audioCodec,
    String videoCodec = 'copy',
    int? aacBitrateKbps,
  }) => [
    '-y',
    '-i',
    video,
    '-i',
    audio,
    '-map',
    '0:v:0',
    '-map',
    '1:a:0',
    '-c:v',
    videoCodec,
    if (videoCodec == 'libx264') ...['-preset', 'ultrafast', '-crf', '23'],
    '-c:a',
    audioCodec,
    if (audioCodec == 'aac' && aacBitrateKbps != null) ...[
      '-b:a',
      '${aacBitrateKbps}k',
    ],
    if (audioCodec != 'copy') ...['-af', 'aresample=async=1'],
    '-avoid_negative_ts',
    'make_zero',
    '-shortest',
    output,
  ];
}
