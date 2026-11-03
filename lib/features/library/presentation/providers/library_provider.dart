import 'dart:io';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/utils/file_utils.dart';
import '../../../../core/utils/url_parser.dart';
import '../../../downloads/data/services/download_registry.dart';
import '../../../downloads/domain/entities/download_task.dart';
import '../../../downloads/domain/enums/download_status.dart';
import '../../../downloads/presentation/providers/download_manager_provider.dart';

/// Filter categories for the Library screen.
enum LibraryFilter {
  all,
  videos,
  audio,
  youtube,
  facebook,
  instagram;

  String get displayName {
    switch (this) {
      case LibraryFilter.all:
        return 'All';
      case LibraryFilter.videos:
        return 'Videos';
      case LibraryFilter.audio:
        return 'Audio';
      case LibraryFilter.youtube:
        return 'YouTube';
      case LibraryFilter.facebook:
        return 'Facebook';
      case LibraryFilter.instagram:
        return 'Instagram';
    }
  }
}

/// Sort options for the Library screen.
enum LibrarySort {
  newest,
  oldest,
  largest,
  name;

  String get displayName {
    switch (this) {
      case LibrarySort.newest:
        return 'Newest';
      case LibrarySort.oldest:
        return 'Oldest';
      case LibrarySort.largest:
        return 'Largest';
      case LibrarySort.name:
        return 'Name';
    }
  }
}

/// View mode options for the Library screen.
enum LibraryViewMode { grid, list }

/// Immutable model representing a downloaded media file in the user's library.
class LibraryMediaItem extends Equatable {
  final String id;
  final String title;
  final String filePath;
  final int fileSize; // In bytes
  final FileType fileType;
  final Duration duration;
  final String? thumbnailUrl;
  final String? thumbnailPath;
  final PlatformType platform;
  final DateTime downloadedAt;
  final String? qualityLabel;
  final String? uploader;

  const LibraryMediaItem({
    required this.id,
    required this.title,
    required this.filePath,
    required this.fileSize,
    required this.fileType,
    this.duration = Duration.zero,
    this.thumbnailUrl,
    this.thumbnailPath,
    this.platform = PlatformType.unknown,
    required this.downloadedAt,
    this.qualityLabel,
    this.uploader,
  });

  /// Creates a [LibraryMediaItem] from an authoritative [DownloadRecord].
  factory LibraryMediaItem.fromRecord(DownloadRecord record) {
    return LibraryMediaItem(
      id: record.id,
      title: record.title,
      filePath: record.filePath,
      fileSize: record.fileSize,
      fileType: record.mediaType,
      duration: record.duration,
      thumbnailUrl: record.thumbnailUrl,
      thumbnailPath: record.thumbnailPath,
      platform: record.platform,
      downloadedAt: record.completedAt,
      qualityLabel: record.qualityLabel,
      uploader: record.uploader,
    );
  }

  /// Formatted file size string (e.g. "1.2 GB", "350 MB", "1.5 KB").
  String get formattedSize => formatFileSize(fileSize);

  /// Formatted duration string (e.g. "1:23:45", "5:30", "0:45").
  String get formattedDuration => formatDuration(duration);

  /// Human-readable format and quality pill text (e.g. "1080p • MP4", "320kbps • MP3").
  String get formatPill {
    final cleanPath = filePath.split('?').first.split('#').first;
    final dotIdx = cleanPath.lastIndexOf('.');
    final ext =
        dotIdx != -1 ? cleanPath.substring(dotIdx + 1).toUpperCase() : '';

    if (qualityLabel != null && qualityLabel!.isNotEmpty) {
      if (ext.isNotEmpty && !qualityLabel!.toUpperCase().contains(ext)) {
        return '$qualityLabel • $ext';
      }
      return qualityLabel!;
    }
    if (ext.isNotEmpty) return ext;
    return fileType.displayName;
  }

  /// Checks if this item matches the selected [LibraryFilter].
  bool matchesFilter(LibraryFilter filter) {
    switch (filter) {
      case LibraryFilter.all:
        return true;
      case LibraryFilter.videos:
        return fileType == FileType.video;
      case LibraryFilter.audio:
        return fileType == FileType.audio;
      case LibraryFilter.youtube:
        return platform == PlatformType.youtube;
      case LibraryFilter.facebook:
        return platform == PlatformType.facebook;
      case LibraryFilter.instagram:
        return platform == PlatformType.instagram;
    }
  }

  LibraryMediaItem copyWith({
    String? id,
    String? title,
    String? filePath,
    int? fileSize,
    FileType? fileType,
    Duration? duration,
    String? thumbnailUrl,
    String? thumbnailPath,
    PlatformType? platform,
    DateTime? downloadedAt,
    String? qualityLabel,
    String? uploader,
  }) {
    return LibraryMediaItem(
      id: id ?? this.id,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      fileType: fileType ?? this.fileType,
      duration: duration ?? this.duration,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      platform: platform ?? this.platform,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      qualityLabel: qualityLabel ?? this.qualityLabel,
      uploader: uploader ?? this.uploader,
    );
  }

