// Developer-only entrypoint. Local fixture transport is labelled explicitly;
// production merge/queue/completion/registry and Android codecs are unmocked.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:mediagrab/app.dart';
import 'package:mediagrab/core/services/download_notification_service.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/downloads/data/services/download_engine.dart';
import 'package:mediagrab/features/downloads/data/services/download_registry.dart';
import 'package:mediagrab/features/downloads/data/services/media_merge_plan.dart';
import 'package:mediagrab/features/downloads/data/services/media_merger.dart';
import 'package:mediagrab/features/downloads/data/services/youtube_media_validation.dart';
import 'package:mediagrab/features/downloads/domain/enums/download_status.dart';
import 'package:mediagrab/features/extractor/data/extractors/facebook_extractor.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';
import 'package:mediagrab/routing/app_router.dart';

late String root;
late File evidence;

Future<void> record(Map<String, Object?> value) async {
  await evidence.writeAsString(
    '${jsonEncode(value)}\n',
    mode: FileMode.append,
    flush: true,
  );
  debugPrint('MEDIA_MERGE_TEST ${jsonEncode(value)}');
}

Future<Map<dynamic, dynamic>> validate(
  String path,
  int width,
  int height,
  String quality,
  Duration duration,
) async {
  final probe = await MediaMerger.inspect(path);
  if (probe == null) throw StateError('Missing output probe');
  YoutubeMediaValidation.validate(
    probe: probe,
    audioOnly: false,
    width: width,
    height: height,
    quality: quality,
    expectedDuration: duration,
  );
  final ok = await MediaMerger.execute(
    [
      '-v',
      'error',
      '-xerror',
      '-i',
      path,
      '-map',
      '0:v:0',
      '-map',
      '0:a:0',
      '-c',
      'copy',
      '-f',
      'null',
      '-',
    ],
    CancelToken(),
    null,
  );
  if (!ok) throw StateError('Integrity scan failed');
  return {
    'streams': [
      for (final s in probe['streams'] as List)
        {
          for (final k in [
            'codec_type',
            'codec_name',
            'width',
            'height',
            'avg_frame_rate',
            'duration',
            'start_time',
          ])
            k: s[k],
        },
    ],
    'duration': probe['format']['duration'],
    'bytes': await File(path).length(),
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DownloadNotificationService.instance.init(requestPermission: false);
  final container = ProviderContainer();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MediaGrabApp(),
    ),
  );
  unawaited(run(container));
}

