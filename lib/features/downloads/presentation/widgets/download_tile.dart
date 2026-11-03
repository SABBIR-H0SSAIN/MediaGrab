import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/file_utils.dart';
import '../../../../shared/widgets/completed_media_tile.dart';
import '../../../../core/utils/url_parser.dart';
import '../../domain/entities/download_task.dart';
import '../../domain/enums/download_status.dart';
import '../providers/download_progress_provider.dart';

/// Ultra-modern Material 3 card presenting a single [DownloadTask] with media thumbnail,
/// duration badge, platform chip, quality/codec pill, real-time speed metrics,
/// animated progress bar, and contextual action controls.
class DownloadTile extends StatelessWidget {
  final DownloadTask task;
  final int index;
  final bool animate;
  final void Function(DownloadTask task)? onPause;
  final void Function(DownloadTask task)? onResume;
  final void Function(DownloadTask task)? onCancel;
  final void Function(DownloadTask task)? onRetry;
  final void Function(DownloadTask task)? onOpen;
  final void Function(DownloadTask task)? onShare;
  final void Function(DownloadTask task)? onOpenWith;
  final void Function(DownloadTask task)? onDelete;

  const DownloadTile({
    super.key,
    required this.task,
    this.index = 0,
    this.animate = true,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onRetry,
    this.onOpen,
    this.onShare,
    this.onOpenWith,
    this.onDelete,
  });

  /// Formats quality and codec into a pill label, e.g. "1080p • MP4" or "320 kbps • MP3".
  static String formatQualityPill(DownloadTask task) {
    final stream = task.selectedStream;
    final container =
        stream.container.isNotEmpty ? stream.container.toUpperCase() : 'MP4';
    if (stream.isAudioOnly) {
      final audioLabel =
          stream.formattedBitrate.isNotEmpty
              ? stream.formattedBitrate
              : (stream.qualityLabel.isNotEmpty
                  ? stream.qualityLabel
                  : 'Audio');
      return '$audioLabel • $container';
    } else {
      final videoLabel =
          stream.qualityLabel.isNotEmpty ? stream.qualityLabel : 'Video';
      return '$videoLabel • $container';
    }
  }

  /// Formatted subtitle description for backward compatibility and tests.
  static String buildSubtitle(DownloadTask task) {
    final quality = formatQualityPill(task);

    switch (task.status) {
      case DownloadStatus.downloading:
        final sizePart =
            (task.downloadedBytes != null && task.totalBytes != null)
                ? '${formatFileSize(task.downloadedBytes!)} / ${formatFileSize(task.totalBytes!)}'
                : task.selectedStream.formattedSize;
        final parts = [quality, sizePart];
        if (task.formattedSpeed.isNotEmpty) {
          parts.add(task.formattedSpeed);
        }
        if (task.formattedEta.isNotEmpty) {
          parts.add(task.formattedEta);
        }
        return parts.join(' • ');

      case DownloadStatus.merging:
        return '$quality • Merging video & audio...';

      case DownloadStatus.converting:
        return '$quality • Converting format...';

      case DownloadStatus.paused:
        return '$quality • Paused (${task.formattedProgress})';

      case DownloadStatus.completed:
        final size =
            task.totalBytes != null
                ? formatFileSize(task.totalBytes!)
                : task.selectedStream.formattedSize;
        return '$quality • $size';

      case DownloadStatus.failed:
        return '$quality • ${task.errorMessage ?? 'Download failed'}';

      case DownloadStatus.queued:
        return '$quality • ${task.selectedStream.formattedSize}';

      case DownloadStatus.cancelled:
        return '$quality • Cancelled';
    }
  }

