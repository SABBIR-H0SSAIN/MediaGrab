import '../../../player/presentation/utils/playback_navigation.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/file_utils.dart';
import '../../../../core/utils/media_error_message.dart';
import '../../domain/entities/download_task.dart';
import '../providers/download_manager_provider.dart';
import '../widgets/download_tile.dart';
import '../widgets/empty_downloads_view.dart';

/// Screen displaying downloads organized into 2 Material 3 tabs:
/// - Active (with count badge, containing active, paused, queued, and failed downloads)
/// - Completed (with count badge, containing finished downloads)
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key, this.initialTab});

  /// Optional initial tab ('active' or 'completed').
  final String? initialTab;

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _sortAscending = false;

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.initialTab == 'completed' ? 1 : 0;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: initialIndex,
    );
    _tabController.addListener(() {
      if (mounted) {
        if (_tabController.index != ref.read(downloadsSelectedTabProvider)) {
          ref.read(downloadsSelectedTabProvider.notifier).state =
              _tabController.index;
        }
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(covariant DownloadsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != null) {
      final targetIndex = widget.initialTab == 'completed' ? 1 : 0;
      if (_tabController.index != targetIndex) {
        _tabController.animateTo(targetIndex);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  List<DownloadTask> _filterAndSort(List<DownloadTask> tasks) {
    var filtered = tasks;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered =
          filtered.where((t) {
            final title = t.mediaInfo.title.toLowerCase();
            final path = (t.filePath ?? '').toLowerCase();
            final quality = t.selectedStream.qualityLabel.toLowerCase();
            return title.contains(q) || path.contains(q) || quality.contains(q);
          }).toList();
    }
    final sorted = List<DownloadTask>.from(filtered);
    sorted.sort((a, b) {
      final aTime = a.completedAt ?? a.createdAt;
      final bTime = b.completedAt ?? b.createdAt;
      return _sortAscending ? aTime.compareTo(bTime) : bTime.compareTo(aTime);
    });
    return sorted;
  }

  Future<void> _handleTaskAction(Future<bool> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mediaErrorMessage(error))));
      }
    }
  }

  Future<void> _handleOpen(BuildContext context, DownloadTask task) async {
    final filePath = task.filePath;
    if (filePath == null) return;

    openLocalPlayback(
      context,
      playbackItemFromTask(task),
      _filterAndSort(
        ref.read(completedDownloadsProvider),
      ).map(playbackItemFromTask),
    );
  }

  Future<void> _openExternal(BuildContext context, String filePath) async {
    final result = await openMediaFile(filePath);
    if (result.type != ResultType.done && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open file: ${result.message}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleShare(BuildContext context, DownloadTask task) async {
    if (task.filePath == null) return;
    final file = File(task.filePath!);
    if (await file.exists()) {
      await Share.shareXFiles([
        XFile(task.filePath!),
      ], text: task.mediaInfo.title);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File not found on device'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleDelete(
    BuildContext context,
    WidgetRef ref,
    DownloadTask task,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: const Text('Delete Download'),
          content: Text(
            'Are you sure you want to delete "${task.mediaInfo.title}"?',
          ),
          actionsAlignment: MainAxisAlignment.end,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await ref
            .read(downloadManagerProvider.notifier)
            .removeTask(task.id, deleteFile: true);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted "${task.mediaInfo.title}" from device'),
            ),
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
  }

  Future<void> _handleClearAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: const Text('Clear Completed Downloads'),
          content: const Text(
            'Are you sure you want to remove all completed downloads from history?',
          ),
          actionsAlignment: MainAxisAlignment.end,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Clear All'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await ref.read(downloadManagerProvider.notifier).clearCompleted();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cleared completed history'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget? _buildActiveHeader(
    BuildContext context,
    WidgetRef ref,
    List<DownloadTask> tasks,
  ) {
    if (tasks.isEmpty) return null;
    final theme = Theme.of(context);
    final hasActive = tasks.any((t) => t.status.isActive);
    final hasPaused = tasks.any((t) => t.status.isPaused);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(
            '${tasks.length} ${tasks.length == 1 ? 'download' : 'downloads'}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.outline,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          if (hasActive)
            TextButton.icon(
              onPressed:
                  () => ref.read(downloadManagerProvider.notifier).pauseAll(),
              icon: const Icon(Icons.pause_circle_outline_rounded, size: 16),
              label: const Text('Pause All'),
            ),
          if (hasPaused)
            TextButton.icon(
              onPressed:
                  () => ref.read(downloadManagerProvider.notifier).resumeAll(),
              icon: const Icon(Icons.play_circle_outline_rounded, size: 16),
              label: const Text('Resume All'),
            ),
        ],
      ),
    );
  }

  Widget? _buildCompletedHeader(
    BuildContext context,
    WidgetRef ref,
    List<DownloadTask> tasks,
  ) {
    if (tasks.isEmpty) return null;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(
            '${tasks.length} ${tasks.length == 1 ? 'file' : 'files'}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.outline,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _handleClearAll(context, ref),
            icon: const Icon(Icons.delete_sweep_outlined, size: 16),
            label: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAppBarActions(
    BuildContext context,
    WidgetRef ref,
    List<DownloadTask> activeTasks,
    List<DownloadTask> completedTasks,
  ) {
    final theme = Theme.of(context);
    return [
      IconButton(
        key: const ValueKey('downloads_search_action'),
        icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded),
        tooltip: _isSearching ? 'Close Search' : 'Search Downloads',
        onPressed: () {
          setState(() {
            _isSearching = !_isSearching;
            if (!_isSearching) {
              _searchController.clear();
              _searchQuery = '';
            }
          });
        },
      ),
      PopupMenuButton<String>(
        key: const ValueKey('downloads_more_menu'),
        icon: const Icon(Icons.more_vert_rounded),
        color: theme.colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        onSelected: (value) {
          switch (value) {
            case 'sort_newest':
              setState(() => _sortAscending = false);
              break;
            case 'sort_oldest':
              setState(() => _sortAscending = true);
              break;
            case 'pause_all':
              ref.read(downloadManagerProvider.notifier).pauseAll();
              break;
            case 'resume_all':
              ref.read(downloadManagerProvider.notifier).resumeAll();
              break;
            case 'clear_completed':
              _handleClearAll(context, ref);
              break;
          }
        },
        itemBuilder: (context) {
          final hasActive = activeTasks.any((t) => t.status.isActive);
          final hasPaused = activeTasks.any((t) => t.status.isPaused);
          return [
            PopupMenuItem(
              value: 'sort_newest',
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_downward_rounded,
                    size: 20,
                    color: !_sortAscending ? theme.colorScheme.primary : null,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Sort by Newest',
                    style: TextStyle(
                      fontWeight:
                          !_sortAscending ? FontWeight.bold : FontWeight.normal,
                      color: !_sortAscending ? theme.colorScheme.primary : null,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'sort_oldest',
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_upward_rounded,
                    size: 20,
                    color: _sortAscending ? theme.colorScheme.primary : null,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Sort by Oldest',
                    style: TextStyle(
                      fontWeight:
                          _sortAscending ? FontWeight.bold : FontWeight.normal,
                      color: _sortAscending ? theme.colorScheme.primary : null,
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            if (hasActive)
              const PopupMenuItem(
                value: 'pause_all',
                child: Row(
                  children: [
                    Icon(Icons.pause_circle_outline_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Pause All'),
                  ],
                ),
              ),
            if (hasPaused)
              const PopupMenuItem(
                value: 'resume_all',
                child: Row(
                  children: [
                    Icon(Icons.play_circle_outline_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Resume All'),
                  ],
                ),
              ),
            if (completedTasks.isNotEmpty)
              const PopupMenuItem(
                value: 'clear_completed',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('Clear Completed'),
                  ],
                ),
              ),
          ];
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(downloadsSelectedTabProvider, (prev, next) {
      if (_tabController.index != next) {
        _tabController.animateTo(next);
      }
    });

    final activeTasks = ref.watch(activeDownloadsProvider);
    final completedTasks = ref.watch(completedDownloadsProvider);
    final filteredActive = _filterAndSort(activeTasks);
    final filteredCompleted = _filterAndSort(completedTasks);
    final activeCount = activeTasks.length;
    final notifier = ref.read(downloadManagerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        title:
            _isSearching
                ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Search downloads...',
                    hintStyle: TextStyle(color: theme.colorScheme.outline),
                    border: InputBorder.none,
                    suffixIcon:
                        _searchQuery.isNotEmpty
                            ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                            : null,
                  ),
                  onChanged: (val) {
                    setState(() => _searchQuery = val.trim());
                  },
                )
                : const Text(
                  'Downloads',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
        centerTitle: false,
        actions: _buildAppBarActions(context, ref, activeTasks, completedTasks),
        bottom: TabBar(
          controller: _tabController,
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorPadding: const EdgeInsets.symmetric(horizontal: 22),
          indicatorColor: theme.colorScheme.primary,
          indicatorWeight: 3.5,
          dividerColor: theme.colorScheme.outlineVariant.withValues(alpha: .35),
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
          tabs: [
            Tab(
              child: Badge.count(
                count: activeCount,
                isLabelVisible: activeCount > 0,
                backgroundColor: theme.colorScheme.primary,
                textColor: theme.colorScheme.onPrimary,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('Active'),
                ),
              ),
            ),
            const Tab(text: 'Completed'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DownloadListTab(
            key: const ValueKey('tab_active_downloads'),
            storageKey: 'active_downloads_list',
            tasks: filteredActive,
            header: _buildActiveHeader(context, ref, filteredActive),
            emptyView: EmptyDownloadsView(
              title:
                  _searchQuery.isNotEmpty
                      ? 'No matching downloads'
                      : 'No active downloads',
              subtitle:
                  _searchQuery.isNotEmpty
                      ? 'No results found for "$_searchQuery"'
                      : 'Start a download to see the progress here',
              icon:
                  _searchQuery.isNotEmpty
                      ? Icons.search_off_rounded
                      : Icons.file_download_rounded,
            ),
            onPause: (t) => notifier.pauseDownload(t.id),
            onResume:
                (t) => _handleTaskAction(() => notifier.resumeDownload(t.id)),
            onCancel: (t) => notifier.cancelDownload(t.id),
            onRetry:
                (t) => _handleTaskAction(() => notifier.retryDownload(t.id)),
            onOpen: (t) => _handleOpen(context, t),
            onOpenWith: (t) {
              if (t.filePath != null) _openExternal(context, t.filePath!);
            },
            onShare: (t) => _handleShare(context, t),
            onDelete: (t) => _handleDelete(context, ref, t),
          ),
          _DownloadListTab(
            key: const ValueKey('tab_completed_downloads'),
            storageKey: 'completed_downloads_list',
            tasks: filteredCompleted,
            header: _buildCompletedHeader(context, ref, filteredCompleted),
            emptyView: EmptyDownloadsView(
              title:
                  _searchQuery.isNotEmpty
                      ? 'No matching downloads'
                      : 'No completed downloads',
              subtitle:
                  _searchQuery.isNotEmpty
                      ? 'No results found for "$_searchQuery"'
                      : 'Downloaded files will appear here',
              icon:
                  _searchQuery.isNotEmpty
                      ? Icons.search_off_rounded
                      : Icons.check_circle_outline_rounded,
              buttonLabel: 'Explore Media',
            ),
            onPause: (t) => notifier.pauseDownload(t.id),
            onResume:
                (t) => _handleTaskAction(() => notifier.resumeDownload(t.id)),
            onCancel: (t) => notifier.cancelDownload(t.id),
            onRetry:
                (t) => _handleTaskAction(() => notifier.retryDownload(t.id)),
            onOpen: (t) => _handleOpen(context, t),
            onOpenWith: (t) {
              if (t.filePath != null) _openExternal(context, t.filePath!);
            },
            onShare: (t) => _handleShare(context, t),
            onDelete: (t) => _handleDelete(context, ref, t),
          ),
        ],
      ),
    );
  }
}

class _DownloadListTab extends StatefulWidget {
  final List<DownloadTask> tasks;
  final Widget? header;
  final Widget emptyView;
  final String storageKey;
  final void Function(DownloadTask task)? onPause;
  final void Function(DownloadTask task)? onResume;
  final void Function(DownloadTask task)? onCancel;
  final void Function(DownloadTask task)? onRetry;
  final void Function(DownloadTask task)? onOpen;
  final void Function(DownloadTask task)? onShare;
  final void Function(DownloadTask task)? onOpenWith;
  final void Function(DownloadTask task)? onDelete;

  const _DownloadListTab({
    super.key,
    required this.tasks,
    this.header,
    required this.emptyView,
    required this.storageKey,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onRetry,
    this.onOpen,
    this.onShare,
    this.onOpenWith,
    this.onDelete,
  });

  @override
  State<_DownloadListTab> createState() => _DownloadListTabState();
}

class _DownloadListTabState extends State<_DownloadListTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.tasks.isEmpty) {
      return widget.emptyView;
    }

    final hasHeader = widget.header != null;
    final totalCount = widget.tasks.length + (hasHeader ? 1 : 0);

    return ListView.builder(
      key: PageStorageKey(widget.storageKey),
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        if (hasHeader && index == 0) {
          return widget.header!;
        }
        final taskIndex = hasHeader ? index - 1 : index;
        final task = widget.tasks[taskIndex];
        return DownloadTile(
          key: ValueKey(task.id),
          task: task,
          index: taskIndex,
          onPause: widget.onPause,
          onResume: widget.onResume,
          onCancel: widget.onCancel,
          onRetry: widget.onRetry,
          onOpen: widget.onOpen,
          onOpenWith: widget.onOpenWith,
          onShare: widget.onShare,
          onDelete: widget.onDelete,
        );
      },
    );
  }
}
