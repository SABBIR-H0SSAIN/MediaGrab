// Isolated developer entrypoint. Never used by the production application.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mediagrab/app.dart';
import 'package:mediagrab/core/services/download_notification_service.dart';
import 'package:mediagrab/features/downloads/data/services/youtube_merge_plan.dart';
import 'package:mediagrab/features/downloads/data/services/youtube_media_validation.dart';
import 'youtube_device_probe.dart' as mission;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DownloadNotificationService.instance.init(requestPermission: false);
  runApp(const ProviderScope(child: MediaGrabApp()));
  unawaited(benchmark());
}

Future<Map<dynamic, dynamic>> inspect(String path) async {
  final session = await FFprobeKit.getMediaInformation(path);
  final properties = session.getMediaInformation()?.getAllProperties();
  if (properties == null) throw StateError('Unprobeable benchmark input');
  return properties;
}

Future<void> execute(List<String> args) async {
  final session = await FFmpegKit.executeWithArguments(args);
  if (!ReturnCode.isSuccess(await session.getReturnCode())) {
    throw StateError('Benchmark FFmpeg failed');
  }
}

Future<void> benchmark() async {
  try {
    final root =
        '${(await getExternalStorageDirectory())!.path}/youtube-merge-benchmark';
    final video = '$root/input.video';
    final audio = '$root/input.audio';
    final results = File('$root/results.jsonl');
    await results.writeAsString('');
    final videoProbe = await inspect(video);
    final track = (videoProbe['streams'] as List).cast<Map>().firstWhere(
      (s) => s['codec_type'] == 'video',
    );
    final duration = double.parse(
      '${(videoProbe['format'] as Map)['duration']}',
    );
    // Alternate order to avoid making the optimized path always use warm cache.
    for (var round = 0; round < 3; round++) {
      for (final mode
          in round.isEven
              ? ['baseline', 'optimized']
              : ['optimized', 'baseline']) {
        final output = '$root/${mode}_$round.mp4';
        final watch = Stopwatch()..start();
        var codec = 'aac';
        if (mode == 'optimized') {
          final probes = await Future.wait([inspect(video), inspect(audio)]);
          codec =
              YoutubeMergePlan.audioCodecs(
                webm: false,
                videoProbe: probes[0],
                audioProbe: probes[1],
              ).first;
        }
        await execute(
          YoutubeMergePlan.arguments(
            video: video,
            audio: audio,
            output: output,
            audioCodec: codec,
          ),
        );
        final mergeMs = watch.elapsedMilliseconds;
        final validation = Stopwatch()..start();
        final probe = await inspect(output);
        YoutubeMediaValidation.validate(
          probe: probe,
          audioOnly: false,
          width: track['width'] as int,
          height: track['height'] as int,
          quality: '1080p60',
          expectedDuration: Duration(milliseconds: (duration * 1000).round()),
        );
        await execute([
          '-v',
          'error',
          '-xerror',
          '-i',
          output,
          '-map',
          '0:a:0',
          '-map',
          '0:v:0',
          '-c',
          'copy',
          '-f',
          'null',
          '-',
        ]);
        final record = {
          'round': round,
          'mode': mode,
          'audioCodec': codec,
          'mergeIncludingProbeMs': mergeMs,
          'validationMs': validation.elapsedMilliseconds,
          'totalMs': watch.elapsedMilliseconds,
          'bytes': await File(output).length(),
          'format': probe['format'],
          'streams': probe['streams'],
          'status': 'VERIFIED',
        };
        await results.writeAsString(
          '${jsonEncode(record)}\n',
          mode: FileMode.append,
          flush: true,
        );
        debugPrint(
          'YOUTUBE_MERGE_BENCHMARK ${jsonEncode({
            for (final key in ['round', 'mode', 'audioCodec', 'mergeIncludingProbeMs', 'validationMs', 'totalMs', 'status']) key: record[key],
          })}',
        );
      }
    }
    debugPrint('YOUTUBE_MERGE_BENCHMARK_DONE');
    await mission.probe();
  } catch (error) {
    debugPrint('YOUTUBE_MERGE_BENCHMARK_FAILED ${error.runtimeType}');
  }
}
