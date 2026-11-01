import 'dart:async';
import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'media_merge_plan.dart';

typedef MediaDiagnostic =
    void Function(String event, Map<String, Object?> values);
typedef MediaProbe = Future<Map<dynamic, dynamic>?> Function(String path);
typedef MediaExecution =
    Future<bool> Function(
      List<String> args,
      CancelToken token,
      MediaDiagnostic? diagnostic,
    );

/// Local media processing only: no platform IDs, extraction or storage policy.
/// New extractors using DownloadEngine inherit this same merge implementation.
class MediaMerger {
  final MediaProbe probe;
  final MediaExecution process;

  const MediaMerger({this.probe = inspect, this.process = execute});

  static Future<Map<dynamic, dynamic>?> inspect(String path) async =>
      (await FFprobeKit.getMediaInformation(
        path,
      )).getMediaInformation()?.getAllProperties();

  Future<bool> merge(
    String video,
    String audio,
    String output, {
    CancelToken? cancelToken,
    MediaDiagnostic? diagnostic,
    int? aacBitrateKbps,
    bool allowVideoTranscode = false,
  }) async {
    final token = cancelToken ?? CancelToken();
    _checkCancelled(token);
    final webm = output.toLowerCase().endsWith('.webm');
    Map<dynamic, dynamic>? videoProbe;
    Map<dynamic, dynamic>? audioProbe;
    if (!webm) {
      try {
        final probes = await Future.wait([probe(video), probe(audio)]);
        videoProbe = probes[0];
        audioProbe = probes[1];
      } catch (_) {
        // Unknown timing keeps audio resampling first, as before.
      }
      _checkCancelled(token);
    }
    final codecs = MediaMergePlan.audioCodecs(
      webm: webm,
      videoProbe: videoProbe,
      audioProbe: audioProbe,
    );
    for (final codec in codecs) {
      diagnostic?.call('merge_start', {
        'audioCodec': codec,
        'videoCodec': 'copy',
      });
      if (await process(
        MediaMergePlan.arguments(
          video: video,
          audio: audio,
          output: output,
          audioCodec: codec,
          aacBitrateKbps: aacBitrateKbps,
        ),
        token,
        diagnostic,
      )) {
        return true;
      }
      _checkCancelled(token);
    }
    if (!allowVideoTranscode) return false;
    // Preserve the generic engine's last-resort container repair. YouTube
    // never enables this: exact selected video is always copied there.
    final videoCodec = webm ? 'libvpx-vp9' : 'libx264';
    final audioCodec = webm ? 'libopus' : 'aac';
    diagnostic?.call('merge_start', {
      'audioCodec': audioCodec,
      'videoCodec': videoCodec,
    });
    return process(
      MediaMergePlan.arguments(
        video: video,
        audio: audio,
        output: output,
        audioCodec: audioCodec,
        videoCodec: videoCodec,
      ),
      token,
      diagnostic,
    );
  }

  static void _checkCancelled(CancelToken token) {
    if (token.isCancelled) throw token.cancelError!;
  }

  /// One cancellable native session. Waiting for its callback acknowledges
  /// actual writer termination before a paused job can resume.
  static Future<bool> execute(
    List<String> args,
    CancelToken token,
    MediaDiagnostic? diagnostic,
  ) async {
    _checkCancelled(token);
    final watch = Stopwatch()..start();
    final complete = Completer<bool>();
    final session = await FFmpegKit.executeWithArgumentsAsync(args, (
      finished,
    ) async {
      final code = await finished.getReturnCode();
      diagnostic?.call('ffmpeg', {
        'exitCode': code?.getValue(),
        'elapsedMs': watch.elapsedMilliseconds,
      });
      if (!complete.isCompleted) complete.complete(ReturnCode.isSuccess(code));
    });
    unawaited(
      token.whenCancel.then((_) async {
        if (!complete.isCompleted) {
          await FFmpegKit.cancel(session.getSessionId());
        }
      }),
    );
    if (token.isCancelled) await FFmpegKit.cancel(session.getSessionId());
    final success = await complete.future;
    _checkCancelled(token);
    return success;
  }
}
