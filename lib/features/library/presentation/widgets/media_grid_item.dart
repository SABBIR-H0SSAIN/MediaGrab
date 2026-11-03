import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/file_utils.dart';
import '../../../../core/utils/url_parser.dart';
import '../providers/library_provider.dart';

/// Grid item widget representing a downloaded media file with 16:9 thumbnail,
/// duration badge, platform tag, title, format pill (e.g. MP4 1080p),
/// file size tag, and action menu.
class MediaGridItem extends ConsumerWidget {
  const MediaGridItem({
    super.key,
    required this.item,
    this.onTap,
    this.onOpen,
    this.onShare,
    this.onDelete,
    this.onInfo,
    this.onActions,
  });

  final LibraryMediaItem item;
  final VoidCallback? onTap;
  final VoidCallback? onOpen;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;
  final VoidCallback? onInfo;
  final VoidCallback? onActions;

  void _showActionsBottomSheet(BuildContext context, WidgetRef ref) {
    if (onActions != null) {
      onActions!();
      return;
    }
    final theme = Theme.of(context);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          item.fileType == FileType.audio
                              ? Icons.music_note_rounded
                              : Icons.movie_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.play_circle_outline_rounded),
                    title: const Text('Open'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      if (onOpen != null) {
                        onOpen!();
                      } else {
                        openMediaFile(item.filePath);
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.share_rounded),
                    title: const Text('Share'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      if (onShare != null) {
                        onShare!();
                      } else if (item.filePath.isNotEmpty) {
                        shareMediaFile(item.filePath, text: item.title);
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: const Text('Info'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      if (onInfo != null) {
                        onInfo!();
                      } else {
                        _showInfoDialog(context);
                      }
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      'Delete',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      if (onDelete != null) {
                        onDelete!();
                      } else {
                        ref
                            .read(libraryProvider.notifier)
                            .removeItem(item.id, deletePhysicalFile: true);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showInfoDialog(BuildContext context) {
    final theme = Theme.of(context);

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Media Details'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('Title', item.title, theme),
                _buildInfoRow('Path', item.filePath, theme),
                _buildInfoRow('Size', item.formattedSize, theme),
                if (item.duration > Duration.zero)
                  _buildInfoRow('Duration', item.formattedDuration, theme),
                _buildInfoRow('Type', item.fileType.displayName, theme),
                _buildInfoRow('Format', item.formatPill, theme),
                if (item.qualityLabel != null)
                  _buildInfoRow('Quality', item.qualityLabel!, theme),
                if (item.platform != PlatformType.unknown)
                  _buildInfoRow('Platform', item.platform.displayName, theme),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context) {
    final theme = Theme.of(context);

    Widget thumbnailContent;
    if (item.thumbnailPath != null &&
        item.thumbnailPath!.isNotEmpty &&
        File(item.thumbnailPath!).existsSync()) {
      thumbnailContent = Image.file(
        File(item.thumbnailPath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    } else if (item.thumbnailUrl != null &&
        item.thumbnailUrl!.startsWith('http')) {
      thumbnailContent = CachedNetworkImage(
        imageUrl: item.thumbnailUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder:
            (context, url) => Container(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
        errorWidget: (context, url, error) => _buildPlaceholder(theme),
      );
    } else {
      thumbnailContent = _buildPlaceholder(theme);
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            thumbnailContent,
            // Duration badge bottom-right
            if (item.duration > Duration.zero)
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
                    item.formattedDuration,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    final IconData placeholderIcon;
    switch (item.fileType) {
      case FileType.video:
        placeholderIcon = Icons.movie_outlined;
        break;
      case FileType.audio:
        placeholderIcon = Icons.music_note_rounded;
        break;
      case FileType.image:
        placeholderIcon = Icons.image_outlined;
        break;
      case FileType.other:
        placeholderIcon = Icons.insert_drive_file_outlined;
        break;
    }

    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          placeholderIcon,
          size: 32,
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap ?? onOpen ?? () => openMediaFile(item.filePath),
        onLongPress: () => _showActionsBottomSheet(context, ref),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _buildThumbnail(context),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Material(
                    color: theme.colorScheme.scrim.withValues(alpha: .6),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Action menu',
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () => _showActionsBottomSheet(context, ref),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 5, 12, 10),
              child: Text(
                '${item.platform.displayName} · ${item.formatPill} · ${item.formattedSize}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
