import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/downloads/data/services/youtube_transfer.dart';
import 'package:mediagrab/features/downloads/data/services/youtube_media_validation.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';

class Adapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) handler;
  Adapter(this.handler);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) => handler(options);
  @override
  void close({bool force = false}) {}
}

StreamInfo media({String token = 'old', int size = 8}) => StreamInfo(
  url:
      'https://example.googlevideo.com/videoplayback?id=test&itag=137&lmt=1&token=$token',
  qualityLabel: '1080p',
  codec: 'avc1',
  container: 'mp4',
  sizeInBytes: size,
  videoWidth: 1920,
  videoHeight: 1080,
  isVideoOnly: true,
);

ResponseBody range(List<int> bytes, int start, int end, int total) =>
    ResponseBody.fromBytes(
      bytes,
      206,
      headers: {
        'content-range': ['bytes $start-$end/$total'],
        'content-length': ['${bytes.length}'],
      },
    );

void main() {
  late Directory directory;
  late String path;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('youtube_transfer_');
    path = '${directory.path}/video.part';
  });
  tearDown(() async => directory.delete(recursive: true));

  Future<void> run(
    Future<ResponseBody> Function(RequestOptions) handler, {
    CancelToken? cancel,
    Future<StreamInfo> Function()? refresh,
    Duration? idle,
  }) => YoutubeTransfer(
    dio: Dio()..httpClientAdapter = Adapter(handler),
    chunkSize: 4,
    idleTimeout: idle ?? const Duration(seconds: 1),
    backoff: Duration.zero,
  ).download(
    selected: media(),
    path: path,
    token: cancel ?? CancelToken(),
    refresh: refresh ?? () async => media(token: 'new'),
  );

  test('downloads all chunks and verifies the total', () async {
    await run((o) async {
      final start = int.parse(
        RegExp(r'bytes=(\d+)').firstMatch(o.headers['Range'])![1]!,
      );
      return range(List.generate(4, (i) => start + i), start, start + 3, 8);
    });
    expect(await File(path).readAsBytes(), List.generate(8, (i) => i));
  });

  test(
    'connection loss resumes from actual received bytes after reconnecting',
    () async {
      final requests = <String>[];
      Stream<Uint8List> interrupted() async* {
        yield Uint8List.fromList([0, 1]);
        throw const SocketException('Connection reset during transfer');
      }

      await run((options) async {
        final requested = options.headers['Range'] as String;
        requests.add(requested);
        if (requests.length == 1) {
          return ResponseBody(
            interrupted(),
            206,
            headers: {
              'content-range': ['bytes 0-3/8'],
              'content-length': ['4'],
            },
          );
        }
        final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(requested)!;
        final start = int.parse(match[1]!);
        final end = int.parse(match[2]!);
        return range(
          List.generate(end - start + 1, (i) => start + i),
          start,
          end,
          8,
        );
      });
      expect(requests, ['bytes=0-3', 'bytes=2-5', 'bytes=6-7']);
      expect(await File(path).readAsBytes(), List.generate(8, (i) => i));
    },
  );

  test(
    'empty keepalive events do not conceal a stalled byte transfer',
    () async {
      final emptyEvents = Stream<Uint8List>.periodic(
        const Duration(milliseconds: 1),
        (_) => Uint8List(0),
      );
      await expectLater(
        YoutubeTransfer.controlledStream(
          emptyEvents,
          CancelToken(),
          const Duration(milliseconds: 10),
        ).drain<void>().timeout(const Duration(seconds: 1)),
        throwsA(
          isA<TimeoutException>().having(
            (e) => e.message,
            'message',
            'YouTube transfer stalled',
          ),
        ),
      );
    },
  );

  test(
    'resume refreshes URL and compares existing overlap before appending',
    () async {
      await File(path).writeAsBytes([0, 1, 2]);
      var refreshes = 0;
      await run(
        (o) async {
          expect(o.uri.queryParameters['token'], 'new');
          final start = int.parse(
            RegExp(r'bytes=(\d+)').firstMatch(o.headers['Range'])![1]!,
          );
          return range(List.generate(4, (i) => start + i), start, start + 3, 8);
        },
        refresh: () async {
          refreshes++;
          return media(token: 'new');
        },
      );
      expect(refreshes, 1);
      expect(await File(path).readAsBytes(), List.generate(8, (i) => i));
    },
  );

  test(
    'mismatched partial bytes are restarted without mixing resources',
    () async {
      await File(path).writeAsBytes([9, 9, 9]);
      await run((o) async {
        final start = int.parse(
          RegExp(r'bytes=(\d+)').firstMatch(o.headers['Range'])![1]!,
        );
        return range(List.generate(4, (i) => start + i), start, start + 3, 8);
      });
      expect(await File(path).readAsBytes(), List.generate(8, (i) => i));
    },
  );

  test('403 refresh uses a new URL and preserves the exact bytes', () async {
    var count = 0;
    await run((o) async {
      if (count++ == 1) {
        throw DioException(
          requestOptions: o,
          response: Response(requestOptions: o, statusCode: 403),
          type: DioExceptionType.badResponse,
        );
      }
      final start = int.parse(
        RegExp(r'bytes=(\d+)').firstMatch(o.headers['Range'])![1]!,
      );
      return range(List.generate(4, (i) => start + i), start, start + 3, 8);
    });
    expect(await File(path).readAsBytes(), List.generate(8, (i) => i));
  });

  test('permanent 403 has a global bounded refresh budget', () async {
    var requests = 0;
    var refreshes = 0;
    await expectLater(
      run(
        (o) async {
          requests++;
          throw DioException(
            requestOptions: o,
            response: Response(requestOptions: o, statusCode: 403),
            type: DioExceptionType.badResponse,
          );
        },
        refresh: () async {
          refreshes++;
          return media();
        },
      ),
      throwsA(isA<HttpException>()),
    );
    expect(requests, 3);
    expect(refreshes, 2);
  });

  for (final scenario in [
    'premature416',
    'wrongRange',
    'changedSize',
    'empty',
    'truncated',
    'oversize',
  ]) {
    test('rejects $scenario without reporting completion', () async {
      if (scenario == 'premature416') await File(path).writeAsBytes([0, 1]);
      await expectLater(
        run((o) async {
          switch (scenario) {
            case 'premature416':
              return ResponseBody.fromBytes(
                [],
                416,
                headers: {
                  'content-range': ['bytes */8'],
                },
              );
            case 'wrongRange':
              return range([1, 2], 2, 3, 8);
            case 'changedSize':
              return range([0, 1, 2, 3], 0, 3, 9);
            case 'empty':
              return range([], 0, 3, 8);
            case 'truncated':
              return range([0, 1], 0, 3, 8);
            default:
              return range([0, 1, 2, 3, 4], 0, 3, 8);
          }
        }),
        throwsA(isA<HttpException>()),
      );
    });
  }

  test('ignored range rewrites instead of duplicating partial bytes', () async {
    await File(path).writeAsBytes([9, 9, 9]);
    await run(
      (o) async => ResponseBody.fromBytes(
        List.generate(8, (i) => i),
        200,
        headers: {
          'content-length': ['8'],
        },
      ),
    );
    expect(await File(path).readAsBytes(), List.generate(8, (i) => i));
  });

  test('stalled response body fails within its activity deadline', () async {
    var calls = 0;
    await expectLater(
      run((o) async {
        calls++;
        return ResponseBody(
          StreamController<Uint8List>().stream,
          206,
          headers: {
            'content-range': ['bytes 0-3/8'],
          },
        );
      }, idle: const Duration(milliseconds: 10)),
      throwsA(
        anyOf(
          isA<TimeoutException>(),
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.receiveTimeout,
          ),
        ),
      ),
    );
    expect(calls, 4);
  });

  test('cancel interrupts a silent transfer and closes its writer', () async {
    final token = CancelToken();
    final body = StreamController<Uint8List>();
    final started = Completer<void>();
    final future = run((o) async {
      started.complete();
      return ResponseBody(
        body.stream,
        206,
        headers: {
          'content-range': ['bytes 0-3/8'],
        },
      );
    }, cancel: token);
    await started.future;
    token.cancel('Pause');
    await expectLater(future, throwsA(isA<DioException>()));
    await File(path).writeAsBytes([7]);
    expect(await File(path).readAsBytes(), [7]);
  });

  test(
    'native timeout cannot hang on an upstream cancellation future',
    () async {
      var closed = false;
      final upstream = StreamController<int>(
        onCancel: () => Completer<void>().future,
      );
      await expectLater(
        YoutubeTransfer.controlledStream(
          upstream.stream,
          CancelToken(),
          const Duration(milliseconds: 10),
          onStop: () {
            closed = true;
          },
        ).drain<void>().timeout(const Duration(seconds: 1)),
        throwsA(
          isA<TimeoutException>().having(
            (e) => e.message,
            'message',
            'YouTube transfer stalled',
          ),
        ),
      );
      expect(closed, isTrue);
    },
  );

  Map<String, Object> probe({
    int height = 1080,
    bool audio = true,
    double duration = 20,
    String fps = '60/1',
  }) => {
    'format': {'duration': '$duration'},
    'streams': [
      {
        'codec_type': 'video',
        'codec_name': 'h264',
        'width': 1920,
        'height': height,
        'avg_frame_rate': fps,
        'duration': '$duration',
      },
      if (audio)
        {'codec_type': 'audio', 'codec_name': 'aac', 'duration': '$duration'},
    ],
  };
  void validate(Map<String, Object> data) => YoutubeMediaValidation.validate(
    probe: data,
    audioOnly: false,
    width: 1920,
    height: 1080,
    quality: '1080p60',
    expectedDuration: const Duration(seconds: 20),
  );

  test(
    'validates exact resolution, audio, frame rate and duration',
    () => validate(probe()),
  );
  for (final scenario in ['resolution', 'audio', 'duration', 'fps']) {
    test('rejects output with incorrect $scenario', () {
      expect(
        () => validate(
          probe(
            height: scenario == 'resolution' ? 720 : 1080,
            audio: scenario != 'audio',
            duration: scenario == 'duration' ? 5 : 20,
            fps: scenario == 'fps' ? '30/1' : '60/1',
          ),
        ),
        throwsStateError,
      );
    });
  }
}
