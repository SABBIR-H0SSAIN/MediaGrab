import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:mediagrab/features/downloads/data/services/youtube_transfer.dart';
import 'package:mediagrab/features/extractor/data/extractors/youtube_extractor.dart';

Future<void> main(List<String> args) async {
  final extractor = YoutubeExtractor();
  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 20)));
  final id = args.isEmpty ? 'aqz-KE-bpKQ' : args.first;
  final quality = args.length > 1 ? args[1] : '360p';
  final watch = Stopwatch()..start();
  final directory = await Directory.systemTemp.createTemp('youtube_live_');
  try {
    final streams = await extractor.getStreams(id);
    final selected = streams.firstWhere((s) => s.qualityLabel == quality);
    await YoutubeTransfer(
      dio: dio,
      diagnostic:
          (event, data) =>
              stdout.writeln(jsonEncode({'event': event, ...data})),
    ).download(
      selected: selected,
      path: '${directory.path}/video.${selected.container}',
      token: CancelToken(),
      refresh: () async {
        extractor.clearManifestCache();
        return (await extractor.getStreams(id)).firstWhere(
          (s) =>
              Uri.parse(s.url).queryParameters['itag'] ==
              Uri.parse(selected.url).queryParameters['itag'],
        );
      },
    );
    stdout.writeln(
      jsonEncode({
        'status': 'TRANSFER_VERIFIED',
        'id': id,
        'quality': quality,
        'ms': watch.elapsedMilliseconds,
        'file': directory.path,
      }),
    );
  } catch (e) {
    stdout.writeln(
      jsonEncode({
        'status': 'FAILED',
        'type': e.runtimeType.toString(),
        'ms': watch.elapsedMilliseconds,
      }),
    );
    exitCode = 1;
  } finally {
    dio.close(force: true);
    extractor.close();
  }
}
