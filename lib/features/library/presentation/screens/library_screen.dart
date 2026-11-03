import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../shared/widgets/completed_media_tile.dart';
import '../../../../core/utils/file_utils.dart';
import '../../../../core/utils/url_parser.dart';
import '../providers/library_provider.dart';
import '../widgets/filter_chips_bar.dart';
import '../widgets/media_grid_item.dart';
import '../widgets/storage_info_card.dart';

/// Screen displaying the user's downloaded media files, storage statistics,
/// category/platform filters, search & sort controls, and file management actions.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _isSearching = false;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final savedMode = prefs.getString('library_view_mode');
        if (savedMode == 'list' && mounted) {
          ref.read(libraryViewModeProvider.notifier).state =
              LibraryViewMode.list;
        } else if (savedMode == 'grid' && mounted) {
          ref.read(libraryViewModeProvider.notifier).state =
              LibraryViewMode.grid;
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        ref.read(librarySearchQueryProvider.notifier).state = '';
      } else {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _handleOpenMedia(BuildContext context, LibraryMediaItem item) {
    final isVideo =
        item.fileType != FileType.audio &&
        (item.fileType == FileType.video ||
            getFileType(item.filePath) == FileType.video);

    if (isVideo) {
      context.push(
        Uri(
          path: '/player',
          queryParameters: {'filePath': item.filePath, 'title': item.title},
        ).toString(),
      );
    } else {
      openMediaFile(item.filePath);
    }
  }

  Future<void> _deleteMedia(
    BuildContext context,
    WidgetRef ref,
    LibraryMediaItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete Download'),
            content: Text('Delete "${item.title}" from device storage?'),
            actionsAlignment: MainAxisAlignment.end,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(libraryProvider.notifier)
          .removeItem(item.id, deletePhysicalFile: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File deleted from device')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not delete file from storage. Check storage permissions and try again.',
            ),
          ),
        );
      }
    }
  }

  void _showActionsBottomSheet(
    BuildContext context,
    WidgetRef ref,
    LibraryMediaItem item,
  ) {
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
                    leading: const Icon(Icons.open_in_new_rounded),
                    title: const Text('Open with'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      openMediaFile(item.filePath);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.share_rounded),
                    title: const Text('Share'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      if (item.filePath.isNotEmpty) {
                        shareMediaFile(item.filePath, text: item.title);
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: const Text('Details'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _showInfoDialog(context, item);
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
                      _deleteMedia(context, ref, item);
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

  void _showInfoDialog(BuildContext context, LibraryMediaItem item) {
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

  Widget _buildEmptyState(
    ThemeData theme,
    LibraryFilter filter,
    String searchQuery,
  ) {
    final String title;
    final String subtitle;

    if (searchQuery.isNotEmpty) {
      title = 'No results found';
      subtitle = 'No downloaded files matched "$searchQuery"';
    } else if (filter != LibraryFilter.all) {
      title = 'No ${filter.displayName} found';
      subtitle =
          'Downloaded ${filter.displayName.toLowerCase()} will appear here';
    } else {
      title = 'Your library is empty';
      subtitle = 'Downloaded files will appear here';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 80,
              height: 70,
              child: CustomPaint(
                painter: _ClapperboardPainter(theme.colorScheme.primary),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaListTile(
    BuildContext context,
    WidgetRef ref,
    LibraryMediaItem item,
    ThemeData theme,
  ) {
    return CompletedMediaTile(
      title: item.title,
      thumbnailUrl: item.thumbnailUrl,
      isAudio: item.fileType == FileType.audio,
      platform: item.platform.displayName,
      format: item.formatPill,
      size: item.formattedSize,
      duration: item.duration > Duration.zero ? item.formattedDuration : null,
      margin: const EdgeInsets.only(bottom: 8),
      onPlay: () => _handleOpenMedia(context, item),
      onMenu: IconButton(
        tooltip: 'Action menu',
        icon: const Icon(Icons.more_vert_rounded),
        onPressed: () => _showActionsBottomSheet(context, ref, item),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ThemeData theme,
    LibraryViewMode viewMode,
    LibrarySort currentSort,
  ) {
    if (_isSearching) {
      return AppBar(
        toolbarHeight: 80,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _toggleSearch,
        ),
        title: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search title or creator...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: theme.colorScheme.outline),
          ),
          style: TextStyle(color: theme.colorScheme.onSurface),
          onChanged: (value) {
            ref.read(librarySearchQueryProvider.notifier).state = value;
          },
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                _searchController.clear();
                ref.read(librarySearchQueryProvider.notifier).state = '';
              },
            ),
          _buildSortMenu(currentSort),
        ],
      );
    }

    return AppBar(
      toolbarHeight: 80,
      title: Text(
        'Library',
        style: theme.textTheme.headlineMedium?.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface,
          letterSpacing: -0.4,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search_rounded),
          tooltip: 'Search media',
          onPressed: _toggleSearch,
        ),
        _buildSortMenu(currentSort),
      ],
    );
  }

  Future<void> _setViewMode(LibraryViewMode mode) async {
    ref.read(libraryViewModeProvider.notifier).state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('library_view_mode', mode.name);
    } catch (_) {}
  }

  Widget _buildSortMenu(LibrarySort currentSort) {
    return PopupMenuButton<Object>(
      icon: const Icon(Icons.tune_rounded),
      tooltip: 'Sort by',
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      onSelected: (value) {
        if (value is LibrarySort) {
          ref.read(librarySortProvider.notifier).state = value;
        }
        if (value is LibraryViewMode) _setViewMode(value);
      },
      itemBuilder:
          (context) => <PopupMenuEntry<Object>>[
            PopupMenuItem<Object>(
              value:
                  ref.watch(libraryViewModeProvider) == LibraryViewMode.grid
                      ? LibraryViewMode.list
                      : LibraryViewMode.grid,
              child: Row(
                children: [
                  Icon(
                    ref.watch(libraryViewModeProvider) == LibraryViewMode.grid
                        ? Icons.view_list_rounded
                        : Icons.grid_view_rounded,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      ref.watch(libraryViewModeProvider) == LibraryViewMode.grid
                          ? 'Switch to list view'
                          : 'Switch to grid view',
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            ...LibrarySort.values.map((sort) {
              final isSelected = sort == currentSort;
              return PopupMenuItem<Object>(
                value: sort,
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 18,
                      color:
                          isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      sort.displayName,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = ref.watch(filteredLibraryProvider);
    final currentFilter = ref.watch(libraryFilterProvider);
    final searchQuery = ref.watch(librarySearchQueryProvider);
    final viewMode = ref.watch(libraryViewModeProvider);
    final currentSort = ref.watch(librarySortProvider);

    final isList =
        viewMode == LibraryViewMode.list ||
        currentFilter == LibraryFilter.audio;

    return Scaffold(
      appBar: _buildAppBar(context, theme, viewMode, currentSort),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: StorageInfoCard(),
            ),
            const FilterChipsBar(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.read(libraryProvider.notifier).refresh(),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child:
                      items.isEmpty
                          ? LayoutBuilder(
                            key: const ValueKey('library_empty_view'),
                            builder:
                                (context, constraints) => SingleChildScrollView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: constraints.maxHeight,
                                    ),
                                    child: _buildEmptyState(
                                      theme,
                                      currentFilter,
                                      searchQuery,
                                    ),
                                  ),
                                ),
                          )
                          : isList
                          ? ListView.builder(
                            key: const ValueKey('library_list_view'),
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return _buildMediaListTile(
                                context,
                                ref,
                                item,
                                theme,
                              );
                            },
                          )
                          : LayoutBuilder(
                            builder: (context, constraints) {
                              final scale =
                                  MediaQuery.textScalerOf(context).scale(14) /
                                  14;
                              final columns =
                                  scale > 1.4
                                      ? (constraints.maxWidth ~/ 280).clamp(
                                        1,
                                        4,
                                      )
                                      : (constraints.maxWidth ~/ 180).clamp(
                                        2,
                                        5,
                                      );
                              final tileWidth =
                                  (constraints.maxWidth -
                                      32 -
                                      12 * (columns - 1)) /
                                  columns;
                              return GridView.builder(
                                key: const ValueKey('library_grid_view'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      mainAxisExtent:
                                          tileWidth * 9 / 16 + 78 * scale + 28,
                                    ),
                                itemCount: items.length,
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  return MediaGridItem(
                                    item: item,
                                    onActions:
                                        () => _showActionsBottomSheet(
                                          context,
                                          ref,
                                          item,
                                        ),
                                    onOpen:
                                        () => _handleOpenMedia(context, item),
                                    onTap:
                                        () => _handleOpenMedia(context, item),
                                  );
                                },
                              );
                            },
                          ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Outlined film clapperboard illustration matching Screen 3 of the design mockup:
/// - Slightly open top clapper bar with diagonal stripes
/// - Bottom container with rounded corners
/// - Centered play button triangle
class _ClapperboardPainter extends CustomPainter {
  final Color color;
  const _ClapperboardPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint =
        Paint()
          ..color = color
          ..strokeWidth = 2.4
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round;

    final fillPaint =
        Paint()
          ..color = color.withValues(alpha: 0.08)
          ..style = PaintingStyle.fill;

    // Dimensions
    const double boardTop = 24.0;
    final double boardHeight = size.height - boardTop;
    final rrect = RRect.fromRectAndCorners(
      Rect.fromLTWH(6, boardTop, size.width - 12, boardHeight - 4),
      bottomLeft: const Radius.circular(10),
      bottomRight: const Radius.circular(10),
      topLeft: const Radius.circular(4),
      topRight: const Radius.circular(4),
    );

    // Draw main clapper board
    canvas.drawRRect(rrect, fillPaint);
    canvas.drawRRect(rrect, strokePaint);

    // Draw center play triangle
    final playPath =
        Path()
          ..moveTo(size.width * 0.45, boardTop + boardHeight * 0.30)
          ..lineTo(size.width * 0.45, boardTop + boardHeight * 0.66)
          ..lineTo(size.width * 0.60, boardTop + boardHeight * 0.48)
          ..close();
    canvas.drawPath(playPath, strokePaint);

    // Draw tilted top clapper bar (slightly tilted up by ~10 degrees)
    canvas.save();
    canvas.translate(6, boardTop);
    canvas.rotate(-0.16);

    final topBarRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, -18, size.width - 12, 16),
      const Radius.circular(4),
    );
    canvas.drawRRect(topBarRRect, fillPaint);
    canvas.drawRRect(topBarRRect, strokePaint);

    // Draw diagonal striped segments
    final barWidth = size.width - 12;
    for (double x = 14; x < barWidth - 6; x += 16) {
      canvas.drawLine(Offset(x, -2), Offset(x + 8, -18), strokePaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ClapperboardPainter oldDelegate) =>
      color != oldDelegate.color;
}