Future<void> run(ProviderContainer container) async {
  root = '${(await getExternalStorageDirectory())!.path}/media-merge-tests';
  await Directory(root).create(recursive: true);
  evidence = File('$root/results.jsonl');
  await evidence.writeAsString('');
  try {
    const longDuration = Duration(milliseconds: 634567);
    for (var round = 0; round < 3; round++) {
      for (final mode
          in round.isEven ? ['baseline', 'shared'] : ['shared', 'baseline']) {
        final output = '$root/${mode}_$round.mp4';
        final watch = Stopwatch()..start();
        final strategies = <String>[];
        final success =
            mode == 'baseline'
                ? await MediaMerger.execute(
                  MediaMergePlan.arguments(
                    video: '$root/long.video',
                    audio: '$root/long.audio',
                    output: output,
                    audioCodec: 'aac',
                    aacBitrateKbps: 192,
                  ),
                  CancelToken(),
                  null,
                )
                : await const MediaMerger().merge(
                  '$root/long.video',
                  '$root/long.audio',
                  output,
                  aacBitrateKbps: 192,
                  allowVideoTranscode: true,
                  diagnostic: (event, values) {
                    if (event == 'merge_start') {
                      strategies.add(
                        '${values['videoCodec']}/${values['audioCodec']}',
                      );
                    }
                  },
                );
        if (!success) throw StateError('Benchmark merge failed');
        final mergeMs = watch.elapsedMilliseconds;
        final proof = await validate(
          output,
          1920,
          1080,
          '1080p60',
          longDuration,
        );
        await record({
          'case': 'paired-benchmark',
          'round': round,
          'mode': mode,
          'mergeMs': mergeMs,
          'totalMs': watch.elapsedMilliseconds,
          'strategies': strategies,
          'proof': proof,
          'status': 'VERIFIED',
        });
      }
    }

    // Genuine incompatible audio must still be encoded, preserving copied video.
    final repair = '$root/repaired.mp4';
    final repaired = await const MediaMerger().merge(
      '$root/short.video',
      '$root/webm.audio',
      repair,
      aacBitrateKbps: 192,
      allowVideoTranscode: true,
    );
    if (!repaired) throw StateError('Audio repair failed');
    await record({
      'case': 'opus-to-mp4-repair',
      'status': 'VERIFIED',
      'proof': await validate(
        repair,
        854,
        480,
        '480p',
        const Duration(seconds: 70),
      ),
    });

    // A real native encoder must stop instead of starting a fallback after Cancel.
    final token = CancelToken();
    var canceled = false;
    final cancelWatch = Stopwatch()..start();
    try {
      await MediaMerger(probe: (_) async => null).merge(
        '$root/long.video',
        '$root/long.audio',
        '$root/cancel.mp4',
        cancelToken: token,
        allowVideoTranscode: true,
        diagnostic: (event, values) {
          if (event == 'merge_start' && !token.isCancelled) {
            Timer(
              const Duration(milliseconds: 100),
              () => token.cancel('Controlled cancellation'),
            );
          }
        },
      );
    } on DioException catch (error) {
      canceled = CancelToken.isCancel(error);
    }
    if (!canceled) throw StateError('Native merge did not cancel');
    await record({
      'case': 'native-merge-cancel',
      'status': 'VERIFIED',
      'elapsedMs': cancelWatch.elapsedMilliseconds,
    });

    final registry = DownloadRegistry();
    final outputs = <String>[];
    for (final platform in [
      PlatformType.facebook,
      PlatformType.instagram,
      PlatformType.unknown,
    ]) {
      final webm = platform == PlatformType.instagram;
      final prefix = webm ? 'webm' : 'short';
      final video = StreamInfo(
        url: Uri.file('$root/$prefix.video').toString(),
        qualityLabel: webm ? '1080p' : '480p',
        codec: webm ? 'vp9' : 'avc1',
        container: webm ? 'webm' : 'mp4',
        videoWidth: webm ? 1920 : 854,
        videoHeight: webm ? 1080 : 480,
        isVideoOnly: true,
      );
      final audio = StreamInfo(
        url: Uri.file('$root/$prefix.audio').toString(),
        qualityLabel: 'Audio',
        codec: webm ? 'opus' : 'aac',
        container: webm ? 'webm' : 'mp4',
        isAudioOnly: true,
      );
      final engine = DownloadEngine(
        downloadRegistry: registry,
        customDownloadExecution: ({
          required task,
          required stream,
          required targetPath,
          required onProgress,
          required onComplete,
          required onError,
        }) async {
          final source = File(
            '$root/$prefix.${stream.isVideoOnly ? 'video' : 'audio'}',
          );
          await source.copy(targetPath);
          await onComplete();
        },
      );
      final watch = Stopwatch()..start();
      final terminal = engine.onTaskUpdated.firstWhere(
        (t) =>
            t.status == DownloadStatus.completed ||
            t.status == DownloadStatus.failed,
      );
      final task = await engine.startDownload(
        MediaInfo(
          id: 'controlled-${platform.name}',
          title: 'Controlled ${platform.name} merge',
          thumbnailUrl: '',
          duration: const Duration(seconds: 70),
          uploader: 'Controlled local transport',
          platform: platform,
        ),
        video,
        '$root/engine-${platform.name}.${video.container}',
        audioStream: audio,
      );
      final result = await terminal.timeout(const Duration(minutes: 2));
      if (result.status != DownloadStatus.completed) {
        throw StateError('Engine fixture failed');
      }
      final proof = await validate(
        result.filePath!,
        video.videoWidth!,
        video.videoHeight!,
        video.qualityLabel,
        const Duration(seconds: 70),
      );
      final records = await registry.getCompletedRecords(
        verifyFileExists: true,
      );
      if (!records.any((r) => r.id == task.id)) {
        throw StateError('Completion missing from registry');
      }
      final player = VideoPlayerController.file(File(result.filePath!));
      await player.initialize();
      await player.setVolume(0);
      await player.play();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final advanced = player.value.position.inMilliseconds > 0;
      await player.pause();
      await player.dispose();
      if (!advanced) throw StateError('Native playback did not advance');
      await record({
        'case': 'engine-controlled-route',
        'platform': platform.name,
        'transport': 'local fixture copy; production merger/registry unmocked',
        'taskId': task.id,
        'elapsedMs': watch.elapsedMilliseconds,
        'proof': proof,
        'playback': 'advanced',
        'registry': true,
        'status': 'VERIFIED',
      });
      outputs.add(result.filePath!);
      engine.dispose();
    }
    // Display a new copied output through the actual existing player screen.
    unawaited(
      container
          .read(appRouterProvider)
          .push(
            '/player?filePath=${Uri.encodeComponent(outputs.first)}&title=Controlled%20shared%20merge',
          ),
    );
    await record({'case': 'controlled-tests-complete', 'status': 'VERIFIED'});

    final liveDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    final extractor = FacebookExtractor(dio: liveDio);
    try {
      const url = 'https://www.facebook.com/share/v/1C9nsJ1VMz/';
      final info = await extractor
          .extractInfo(url)
          .timeout(const Duration(seconds: 30));
      final streams = await extractor
          .getStreams(url)
          .timeout(const Duration(seconds: 30));
      await record({
        'case': 'user-facebook-live-extraction',
        'status': 'EXTRACTED',
        'durationMs': info.duration.inMilliseconds,
        'formats': [
          for (final s in streams)
            {
              'quality': s.qualityLabel,
              'codec': s.codec,
              'videoOnly': s.isVideoOnly,
              'audioOnly': s.isAudioOnly,
            },
        ],
      });
      final videos =
          streams
              .where((s) => !s.isAudioOnly && (s.videoHeight ?? 0) <= 1080)
              .toList()
            ..sort(
              (a, b) => (b.videoHeight ?? 0).compareTo(a.videoHeight ?? 0),
            );
      if (videos.isNotEmpty) {
        final selected = videos.first;
        final audios = streams.where((s) => s.isAudioOnly).toList();
        final engine = DownloadEngine(dio: liveDio, downloadRegistry: registry);
        final terminal = engine.onTaskUpdated.firstWhere(
          (t) =>
              t.status == DownloadStatus.completed ||
              t.status == DownloadStatus.failed,
        );
        final task = await engine.startDownload(
          info,
          selected,
          '$root/user-facebook.${selected.container}',
          audioStream: audios.isEmpty ? null : audios.first,
        );
        try {
          final result = await terminal.timeout(const Duration(minutes: 3));
          if (result.status == DownloadStatus.completed) {
            final properties = await MediaMerger.inspect(result.filePath!);
            final track = (properties!['streams'] as List)
                .cast<Map>()
                .firstWhere((s) => s['codec_type'] == 'video');
            final proof = await validate(
              result.filePath!,
              track['width'] as int,
              track['height'] as int,
              selected.qualityLabel,
              info.duration,
            );
            await record({
              'case': 'user-facebook-live-download',
              'status': 'VERIFIED',
              'quality': selected.qualityLabel,
              'adaptive': selected.isVideoOnly,
              'proof': proof,
            });
          } else {
            await record({
              'case': 'user-facebook-live-download',
              'status': 'FAILED',
              'taskId': task.id,
            });
          }
        } on TimeoutException {
          await engine.cancelDownload(task.id);
          await record({
            'case': 'user-facebook-live-download',
            'status': 'TIMED_OUT',
          });
        } finally {
          engine.dispose();
        }
      }
    } catch (e) {
      await record({
        'case': 'user-facebook-live-extraction',
        'status': 'FAILED_BEFORE_TRANSFER',
        'type': e.runtimeType.toString(),
      });
    } finally {
      extractor.close();
      liveDio.close(force: true);
    }
    debugPrint('MEDIA_MERGE_TEST_DONE');
  } catch (e) {
    await record({
      'case': 'probe',
      'status': 'FAILED',
      'type': e.runtimeType.toString(),
    });
  }
}
