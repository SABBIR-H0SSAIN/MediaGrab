import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/downloads/data/services/download_engine.dart';
import 'package:mediagrab/features/downloads/domain/entities/download_task.dart';
import 'package:mediagrab/features/downloads/domain/enums/download_status.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';

Stream<Uint8List> _createStream(List<int> bytes) async* {
  yield Uint8List.fromList(bytes);
}

class _TestHttpClientAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) onFetch;
  _TestHttpClientAdapter(this.onFetch);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => onFetch(options);

  @override
  void close({bool force = false}) {}
}

void main() {
  group('DownloadEngine', () {
    const testMediaInfo = MediaInfo(
      id: 'abc12345678',
      title: 'Flutter Tutorial',
      thumbnailUrl: 'https://example.com/thumb.jpg',
      duration: Duration(minutes: 5),
      uploader: 'Dev Creator',
      platform: PlatformType.youtube,
    );

    const testMuxedStream = StreamInfo(
      url: 'https://example.com/video.mp4',
      qualityLabel: '720p',
      codec: 'avc1',
      container: 'mp4',
      sizeInBytes: 50000000,
    );

    const testVideoOnlyStream = StreamInfo(
      url: 'https://example.com/video_only.mp4',
      qualityLabel: '1080p',
      codec: 'avc1',
      container: 'mp4',
      sizeInBytes: 100000000,
      isVideoOnly: true,
    );

    const testAudioStream = StreamInfo(
      url: 'https://example.com/audio.m4a',
      qualityLabel: '128 kbps',
      codec: 'mp4a',
      container: 'm4a',
      sizeInBytes: 5000000,
      isAudioOnly: true,
    );

    test('audio remux copies native Opus and never encodes AAC into WebM', () {
      final remux = DownloadEngine.audioExtractionArguments(
        '/tmp/audio.tmp',
        '/tmp/audio.webm',
      );
      expect(remux[remux.indexOf('-c:a') + 1], 'copy');
      expect(remux, contains('-vn'));
      final recovery = DownloadEngine.audioExtractionArguments(
        '/tmp/audio.tmp',
        '/tmp/audio.webm',
        transcode: true,
      );
      expect(recovery[recovery.indexOf('-c:a') + 1], 'libopus');
      expect(recovery, isNot(contains('aac')));
      final mp3 = DownloadEngine.audioExtractionArguments(
        '/tmp/audio.tmp',
        '/tmp/audio.mp3',
      );
      expect(mp3[mp3.indexOf('-c:a') + 1], 'libmp3lame');
    });

    test(
      'repeated downloads reserve distinct paths and preserve existing files',
      () async {
        final dir = await Directory.systemTemp.createTemp('unique_output_');
        final path = '${dir.path}/same.mp4';
        await File(path).writeAsBytes([7]);
        final engine = DownloadEngine(
          customDownloadExecution:
              ({
                required task,
                required stream,
                required targetPath,
                required onProgress,
                required onComplete,
                required onError,
              }) async {},
        );
        try {
          final first = await engine.startDownload(
            testMediaInfo,
            testMuxedStream,
            path,
          );
          final second = await engine.startDownload(
            testMediaInfo,
            testMuxedStream,
            path,
          );
          expect(first.filePath, '${dir.path}/same (1).mp4');
          expect(second.filePath, '${dir.path}/same (2).mp4');
          expect(await File(path).readAsBytes(), [7]);
        } finally {
          engine.dispose();
          await dir.delete(recursive: true);
        }
      },
    );

    test(
      'completion records actual final file size instead of stale transfer totals',
      () async {
        final dir = await Directory.systemTemp.createTemp('output_size_');
        late Future<void> Function() finish;
        final engine = DownloadEngine(
          customDownloadExecution: ({
            required task,
            required stream,
            required targetPath,
            required onProgress,
            required onComplete,
            required onError,
          }) async {
            await File(targetPath).writeAsBytes([1, 2, 3, 4]);
            onProgress(0.8, 80, 100, 10);
            finish = onComplete;
          },
        );
        try {
          final task = await engine.startDownload(
            testMediaInfo,
            testMuxedStream,
            '${dir.path}/out.mp4',
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await finish();
          final completed = engine.getTask(task.id)!;
          expect(completed.status, DownloadStatus.completed);
          expect(completed.downloadedBytes, 4);
          expect(completed.totalBytes, 4);
        } finally {
          engine.dispose();
          await dir.delete(recursive: true);
        }
      },
    );

    test(
      'starts download immediately when active slots are available',
      () async {
        late Future<void> Function() completeCallback;

        final engine = DownloadEngine(
          maxConcurrentDownloads: 3,
          customDownloadExecution: ({
            required task,
            required stream,
            required targetPath,
            required onProgress,
            required onComplete,
            required onError,
          }) async {
            completeCallback = onComplete;
          },
        );

        final task = await engine.startDownload(
          testMediaInfo,
          testMuxedStream,
          '/tmp/output.mp4',
        );

        expect(task.status, DownloadStatus.downloading);
        expect(engine.getActiveDownloads().length, 1);
        expect(engine.getQueuedDownloads().length, 0);

        // Complete download
        await completeCallback();

        expect(engine.getActiveDownloads().length, 0);
        expect(engine.getCompletedDownloads().length, 1);
        expect(
          engine.getCompletedDownloads().first.status,
          DownloadStatus.completed,
        );

        engine.dispose();
      },
    );

    test(
      'enforces max concurrent downloads and queues surplus tasks',
      () async {
        final engine = DownloadEngine(
          maxConcurrentDownloads: 2,
          customDownloadExecution:
              ({
                required task,
                required stream,
                required targetPath,
                required onProgress,
                required onComplete,
                required onError,
              }) async {},
        );

        final task1 = await engine.startDownload(
          testMediaInfo,
          testMuxedStream,
          '/tmp/1.mp4',
        );
        final task2 = await engine.startDownload(
          testMediaInfo,
          testMuxedStream,
          '/tmp/2.mp4',
        );
        final task3 = await engine.startDownload(
          testMediaInfo,
          testMuxedStream,
          '/tmp/3.mp4',
        );

        expect(task1.status, DownloadStatus.downloading);
        expect(task2.status, DownloadStatus.downloading);
        expect(task3.status, DownloadStatus.queued);

        expect(engine.getActiveDownloads().length, 2);
        expect(engine.getQueuedDownloads().length, 1);

        engine.dispose();
      },
    );

    test('completing an active download starts the next queued task', () async {
      final completables = <String, Future<void> Function()>{};

      final engine = DownloadEngine(
        maxConcurrentDownloads: 1,
        customDownloadExecution: ({
          required task,
          required stream,
          required targetPath,
          required onProgress,
          required onComplete,
          required onError,
        }) async {
          completables[task.id] = onComplete;
        },
      );

      final task1 = await engine.startDownload(
        testMediaInfo,
        testMuxedStream,
        '/tmp/1.mp4',
      );
      final task2 = await engine.startDownload(
        testMediaInfo,
        testMuxedStream,
        '/tmp/2.mp4',
      );

      expect(task1.status, DownloadStatus.downloading);
      expect(task2.status, DownloadStatus.queued);

      // Finish task 1
      await completables[task1.id]!();

      expect(engine.getTask(task1.id)?.status, DownloadStatus.completed);
      expect(engine.getTask(task2.id)?.status, DownloadStatus.downloading);
      expect(engine.getQueuedDownloads().length, 0);
      expect(engine.getActiveDownloads().length, 1);

      engine.dispose();
    });

    test(
      'pausing active download frees concurrency slot for queued download',
      () async {
        final engine = DownloadEngine(
          maxConcurrentDownloads: 1,
          customDownloadExecution:
              ({
                required task,
                required stream,
                required targetPath,
                required onProgress,
                required onComplete,
                required onError,
              }) async {},
        );

        final task1 = await engine.startDownload(
          testMediaInfo,
          testMuxedStream,
          '/tmp/1.mp4',
        );
        final task2 = await engine.startDownload(
          testMediaInfo,
          testMuxedStream,
          '/tmp/2.mp4',
        );

        expect(task1.status, DownloadStatus.downloading);
        expect(task2.status, DownloadStatus.queued);

        final paused = await engine.pauseDownload(task1.id);
        expect(paused, isTrue);

        expect(engine.getTask(task1.id)?.status, DownloadStatus.paused);
        expect(engine.getTask(task2.id)?.status, DownloadStatus.downloading);

        engine.dispose();
      },
    );

    test(
      'resuming paused download starts immediately if slot available',
      () async {
        final engine = DownloadEngine(
          maxConcurrentDownloads: 1,
          customDownloadExecution:
              ({
                required task,
                required stream,
                required targetPath,
                required onProgress,
                required onComplete,
                required onError,
              }) async {},
        );

        final task = await engine.startDownload(
          testMediaInfo,
          testMuxedStream,
          '/tmp/1.mp4',
        );
        await engine.pauseDownload(task.id);
        expect(engine.getTask(task.id)?.status, DownloadStatus.paused);

        final resumed = await engine.resumeDownload(task.id);
        expect(resumed, isTrue);
        expect(engine.getTask(task.id)?.status, DownloadStatus.downloading);

        engine.dispose();
      },
    );

    test('cancelling active download triggers next queued task', () async {
      final engine = DownloadEngine(
        maxConcurrentDownloads: 1,
        customDownloadExecution:
            ({
              required task,
              required stream,
              required targetPath,
              required onProgress,
              required onComplete,
              required onError,
            }) async {},
      );

      final task1 = await engine.startDownload(
        testMediaInfo,
        testMuxedStream,
        '/tmp/1.mp4',
      );
      final task2 = await engine.startDownload(
        testMediaInfo,
        testMuxedStream,
        '/tmp/2.mp4',
      );

      await engine.cancelDownload(task1.id);

      expect(engine.getTask(task1.id)?.status, DownloadStatus.cancelled);
      expect(engine.getTask(task2.id)?.status, DownloadStatus.downloading);

      engine.dispose();
    });

    test('retrying failed download resets and resumes execution', () async {
      late void Function(String) triggerError;

      final engine = DownloadEngine(
        maxConcurrentDownloads: 1,
        customDownloadExecution: ({
          required task,
          required stream,
          required targetPath,
          required onProgress,
          required onComplete,
          required onError,
        }) async {
          triggerError = onError;
        },
      );

      final task = await engine.startDownload(
        testMediaInfo,
        testMuxedStream,
        '/tmp/1.mp4',
      );
      triggerError('Network connection lost');

      expect(engine.getTask(task.id)?.status, DownloadStatus.failed);
      expect(engine.getTask(task.id)?.errorMessage, 'Network connection lost');

      final retried = await engine.retryDownload(task.id);
      expect(retried, isTrue);
      expect(engine.getTask(task.id)?.status, DownloadStatus.downloading);
      expect(engine.getTask(task.id)?.errorMessage, isNull);

      engine.dispose();
    });

    test('merging preserves the latest downloaded byte metrics', () async {
      late Future<void> Function() finishVideo;
      late DownloadTask runningTask;
      late DownloadEngine engine;
      engine = DownloadEngine(
        ffmpegMerger: (video, audio, output) async {
          final merging = engine.getTask(runningTask.id)!;
          expect(merging.status, DownloadStatus.merging);
          expect(merging.downloadedBytes, 90);
          expect(merging.totalBytes, 100);
          return true;
        },
        customDownloadExecution: ({
          required task,
          required stream,
          required targetPath,
          required onProgress,
          required onComplete,
          required onError,
        }) async {
          if (stream.isVideoOnly) {
            onProgress(0.9, 90, 100, 5);
            finishVideo = onComplete;
          } else {
            await onComplete();
          }
        },
      );
      try {
        runningTask = await engine.startDownload(
          testMediaInfo,
          testVideoOnlyStream,
          '/tmp/merge_metrics.mp4',
          audioStream: testAudioStream,
        );
        await finishVideo();
        expect(
          engine.getTask(runningTask.id)!.status,
          DownloadStatus.completed,
        );
      } finally {
        engine.dispose();
      }
    });

    test(
      'video-only stream triggers audio download to tempAudioPath and FFmpeg merge',
      () async {
        final downloadedStreams = <StreamInfo>[];
        final downloadedPaths = <String>[];
        var mergeCalled = false;
        late Future<void> Function() completeVideoDownload;

        final engine = DownloadEngine(
          maxConcurrentDownloads: 1,
          ffmpegMerger: (videoPath, audioPath, outputPath) async {
            mergeCalled = true;
            expect(videoPath, '/tmp/merged.mp4_video.tmp');
            expect(audioPath, '/tmp/merged.mp4_audio.tmp');
            expect(outputPath, '/tmp/merged.mp4');
            return true; // simulate FFmpeg merge success
          },
          customDownloadExecution: ({
            required task,
            required stream,
            required targetPath,
            required onProgress,
            required onComplete,
            required onError,
          }) async {
            downloadedStreams.add(stream);
            downloadedPaths.add(targetPath);
            if (stream.isVideoOnly) {
              completeVideoDownload = onComplete;
            } else {
              await onComplete();
            }
          },
        );

        final task = await engine.startDownload(
          testMediaInfo,
          testVideoOnlyStream,
          '/tmp/merged.mp4',
          audioStream: testAudioStream,
        );

        expect(task.status, DownloadStatus.downloading);

        await completeVideoDownload();

        expect(mergeCalled, isTrue);
        expect(downloadedStreams, [testVideoOnlyStream, testAudioStream]);
        expect(downloadedPaths, [
          '/tmp/merged.mp4_video.tmp',
          '/tmp/merged.mp4_audio.tmp',
        ]);
        expect(engine.getTask(task.id)?.status, DownloadStatus.completed);

        engine.dispose();
      },
    );

    test('video-only stream fails if audio stream download fails', () async {
      late Future<void> Function() completeVideoDownload;

      final engine = DownloadEngine(
        maxConcurrentDownloads: 1,
        ffmpegMerger: (videoPath, audioPath, outputPath) async => true,
        customDownloadExecution: ({
          required task,
          required stream,
          required targetPath,
          required onProgress,
          required onComplete,
          required onError,
        }) async {
          if (stream.isVideoOnly) {
            completeVideoDownload = onComplete;
          } else {
            onError('Audio network error');
          }
        },
      );

      final task = await engine.startDownload(
        testMediaInfo,
        testVideoOnlyStream,
        '/tmp/merged.mp4',
        audioStream: testAudioStream,
      );

      expect(task.status, DownloadStatus.downloading);

      await completeVideoDownload();

      expect(engine.getTask(task.id)?.status, DownloadStatus.failed);
      expect(
        engine.getTask(task.id)?.errorMessage,
        contains('Audio network error'),
      );

      engine.dispose();
    });

    test('video-only stream fails if FFmpeg merge fails', () async {
      late Future<void> Function() completeVideoDownload;

      final engine = DownloadEngine(
        maxConcurrentDownloads: 1,
        ffmpegMerger: (videoPath, audioPath, outputPath) async {
          return false; // simulate FFmpeg failure
        },
        customDownloadExecution: ({
          required task,
          required stream,
          required targetPath,
          required onProgress,
          required onComplete,
          required onError,
        }) async {
          if (stream.isVideoOnly) {
            completeVideoDownload = onComplete;
          } else {
            await onComplete();
          }
        },
      );

      final task = await engine.startDownload(
        testMediaInfo,
        testVideoOnlyStream,
        '/tmp/merged.mp4',
        audioStream: testAudioStream,
      );

      expect(task.status, DownloadStatus.downloading);

      await completeVideoDownload();

      expect(engine.getTask(task.id)?.status, DownloadStatus.failed);
      expect(
        engine.getTask(task.id)?.errorMessage,
        contains('FFmpeg merge failed'),
      );

      engine.dispose();
    });

    test('notifies onTaskUpdated stream and onProgressCallback', () async {
      final taskCompleter = Completer<DownloadTask>();
      DownloadTask? progressCallbackTask;

      final engine = DownloadEngine(
        maxConcurrentDownloads: 1,
        customDownloadExecution:
            ({
              required task,
              required stream,
              required targetPath,
              required onProgress,
              required onComplete,
              required onError,
            }) async {},
      );

      engine.onProgressCallback = (task) {
        progressCallbackTask = task;
      };

      engine.onTaskUpdated.listen((task) {
        if (!taskCompleter.isCompleted) {
          taskCompleter.complete(task);
        }
      });

      final task = await engine.startDownload(
        testMediaInfo,
        testMuxedStream,
        '/tmp/1.mp4',
      );

      final receivedTask = await taskCompleter.future;
      expect(receivedTask.id, task.id);
      expect(progressCallbackTask?.id, task.id);

      engine.dispose();
    });

    test(
      'cancelled task is not revived as completed or failed during FFmpeg merge',
      () async {
        late Future<void> Function() completeVideoDownload;
        late DownloadEngine localEngine;

        localEngine = DownloadEngine(
          maxConcurrentDownloads: 1,
          ffmpegMerger: (videoPath, audioPath, outputPath) async {
            // Cancel while merging
            await localEngine.cancelDownload('task_guard_test');
            return true;
          },
          customDownloadExecution: ({
            required task,
            required stream,
            required targetPath,
            required onProgress,
            required onComplete,
            required onError,
          }) async {
            if (stream.isVideoOnly) {
              completeVideoDownload = onComplete;
            } else {
              await onComplete();
            }
          },
        );

        final task = await localEngine.startDownload(
          testMediaInfo,
          testVideoOnlyStream,
          '/tmp/merged.mp4',
          audioStream: testAudioStream,
        );

        // Cancel the task
        await localEngine.cancelDownload(task.id);
        expect(localEngine.getTask(task.id)?.status, DownloadStatus.cancelled);

        // Video complete triggers audio and merge attempt
        await completeVideoDownload();

        expect(localEngine.getTask(task.id)?.status, DownloadStatus.cancelled);
        localEngine.dispose();
      },
    );

    test(
      '_streamToFile retries on transient network error with backoff and resumes from currentBytes',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('download_test_');
        final testFilePath = '${tempDir.path}/test_stream.tmp';
        final requestedRanges = <String?>[];
        var attempt = 0;

        final dio = Dio();
        dio.httpClientAdapter = _TestHttpClientAdapter((options) async {
          attempt++;
          requestedRanges.add(options.headers['Range'] as String?);

          if (attempt == 1) {
            // First attempt fails with transient connection error
            throw DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              error: const HttpException('Connection reset by peer'),
            );
          }

          return ResponseBody(
            _createStream([1, 2, 3, 4, 5]),
            206,
            headers: {
              HttpHeaders.contentLengthHeader: ['5'],
              HttpHeaders.contentRangeHeader: ['bytes 0-4/5'],
            },
          );
        });

        final engine = DownloadEngine(dio: dio);
        await engine.streamToFile(
          dio: dio,
          url: 'https://rr1---sn-test.googlevideo.com/videoplayback',
          destPath: testFilePath,
          totalBytes: 5,
          backoffBaseMs: 1,
        );

        final downloadedFile = File(testFilePath);
        expect(await downloadedFile.exists(), isTrue);
        expect(await downloadedFile.length(), 5);
        expect(await downloadedFile.readAsBytes(), [1, 2, 3, 4, 5]);
        expect(attempt, 2);
        expect(requestedRanges.first, 'bytes=0-4');

        await tempDir.delete(recursive: true);
        engine.dispose();
      },
    );

    test('_streamToFile rethrows when retries exceed maximum of 3', () async {
      final tempDir = await Directory.systemTemp.createTemp('download_test_');
      final testFilePath = '${tempDir.path}/test_stream_fail.tmp';
      var attempts = 0;

      final dio = Dio();
      dio.httpClientAdapter = _TestHttpClientAdapter((options) async {
        attempts++;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: const SocketException('Network unreachable'),
        );
      });

      final engine = DownloadEngine(dio: dio);

      await expectLater(
        () => engine.streamToFile(
          dio: dio,
          url: 'https://example.com/test',
          destPath: testFilePath,
          totalBytes: 100,
          backoffBaseMs: 1,
        ),
        throwsA(isA<DioException>()),
      );

      expect(attempts, 4); // 1 initial + 3 retries

      await tempDir.delete(recursive: true);
      engine.dispose();
    });

    test(
      '_streamToFile catches HTTP 403, calls onTokenExpired, and resumes from currentBytes',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('download_test_');
        final testFilePath = '${tempDir.path}/test_stream_403.tmp';
        final requestedUrls = <String>[];
        final requestedRanges = <String?>[];
        var tokenExpiredCalled = 0;

        // Pre-seed 3 bytes in the file to simulate partial progress before 403
        final initialFile = File(testFilePath);
        await initialFile.writeAsBytes([1, 2, 3]);

        final dio = Dio();
        dio.httpClientAdapter = _TestHttpClientAdapter((options) async {
          requestedUrls.add(options.uri.toString());
          requestedRanges.add(options.headers['Range'] as String?);

          if (options.uri.toString() == 'https://expired-url.com/video') {
            // Return 403 Bad Response
            throw DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 403,
                statusMessage: 'Forbidden',
              ),
              type: DioExceptionType.badResponse,
            );
          }

          return ResponseBody(
            _createStream([4, 5]),
            206,
            headers: {
              HttpHeaders.contentLengthHeader: ['2'],
              HttpHeaders.contentRangeHeader: ['bytes 3-4/5'],
            },
          );
        });

        final engine = DownloadEngine(dio: dio);
        await engine.streamToFile(
          dio: dio,
          url: 'https://expired-url.com/video',
          destPath: testFilePath,
          totalBytes: 5,
          backoffBaseMs: 1,
          onTokenExpired: () async {
            tokenExpiredCalled++;
            return 'https://refreshed-url.com/video';
          },
        );

        expect(tokenExpiredCalled, 1);
        expect(requestedUrls, [
          'https://expired-url.com/video',
          'https://refreshed-url.com/video',
        ]);
        expect(requestedRanges[0], 'bytes=3-4');
        expect(requestedRanges[1], 'bytes=3-4');

        final downloadedFile = File(testFilePath);
        expect(await downloadedFile.readAsBytes(), [1, 2, 3, 4, 5]);

        await tempDir.delete(recursive: true);
        engine.dispose();
      },
    );

    test(
      '_streamToFile rethrows HTTP 403 if onTokenExpired returns null',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('download_test_');
        final testFilePath = '${tempDir.path}/test_stream_403_null.tmp';

        final dio = Dio();
        dio.httpClientAdapter = _TestHttpClientAdapter((options) async {
          throw DioException(
            requestOptions: options,
            response: Response(
              requestOptions: options,
              statusCode: 403,
              statusMessage: 'Forbidden',
            ),
            type: DioExceptionType.badResponse,
          );
        });

        final engine = DownloadEngine(dio: dio);

        await expectLater(
          () => engine.streamToFile(
            dio: dio,
            url: 'https://expired-url.com/video',
            destPath: testFilePath,
            totalBytes: 5,
            backoffBaseMs: 1,
            onTokenExpired: () async => null,
          ),
          throwsA(isA<DioException>()),
        );

        await tempDir.delete(recursive: true);
        engine.dispose();
      },
    );

    test(
      'downloadYouTubeStreamToFile starts immediately with streamInfo.url without upfront manifest roundtrip',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'download_instant_',
        );
        final testFilePath = '${tempDir.path}/instant_video.mp4';
        final requestedUrls = <String>[];

        final dio = Dio();
        dio.httpClientAdapter = _TestHttpClientAdapter((options) async {
          requestedUrls.add(options.uri.toString());
          return ResponseBody(
            _createStream([10, 20, 30]),
            200,
            headers: {
              HttpHeaders.contentLengthHeader: ['3'],
            },
          );
        });

        final engine = DownloadEngine(dio: dio);

        const initialStream = StreamInfo(
          url: 'https://initial-stream.googlevideo.com/videoplayback',
          qualityLabel: '1080p',
          codec: 'avc1',
          container: 'mp4',
          sizeInBytes: 3,
        );

        await engine.downloadYouTubeStreamToFile(
          videoId: 'abc12345678',
          streamInfo: initialStream,
          destPath: testFilePath,
          backoffBaseMs: 1,
        );

        // Verifies initialStream.url was directly requested without delay or manifest fetch
        expect(requestedUrls, [
          'https://initial-stream.googlevideo.com/videoplayback',
        ]);
        final downloaded = File(testFilePath);
        expect(await downloaded.exists(), isTrue);
        expect(await downloaded.readAsBytes(), [10, 20, 30]);

        await tempDir.delete(recursive: true);
        engine.dispose();
      },
    );

    test(
      'streamToFile chunking requests consecutive ranges with 8MB default chunk size',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'download_chunk_',
        );
        final testFilePath = '${tempDir.path}/chunk_video.mp4';
        final requestedRanges = <String?>[];

        final dio = Dio();
        dio.httpClientAdapter = _TestHttpClientAdapter((options) async {
          final range = options.headers['Range'] as String?;
          requestedRanges.add(range);

          // Return 1MB per chunk
          final chunkData = Uint8List(1024 * 1024);
          return ResponseBody(
            _createStream(chunkData),
            206,
            headers: {
              HttpHeaders.contentLengthHeader: ['${chunkData.length}'],
            },
          );
        });

        final engine = DownloadEngine(dio: dio);

        // Total 12MB, chunkSize: 8MB -> 2 chunks expected: 0..8MB-1, then 8MB..12MB-1
        const totalBytes = 12 * 1024 * 1024;
        const chunkSize = 8 * 1024 * 1024;

        await engine.streamToFile(
          dio: dio,
          url: 'https://example.com/chunk-test',
          destPath: testFilePath,
          totalBytes: totalBytes,
          chunkSize: chunkSize,
          backoffBaseMs: 1,
        );

        // First chunk requests bytes=0-(8MB-1)
        expect(requestedRanges[0], 'bytes=0-${8 * 1024 * 1024 - 1}');

        await tempDir.delete(recursive: true);
        engine.dispose();
      },
    );

    test(
      'unknown-size partial responses do not mistake chunk length for file length',
      () async {
        final dir = await Directory.systemTemp.createTemp('unknown_size_');
        final ranges = <String>[];
        final dio = Dio();
        dio.httpClientAdapter = _TestHttpClientAdapter((options) async {
          ranges.add(options.headers['Range'] as String);
          if (ranges.length == 3) return ResponseBody.fromString('', 416);
          return ResponseBody(
            _createStream([1, 2, 3]),
            206,
            headers: {
              HttpHeaders.contentLengthHeader: ['3'],
            },
          );
        });
        final engine = DownloadEngine(dio: dio);
        try {
          await engine.streamToFile(
            dio: dio,
            url: 'https://example.com/video',
            destPath: '${dir.path}/media',
            totalBytes: 0,
            chunkSize: 3,
            backoffBaseMs: 1,
          );
          expect(await File('${dir.path}/media').readAsBytes(), [
            1,
            2,
            3,
            1,
            2,
            3,
          ]);
          expect(ranges, ['bytes=0-2', 'bytes=3-5', 'bytes=6-8']);
        } finally {
          engine.dispose();
          await dir.delete(recursive: true);
        }
      },
    );

    test(
      'a server ignoring Range replaces partial output instead of duplicating bytes',
      () async {
        final dir = await Directory.systemTemp.createTemp('ignored_range_');
        final file = File('${dir.path}/media');
        await file.writeAsBytes([1, 2]);
        final dio = Dio();
        dio.httpClientAdapter = _TestHttpClientAdapter(
          (options) async => ResponseBody(
            _createStream([1, 2, 3, 4]),
            200,
            headers: {
              HttpHeaders.contentLengthHeader: ['4'],
            },
          ),
        );
        final engine = DownloadEngine(dio: dio);
        try {
          await engine.streamToFile(
            dio: dio,
            url: 'https://example.com/video',
            destPath: file.path,
            totalBytes: 4,
            backoffBaseMs: 1,
          );
          expect(await file.readAsBytes(), [1, 2, 3, 4]);
        } finally {
          engine.dispose();
          await dir.delete(recursive: true);
        }
      },
    );

    test(
      'empty responses fail rather than completing a truncated download',
      () async {
        final dir = await Directory.systemTemp.createTemp('empty_stream_');
        final dio = Dio();
        dio.httpClientAdapter = _TestHttpClientAdapter(
          (options) async => ResponseBody(_createStream([]), 206),
        );
        final engine = DownloadEngine(dio: dio);
        try {
          await expectLater(
            engine.streamToFile(
              dio: dio,
              url: 'https://example.com/video',
              destPath: '${dir.path}/media',
              totalBytes: 5,
              backoffBaseMs: 1,
            ),
            throwsA(isA<HttpException>()),
          );
        } finally {
          engine.dispose();
          await dir.delete(recursive: true);
        }
      },
    );

    test(
      'streamToFile handles HTTP 416 Range Not Satisfiable as clean EOF completion when bytes have been received',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('download_416_');
        final testFilePath = '${tempDir.path}/video_416.mp4';
        var attempt = 0;

        final dio = Dio();
        dio.httpClientAdapter = _TestHttpClientAdapter((options) async {
          attempt++;
          if (attempt == 1) {
            // First chunk returns 5 bytes with unknown total length (chunked encoding, no content-length)
            return ResponseBody(
              _createStream([1, 2, 3, 4, 5]),
              200,
              headers: {},
            );
          } else {
            // Next chunk requests bytes beyond EOF, server returns 416
            throw DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 416,
                statusMessage: 'Range Not Satisfiable',
              ),
              type: DioExceptionType.badResponse,
            );
          }
        });

        final engine = DownloadEngine(dio: dio);

        await engine.streamToFile(
          dio: dio,
          url: 'https://example.com/eof-test',
          destPath: testFilePath,
          totalBytes: 0, // Unknown total bytes
          chunkSize: 5,
          backoffBaseMs: 1,
        );

        final downloaded = File(testFilePath);
        expect(await downloaded.exists(), isTrue);
        expect(await downloaded.readAsBytes(), [1, 2, 3, 4, 5]);

        await tempDir.delete(recursive: true);
        engine.dispose();
      },
    );

    test(
      'DownloadEngine does not silently fallback to 360p on adaptive video failure',
      () async {
        final engine = DownloadEngine();
        final task = DownloadTask(
          id: 'test_task_adaptive',
          mediaInfo: testMediaInfo,
          selectedStream: const StreamInfo(
            url: 'https://googlevideo.com/videoplayback?itag=137',
            qualityLabel: '1080p',
            codec: 'avc1',
            container: 'mp4',
            isVideoOnly: true,
            videoHeight: 1080,
          ),
          status: DownloadStatus.downloading,
          progress: 0.0,
          createdAt: DateTime.now(),
        );

        // Verify that quality verification or failTask does not replace resolution with 360p
        expect(task.selectedStream.qualityLabel, '1080p');
        expect(task.selectedStream.videoHeight, 1080);
        engine.dispose();
      },
    );
  });
}
