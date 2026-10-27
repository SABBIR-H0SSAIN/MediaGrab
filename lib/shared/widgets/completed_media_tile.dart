import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A saved-media row: tap anywhere to play, use the menu for secondary actions.
class CompletedMediaTile extends StatelessWidget {
  const CompletedMediaTile({
    super.key,
    required this.title,
    this.thumbnailUrl,
    required this.isAudio,
    required this.platform,
    required this.format,
    required this.size,
    this.duration,
    this.onPlay,
    required this.onMenu,
    this.margin = EdgeInsets.zero,
  });

  final String title, platform, format, size;
  final String? thumbnailUrl, duration;
  final bool isAudio;
  final VoidCallback? onPlay;
  final Widget onMenu;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final placeholder = Icon(
      isAudio ? Icons.music_note_rounded : Icons.movie_outlined,
      color: colors.onSurfaceVariant,
    );
    return Card(
      margin: margin,
      elevation: 0,
      color: colors.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 88,
                  height: 66,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: colors.surfaceContainerHighest,
                        child:
                            thumbnailUrl != null && thumbnailUrl!.isNotEmpty
                                ? CachedNetworkImage(
                                  imageUrl: thumbnailUrl!,
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) => placeholder,
                                  errorWidget: (_, _, _) => placeholder,
                                )
                                : placeholder,
                      ),
                      if (duration != null)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.scrim.withValues(alpha: .75),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              duration!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      platform,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$format · $size',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 48, height: 48, child: onMenu),
            ],
          ),
        ),
      ),
    );
  }
}
