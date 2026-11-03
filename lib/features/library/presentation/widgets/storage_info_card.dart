import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/file_utils.dart';
import '../../../../core/utils/url_parser.dart';
import '../providers/library_provider.dart';

/// Card showing app storage footprint, matching Screen 3 of the design mockup:
/// - Folder icon in themed square container
/// - "App Storage" title
/// - "$formattedStorage used • $itemCount items" subtitle
/// - Purple linear progress bar
/// - Trailing chevron
class StorageInfoCard extends ConsumerWidget {
  const StorageInfoCard({
    super.key,
    this.customCount,
    this.customFormattedStorage,
    this.onRefresh,
    this.progressValue,
  });

  /// Optional custom count override for direct testing.
  final int? customCount;

  /// Optional custom storage string override for direct testing.
  final String? customFormattedStorage;

  /// Optional refresh callback.
  final VoidCallback? onRefresh;

  /// Optional progress value between 0.0 and 1.0.
  final double? progressValue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final String formattedStorage =
        customFormattedStorage ?? ref.watch(formattedTotalStorageProvider);
    final int totalBytes = ref.watch(totalStorageBytesProvider);
    final int itemCount = customCount ?? ref.watch(totalDownloadsCountProvider);

    // Calculate clean progress ratio (relative to 128 GB device capacity)
    final double progress =
        progressValue ??
        (totalBytes > 0
            ? (totalBytes / (128 * 1024 * 1024 * 1024)).clamp(0.01, 1.0)
            : 0.0);

    final String itemLabel = itemCount == 1 ? '1 item' : '$itemCount items';
    final String subtitle = '$formattedStorage used • $itemLabel';

    return InkWell(
      key: const ValueKey('app_storage_card'),
      onTap: () {
        if (onRefresh != null) {
          onRefresh!();
        } else {
          ref.read(libraryProvider.notifier).refresh();
        }
        _showStorageBreakdownSheet(
          context,
          ref,
          formattedStorage,
          totalBytes,
          itemCount,
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant, width: .6),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.folder_outlined,
                color: colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'App Storage',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  void _showStorageBreakdownSheet(
    BuildContext context,
    WidgetRef ref,
    String totalFormatted,
    int totalBytes,
    int totalItems,
  ) {
    final theme = Theme.of(context);
    final items = ref.read(libraryProvider);

    int videoBytes = 0;
    int videoCount = 0;
    int audioBytes = 0;
    int audioCount = 0;
    int ytBytes = 0;
    int fbBytes = 0;
    int igBytes = 0;

    for (final item in items) {
      if (item.fileType == FileType.video) {
        videoBytes += item.fileSize;
        videoCount++;
      } else if (item.fileType == FileType.audio) {
        audioBytes += item.fileSize;
        audioCount++;
      }
      switch (item.platform) {
        case PlatformType.youtube:
          ytBytes += item.fileSize;
          break;
        case PlatformType.facebook:
          fbBytes += item.fileSize;
          break;
        case PlatformType.instagram:
          igBytes += item.fileSize;
          break;
        default:
          break;
      }
    }

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.pie_chart_outline_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Storage Breakdown',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      totalFormatted,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Media Types',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.outline,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _buildBreakdownRow(
                  'Videos',
                  '$videoCount files',
                  formatFileSize(videoBytes),
                  theme,
                ),
                const SizedBox(height: 6),
                _buildBreakdownRow(
                  'Audio',
                  '$audioCount files',
                  formatFileSize(audioBytes),
                  theme,
                ),
                const SizedBox(height: 16),
                Text(
                  'Platforms',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.outline,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _buildBreakdownRow(
                  'YouTube',
                  '',
                  formatFileSize(ytBytes),
                  theme,
                ),
                const SizedBox(height: 6),
                _buildBreakdownRow(
                  'Facebook',
                  '',
                  formatFileSize(fbBytes),
                  theme,
                ),
                const SizedBox(height: 6),
                _buildBreakdownRow(
                  'Instagram',
                  '',
                  formatFileSize(igBytes),
                  theme,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBreakdownRow(
    String label,
    String subtitle,
    String size,
    ThemeData theme,
  ) {
    return Row(
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(
            '($subtitle)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
        const Spacer(),
        Text(
          size,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
