import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/utils/file_utils.dart';
import '../../../downloads/domain/entities/download_task.dart';
import '../../../downloads/presentation/providers/download_manager_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/media_info.dart';
import '../../domain/entities/prepared_download.dart';
import '../../domain/entities/stream_info.dart';
import '../providers/extractor_provider.dart';

/// Centralized helper to resolve download directories and actual media streams,
/// sanitize filenames, and enqueue a batch of [MediaInfo] items into [downloadManagerProvider].
Future<List<DownloadTask>> enqueueBatchMediaDownloads({
  required WidgetRef ref,
  List<MediaInfo> videos = const [],
  List<PreparedDownload> prepared = const [],
  void Function(String sourceUrl, Object error)? onItemError,
  void Function(String sourceUrl, DownloadTask task)? onItemQueued,
  String? targetDirectory,
}) async {
  if (videos.isEmpty && prepared.isEmpty) return const [];

  final settings = ref.read(settingsProvider);
  final factory = ref.read(extractorFactoryProvider);
  final downloadManager = ref.read(downloadManagerProvider.notifier);
  String baseDir = targetDirectory ?? '';
  if (baseDir.isEmpty) {
    baseDir = settings.downloadDirectory.trim();
  }
  if (baseDir.isEmpty) {
    try {
      final dir = await getApplicationDocumentsDirectory();
      baseDir = dir.path;
    } catch (_) {
      try {
        final extDir = await getExternalStorageDirectory();
        baseDir = extDir?.path ?? Directory.systemTemp.path;
      } catch (_) {
        baseDir = Directory.systemTemp.path;
      }
    }
  }

  final tasks = <DownloadTask>[];

  for (var index = 0; index < videos.length + prepared.length; index++) {
    final reviewed =
        index >= videos.length ? prepared[index - videos.length] : null;
    final video = reviewed?.media ?? videos[index];
    final videoUrl =
        reviewed != null
            ? reviewed.sourceUrl
            : video.id.startsWith('http')
            ? video.id
            : 'https://www.youtube.com/watch?v=${video.id}';
    try {
      final extractor = factory.getExtractorOrThrow(videoUrl);
      final media =
          reviewed?.media ??
          (video.id.startsWith('http')
              ? await extractor.extractInfo(videoUrl)
              : video);
      final streams =
          reviewed != null
              ? [
                reviewed.stream,
                if (reviewed.audioStream != null) reviewed.audioStream!,
              ]
              : await extractor.getStreams(videoUrl);
      final wantsAudio = settings.defaultVideoQuality.toLowerCase().contains(
        'audio',
      );
      final candidates =
          streams
              .where(
                (s) =>
                    s.isAudioOnly ==
                    (reviewed?.stream.isAudioOnly ?? wantsAudio),
              )
              .toList();
      if (candidates.isEmpty) {
        throw StateError('No downloadable streams found for "${media.title}"');
      }
      candidates.sort(
        (a, b) =>
            wantsAudio
                ? (b.bitrate ?? 0).compareTo(a.bitrate ?? 0)
                : (b.videoHeight ?? 0).compareTo(a.videoHeight ?? 0),
      );
      var selected = reviewed?.stream ?? candidates.first;
      final preferredHeight = int.tryParse(
        settings.defaultVideoQuality.replaceAll(RegExp(r'[^0-9]'), ''),
      );
      if (reviewed == null && !wantsAudio && preferredHeight != null) {
        selected = candidates.firstWhere(
          (s) => s.videoHeight == preferredHeight,
          orElse: () => candidates.first,
        );
      }
      final audio =
          streams.where((s) => s.isAudioOnly).toList()
            ..sort((a, b) => (b.bitrate ?? 0).compareTo(a.bitrate ?? 0));
      final StreamInfo? companion =
          reviewed?.audioStream ??
          (selected.isVideoOnly && audio.isNotEmpty ? audio.first : null);
      if (selected.isVideoOnly && companion == null) {
        throw StateError('No companion audio available for "${media.title}"');
      }
      final container = selected.container.replaceAll('.', '').trim();
      final ext =
          selected.isAudioOnly && container == 'mp4' ? 'm4a' : container;
      final name = sanitizeFilename('${media.title} [${media.id}]');
      final task = await downloadManager.startDownload(
        media,
        selected,
        '$baseDir/$name.${ext.isEmpty ? 'mp4' : ext}',
        audioStream: companion,
      );
      tasks.add(task);
      onItemQueued?.call(videoUrl, task);
    } on CellularDownloadBlockedException catch (error) {
      onItemError?.call(videoUrl, error);
      if (onItemError == null) break;
    } catch (error) {
      onItemError?.call(videoUrl, error);
      if (onItemError == null && videos.length + prepared.length == 1) rethrow;
    }
  }

  return tasks;
}
