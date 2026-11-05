import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/utils/media_error_message.dart';
import '../../domain/entities/media_info.dart';
import '../../domain/entities/playlist_info.dart';
import '../utils/batch_download_helper.dart';

/// Modal bottom sheet for batch playlist download with multi-selection.
class PlaylistSelectorSheet extends ConsumerStatefulWidget {
  final PlaylistInfo playlist;
  final void Function(List<MediaInfo> selectedVideos)? onDownloadBatch;

  const PlaylistSelectorSheet({
    super.key,
    required this.playlist,
    this.onDownloadBatch,
  });

  /// Helper to display this sheet as a modal bottom sheet.
  static Future<List<MediaInfo>?> show(
    BuildContext context, {
    required PlaylistInfo playlist,
    void Function(List<MediaInfo> selectedVideos)? onDownloadBatch,
  }) {
    return showModalBottomSheet<List<MediaInfo>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => PlaylistSelectorSheet(
            playlist: playlist,
            onDownloadBatch: onDownloadBatch,
          ),
    );
  }

  @override
  ConsumerState<PlaylistSelectorSheet> createState() =>
      _PlaylistSelectorSheetState();
}

class _PlaylistSelectorSheetState extends ConsumerState<PlaylistSelectorSheet> {
  late Set<String> _selectedIds;
  bool _isEnqueueing = false;

  @override
  void initState() {
    super.initState();
    // Pre-select all videos by default
    _selectedIds = widget.playlist.videos.map((v) => v.id).toSet();
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedIds.length == widget.playlist.videos.length) {
        _selectedIds.clear();
      } else {
        _selectedIds = widget.playlist.videos.map((v) => v.id).toSet();
      }
    });
  }

  void _toggleItem(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _handleDownload() async {
    final selectedVideos =
        widget.playlist.videos
            .where((v) => _selectedIds.contains(v.id))
            .toList();
    if (selectedVideos.isEmpty || _isEnqueueing) return;

    setState(() {
      _isEnqueueing = true;
    });

    try {
      if (widget.onDownloadBatch != null) {
        widget.onDownloadBatch!(selectedVideos);
        if (mounted) {
          Navigator.of(context).pop(selectedVideos);
        }
        return;
      }

      final tasks = await enqueueBatchMediaDownloads(
        ref: ref,
        videos: selectedVideos,
      );

      if (mounted) {
        if (tasks.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No downloads could be queued. Check your connection and try each video individually.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tasks.length == selectedVideos.length
                  ? 'Starting download for ${tasks.length} videos'
                  : 'Queued ${tasks.length} of ${selectedVideos.length} videos',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(tasks.map((task) => task.mediaInfo).toList());
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mediaErrorMessage(error)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isEnqueueing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalCount = widget.playlist.videos.length;
    final selectedCount = _selectedIds.length;
    final allSelected = selectedCount == totalCount && totalCount > 0;
    final noneSelected = selectedCount == 0;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(
                        Icons.playlist_play_rounded,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.playlist.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${widget.playlist.author} • ${widget.playlist.videoCount} videos',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Select All Row
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Material(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _toggleSelectAll,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value:
                                allSelected
                                    ? true
                                    : (noneSelected ? false : null),
                            tristate: true,
                            onChanged: (_) => _toggleSelectAll(),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Select All',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$selectedCount / $totalCount selected',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const Divider(height: 16),

              // Video List
              Expanded(
                child:
                    widget.playlist.videos.isEmpty
                        ? Center(
                          child: Text(
                            'No videos in playlist',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        )
                        : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          itemCount: widget.playlist.videos.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final video = widget.playlist.videos[index];
                            final isSelected = _selectedIds.contains(video.id);

                            return Material(
                              color:
                                  isSelected
                                      ? theme.colorScheme.primaryContainer
                                          .withValues(alpha: 0.35)
                                      : theme.colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _toggleItem(video.id),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Row(
                                    children: [
                                      // Individual Checkbox
                                      Checkbox(
                                        value: isSelected,
                                        onChanged: (_) => _toggleItem(video.id),
                                      ),
                                      // Index Pill (#1, #2...)
                                      Container(
                                        width: 28,
                                        alignment: Alignment.center,
                                        child: Text(
                                          '#${index + 1}',
                                          style: theme.textTheme.labelMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color:
                                                    theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // Video Thumbnail with Duration badge
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: SizedBox(
                                          width: 84,
                                          height: 48,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              CachedNetworkImage(
                                                imageUrl: video.thumbnailUrl,
                                                fit: BoxFit.cover,
                                                placeholder:
                                                    (
                                                      context,
                                                      url,
                                                    ) => Shimmer.fromColors(
                                                      baseColor:
                                                          theme
                                                              .colorScheme
                                                              .surfaceContainerHighest,
                                                      highlightColor:
                                                          theme
                                                              .colorScheme
                                                              .surfaceContainer,
                                                      child: Container(
                                                        color:
                                                            theme
                                                                .colorScheme
                                                                .surfaceContainerHighest,
                                                      ),
                                                    ),
                                                errorWidget:
                                                    (
                                                      context,
                                                      url,
                                                      error,
                                                    ) => Container(
                                                      color:
                                                          theme
                                                              .colorScheme
                                                              .surfaceContainerHighest,
                                                      child: Icon(
                                                        Icons.broken_image,
                                                        size: 20,
                                                        color:
                                                            theme
                                                                .colorScheme
                                                                .outline,
                                                      ),
                                                    ),
                                              ),
                                              if (video.duration >
                                                  Duration.zero)
                                                Positioned(
                                                  bottom: 2,
                                                  right: 2,
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 4,
                                                          vertical: 1,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black87,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      video.formattedDuration,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Title & Author
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              video.title,
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              video.uploader,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color:
                                                        theme
                                                            .colorScheme
                                                            .outline,
                                                  ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
              ),

              // Bottom bar with "Download Selected (N videos)" button
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed:
                          selectedCount == 0 || _isEnqueueing
                              ? null
                              : _handleDownload,
                      icon:
                          _isEnqueueing
                              ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              )
                              : const Icon(Icons.download_rounded),
                      label: Text(
                        'Download Selected ($selectedCount ${selectedCount == 1 ? "video" : "videos"})',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
