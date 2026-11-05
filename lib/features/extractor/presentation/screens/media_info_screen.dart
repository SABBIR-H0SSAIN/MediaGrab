import '../../../../core/utils/media_error_message.dart';
import '../../../../shared/widgets/media_feedback_content.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/utils/file_utils.dart';
import '../../../downloads/presentation/providers/download_manager_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/media_info.dart';
import '../../domain/entities/playlist_info.dart';
import '../../domain/entities/stream_info.dart';
import '../providers/extractor_provider.dart';
import '../utils/batch_download_helper.dart';
import '../widgets/playlist_selector_sheet.dart';
import '../widgets/quality_selector_sheet.dart';
import '../widgets/video_preview_card.dart';

/// Screen displaying extracted media information and download options for a given URL.
class MediaInfoScreen extends ConsumerStatefulWidget {
  final String url;

  const MediaInfoScreen({super.key, required this.url});

  @override
  ConsumerState<MediaInfoScreen> createState() => _MediaInfoScreenState();
}

class _MediaInfoScreenState extends ConsumerState<MediaInfoScreen> {
  bool _isDescriptionExpanded = false;
  bool _isEnqueueingPlaylist = false;

  @override
  void initState() {
    super.initState();
    // Prefetch streams concurrently with media info so quality options load instantly
    ref.read(streamsProvider(widget.url));
  }

