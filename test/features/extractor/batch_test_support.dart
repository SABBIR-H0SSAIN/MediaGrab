import 'dart:async';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/extractor/data/extractors/base_extractor.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';

const batchVideo = StreamInfo(
  url: 'https://cdn.example/720',
  qualityLabel: '720p',
  codec: 'h264',
  container: 'mp4',
  videoHeight: 720,
);
const batchAdaptive = StreamInfo(
  url: 'https://cdn.example/1080',
  qualityLabel: '1080p',
  codec: 'h264',
  container: 'mp4',
  videoHeight: 1080,
  isVideoOnly: true,
);
const batchAudio = StreamInfo(
  url: 'https://cdn.example/audio',
  qualityLabel: '128 kbps',
  codec: 'aac',
  container: 'm4a',
  isAudioOnly: true,
  bitrate: 128000,
);

class BatchTestExtractor extends BaseExtractor {
  final gates = <String, Completer<void>>{};
  final failures = <String>{};
  final metadataCalls = <String>[];
  final streamCalls = <String>[];
  List<StreamInfo> streams = [batchAdaptive, batchVideo, batchAudio];
  int active = 0;
  int maxActive = 0;
  @override
  bool canHandle(String url) => true;
  @override
  Future<MediaInfo> extractInfo(String url) async {
    metadataCalls.add(url);
    active++;
    if (active > maxActive) maxActive = active;
    try {
      await gates[url]?.future;
      if (failures.contains(url)) throw StateError('This video is private.');
      return MediaInfo(
        id: Uri.parse(url).queryParameters['v'] ?? url,
        title: 'Video ${Uri.parse(url).queryParameters['v'] ?? 'social'}',
        thumbnailUrl: '',
        duration: const Duration(seconds: 60),
        uploader: 'Author',
        platform: detectPlatform(url),
      );
    } finally {
      active--;
    }
  }

  @override
  Future<List<StreamInfo>> getStreams(String url) async {
    streamCalls.add(url);
    return streams;
  }
}
