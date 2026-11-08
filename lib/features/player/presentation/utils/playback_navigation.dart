import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import '../../../downloads/domain/entities/download_task.dart';
import '../../domain/playback_state.dart';

PlaybackItem playbackItemFromTask(DownloadTask task) => PlaybackItem(
  id: task.id,
  filePath: task.filePath ?? '',
  title: task.mediaInfo.title,
  isAudio: task.selectedStream.isAudioOnly,
);

void openLocalPlayback(
  BuildContext context,
  PlaybackItem selected,
  Iterable<PlaybackItem> visibleItems,
) {
  final items = visibleItems.where((item) => item.filePath.isNotEmpty).toList();
  var index = items.indexWhere((item) => item.filePath == selected.filePath);
  if (index < 0) {
    items.add(selected);
    index = items.length - 1;
  }
  context.push(
    Uri(
      path: '/player',
      queryParameters: {'filePath': selected.filePath, 'title': selected.title},
    ).toString(),
    extra: PlaybackQueue(items, index: index),
  );
}
