import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../extractor/domain/entities/media_info.dart';
import '../../../extractor/domain/entities/stream_info.dart';
import '../../../extractor/presentation/providers/extractor_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/services/download_engine.dart';
import '../../data/services/download_registry.dart';
import '../../data/services/download_session_store.dart';
import '../../domain/entities/download_task.dart';
import '../../domain/enums/download_status.dart';

/// Exception thrown when download attempt is rejected because downloadOverCellular is false
/// and the device is connected exclusively to cellular data.
class CellularDownloadBlockedException implements Exception {
  final String message;

  const CellularDownloadBlockedException([
    this.message =
        'Cellular downloading is disabled in settings. Connect to Wi-Fi to proceed.',
  ]);

  @override
  String toString() => message;
}

/// Provider for the [Connectivity] service, overridable in tests.
final connectivityProvider = Provider<Connectivity?>((ref) {
  try {
    ServicesBinding.instance;
    return Connectivity();
  } catch (_) {
    return null;
  }
});

/// Provider for the [DownloadEngine] instance.
final downloadEngineProvider = Provider<DownloadEngine>((ref) {
  final extractorFactory = ref.watch(extractorFactoryProvider);
  final initialSettings = ref.read(settingsProvider);
  final registry = ref.watch(downloadRegistryProvider);
  final engine = DownloadEngine(
    extractorFactory: extractorFactory,
    maxConcurrentDownloads: initialSettings.maxConcurrentDownloads,
    downloadRegistry: registry,
    sessionStore: DownloadSessionStore(),
  );
  unawaited(engine.restoreSession());
  ref.onDispose(() {
    engine.dispose();
  });
  return engine;
});

/// StateNotifier managing the list of all download tasks and coordinating with [DownloadEngine].
class DownloadManagerNotifier extends StateNotifier<List<DownloadTask>> {
  final DownloadEngine _engine;
  SettingsState _settings;
  final Connectivity? _connectivity;
  final Future<bool> Function()? _cellularChecker;
  final Set<String> _pausedForCellularTaskIds = {};

  StreamSubscription<List<DownloadTask>>? _tasksSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  DownloadManagerNotifier(
    this._engine, [
    List<DownloadTask>? initialTasks,
    SettingsState settings = const SettingsState(),
    Connectivity? connectivity,
    Future<bool> Function()? cellularChecker,
  ]) : _settings = settings,
       _connectivity = connectivity,
       _cellularChecker = cellularChecker,
       super(initialTasks ?? _engine.getAllDownloads()) {
    _engine.updateMaxConcurrentDownloads(_settings.maxConcurrentDownloads);
    _tasksSub = _engine.onTasksChanged.listen((_) {
      // A queued stream snapshot can be older than an awaited control action.
      state = List.unmodifiable(_engine.getAllDownloads());
    });
    _initConnectivity();
  }

  /// Current settings observed by this manager.
  SettingsState get settings => _settings;

  /// IDs of tasks temporarily paused due to cellular-only connection.
  Set<String> get pausedForCellularTaskIds =>
      Set.unmodifiable(_pausedForCellularTaskIds);

  void _initConnectivity() {
    final connectivity = _connectivity;
    if (connectivity != null) {
      try {
        _connectivitySub = connectivity.onConnectivityChanged.listen((results) {
          _handleConnectivityChange(results);
        });
      } catch (_) {}
    }
  }

  Future<void> _handleConnectivityChange(
    List<ConnectivityResult> results,
  ) async {
    final hasCellular = results.contains(ConnectivityResult.mobile);
    final hasWifi =
        results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
    final isCellularOnly = hasCellular && !hasWifi;

    if (!_settings.downloadOverCellular && isCellularOnly) {
      // Pause all active downloads
      final activeTasks = _engine.getActiveDownloads();
      for (final task in activeTasks) {
        _pausedForCellularTaskIds.add(task.id);
        await _engine.pauseDownload(task.id);
      }
    } else if (hasWifi || _settings.downloadOverCellular) {
      // Resume downloads paused due to cellular
      if (_pausedForCellularTaskIds.isNotEmpty) {
        final toResume = List<String>.from(_pausedForCellularTaskIds);
        _pausedForCellularTaskIds.clear();
        for (final id in toResume) {
          await _engine.resumeDownload(id);
        }
      }
    }
  }