  @override
  void didUpdateWidget(covariant MediaInfoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      ref.read(streamsProvider(widget.url));
    }
  }

  void _openQualitySheet(
    BuildContext context,
    WidgetRef ref,
    MediaInfo mediaInfo, {
    bool initialIsAudio = false,
  }) {
    QualitySelectorSheet.show(
      context,
      url: widget.url,
      initialIsAudio: initialIsAudio,
      onDownloadWithAudio: (StreamInfo stream, StreamInfo? audioStream) async {
        final settings = ref.read(settingsProvider);
        String baseDir = settings.downloadDirectory.trim();
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

        final cleanContainer = stream.container.replaceAll('.', '').trim();
        final ext =
            cleanContainer.isNotEmpty
                ? (stream.isAudioOnly && cleanContainer == 'mp4'
                    ? 'm4a'
                    : cleanContainer)
                : (stream.isAudioOnly ? 'm4a' : 'mp4');
        final sanitizedTitle = sanitizeFilename(mediaInfo.title);
        final targetPath = '$baseDir/$sanitizedTitle.$ext';

        try {
          await ref
              .read(downloadManagerProvider.notifier)
              .startDownload(
                mediaInfo,
                stream,
                targetPath,
                audioStream: audioStream,
              );

          if (context.mounted) {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
            ref.read(downloadsSelectedTabProvider.notifier).state = 0;
            try {
              context.go('/downloads?tab=active');
            } catch (_) {
              try {
                context.push('/downloads?tab=active');
              } catch (_) {}
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: MediaFeedbackContent(
                  message: 'Download started · ${stream.qualityLabel}',
                  title: mediaInfo.title,
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } on CellularDownloadBlockedException catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(e.message),
                behavior: SnackBarBehavior.floating,
                action: SnackBarAction(
                  label: 'Settings',
                  onPressed: () {
                    try {
                      context.go('/settings');
                    } catch (_) {
                      try {
                        context.push('/settings');
                      } catch (_) {}
                    }
                  },
                ),
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: MediaFeedbackContent(
                  message: 'Failed to start download: ${mediaErrorMessage(e)}',
                ),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
        }
      },
    );
  }

  void _openPlaylistSheet(
    BuildContext context,
    WidgetRef ref,
    PlaylistInfo playlist,
  ) async {
    final selected = await PlaylistSelectorSheet.show(
      context,
      playlist: playlist,
    );
    if (selected != null && selected.isNotEmpty && context.mounted) {
      ref.read(downloadsSelectedTabProvider.notifier).state = 0;
      try {
        context.go('/downloads?tab=active');
      } catch (_) {
        try {
          context.push('/downloads?tab=active');
        } catch (_) {}
      }
    }
  }

  Future<void> _downloadEntirePlaylist(
    BuildContext context,
    WidgetRef ref,
    PlaylistInfo playlist,
  ) async {
    if (playlist.videos.isEmpty || _isEnqueueingPlaylist) return;
    setState(() => _isEnqueueingPlaylist = true);
    try {
      final tasks = await enqueueBatchMediaDownloads(
        ref: ref,
        videos: playlist.videos,
      );
      if (!context.mounted) return;
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
            tasks.length == playlist.videos.length
                ? 'Starting download for ${tasks.length} videos from playlist'
                : 'Queued ${tasks.length} of ${playlist.videos.length} videos from playlist',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      ref.read(downloadsSelectedTabProvider.notifier).state = 0;
      final router = GoRouter.maybeOf(context);
      router?.go('/downloads?tab=active');
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mediaErrorMessage(error)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isEnqueueingPlaylist = false);
    }
  }

  Future<void> _openInBrowser(BuildContext context, String urlString) async {
    try {
      final uri = Uri.tryParse(urlString);
      if (uri == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open link in browser'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open link in browser'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to open link in browser'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _shareUrl(
    BuildContext context,
    String urlString,
    String title,
  ) async {
    try {
      await Share.share(urlString, subject: title);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to share link'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildShimmerLoading(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.surfaceContainerHighest;
    final highlightColor = theme.colorScheme.surfaceContainer;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Shimmer.fromColors(
        baseColor: baseColor,
        highlightColor: highlightColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail skeleton
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Title skeleton (2 lines)
            Container(
              height: 20,
              width: double.infinity,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 20,
              width: 200,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            // Uploader skeleton
            Row(
              children: [
                CircleAvatar(backgroundColor: baseColor, radius: 18),
                const SizedBox(width: 10),
                Container(
                  height: 14,
                  width: 140,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Action button skeleton
            Container(
              height: 52,
              width: double.infinity,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, WidgetRef ref, Object error) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Extraction Failed',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              mediaErrorMessage(error),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                ref.invalidate(mediaInfoProvider(widget.url));
                ref.invalidate(streamsProvider(widget.url));
                ref.invalidate(playlistProvider(widget.url));
                ref.read(streamsProvider(widget.url));
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistHeaderCard(
    BuildContext context,
    WidgetRef ref,
    PlaylistInfo playlist,
  ) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  radius: 22,
                  child: const Icon(Icons.playlist_play_rounded, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'PLAYLIST',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        playlist.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${playlist.videoCount} videos • ${playlist.author}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _openPlaylistSheet(context, ref, playlist),
                    icon: const Icon(Icons.checklist_rounded),
                    label: const Text('Select Videos to Download'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    _isEnqueueingPlaylist
                        ? null
                        : () => _downloadEntirePlaylist(context, ref, playlist),
                icon: const Icon(Icons.download_for_offline_rounded),
                label: const Text('Download Entire Playlist'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDescriptionCard(BuildContext context, String description) {
    final theme = Theme.of(context);
    final isLong = description.length > 150;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap:
            isLong
                ? () {
                  setState(() {
                    _isDescriptionExpanded = !_isDescriptionExpanded;
                  });
                }
                : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
                maxLines: _isDescriptionExpanded ? null : 4,
                overflow: _isDescriptionExpanded ? null : TextOverflow.ellipsis,
              ),
              if (isLong) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      _isDescriptionExpanded ? 'Show less' : 'Show more',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Icon(
                      _isDescriptionExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 16,
                      color: theme.colorScheme.primary,
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
    final theme = Theme.of(context);
    final mediaInfoAsync = ref.watch(mediaInfoProvider(widget.url));
    final playlistAsync = ref.watch(playlistProvider(widget.url));

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(title: const Text('Media Details'), centerTitle: false),
      body: mediaInfoAsync.when(
        data: (mediaInfo) {
          final playlist = playlistAsync.value;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VideoPreviewCard(mediaInfo: mediaInfo),

                // Prominent Playlist Header Card if URL is playlist or playlist data is present
                if (playlist != null) ...[
                  const SizedBox(height: 16),
                  _buildPlaylistHeaderCard(context, ref, playlist),
                ],

                const SizedBox(height: 16),

                // Action buttons: Download & Audio Only
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed:
                            () => _openQualitySheet(
                              context,
                              ref,
                              mediaInfo,
                              initialIsAudio: false,
                            ),
                        icon: const Icon(Icons.download),
                        label: const Text('Download'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed:
                            () => _openQualitySheet(
                              context,
                              ref,
                              mediaInfo,
                              initialIsAudio: true,
                            ),
                        icon: const Icon(Icons.audiotrack),
                        label: const Text('Audio Only'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Browser & Share actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openInBrowser(context, widget.url),
                        icon: const Icon(Icons.open_in_browser),
                        label: const Text(
                          'Open in Browser',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            () =>
                                _shareUrl(context, widget.url, mediaInfo.title),
                        icon: const Icon(Icons.share),
                        label: const Text(
                          'Share',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                Text(
                  'Download Options',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(
                        Icons.tune_rounded,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(
                      'Choose Quality & Format',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      'Select resolution, format, and bitrate',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openQualitySheet(context, ref, mediaInfo),
                  ),
                ),

                // Expandable Description
                if (mediaInfo.description != null &&
                    mediaInfo.description!.trim().isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Description',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildDescriptionCard(context, mediaInfo.description!),
                ],
              ],
            ),
          );
        },
        loading: () => _buildShimmerLoading(context),
        error: (error, stack) => _buildErrorState(context, ref, error),
      ),
    );
  }
}