  @override
  List<Object?> get props => [
    id,
    title,
    filePath,
    fileSize,
    fileType,
    duration,
    thumbnailUrl,
    thumbnailPath,
    platform,
    downloadedAt,
    qualityLabel,
    uploader,
  ];
}

/// Helper to discover candidate directories where downloaded media might reside.
Future<List<String>> getCandidateDownloadDirectories({
  String? settingsDownloadDirectory,
}) async {
  final dirs = <String>{};

  // Include user-configured download directory from settings
  if (settingsDownloadDirectory != null &&
      settingsDownloadDirectory.trim().isNotEmpty) {
    dirs.add(settingsDownloadDirectory.trim());
    dirs.add('${settingsDownloadDirectory.trim()}/MediaGrab');
  }

  // Standard external download folder (only dedicated app subfolder, never root Download directory!)
  dirs.add('/storage/emulated/0/Download/MediaGrab');

  // Skip path_provider platform channels in test environments to avoid method channel timeouts
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return dirs.toList();
  }

  // App documents directory
  try {
    final docDir = await getApplicationDocumentsDirectory();
    dirs.add(docDir.path);
    dirs.add('${docDir.path}/MediaGrab');
  } catch (_) {}

  // App external files directory
  try {
    final extDir = await getExternalStorageDirectory();
    if (extDir != null) {
      dirs.add(extDir.path);
      dirs.add('${extDir.path}/MediaGrab');
    }
  } catch (_) {}

  // Downloads directory from path_provider
  try {
    final downloadsDir = await getDownloadsDirectory();
    if (downloadsDir != null) {
      dirs.add(downloadsDir.path);
      dirs.add('${downloadsDir.path}/MediaGrab');
    }
  } catch (_) {}

  return dirs.toList();
}

/// Manages the state of downloaded media files in the library.
class LibraryNotifier extends StateNotifier<List<LibraryMediaItem>> {
  LibraryNotifier([
    List<LibraryMediaItem>? initialItems,
    Ref? ref,
    DownloadRegistry? registry,
  ]) : _ref = ref,
       _registry = registry,
       super(initialItems ?? const []) {
    if (initialItems == null) {
      refresh();
    }
  }

  final Ref? _ref;
  final DownloadRegistry? _registry;

  DownloadRegistry? get registry =>
      _registry ?? _ref?.read(downloadRegistryProvider);

  /// Adds a new media item to the library.
  void addItem(LibraryMediaItem item) {
    state = [item, ...state.where((i) => i.id != item.id)];
  }

  /// Adds a completed download task to the library and registers it in the persistent download registry.
  void addDownloadedItem(DownloadTask task) {
    if (task.status != DownloadStatus.completed) return;
    if (state.any((item) => item.id == task.id)) return;

    final filePath = task.filePath ?? '';
    FileType fileType;
    if (task.selectedStream.isAudioOnly) {
      fileType = FileType.audio;
    } else {
      final detected = getFileType(filePath);
      fileType = detected == FileType.other ? FileType.video : detected;
    }

    var cleanTitle = task.mediaInfo.title.trim();
    if (cleanTitle.contains('/') || cleanTitle.contains('\\')) {
      cleanTitle = cleanTitle.split(RegExp(r'[/\\]')).last.trim();
    }

    final item = LibraryMediaItem(
      id: task.id,
      title: cleanTitle.isNotEmpty ? cleanTitle : 'Untitled Video',
      filePath: filePath,
      fileSize:
          (task.totalBytes != null && task.totalBytes! > 0)
              ? task.totalBytes!
              : (task.downloadedBytes ?? 0),
      fileType: fileType,
      duration: task.mediaInfo.duration,
      thumbnailUrl: task.mediaInfo.thumbnailUrl,
      platform: task.mediaInfo.platform,
      downloadedAt: task.completedAt ?? task.createdAt,
      qualityLabel: task.selectedStream.qualityLabel,
      uploader: task.mediaInfo.uploader,
    );

    // Register with authoritative persistent registry
    final reg = registry;
    if (reg != null) {
      reg.register(DownloadRecord.fromTask(task));
    }

    addItem(item);
  }

  /// Removes an item from the library, cleans up persistent registry, and optionally deletes the physical file.
  Future<void> removeItem(String id, {bool deletePhysicalFile = false}) async {
    final item = state.firstWhere(
      (element) => element.id == id,
      orElse:
          () => LibraryMediaItem(
            id: '',
            title: '',
            filePath: '',
            fileSize: 0,
            fileType: FileType.other,
            downloadedAt: DateTime.now(),
          ),
    );

    if (deletePhysicalFile && item.id.isNotEmpty) {
      await deleteMediaFile(item.filePath);
    }

    if (_ref != null) {
      await _ref.read(downloadManagerProvider.notifier).removeTask(id);
    }

    // Remove from authoritative persistent registry
    final reg = registry;
    if (reg != null) {
      await reg.remove(id);
    }
    state = state.where((item) => item.id != id).toList();
  }

