import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../../home/presentation/widgets/platform_chip.dart';
import '../../domain/entities/media_info.dart';

/// Preview card displaying video thumbnail, duration badge, title, author avatar & channel name, view count, and upload date.
class VideoPreviewCard extends StatelessWidget {
  final MediaInfo mediaInfo;

  const VideoPreviewCard({super.key, required this.mediaInfo});

  static const _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _formatDate(DateTime date) {
    final month = _monthNames[date.month - 1];
    return '$month ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thumbnail with aspect ratio 16:9 and rounded corners
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: mediaInfo.thumbnailUrl,
                      fit: BoxFit.cover,
                      placeholder:
                          (context, url) => Shimmer.fromColors(
                            baseColor:
                                theme.colorScheme.surfaceContainerHighest,
                            highlightColor: theme.colorScheme.surfaceContainer,
                            child: Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                            ),
                          ),
                      errorWidget:
                          (context, url, error) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.broken_image,
                              size: 48,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                    ),
                    // Platform icon chip in top-left corner
                    Positioned(
                      top: 8,
                      left: 8,
                      child: PlatformChip(platform: mediaInfo.platform),
                    ),
                    // Duration badge in bottom-right corner
                    if (mediaInfo.duration > Duration.zero)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            mediaInfo.formattedDuration,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Title (titleMedium, max 2 lines)
            Text(
              mediaInfo.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            // Author avatar & channel name + view count & upload date
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    mediaInfo.uploader.isNotEmpty
                        ? mediaInfo.uploader[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mediaInfo.uploader,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (mediaInfo.viewCount != null ||
                          mediaInfo.uploadDate != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (mediaInfo.viewCount != null)
                              Text(
                                mediaInfo.formattedViews,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            if (mediaInfo.viewCount != null &&
                                mediaInfo.uploadDate != null)
                              Text(
                                ' • ',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            if (mediaInfo.uploadDate != null)
                              Text(
                                _formatDate(mediaInfo.uploadDate!),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
