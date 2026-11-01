import 'media_merge_plan.dart';

/// Compatibility entrypoint for existing YouTube callers and probes.
/// All platforms now use the same codec/timing policy.
class YoutubeMergePlan {
  static List<String> audioCodecs({
    required bool webm,
    Map<dynamic, dynamic>? videoProbe,
    Map<dynamic, dynamic>? audioProbe,
  }) => MediaMergePlan.audioCodecs(
    webm: webm,
    videoProbe: videoProbe,
    audioProbe: audioProbe,
  );

  static List<String> arguments({
    required String video,
    required String audio,
    required String output,
    required String audioCodec,
  }) => MediaMergePlan.arguments(
    video: video,
    audio: audio,
    output: output,
    audioCodec: audioCodec,
  );
}