  /// Updates an existing media item in place.
  void updateItem(LibraryMediaItem updated) {
    state = [
      for (final item in state)
        if (item.id == updated.id) updated else item,
    ];
  }

  /// Updates the visible list after a completed task is removed elsewhere.
  void removeItemsFromView(Set<String> ids) {
    state = state.where((item) => !ids.contains(item.id)).toList();
  }

  /// Replaces the library items with a new list.
  void setItems(List<LibraryMediaItem> items) {
    state = List.unmodifiable(items);
  }

  /// Clears all library items.
  void clear() {
    state = const [];
  }

  /// Compatibility entry point: the registry remains the only source of media.
  Future<void> scanDirectories({
    List<String>? customDirectories,
    String? settingsDownloadDirectory,
  }) => refresh();

  /// Refreshes exclusively from completed registry records whose files exist.
  Future<void> refresh({
    List<String>? directoriesToScan,
    String? settingsDownloadDirectory,
  }) async {
    final reg = registry;
    if (reg == null) return;
    final records = await reg.getCompletedRecords(verifyFileExists: true);
    if (!mounted) return;
    state = records.map(LibraryMediaItem.fromRecord).toList();
  }
}

/// Provider for the selected library filter category.
final libraryFilterProvider = StateProvider<LibraryFilter>(
  (ref) => LibraryFilter.all,
);

/// Provider for the search query in the Library screen.
final librarySearchQueryProvider = StateProvider<String>((ref) => '');

/// Provider for the selected sort option.
final librarySortProvider = StateProvider<LibrarySort>(
  (ref) => LibrarySort.newest,
);

/// Provider for grid vs list view mode.
final libraryViewModeProvider = StateProvider<LibraryViewMode>(
  (ref) => LibraryViewMode.grid,
);

/// Main provider holding the list of all media items in the library.
final libraryProvider =
    StateNotifierProvider<LibraryNotifier, List<LibraryMediaItem>>((ref) {
      final notifier = LibraryNotifier(null, ref);

      ref.listen<List<DownloadTask>>(completedDownloadsProvider, (
        previous,
        completedTasks,
      ) {
        final remainingIds = completedTasks.map((task) => task.id).toSet();
        final removedIds =
            (previous ?? const <DownloadTask>[])
                .map((task) => task.id)
                .where((id) => !remainingIds.contains(id))
                .toSet();
        if (removedIds.isNotEmpty) {
          notifier.removeItemsFromView(removedIds);
        }
        for (final task in completedTasks) {
          notifier.addDownloadedItem(task);
        }
      }, fireImmediately: true);

      return notifier;
    });

/// Filtered, searched, and sorted list of media files.
final filteredLibraryProvider = Provider<List<LibraryMediaItem>>((ref) {
  final items = ref.watch(libraryProvider);
  final filter = ref.watch(libraryFilterProvider);
  final query = ref.watch(librarySearchQueryProvider).trim().toLowerCase();
  final sort = ref.watch(librarySortProvider);

  // 1. Filter by category/platform
  var filtered =
      filter == LibraryFilter.all
          ? items
          : items.where((item) => item.matchesFilter(filter)).toList();

  // 2. Filter by search query
  if (query.isNotEmpty) {
    filtered =
        filtered.where((item) {
          final titleMatch = item.title.toLowerCase().contains(query);
          final uploaderMatch =
              item.uploader?.toLowerCase().contains(query) ?? false;
          return titleMatch || uploaderMatch;
        }).toList();
  }

  // 3. Sort
  final result = List<LibraryMediaItem>.from(filtered);
  switch (sort) {
    case LibrarySort.newest:
      result.sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
      break;
    case LibrarySort.oldest:
      result.sort((a, b) => a.downloadedAt.compareTo(b.downloadedAt));
      break;
    case LibrarySort.largest:
      result.sort((a, b) => b.fileSize.compareTo(a.fileSize));
      break;
    case LibrarySort.name:
      result.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
      break;
  }

  return result;
});

/// Total number of downloads in the library.
final totalDownloadsCountProvider = Provider<int>((ref) {
  return ref.watch(libraryProvider).length;
});

/// Total storage in bytes occupied by downloaded media files.
final totalStorageBytesProvider = Provider<int>((ref) {
  final items = ref.watch(libraryProvider);
  return items.fold<int>(0, (sum, item) => sum + item.fileSize);
});

/// Formatted total storage string (e.g. "1.2 GB").
final formattedTotalStorageProvider = Provider<String>((ref) {
  final totalBytes = ref.watch(totalStorageBytesProvider);
  return formatFileSize(totalBytes);
});
