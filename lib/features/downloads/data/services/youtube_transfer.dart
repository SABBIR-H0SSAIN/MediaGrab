import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import '../../../extractor/domain/entities/stream_info.dart';

typedef YoutubeDiagnostic =
    void Function(String event, Map<String, Object?> data);

/// Range transport used only by YouTube. Never infer completion from a 416 alone.
class YoutubeTransfer {
  final Dio dio;
  final Duration idleTimeout;
  final Duration backoff;
  final int chunkSize;
  final YoutubeDiagnostic? diagnostic;

  YoutubeTransfer({
    required this.dio,
    this.idleTimeout = const Duration(seconds: 20),
    this.backoff = const Duration(milliseconds: 500),
    this.chunkSize = 1024 * 1024,
    this.diagnostic,
  });

  Future<void> download({
    required StreamInfo selected,
    required String path,
    required CancelToken token,
    required Future<StreamInfo> Function() refresh,
    void Function(int, int)? onProgress,
  }) async {
    var resource = selected;
    var total = resource.sizeInBytes ?? 0;
    final file = File(path);
    await file.parent.create(recursive: true);
    final output = await file.open(mode: FileMode.append);
    var offset = await output.length();
    // Check an overlap before trusting partial data, including a full-size file.
    var continuity = offset > 0;
    var retries = 0;
    var refreshes = 0;
    try {
      if (offset > 0) {
        resource = await _controlled(
          refresh(),
          token,
          timeout: const Duration(seconds: 45),
        );
        total = resource.sizeInBytes ?? 0;
      }
      if (total <= 0 || offset > total || !_sameResource(selected, resource)) {
        await output.truncate(0);
        offset = 0;
        continuity = false;
        diagnostic?.call('restart', {
          'reason': 'media identity or size changed',
        });
      }
      while (total <= 0 || offset < total || continuity) {
        token.throwIfCancellationRequested();
        final start = continuity ? math.max(0, offset - 65536) : offset;
        final end =
            total > 0
                ? math.min(start + chunkSize - 1, total - 1)
                : start + chunkSize - 1;
        final requestToken = CancelToken();
        unawaited(token.whenCancel.then((e) => requestToken.cancel(e)));
        try {
          final client = Uri.parse(resource.url).queryParameters['c'] ?? '';
          final response = await _controlled<Response<ResponseBody>>(
            dio.get<ResponseBody>(
              resource.url,
              options: Options(
                responseType: ResponseType.stream,
                receiveTimeout: idleTimeout,
                sendTimeout: idleTimeout,
                headers: {
                  'User-Agent':
                      client.startsWith('ANDROID')
                          ? 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip'
                          : 'Mozilla/5.0',
                  'Accept': '*/*',
                  'Accept-Encoding': 'identity',
                  'Range': 'bytes=$start-$end',
                },
                validateStatus: (s) => s == 200 || s == 206 || s == 416,
              ),
              cancelToken: requestToken,
            ),
            token,
          );
          final status = response.statusCode;
          diagnostic?.call('http', {'status': status, 'offset': start});
          if (status == 416) {
            final match = RegExp(
              r'^bytes \*/(\d+)$',
            ).firstMatch(response.headers.value('content-range') ?? '');
            final actual = match == null ? null : int.tryParse(match[1]!);
            if (actual != null &&
                actual == offset &&
                total == offset &&
                !continuity) {
              break;
            }
            throw const HttpException(
              'YouTube rejected a range before verified completion',
            );
          }
          final range = RegExp(
            r'^bytes (\d+)-(\d+)/(\d+)$',
          ).firstMatch(response.headers.value('content-range') ?? '');
          int expected;
          if (status == 206) {
            if (range == null || int.parse(range[1]!) != start) {
              throw const HttpException(
                'YouTube returned an invalid Content-Range',
              );
            }
            final rangeEnd = int.parse(range[2]!);
            final rangeTotal = int.parse(range[3]!);
            if (rangeEnd < start ||
                rangeEnd > end ||
                rangeEnd >= rangeTotal ||
                (total > 0 && total != rangeTotal)) {
              throw const HttpException(
                'YouTube resource length or range changed',
              );
            }
            total = rangeTotal;
            expected = rangeEnd - start + 1;
          } else {
            // Ignored Range: rewrite from zero, never append a whole response.
            if (start > 0 || offset > 0) {
              await output.truncate(0);
              offset = 0;
              continuity = false;
            }
            expected =
                int.tryParse(response.headers.value('content-length') ?? '') ??
                total;
            if (total > 0 && expected > 0 && expected != total) {
              throw const HttpException('YouTube full response length changed');
            }
            if (total <= 0) total = expected;
          }
          var received = 0;
          final overlap = continuity ? offset - start : 0;
          Uint8List? old;
          if (overlap > 0) {
            await output.setPosition(start);
            old = await output.read(overlap);
          }
          await output.setPosition(offset);
          await for (final bytes in controlledStream(
            response.data!.stream,
            token,
            idleTimeout,
          )) {
            final previous = received;
            received += bytes.length;
            if (expected > 0 && received > expected) {
              throw const HttpException(
                'YouTube response exceeds the requested length',
              );
            }
            var skip = 0;
            while (old != null &&
                previous + skip < overlap &&
                skip < bytes.length) {
              if (old[previous + skip] != bytes[skip]) {
                await output.truncate(0);
                offset = 0;
                continuity = false;
                throw const HttpException(
                  'YouTube partial data changed; restarting stream',
                );
              }
              skip++;
            }
            if (skip < bytes.length) {
              await output.writeFrom(bytes, skip);
              offset += bytes.length - skip;
              onProgress?.call(offset, total);
            }
          }
          if (expected <= 0 || received != expected || received < overlap) {
            throw const HttpException(
              'YouTube response ended before its expected length',
            );
          }
          continuity = false;
          retries = 0;
          diagnostic?.call('bytes', {'downloaded': offset, 'total': total});
        } catch (error) {
          token.throwIfCancellationRequested();
          final status =
              error is DioException ? error.response?.statusCode : null;
          diagnostic?.call('recovery', {
            'status': status,
            'type': error.runtimeType.toString(),
            'retry': retries,
            'refresh': refreshes,
          });
          if (status == 403 || status == 410) {
            if (++refreshes > 2) {
              throw const HttpException(
                'YouTube access denied after fresh extraction (HTTP 403/410). The video may require authentication or client attestation.',
              );
            }
            final fresh = await _controlled(
              refresh(),
              token,
              timeout: const Duration(seconds: 45),
            );
            if (!_sameResource(resource, fresh)) {
              await output.truncate(0);
              offset = 0;
            }
            resource = fresh;
            total = fresh.sizeInBytes ?? 0;
            continuity = offset > 0;
          } else {
            if (status != null &&
                status >= 400 &&
                status < 500 &&
                status != 408 &&
                status != 429) {
              rethrow;
            }
            if (error is! DioException &&
                error is! HttpException &&
                error is! SocketException &&
                error is! TimeoutException) {
              rethrow;
            }
            if (++retries > 3) rethrow;
          }
          await _controlled(
            Future<void>.delayed(
              backoff * (1 << math.min(retries + refreshes - 1, 4)),
            ),
            token,
          );
        } finally {
          // Terminates rejected response bodies and timed-out requests too.
          requestToken.cancel('YouTube range finished');
        }
      }
      if (total <= 0 || offset != total) {
        throw const HttpException('YouTube stream is incomplete');
      }
      await output.flush();
      onProgress?.call(offset, total);
    } finally {
      await output.close();
    }
  }

