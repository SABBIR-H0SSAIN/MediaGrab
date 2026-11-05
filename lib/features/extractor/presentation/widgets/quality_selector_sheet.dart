import '../../../../core/utils/media_error_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/stream_info.dart';
import '../providers/extractor_provider.dart';
import '../utils/video_quality_options.dart';

/// Modal bottom sheet allowing users to browse and pick video/audio stream qualities.
class QualitySelectorSheet extends ConsumerStatefulWidget {
  final String url;
  final List<StreamInfo>? prefetchedStreams;
  final StreamInfo? initialSelection;
  final StreamInfo? initialAudioStream;
  final bool selectionOnly;
  final void Function(StreamInfo stream)? onDownload;
  final void Function(StreamInfo stream, StreamInfo? audioStream)?
  onDownloadWithAudio;
  final bool initialIsAudio;

  const QualitySelectorSheet({
    super.key,
    required this.url,
    this.prefetchedStreams,
    this.initialSelection,
    this.initialAudioStream,
    this.selectionOnly = false,
    this.onDownload,
    this.onDownloadWithAudio,
    this.initialIsAudio = false,
  });

  /// Helper to display this sheet as a modal bottom sheet.
  static Future<StreamInfo?> show(
    BuildContext context, {
    required String url,
    List<StreamInfo>? prefetchedStreams,
    StreamInfo? initialSelection,
    StreamInfo? initialAudioStream,
    bool selectionOnly = false,
    void Function(StreamInfo stream)? onDownload,
    void Function(StreamInfo stream, StreamInfo? audioStream)?
    onDownloadWithAudio,
    bool initialIsAudio = false,
  }) {
    return showModalBottomSheet<StreamInfo>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => QualitySelectorSheet(
            url: url,
            prefetchedStreams: prefetchedStreams,
            initialSelection: initialSelection,
            initialAudioStream: initialAudioStream,
            selectionOnly: selectionOnly,
            onDownload: onDownload,
            onDownloadWithAudio: onDownloadWithAudio,
            initialIsAudio: initialIsAudio,
          ),
    );
  }

  @override
  ConsumerState<QualitySelectorSheet> createState() =>
      _QualitySelectorSheetState();
}

