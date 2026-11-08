import '../../../player/presentation/utils/playback_navigation.dart';
import '../../../../shared/widgets/brand_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/utils/url_parser.dart';
import '../../../downloads/domain/entities/download_task.dart';
import '../../../downloads/domain/enums/download_status.dart';
import '../../../downloads/presentation/providers/download_manager_provider.dart';

/// Section showing recent downloads from [recentDownloadsProvider] with a "See all" button.
///
/// If empty, displays a polished Material 3 empty state illustration and message.
/// When items exist, displays horizontal cards showing thumbnail, quality badge,
/// platform badge, title, and status.
class RecentDownloadsSection extends ConsumerWidget {
  const RecentDownloadsSection({super.key, this.onSeeAll, this.onTapDownload});

  final VoidCallback? onSeeAll;
  final void Function(DownloadTask task)? onTapDownload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final recentDownloads = ref.watch(recentDownloadsProvider);

    return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Recent Downloads',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 4,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    if (onSeeAll != null) {
                      onSeeAll!();
                    } else if (GoRouter.maybeOf(context) != null) {
                      ref.read(downloadsSelectedTabProvider.notifier).state = 1;
                      context.go('/downloads?tab=completed');
                    }
                  },
                  child: Text(
                    'See all',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (recentDownloads.isEmpty)
              _buildEmptyState(context, theme)
            else
              _buildDownloadsList(context, theme, ref, recentDownloads),
          ],
        )
        .animate(delay: 200.ms)
        .fadeIn(duration: 400.ms, curve: Curves.easeOut)
        .slideY(begin: 0.08, end: 0, duration: 400.ms, curve: Curves.easeOut);
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: .6,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MediaStackArtwork(size: 52, icon: Icons.play_arrow_rounded),
          const SizedBox(height: 8),
          Text(
            'No recent downloads',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your downloaded videos will appear here',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadsList(
    BuildContext context,
    ThemeData theme,
    WidgetRef ref,
    List<DownloadTask> tasks,
  ) {
    return SizedBox(
      height: 195,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tasks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final task = tasks[index];
          return _buildDownloadCard(context, theme, ref, task, tasks);
        },
      ),
    );
  }

  Widget _buildDownloadCard(
    BuildContext context,
    ThemeData theme,
    WidgetRef ref,
    DownloadTask task,
    List<DownloadTask> visibleTasks,
  ) {
    final qualityLabel = task.selectedStream.qualityLabel;
    final platform = task.mediaInfo.platform;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (onTapDownload != null) {
            onTapDownload!(task);
            return;
          }
          final filePath = task.filePath;
          if (filePath != null && task.status == DownloadStatus.completed) {
            openLocalPlayback(
              context,
              playbackItemFromTask(task),
              visibleTasks
                  .where((t) => t.status == DownloadStatus.completed)
                  .map(playbackItemFromTask),
            );
            return;
          }
          if (GoRouter.maybeOf(context) != null) {
            ref.read(downloadsSelectedTabProvider.notifier).state = 1;
            context.go('/downloads?tab=completed');
          }
        },
        child: SizedBox(
          width: 230,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail area with badges
              Stack(
                children: [
                  Container(
                    height: 105,
                    width: double.infinity,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child:
                        task.mediaInfo.thumbnailUrl.isNotEmpty
                            ? Image.network(
                              task.mediaInfo.thumbnailUrl,
                              fit: BoxFit.cover,
                              errorBuilder:
                                  (_, __, ___) => _buildThumbPlaceholder(theme),
                            )
                            : _buildThumbPlaceholder(theme),
                  ),
                  // Platform indicator (top-left)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: _buildPlatformBadge(platform),
                  ),
                  // Quality badge (bottom-right)
                  if (qualityLabel.isNotEmpty)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          qualityLabel,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              // Meta info
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.mediaInfo.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildStatusRow(theme, task),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbPlaceholder(ThemeData theme) {
    return Center(
      child: Icon(
        Icons.smart_display_rounded,
        size: 36,
        color: theme.colorScheme.outlineVariant,
      ),
    );
  }

  Widget _buildPlatformBadge(PlatformType platform) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        shape: BoxShape.circle,
      ),
      child: PlatformLogo(platform: platform.name, size: 14),
    );
  }

  Widget _buildStatusRow(ThemeData theme, DownloadTask task) {
    if (task.status.isActive) {
      return Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress > 0 ? task.progress : null,
                minHeight: 4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            task.formattedProgress,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      );
    }

    final IconData icon;
    final Color color;
    final String label;

    switch (task.status) {
      case DownloadStatus.completed:
        icon = Icons.check_circle_rounded;
        color = Colors.green;
        label = 'Completed';
        break;
      case DownloadStatus.paused:
        icon = Icons.pause_circle_rounded;
        color = Colors.orange;
        label = 'Paused';
        break;
      case DownloadStatus.failed:
        icon = Icons.error_outline_rounded;
        color = theme.colorScheme.error;
        label = 'Failed';
        break;
      case DownloadStatus.queued:
        icon = Icons.schedule_rounded;
        color = theme.colorScheme.outline;
        label = 'Queued';
        break;
      case DownloadStatus.cancelled:
        icon = Icons.cancel_outlined;
        color = theme.colorScheme.outline;
        label = 'Cancelled';
        break;
      default:
        icon = Icons.info_outline_rounded;
        color = theme.colorScheme.outline;
        label = task.status.displayName;
    }

    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
