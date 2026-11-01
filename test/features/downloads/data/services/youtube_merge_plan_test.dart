import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/downloads/data/services/youtube_merge_plan.dart';

Map<String, dynamic> probe(
  String type,
  String codec, {
  String? start = '0.000000',
  String? duration = '634.566667',
}) => {
  'streams': [
    {
      'codec_type': type,
      'codec_name': codec,
      if (start != null) 'start_time': start,
      if (duration != null) 'duration': duration,
    },
  ],
};

void main() {
  final video = probe('video', 'h264');
  List<String> codecs(Map<String, dynamic>? audio) =>
      YoutubeMergePlan.audioCodecs(
        webm: false,
        videoProbe: video,
        audioProbe: audio,
      );

  test(
    'aligned original AAC uses lossless copy before resampling fallback',
    () {
      expect(codecs(probe('audio', 'aac', duration: '634.624580')), [
        'copy',
        'aac',
      ]);
    },
  );

  test('incompatible audio is encoded to AAC before MP4 muxing', () {
    expect(codecs(probe('audio', 'opus')), ['aac', 'copy']);
  });

  test('offset or mismatched duration keeps synchronization repair first', () {
    expect(codecs(probe('audio', 'aac', start: '0.2')), ['aac', 'copy']);
    expect(codecs(probe('audio', 'aac', duration: '632')), ['aac', 'copy']);
  });

  test('unverified or invalid timing cannot enable the fast path', () {
    for (final audio in [
      null,
      probe('audio', 'aac', start: null),
      probe('audio', 'aac', duration: null),
      probe('audio', 'aac', duration: 'NaN'),
      probe('audio', 'aac', duration: 'Infinity'),
      probe('audio', 'aac', duration: '-1'),
    ]) {
      expect(codecs(audio), ['aac', 'copy']);
    }
    expect(
      YoutubeMergePlan.audioCodecs(
        webm: false,
        audioProbe: probe('audio', 'aac'),
      ),
      ['aac', 'copy'],
    );
  });

  test('WebM retains copy and Opus fallback and never AAC', () {
    expect(YoutubeMergePlan.audioCodecs(webm: true), ['copy', 'libopus']);
  });

  test(
    'copy preserves timestamps and video without conflicting audio filters',
    () {
      final args = YoutubeMergePlan.arguments(
        video: 'v',
        audio: 'a',
        output: 'out.mp4',
        audioCodec: 'copy',
      );
      expect(args[args.indexOf('-c:v') + 1], 'copy');
      expect(args[args.indexOf('-c:a') + 1], 'copy');
      expect(
        args,
        containsAllInOrder(['-avoid_negative_ts', 'make_zero', '-shortest']),
      );
      expect(args, isNot(contains('-af')));
    },
  );

  test('encoding fallback retains async audio synchronization', () {
    final args = YoutubeMergePlan.arguments(
      video: 'v',
      audio: 'a',
      output: 'out.mp4',
      audioCodec: 'aac',
    );
    expect(args, containsAllInOrder(['-af', 'aresample=async=1']));
    expect(args[args.indexOf('-c:v') + 1], 'copy');
  });
}