  Widget _buildThumbnail(BuildContext context, DownloadTask currentTask) {
    final theme = Theme.of(context);
    final mediaInfo = currentTask.mediaInfo;
    final isAudio = currentTask.selectedStream.isAudioOnly;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 82,
        height: 58,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Media Image
            if (mediaInfo.thumbnailUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: mediaInfo.thumbnailUrl,
                fit: BoxFit.cover,
                placeholder:
                    (context, url) => Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                errorWidget:
                    (context, url, error) => Center(
                      child: Icon(
                        isAudio
                            ? Icons.audiotrack_rounded
                            : Icons.movie_outlined,
                        color: theme.colorScheme.primary,
                        size: 26,
                      ),
                    ),
              )
            else
              Center(
                child: Icon(
                  isAudio ? Icons.audiotrack_rounded : Icons.movie_outlined,
                  color: theme.colorScheme.primary,
                  size: 26,
                ),
              ),

            // Platform chip (top-left)
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  mediaInfo.platform.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                  ),
                ),
              ),
            ),

            // Duration badge (bottom-right)
            if (mediaInfo.duration > Duration.zero)
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    mediaInfo.formattedDuration,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrailingControls(
    BuildContext context,
    DownloadTask currentTask,
  ) {
    final theme = Theme.of(context);

    if (currentTask.status.isActive) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (currentTask.status == DownloadStatus.downloading)
            IconButton(
              icon: const Icon(Icons.pause_rounded),
              tooltip: 'Pause',
              color: theme.colorScheme.onSurfaceVariant,
              onPressed: onPause != null ? () => onPause!(currentTask) : null,
            ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cancel',
            color: theme.colorScheme.onSurfaceVariant,
            onPressed: onCancel != null ? () => onCancel!(currentTask) : null,
          ),
        ],
      );
    }

    if (currentTask.status == DownloadStatus.paused) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.play_arrow_rounded),
            tooltip: 'Resume',
            color: theme.colorScheme.primary,
            onPressed: onResume != null ? () => onResume!(currentTask) : null,
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cancel',
            color: theme.colorScheme.onSurfaceVariant,
            onPressed: onCancel != null ? () => onCancel!(currentTask) : null,
          ),
        ],
      );
    }

    if (currentTask.status == DownloadStatus.queued) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cancel',
            color: theme.colorScheme.onSurfaceVariant,
            onPressed: onCancel != null ? () => onCancel!(currentTask) : null,
          ),
        ],
      );
    }

    if (currentTask.status == DownloadStatus.completed) {
      return _buildCompletedTrailingControls(context, currentTask);
    }

    if (currentTask.status == DownloadStatus.failed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Retry',
            color: theme.colorScheme.primary,
            onPressed: onRetry != null ? () => onRetry!(currentTask) : null,
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Remove',
            color: theme.colorScheme.onSurfaceVariant,
            onPressed: onDelete != null ? () => onDelete!(currentTask) : null,
          ),
        ],
      );
    }

    // Cancelled fallback
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Retry',
          color: theme.colorScheme.primary,
          onPressed: onRetry != null ? () => onRetry!(currentTask) : null,
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Remove',
          color: theme.colorScheme.onSurfaceVariant,
          onPressed: onDelete != null ? () => onDelete!(currentTask) : null,
        ),
      ],
    );
  }

  Widget _buildCompletedTrailingControls(
    BuildContext context,
    DownloadTask currentTask,
  ) {
    final theme = Theme.of(context);

    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert_rounded,
        color: theme.colorScheme.onSurfaceVariant,
        size: 20,
      ),
      color: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      onSelected: (value) {
        switch (value) {
          case 'openWith':
            onOpenWith?.call(currentTask);
            break;
          case 'share':
            onShare?.call(currentTask);
            break;
          case 'details':
            _showDetailsDialog(context, currentTask);
            break;
          case 'delete':
            onDelete?.call(currentTask);
            break;
        }
      },
      itemBuilder:
          (context) => [
            const PopupMenuItem(
              value: 'openWith',
              child: Row(
                children: [
                  Icon(Icons.open_in_new_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('Open with'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'share',
              child: Row(
                children: [
                  Icon(Icons.share_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('Share'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'details',
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('Details'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Delete',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ),
            ),
          ],
    );
  }

  void _showDetailsDialog(BuildContext context, DownloadTask task) {
    final theme = Theme.of(context);
    final fileName =
        task.filePath?.split(Platform.pathSeparator).last ?? 'Unknown';

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: theme.colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          title: Text(
            'Media Details',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Title', task.mediaInfo.title, theme),
              const SizedBox(height: 8),
              _buildDetailRow('Filename', fileName, theme),
              const SizedBox(height: 8),
              if (task.filePath != null) ...[
                _buildDetailRow('Location', task.filePath!, theme),
                const SizedBox(height: 8),
              ],
              _buildDetailRow(
                'Quality',
                '${task.selectedStream.qualityLabel} • ${task.selectedStream.container.toUpperCase()}',
                theme,
              ),
              const SizedBox(height: 8),
              if (task.totalBytes != null && task.totalBytes! > 0) ...[
                _buildDetailRow(
                  'Size',
                  formatFileSize(task.totalBytes!),
                  theme,
                ),
                const SizedBox(height: 8),
              ],
              _buildDetailRow(
                'Platform',
                task.mediaInfo.platform.name.toUpperCase(),
                theme,
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.end,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildTileContent(BuildContext context, DownloadTask currentTask) {
    if (currentTask.status.isCompleted) {
      return CompletedMediaTile(
        title: currentTask.mediaInfo.title,
        thumbnailUrl: currentTask.mediaInfo.thumbnailUrl,
        isAudio: currentTask.selectedStream.isAudioOnly,
        platform: currentTask.mediaInfo.platform.displayName,
        format: formatQualityPill(currentTask),
        size: formatFileSize(
          currentTask.totalBytes ??
              currentTask.downloadedBytes ??
              currentTask.selectedStream.sizeInBytes ??
              0,
        ),
        duration:
            currentTask.mediaInfo.duration > Duration.zero
                ? currentTask.mediaInfo.formattedDuration
                : null,
        onPlay: onOpen == null ? null : () => onOpen!(currentTask),
        onMenu: _buildCompletedTrailingControls(context, currentTask),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      );
    }
    final theme = Theme.of(context);
    final isDownloading = currentTask.status == DownloadStatus.downloading;
    final isPaused = currentTask.status.isPaused;
    final isMerging = currentTask.status == DownloadStatus.merging;
    final isFailed = currentTask.status.isFailed;
    final isQueued = currentTask.status == DownloadStatus.queued;
    final showProgress = currentTask.status.isActive || isPaused;

    final downloaded = currentTask.downloadedBytes ?? 0;
    final total =
        currentTask.totalBytes ?? currentTask.selectedStream.sizeInBytes ?? 0;
    final transferredStr = formatFileSize(downloaded);
    final totalStr =
        total > 0
            ? formatFileSize(total)
            : currentTask.selectedStream.formattedSize;
    final sizeMetric = '$transferredStr / $totalStr';

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Row: Thumbnail + Title/Pills (+ Trailing Actions if not completed)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildThumbnail(context, currentTask),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Title (max 2 lines, spanning full available width)
                        Text(
                          currentTask.mediaInfo.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Single unified metadata pill row under title
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.secondaryContainer
                                    .withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                formatQualityPill(currentTask),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSecondaryContainer,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            if (isQueued)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.tertiaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Queued',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color:
                                        theme.colorScheme.onTertiaryContainer,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            if (isPaused)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Paused',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  _buildTrailingControls(context, currentTask),
                ],
              ),

              // Active / Paused Progress Bar & Real-time Metrics Row
              if (showProgress) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child:
                      animate
                          ? TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                            tween: Tween<double>(
                              begin: 0.0,
                              end:
                                  isMerging
                                      ? 0.95
                                      : currentTask.progress.clamp(0.0, 1.0),
                            ),
                            builder: (context, animatedProgress, _) {
                              return LinearProgressIndicator(
                                value: isMerging ? null : animatedProgress,
                                backgroundColor:
                                    theme.colorScheme.surfaceContainerHighest,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isPaused
                                      ? theme.colorScheme.outline
                                      : theme.colorScheme.primary,
                                ),
                                minHeight: 6,
                              );
                            },
                          )
                          : LinearProgressIndicator(
                            value:
                                isMerging
                                    ? null
                                    : currentTask.progress.clamp(0.0, 1.0),
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isPaused
                                  ? theme.colorScheme.outline
                                  : theme.colorScheme.primary,
                            ),
                            minHeight: 6,
                          ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    // Transferred vs Total
                    Text(
                      sizeMetric,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    // Speed
                    if (currentTask.formattedSpeed.isNotEmpty &&
                        isDownloading) ...[
                      Text(
                        currentTask.formattedSpeed,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // ETA
                    if (currentTask.formattedEta.isNotEmpty &&
                        isDownloading) ...[
                      Text(
                        currentTask.formattedEta,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // Percentage
                    Text(
                      isMerging
                          ? 'Merging...'
                          : (isPaused
                              ? 'Paused (${currentTask.formattedProgress})'
                              : currentTask.formattedProgress),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color:
                            isPaused
                                ? theme.colorScheme.outline
                                : theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ],

              // Failed State Information Row
              if (isFailed) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: theme.colorScheme.error,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        currentTask.errorMessage ?? 'Download failed',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasScope =
        context
            .dependOnInheritedWidgetOfExactType<UncontrolledProviderScope>() !=
        null;

    Widget content =
        !hasScope
            ? _buildTileContent(context, task)
            : Consumer(
              builder: (context, ref, _) {
                final currentTask =
                    ref.watch(downloadProgressProvider(task.id)) ?? task;
                return _buildTileContent(context, currentTask);
              },
            );

    if (animate) {
      content = content
          .animate(delay: (50 * index).ms)
          .fadeIn(duration: 300.ms, curve: Curves.easeOut)
          .slideY(begin: 0.1, end: 0, duration: 300.ms, curve: Curves.easeOut);
    }

    return content;
  }
}
