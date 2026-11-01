import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/downloads/data/services/media_merger.dart';
import 'package:mediagrab/features/downloads/data/services/media_merge_plan.dart';

Map<String, dynamic> input(
  String type, {
  String codec = 'aac',
  String start = '0',
  String duration = '80',
}) => {
  'streams': [
    {
      'codec_type': type,
      'codec_name': type == 'video' ? 'h264' : codec,
      'start_time': start,
      'duration': duration,
    },
  ],
};

void main() {
  test(
    'compatible AAC reaches copy first and does not invoke an encoder',
    () async {
      final commands = <List<String>>[];
      final merger = MediaMerger(
        probe: (path) async => input(path == 'video' ? 'video' : 'audio'),
        process: (args, token, diagnostic) async {
          commands.add(args);
          return true;
        },
      );
      expect(
        await merger.merge(
          'video',
          'audio',
          'output.mp4',
          allowVideoTranscode: true,
          aacBitrateKbps: 192,
        ),
        isTrue,
      );
      expect(commands, hasLength(1));
      expect(commands.single[commands.single.indexOf('-c:a') + 1], 'copy');
      expect(commands.single, isNot(contains('-af')));
      expect(commands.single, isNot(contains('-b:a')));
    },
  );

  test(
    'failed copy keeps the video and repairs audio with existing bitrate/sync',
    () async {
      final commands = <List<String>>[];
      final merger = MediaMerger(
        probe: (path) async => input(path == 'video' ? 'video' : 'audio'),
        process: (args, token, diagnostic) async {
          commands.add(args);
          return commands.length == 2;
        },
      );
      expect(
        await merger.merge('video', 'audio', 'output.mp4', aacBitrateKbps: 192),
        isTrue,
      );
      expect(commands, hasLength(2));
      final fallback = commands.last;
      expect(
        fallback,
        containsAllInOrder([
          '-c:v',
          'copy',
          '-c:a',
          'aac',
          '-b:a',
          '192k',
          '-af',
          'aresample=async=1',
        ]),
      );
    },
  );

  for (final kind in ['opus', 'offset', 'duration', 'unknown']) {
    test('$kind audio does not enter the AAC-copy fast path', () async {
      late List<String> command;
      final merger = MediaMerger(
        probe:
            (path) async =>
                kind == 'unknown'
                    ? null
                    : input(
                      path == 'video' ? 'video' : 'audio',
                      codec: kind == 'opus' ? 'opus' : 'aac',
                      start: path == 'audio' && kind == 'offset' ? '.2' : '0',
                      duration:
                          path == 'audio' && kind == 'duration' ? '70' : '80',
                    ),
        process: (args, token, diagnostic) async {
          command = args;
          return true;
        },
      );
      expect(await merger.merge('video', 'audio', 'output.mp4'), isTrue);
      expect(command[command.indexOf('-c:a') + 1], 'aac');
    });
  }

  test('probe errors use the established repair path', () async {
    late List<String> command;
    final merger = MediaMerger(
      probe: (_) async => throw StateError('Probe unavailable'),
      process: (args, token, diagnostic) async {
        command = args;
        return true;
      },
    );
    expect(await merger.merge('video', 'audio', 'output.mp4'), isTrue);
    expect(
      command,
      containsAllInOrder(['-c:a', 'aac', '-af', 'aresample=async=1']),
    );
  });

  test('WebM copy failure uses Opus and never AAC', () async {
    final codecs = <String>[];
    final merger = MediaMerger(
      probe: (_) async => throw StateError('No WebM input probe required'),
      process: (args, token, diagnostic) async {
        codecs.add(args[args.indexOf('-c:a') + 1]);
        return codecs.length == 2;
      },
    );
    expect(await merger.merge('v', 'a', 'out.WEBM'), isTrue);
    expect(codecs, ['copy', 'libopus']);
  });

  test(
    'YouTube-compatible default never re-encodes video on failure',
    () async {
      final commands = <List<String>>[];
      final merger = MediaMerger(
        probe: (_) async => null,
        process: (args, token, diagnostic) async {
          commands.add(args);
          return false;
        },
      );
      expect(await merger.merge('v', 'a', 'out.mp4'), isFalse);
      expect(commands, hasLength(2));
      expect(commands.every((a) => a[a.indexOf('-c:v') + 1] == 'copy'), isTrue);
    },
  );

  test(
    'generic container repair remains a last resort after both cheap strategies',
    () async {
      final codecs = <String>[];
      final merger = MediaMerger(
        probe: (_) async => null,
        process: (args, token, diagnostic) async {
          codecs.add(args[args.indexOf('-c:v') + 1]);
          return codecs.length == 3;
        },
      );
      expect(
        await merger.merge('v', 'a', 'out.mp4', allowVideoTranscode: true),
        isTrue,
      );
      expect(codecs, ['copy', 'copy', 'libx264']);
    },
  );

  test('cancellation cannot start a fallback encoder', () async {
    final token = CancelToken();
    var calls = 0;
    final merger = MediaMerger(
      probe: (_) async => null,
      process: (args, token, diagnostic) async {
        calls++;
        token.cancel('Paused');
        return false;
      },
    );
    await expectLater(
      merger.merge(
        'v',
        'a',
        'out.mp4',
        cancelToken: token,
        allowVideoTranscode: true,
      ),
      throwsA(isA<DioException>()),
    );
    expect(calls, 1);
  });

  test(
    'shared argument policy keeps video quality and timestamp normalization',
    () {
      final a = MediaMergePlan.arguments(
        video: 'v',
        audio: 'a',
        output: 'out.mp4',
        audioCodec: 'copy',
      );
      expect(
        a,
        containsAllInOrder([
          '-c:v',
          'copy',
          '-c:a',
          'copy',
          '-avoid_negative_ts',
          'make_zero',
          '-shortest',
        ]),
      );
    },
  );
}