  /// Updates settings observed by the download manager and applies them to engine and queue.
  void updateSettings(SettingsState newSettings) {
    final oldSettings = _settings;
    _settings = newSettings;
    _engine.updateMaxConcurrentDownloads(newSettings.maxConcurrentDownloads);

    if (oldSettings.downloadOverCellular != newSettings.downloadOverCellular) {
      if (!newSettings.downloadOverCellular) {
        isCellularOnly().then((isCellular) async {
          if (isCellular) {
            final activeTasks = _engine.getActiveDownloads();
            for (final task in activeTasks) {
              _pausedForCellularTaskIds.add(task.id);
              await _engine.pauseDownload(task.id);
            }
          }
        });
      } else {
        if (_pausedForCellularTaskIds.isNotEmpty) {
          final toResume = List<String>.from(_pausedForCellularTaskIds);
          _pausedForCellularTaskIds.clear();
          for (final id in toResume) {
            _engine.resumeDownload(id);
          }
        }
      }
    }
  }

  /// Checks whether current connection is cellular only.
  Future<bool> isCellularOnly() async {
    final checker = _cellularChecker;
    if (checker != null) {
      return await checker();
    }
    final connectivity = _connectivity;
    if (connectivity == null) {
      return false;
    }
    try {
      final results = await connectivity.checkConnectivity();
      final hasCellular = results.contains(ConnectivityResult.mobile);
      final hasWifi =
          results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet);
      return hasCellular && !hasWifi;
    } catch (_) {
      return false;
    }
  }

  /// Resolves the final download path respecting [SettingsState.downloadDirectory].
  String resolveDownloadPath(String outputPath) {
    final customDir = _settings.downloadDirectory.trim();
    if (customDir.isNotEmpty) {
      final fileName = p.basename(outputPath);
      return p.join(customDir, fileName);
    }
    return outputPath;
  }

  /// Initiates a download with the specified media metadata and stream options.
  Future<DownloadTask> startDownload(
    MediaInfo mediaInfo,
    StreamInfo selectedStream,
    String outputPath, {
    StreamInfo? audioStream,
  }) async {
    if (!_settings.downloadOverCellular) {
      final isCellular = await isCellularOnly();
      if (isCellular) {
        throw const CellularDownloadBlockedException();
      }
    }

    final effectivePath = resolveDownloadPath(outputPath);

    final task = await _engine.startDownload(
      mediaInfo,
      selectedStream,
      effectivePath,
      audioStream: audioStream,
    );
    state = List.unmodifiable(_engine.getAllDownloads());
    return task;
  }

  /// Pauses an active download.
  Future<bool> pauseDownload(String taskId) async {
    _pausedForCellularTaskIds.remove(taskId);
    final accepted = await _engine.pauseDownload(taskId);
    state = List.unmodifiable(_engine.getAllDownloads());
    return accepted;
  }

  /// Resumes a paused download.
  Future<bool> resumeDownload(String taskId) async {
    if (!_settings.downloadOverCellular) {
      final isCellular = await isCellularOnly();
      if (isCellular) {
        throw const CellularDownloadBlockedException();
      }
    }
    _pausedForCellularTaskIds.remove(taskId);
    final accepted = await _engine.resumeDownload(taskId);
    state = List.unmodifiable(_engine.getAllDownloads());
    return accepted;
  }

  /// Cancels an in-progress or queued download.
  Future<bool> cancelDownload(String taskId) async {
    _pausedForCellularTaskIds.remove(taskId);
    final accepted = await _engine.cancelDownload(taskId);
    state = List.unmodifiable(_engine.getAllDownloads());
    return accepted;
  }

  /// Retries a failed or cancelled download.
  Future<bool> retryDownload(String taskId) async {
    if (!_settings.downloadOverCellular) {
      final isCellular = await isCellularOnly();
      if (isCellular) {
        throw const CellularDownloadBlockedException();
      }
    }
    final accepted = await _engine.retryDownload(taskId);
    state = List.unmodifiable(_engine.getAllDownloads());
    return accepted;
  }

  /// Pauses all active downloads.
  Future<void> pauseAll() async {
    await _engine.pauseAll();
    state = List.unmodifiable(_engine.getAllDownloads());
  }

  /// Resumes all paused downloads.
  Future<void> resumeAll() async {
    if (!_settings.downloadOverCellular) {
      final isCellular = await isCellularOnly();
      if (isCellular) {
        throw const CellularDownloadBlockedException();
      }
    }
    _pausedForCellularTaskIds.clear();
    await _engine.resumeAll();
    state = List.unmodifiable(_engine.getAllDownloads());
  }

  /// Clears completed downloads history, optionally deleting local files.
  Future<void> clearCompleted({bool deleteFiles = false}) async {
    await _engine.clearCompleted(deleteFiles: deleteFiles);
    state = state.where((t) => t.status != DownloadStatus.completed).toList();
  }

  /// Removes a task from the list and optionally deletes its physical file.
  Future<void> removeTask(String taskId, {bool deleteFile = false}) async {
    _pausedForCellularTaskIds.remove(taskId);
    await _engine.removeTask(taskId, deleteFile: deleteFile);
    state = state.where((t) => t.id != taskId).toList();
  }

  /// Updates a task in place (useful for unit testing and direct UI updates).
  void updateTask(DownloadTask updated) {
    _engine.updateTaskDirectly(updated);
    state = [
      for (final task in state)
        if (task.id == updated.id) updated else task,
    ];
  }

  /// Sets state directly with a list of tasks.
  void setTasks(List<DownloadTask> tasks) {
    state = List.unmodifiable(tasks);
  }

  @override
  void dispose() {
    _tasksSub?.cancel();
    try {
      _connectivitySub?.cancel();
    } catch (_) {}
    super.dispose();
  }
}