  Future<T> _controlled<T>(
    Future<T> future,
    CancelToken token, {
    Duration? timeout,
  }) => Future.any([
    future.timeout(timeout ?? idleTimeout),
    token.whenCancel.then<T>((error) => throw error),
  ]);

  static bool _sameResource(StreamInfo a, StreamInfo b) {
    final x = Uri.parse(a.url).queryParameters;
    final y = Uri.parse(b.url).queryParameters;
    return a.sizeInBytes != null &&
        a.sizeInBytes! > 0 &&
        a.sizeInBytes == b.sizeInBytes &&
        a.codec == b.codec &&
        a.container == b.container &&
        a.qualityLabel == b.qualityLabel &&
        ['itag', 'lmt', 'clen', 'xtags'].every((key) => x[key] == y[key]);
  }

  /// Cancellation interrupts a silent socket; the owner also closes its client.
  static Stream<T> controlledStream<T>(
    Stream<T> source,
    CancelToken token,
    Duration idle, {
    void Function()? onStop,
  }) {
    late StreamController<T> controller;
    StreamSubscription<T>? subscription;
    Timer? timer;
    void stop(Object error) {
      if (controller.isClosed) return;
      timer?.cancel();
      onStop?.call();
      unawaited(subscription?.cancel().catchError((Object _) {}));
      controller.addError(error);
      unawaited(controller.close());
    }

    void arm() {
      timer?.cancel();
      timer = Timer(
        idle,
        () => stop(TimeoutException('YouTube transfer stalled', idle)),
      );
    }

    controller = StreamController<T>(
      onListen: () {
        arm();
        subscription = source.listen(
          (data) {
            if (controller.isClosed) return;
            if (data is List && data.isEmpty) return;
            arm();
            controller.add(data);
          },
          onError: (Object error, StackTrace stack) => stop(error),
          onDone: () {
            timer?.cancel();
            unawaited(controller.close());
          },
        );
        unawaited(token.whenCancel.then(stop));
      },
      onCancel: () {
        timer?.cancel();
        onStop?.call();
        unawaited(subscription?.cancel().catchError((Object _) {}));
      },
    );
    return controller.stream;
  }
}

/// Dio exposes cancellation as a future and nullable error.
extension YoutubeCancellation on CancelToken {
  void throwIfCancellationRequested() {
    if (isCancelled) throw cancelError!;
  }
}
