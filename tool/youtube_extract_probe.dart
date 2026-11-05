// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:mediagrab/features/extractor/data/extractors/youtube_extractor.dart';

Future<void> main(List<String> args) async {
  final extractor = YoutubeExtractor();
  try {
    for (final id in args.isEmpty ? ['BaW_jenozKc'] : args) {
      final watch = Stopwatch()..start();
      try {
        final streams = await extractor
            .getStreams(id)
            .timeout(const Duration(seconds: 90));
        print(
          jsonEncode({
            'id': id,
            'ms': watch.elapsedMilliseconds,
            'formats':
                streams
                    .map(
                      (s) => {
                        'itag': Uri.parse(s.url).queryParameters['itag'],
                        'client': Uri.parse(s.url).queryParameters['c'],
                        'quality': s.qualityLabel,
                        'codec': s.codec,
                        'size': s.sizeInBytes,
                      },
                    )
                    .toList(),
          }),
        );
      } catch (e) {
        print(
          jsonEncode({
            'id': id,
            'ms': watch.elapsedMilliseconds,
            'error': e.runtimeType.toString(),
          }),
        );
      }
    }
  } finally {
    extractor.close();
  }
}
