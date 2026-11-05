import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:mediagrab/features/downloads/data/services/youtube_transfer.dart';
import 'package:mediagrab/features/downloads/data/services/youtube_media_validation.dart';
import 'package:mediagrab/features/extractor/data/extractors/youtube_extractor.dart';
import 'package:mediagrab/features/extractor/data/extractors/youtube_recovery.dart';
import 'package:mediagrab/features/extractor/data/extractors/youtube_stream_selection.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

/// Real host integration tests; these supplement, not replace Android tests.
Future<void> main(List<String> args) async {
  final directory = Directory(
    Platform.environment['MEDIAGRAB_YOUTUBE_HOST_OUTPUT'] ??
        '/private/tmp/mediagrab-youtube-host-e2e',
  );
  await directory.create(recursive: true);
  final extractor = YoutubeExtractor();
  final client = yt.YoutubeExplode();
  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 20)));
  final cases =
      args.isNotEmpty
          ? args
          : [
            '39h7ZJbRcsw|360p|avc',
            '39h7ZJbRcsw|720p|avc',
            '39h7ZJbRcsw|1080p|avc',
            '39h7ZJbRcsw|1440p|av01',
            '39h7ZJbRcsw|2160p|vp9',
            '-hwMHF1rXvU|360p|avc',
            '-hwMHF1rXvU|480p|avc',
            '-hwMHF1rXvU|720p|av01',
            '-hwMHF1rXvU|1080p|vp9',
            '-hwMHF1rXvU|1440p|av01',
            'aqz-KE-bpKQ|720p60|avc',
            'aqz-KE-bpKQ|1080p60|avc',
          ];
  try {
    for (final testCase in cases) {
      final parts = testCase.split('|');
      final watch = Stopwatch()..start();
      var httpErrors = 0;
      var refreshes = 0;
      var transferred = 0;
      var recoveries = 0;
      var phase = 'extraction';
      final httpStatuses = <String, int>{};
      int? audioItag;
      try {
        final info = await extractor.extractInfo(parts[0]);
        final streams = await extractor.getStreams(parts[0]);
        final selected = streams.firstWhere(
          (s) => s.qualityLabel == parts[1] && s.codec.startsWith(parts[2]),
        );
        final stem = '${directory.path}/${parts[0]}_${parts[1]}_${parts[2]}';
        final videoPath =
            selected.isVideoOnly
                ? '$stem.video'
                : '$stem.${selected.container}';
        final reusedVideo =
            await File(videoPath).exists() &&
            await File(videoPath).length() > 0;
        Future<void> transfer(StreamInfo stream, String path) =>
            YoutubeTransfer(
              dio: dio,
              diagnostic: (event, data) {
                if (event == 'recovery') {
                  recoveries++;
                  if (data['status'] != null) {
                    httpErrors++;
                    final status = '${data['status']}';
                    httpStatuses[status] = (httpStatuses[status] ?? 0) + 1;
                  }
                }
              },
            ).download(
              selected: stream,
              path: path,
              token: CancelToken(),
              refresh: () async {
                refreshes++;
                return refreshedYoutubeEntity(
                  await YoutubeRecovery.resolve(client, parts[0], stream),
                  stream,
                );
              },
              onProgress: (bytes, total) {
                transferred = bytes;
              },
            );
        final output = '$stem.${selected.container}';
        phase = 'video';
        await transfer(selected, videoPath);
        if (selected.isVideoOnly) {
          final preferredAudio = streams.firstWhere(
            (s) =>
                s.isAudioOnly &&
                (selected.container == 'webm'
                    ? s.codec == 'opus'
                    : s.codec == 'mp4a.40.2'),
          );
          final audio = await YoutubeRecovery.companion(
            client,
            parts[0],
            preferredAudio,
            selected.container,
          );
          audioItag = int.tryParse(
            Uri.parse(audio.url).queryParameters['itag'] ?? '',
          );
          phase = 'audio';
          await transfer(audio, '$stem.audio');
          phase = 'merging';
          final result = await Process.run('ffmpeg', [
            '-v',
            'error',
            '-y',
            '-i',
            '$stem.video',
            '-i',
            '$stem.audio',
            '-map',
            '0:v:0',
            '-map',
            '1:a:0',
            '-c:v',
            'copy',
            '-c:a',
            selected.container == 'webm' ? 'copy' : 'aac',
            if (selected.container != 'webm') ...['-af', 'aresample=async=1'],
            '-avoid_negative_ts',
            'make_zero',
            '-shortest',
            output,
          ]);
          if (result.exitCode != 0) {
            throw StateError('FFmpeg exit ${result.exitCode}');
          }
        }
        phase = 'validation';
        final probe = await Process.run('ffprobe', [
          '-v',
          'error',
          '-show_streams',
          '-show_format',
          '-of',
          'json',
          output,
        ]);
        if (probe.exitCode != 0) {
          throw StateError('FFprobe exit ${probe.exitCode}');
        }
        final properties =
            jsonDecode(probe.stdout as String) as Map<String, dynamic>;
        YoutubeMediaValidation.validate(
          probe: properties,
          audioOnly: false,
          width: selected.videoWidth,
          height: selected.videoHeight,
          quality: selected.qualityLabel,
          expectedDuration: info.duration,
        );
        final scan = await Process.run('ffmpeg', [
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
        if (scan.exitCode != 0) throw StateError('Media integrity scan failed');
        final record = {
          'case': testCase,
          'status': 'VERIFIED',
          'bytes': await File(output).length(),
          'ms': watch.elapsedMilliseconds,
          'httpErrors': httpErrors,
          'httpStatuses': httpStatuses,
          'recoveryAttempts': recoveries,
          'refreshes': refreshes,
          'reusedVideo': reusedVideo,
          'videoItag': Uri.parse(selected.url).queryParameters['itag'],
          'audioItag': audioItag,
          'expectedDurationMs': info.duration.inMilliseconds,
          'format': properties['format']['duration'],
          'streams':
              (properties['streams'] as List)
                  .map(
                    (s) => {
                      'codec': s['codec_name'],
                      'type': s['codec_type'],
                      'width': s['width'],
                      'height': s['height'],
                      'fps': s['avg_frame_rate'],
                    },
                  )
                  .toList(),
          'ffprobe': 0,
          'integrityScan': 0,
          'path': output,
        };
        await File('${directory.path}/results.jsonl').writeAsString(
          '${jsonEncode(record)}\n',
          mode: FileMode.append,
          flush: true,
        );
        stdout.writeln(jsonEncode(record));
      } catch (e) {
        final record = {
          'case': testCase,
          'status': 'FAILED',
          'type': e.runtimeType.toString(),
          'message': e.toString().replaceAll(
            RegExp(r'https?://[^\s]+'),
            '[URL]',
          ),
          'ms': watch.elapsedMilliseconds,
          'phase': phase,
          'transferred': transferred,
          'httpErrors': httpErrors,
          'httpStatuses': httpStatuses,
          'recoveryAttempts': recoveries,
          'refreshes': refreshes,
        };
        await File('${directory.path}/results.jsonl').writeAsString(
          '${jsonEncode(record)}\n',
          mode: FileMode.append,
          flush: true,
        );
        stdout.writeln(jsonEncode(record));
      }
    }
  } finally {
    extractor.close();
    client.close();
    dio.close(force: true);
  }
}