class _QualitySelectorSheetState extends ConsumerState<QualitySelectorSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  StreamInfo? _selectedVideoStream;
  StreamInfo? _selectedAudioStream;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    final isAudioQuality = settings.defaultVideoQuality.toLowerCase().contains(
      'audio',
    );
    _selectedVideoStream =
        widget.initialSelection?.isAudioOnly == false
            ? widget.initialSelection
            : null;
    _selectedAudioStream =
        widget.initialSelection?.isAudioOnly == true
            ? widget.initialSelection
            : widget.initialAudioStream;
    final initialTab =
        widget.initialSelection != null
            ? (widget.initialSelection!.isAudioOnly ? 1 : 0)
            : (widget.initialIsAudio || isAudioQuality)
            ? 1
            : 0;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: initialTab,
    );
    _tabController.addListener(_handleTabChanged);
  }

  void _handleTabChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  StreamInfo? _findMatchingVideoStream(
    List<StreamInfo> videoStreams,
    String defaultQuality,
  ) {
    if (videoStreams.isEmpty) return null;
    final qualityLower = defaultQuality.toLowerCase();
    if (qualityLower == 'best' || qualityLower.contains('audio')) {
      return videoStreams.first;
    }

    // Direct match on qualityLabel (e.g. "1080p", "720p")
    for (final s in videoStreams) {
      if (s.qualityLabel.toLowerCase().contains(qualityLower)) {
        return s;
      }
    }

    // Numeric height matching (closest available resolution)
    final targetHeight = int.tryParse(
      qualityLower.replaceAll(RegExp(r'[^0-9]'), ''),
    );
    if (targetHeight != null && targetHeight > 0) {
      StreamInfo closest = videoStreams.first;
      int minDiff = 999999;
      for (final s in videoStreams) {
        final h = videoResolution(s) ?? 0;
        if (h > 0) {
          final diff = (h - targetHeight).abs();
          if (diff < minDiff) {
            minDiff = diff;
            closest = s;
          }
        }
      }
      return closest;
    }

    return videoStreams.first;
  }

  StreamInfo? _findMatchingAudioStream(
    List<StreamInfo> audioStreams,
    String defaultFormat,
  ) {
    if (audioStreams.isEmpty) return null;
    final formatLower = defaultFormat.toLowerCase();
    for (final s in audioStreams) {
      if (s.container.toLowerCase().contains(formatLower) ||
          s.codec.toLowerCase().contains(formatLower)) {
        return s;
      }
    }
    return audioStreams.first;
  }

  List<StreamInfo> _videoOptions(List<StreamInfo> streams) {
    final hasAudio = streams.any((s) => s.isAudioOnly);
    final options = bestVideoQualityOptions(
      widget.selectionOnly && !hasAudio
          ? streams.where((s) => !s.isVideoOnly)
          : streams,
    );
    // Opening a reviewed selection must not silently replace its stream variant.
    final selected = _selectedVideoStream;
    if (widget.selectionOnly &&
        selected != null &&
        streams.contains(selected) &&
        (!selected.isVideoOnly || hasAudio)) {
      final index = options.indexWhere(
        (s) =>
            videoResolution(s) == videoResolution(selected) &&
            (videoResolution(s) != null ||
                s.qualityLabel == selected.qualityLabel),
      );
      if (index >= 0) {
        options[index] = selected;
      }
    }
    return options;
  }

  void _triggerDownload(StreamInfo stream, [StreamInfo? audioStream]) {
    Navigator.of(context).pop(stream);
    if (widget.onDownloadWithAudio != null) {
      widget.onDownloadWithAudio!(stream, audioStream);
    } else if (widget.onDownload != null) {
      widget.onDownload!(stream);
    }
  }

  String? _getQualityBadge(StreamInfo stream) {
    if (stream.isAudioOnly) {
      final b = stream.bitrate ?? 0;
      if (b >= 320000 || stream.qualityLabel.contains('320')) return 'High';
      if (b >= 256000 || stream.qualityLabel.contains('256')) return 'HQ';
      if (b >= 128000 || stream.qualityLabel.contains('128')) return 'Standard';
      if (b > 0 ||
          stream.qualityLabel.contains('64') ||
          stream.qualityLabel.contains('96')) {
        return 'Basic';
      }
      return null;
    } else {
      final h = videoResolution(stream) ?? 0;
      final q = stream.qualityLabel.toLowerCase();
      if (h >= 2160 || q.contains('2160') || q.contains('4k')) return '4K UHD';
      if (h >= 1440 || q.contains('1440') || q.contains('2k')) return 'QHD';
      if (h >= 1080 || q.contains('1080')) return 'FHD';
      if (h >= 720 || q.contains('720')) return 'HD';
      if (h > 0 ||
          q.contains('480') ||
          q.contains('360') ||
          q.contains('240') ||
          q.contains('144') ||
          q.contains('sd')) {
        return 'SD';
      }
      return null;
    }
  }

  Widget _buildTierBadge(
    BuildContext context,
    String label, {
    required bool isSelected,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color:
            isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color:
              isSelected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }

  Widget _buildCodecBadge(
    BuildContext context,
    String label, {
    required bool isSelected,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color:
            isSelected
                ? theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.12)
                : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color:
              isSelected
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildStreamTile({
    required BuildContext context,
    required StreamInfo stream,
    required bool isSelected,
  }) {
    final theme = Theme.of(context);
    final isAudio = stream.isAudioOnly;

    final primaryText =
        isAudio && stream.formattedBitrate.isNotEmpty
            ? stream.formattedBitrate
            : stream.qualityLabel;
    final secondaryBadgeText = stream.container.toUpperCase();
    final qualityBadge = _getQualityBadge(stream);

    final sizeStr =
        stream.sizeInBytes != null && stream.sizeInBytes! > 0
            ? '~${stream.formattedSize}'
            : stream.formattedSize;

    final subtitleText = sizeStr;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color:
            isSelected
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color:
                isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          onTap: () {
            setState(() {
              if (stream.isAudioOnly) {
                _selectedAudioStream = stream;
              } else {
                _selectedVideoStream = stream;
              }
            });
          },
          leading: CircleAvatar(
            backgroundColor:
                isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
            foregroundColor:
                isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant,
            radius: 20,
            child: Icon(
              isAudio ? Icons.audiotrack_rounded : Icons.videocam_rounded,
              size: 20,
            ),
          ),
          title: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                primaryText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color:
                      isSelected
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurface,
                ),
              ),
              if (qualityBadge != null)
                _buildTierBadge(context, qualityBadge, isSelected: isSelected),
              if (secondaryBadgeText.isNotEmpty)
                _buildCodecBadge(
                  context,
                  secondaryBadgeText,
                  isSelected: isSelected,
                ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              subtitleText,
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    isSelected
                        ? theme.colorScheme.onPrimaryContainer.withValues(
                          alpha: 0.8,
                        )
                        : theme.colorScheme.outline,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          trailing: Icon(
            isSelected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color:
                isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
            size: 22,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final streamsAsync =
        widget.prefetchedStreams != null
            ? AsyncValue<List<StreamInfo>>.data(widget.prefetchedStreams!)
            : ref.watch(streamsProvider(widget.url));
    final settings = ref.watch(settingsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        StreamInfo? effectiveVideoStream;
        StreamInfo? effectiveAudioStream;
        StreamInfo? effectiveSelected;

        streamsAsync.whenData((streams) {
          final videoStreams = _videoOptions(streams);
          final audioStreams = streams.where((s) => s.isAudioOnly).toList();

          effectiveVideoStream =
              (_selectedVideoStream != null &&
                      videoStreams.contains(_selectedVideoStream))
                  ? _selectedVideoStream
                  : _findMatchingVideoStream(
                    videoStreams,
                    _selectedVideoStream == null
                        ? settings.defaultVideoQuality
                        : (videoResolution(_selectedVideoStream!)?.toString() ??
                            _selectedVideoStream!.qualityLabel),
                  );

          effectiveAudioStream =
              (_selectedAudioStream != null &&
                      audioStreams.contains(_selectedAudioStream))
                  ? _selectedAudioStream
                  : _findMatchingAudioStream(
                    audioStreams,
                    settings.defaultAudioFormat,
                  );

          final isAudioTab = _tabController.index == 1;
          effectiveSelected =
              isAudioTab ? effectiveAudioStream : effectiveVideoStream;
        });

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
              // Header with title and close button
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.selectionOnly
                            ? 'Choose quality'
                            : 'Download Options',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              // SegmentedButton / TabBar in pill container
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor: theme.colorScheme.onPrimaryContainer,
                    unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                    labelStyle: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    tabs: const [
                      Tab(
                        icon: Icon(Icons.videocam_rounded, size: 20),
                        text: 'Video',
                        iconMargin: EdgeInsets.only(bottom: 2),
                      ),
                      Tab(
                        icon: Icon(Icons.audiotrack_rounded, size: 20),
                        text: 'Audio',
                        iconMargin: EdgeInsets.only(bottom: 2),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // TabBarView / Stream lists
              Expanded(
                child: streamsAsync.when(
                  data: (streams) {
                    final videoStreams = _videoOptions(streams);
                    final audioStreams =
                        streams.where((s) => s.isAudioOnly).toList();

                    return TabBarView(
                      controller: _tabController,
                      children: [
                        // Video Tab
                        videoStreams.isEmpty
                            ? Center(
                              child: Text(
                                'No video streams found',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            )
                            : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.only(bottom: 8),
                              itemCount: videoStreams.length,
                              itemBuilder: (context, index) {
                                final stream = videoStreams[index];
                                final isSelected =
                                    effectiveVideoStream == stream;
                                return _buildStreamTile(
                                  context: context,
                                  stream: stream,
                                  isSelected: isSelected,
                                );
                              },
                            ),
                        // Audio Tab
                        audioStreams.isEmpty
                            ? Center(
                              child: Text(
                                'No audio streams found',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            )
                            : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.only(bottom: 8),
                              itemCount: audioStreams.length,
                              itemBuilder: (context, index) {
                                final stream = audioStreams[index];
                                final isSelected =
                                    effectiveAudioStream == stream;
                                return _buildStreamTile(
                                  context: context,
                                  stream: stream,
                                  isSelected: isSelected,
                                );
                              },
                            ),
                      ],
                    );
                  },
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error:
                      (error, stack) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 48,
                                color: theme.colorScheme.error,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Failed to load streams',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                mediaErrorMessage(error),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: () {
                                  ref.invalidate(streamsProvider(widget.url));
                                },
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ),
                ),
              ),
              // Bottom "Download Selected" button
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.download),
                      label: Text(
                        widget.selectionOnly
                            ? 'Use quality'
                            : effectiveSelected != null
                            ? 'Download Selected (${effectiveSelected!.qualityLabel})'
                            : 'Download Now',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed:
                          effectiveSelected != null &&
                                  (!effectiveSelected!.isVideoOnly ||
                                      effectiveAudioStream != null)
                              ? () => _triggerDownload(
                                effectiveSelected!,
                                effectiveAudioStream,
                              )
                              : null,
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