/// Provider managing the list and queue operations of all download tasks.
final downloadManagerProvider =
    StateNotifierProvider<DownloadManagerNotifier, List<DownloadTask>>((ref) {
      final engine = ref.watch(downloadEngineProvider);
      final connectivity = ref.watch(connectivityProvider);
      final initialSettings = ref.read(settingsProvider);

      final notifier = DownloadManagerNotifier(
        engine,
        null,
        initialSettings,
        connectivity,
      );

      ref.listen<SettingsState>(settingsProvider, (previous, next) {
        notifier.updateSettings(next);
      });

      return notifier;
    });

/// Provider for active downloads (all non-completed downloads: downloading, merging, converting, queued, paused, failed, cancelled).
final activeDownloadsProvider = Provider<List<DownloadTask>>((ref) {
  final tasks = ref.watch(downloadManagerProvider);
  return tasks.where((t) => !t.status.isCompleted).toList();
});

/// Controls the currently selected tab in DownloadsScreen:
/// 0 = Active downloads, 1 = Completed downloads.
final downloadsSelectedTabProvider = StateProvider<int>((ref) => 0);

/// Provider for queued downloads waiting to run.
final queuedDownloadsProvider = Provider<List<DownloadTask>>((ref) {
  final tasks = ref.watch(downloadManagerProvider);
  return tasks.where((t) => t.status == DownloadStatus.queued).toList();
});

/// Provider for completed downloads (sorted newest completed first by default).
final completedDownloadsProvider = Provider<List<DownloadTask>>((ref) {
  final tasks = ref.watch(downloadManagerProvider);
  final completed =
      tasks.where((t) => t.status == DownloadStatus.completed).toList();
  completed.sort((a, b) {
    final aTime = a.completedAt ?? a.createdAt;
    final bTime = b.completedAt ?? b.createdAt;
    return bTime.compareTo(aTime);
  });
  return completed;
});

/// Provider for failed downloads.
final failedDownloadsProvider = Provider<List<DownloadTask>>((ref) {
  final tasks = ref.watch(downloadManagerProvider);
  return tasks.where((t) => t.status == DownloadStatus.failed).toList();
});

/// Count of active downloads.
final activeDownloadsCountProvider = Provider<int>((ref) {
  return ref.watch(activeDownloadsProvider).length;
});

/// Count of queued downloads.
final queuedDownloadsCountProvider = Provider<int>((ref) {
  return ref.watch(queuedDownloadsProvider).length;
});

/// Count of completed downloads.
final completedDownloadsCountProvider = Provider<int>((ref) {
  return ref.watch(completedDownloadsProvider).length;
});

/// Provider for the most recent downloads (up to 10 newest downloads first).
final recentDownloadsProvider = Provider<List<DownloadTask>>((ref) {
  final tasks = ref.watch(downloadManagerProvider);
  if (tasks.isEmpty) return const [];
  final sorted = List<DownloadTask>.from(tasks)
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return sorted.take(10).toList();
});
