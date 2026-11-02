import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:background_downloader/background_downloader.dart' as bg;
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_exp;

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/download_notification_service.dart';
import '../../../../core/utils/url_parser.dart';
import '../../../../core/utils/file_utils.dart';
import '../../../../core/utils/permission_utils.dart';
import '../../../extractor/data/extractor_factory.dart';
import '../../../extractor/domain/entities/media_info.dart';
import '../../../extractor/domain/entities/stream_info.dart';
import '../../domain/entities/download_task.dart';
import '../../domain/enums/download_status.dart';
import 'download_registry.dart';
import 'download_session_store.dart';
import 'youtube_transfer.dart';
import 'youtube_diagnostics.dart';
import 'youtube_media_validation.dart';
import 'media_merger.dart';
import '../../../extractor/data/extractors/youtube_stream_selection.dart';
import '../../../extractor/data/extractors/youtube_recovery.dart';

typedef FFmpegMergeFunction =
    Future<bool> Function(
      String videoPath,
      String audioPath,
      String outputPath,
    );

typedef CustomDownloadExecution =
    Future<void> Function({
      required DownloadTask task,
      required StreamInfo stream,
      required String targetPath,
      required void Function(
        double progress,
        int downloadedBytes,
        int totalBytes,
        double speedBytesPerSec,
      )
      onProgress,
      required Future<void> Function() onComplete,
      required void Function(String error) onError,
    });

/// Core download engine orchestrating background downloads, queueing, concurrency limits,
/// and FFmpeg merging for separate video/audio streams.
class DownloadEngine {
  int maxConcurrentDownloads;
  final bg.FileDownloader? _downloader;
  final Dio? _dio;
  final FFmpegMergeFunction? _ffmpegMerger;
  final ExtractorFactory? _extractorFactory;
  final CustomDownloadExecution? _customDownloadExecution;
  final yt_exp.YoutubeExplode? _youtubeExplode;
  final DownloadRegistry? _downloadRegistry;
  final DownloadSessionStore? _sessionStore;
  Future<void>? _restoringSession;
  final Map<String, Future<void>> _youtubeRuns = {};
  final Map<String, Future<void>> _mergeRuns = {};
  final Map<String, CancelToken> _mergeTokens = {};
  final Map<String, YoutubeDiagnostics> _youtubeLogs = {};
  final bool _customMerger;
  Timer? _checkpointTimer;

  /// Reconnect native jobs; interrupted in-process work waits for explicit Resume.
  Future<void> restoreSession() => _restoringSession ??= _restoreSession();

  Future<void> _restoreSession() async {
    if (_sessionStore == null) return;
    try {
      await loadCompletedFromRegistry();
      try {
        await _downloader?.trackTasks(markDownloadedComplete: false);
      } catch (error) {
        debugPrint('Native task tracking unavailable: $error');
      }
      final completedInBackground = <DownloadTask>[];
      final entries = await _sessionStore.load();
      for (final entry in entries) {
        try {
          var task = DownloadSessionStore.readTask(entry);
          if (_tasks.containsKey(task.id)) continue;
          if (entry['audio'] != null) {
            _pendingAudioStreams[task.id] = DownloadSessionStore.readStream(
              entry['audio'] as Map<String, dynamic>,
            );
          }
          if (task.status.isActive ||
              task.status.isQueued ||
              task.status.isPaused) {
            bg.Task? native;
            bg.TaskRecord? record;
            try {
              native = await _downloader?.taskForId(task.id);
              record = await _downloader?.database.recordForId(task.id);
            } catch (error) {
              debugPrint('Native checkpoint lookup unavailable: $error');
            }
            final stored = entry['background'];
            final background =
                native ??
                record?.task ??
                (stored == null
                    ? null
                    : bg.DownloadTask.fromJson(stored as Map<String, dynamic>));
            if (background is bg.DownloadTask) _bgTasks[task.id] = background;
            if (record?.status == bg.TaskStatus.complete) {
              task = task.copyWith(status: DownloadStatus.downloading);
              completedInBackground.add(task);
            } else if (record?.status == bg.TaskStatus.failed ||
                record?.status == bg.TaskStatus.notFound) {
              task = task.copyWith(
                status: DownloadStatus.failed,
                errorMessage:
                    'Background download was interrupted. Please retry.',
              );
            } else if (native is bg.DownloadTask && !task.status.isPaused) {
              task = task.copyWith(status: DownloadStatus.downloading);
              _activeTaskIds.add(task.id);
            } else {
              task = task.copyWith(
                status: DownloadStatus.paused,
                speedBytesPerSecond: 0,
              );
            }
          }
          _tasks[task.id] = task;
        } catch (error) {
          debugPrint('Skipping invalid download checkpoint: $error');
        }
      }
      if (!_tasksListController.isClosed) {
        _tasksListController.add(getAllDownloads());
      }
      for (final task in completedInBackground) {
        await _onDownloadSuccessful(task);
      }
      await _downloader?.resumeFromBackground();
    } catch (error) {
      debugPrint('Download session restore failed: $error');
    }
  }

  Future<void> checkpointSession() async {
    if (_sessionStore == null) return;
    try {
      await _sessionStore.save([
        for (final task in _tasks.values.where(
          (task) => !task.status.isCompleted,
        ))
          {
            ...DownloadSessionStore.taskJson(task),
            if (_bgTasks[task.id] != null)
              'background': _bgTasks[task.id]!.toJson(),
            if (_pendingAudioStreams[task.id] != null)
              'audio': DownloadSessionStore.streamJson(
                _pendingAudioStreams[task.id]!,
              ),
          },
      ]);
    } catch (error) {
      debugPrint('Download checkpoint failed: $error');
    }
  }

  static int _idCounter = 0;

  final Map<String, DownloadTask> _tasks = {};
  final Set<String> _activeTaskIds = {};
  final List<String> _queuedTaskIds = [];
  final Map<String, StreamInfo?> _pendingAudioStreams = {};
  final Map<String, bg.DownloadTask> _bgTasks = {};
  final Map<String, _SpeedTracker> _taskSpeedTrackers = {};
  final Map<String, CancelToken> _dioCancelTokens = {};

  final StreamController<DownloadTask> _taskUpdateController =
      StreamController<DownloadTask>.broadcast();
  final StreamController<List<DownloadTask>> _tasksListController =
      StreamController<List<DownloadTask>>.broadcast();

  void Function(DownloadTask task)? onProgressCallback;

  DownloadEngine({
    this.maxConcurrentDownloads = AppConstants.maxConcurrentDownloads,
    bg.FileDownloader? fileDownloader,
    Dio? dio,
    FFmpegMergeFunction? ffmpegMerger,
    ExtractorFactory? extractorFactory,
    CustomDownloadExecution? customDownloadExecution,
    yt_exp.YoutubeExplode? youtubeExplode,
    DownloadRegistry? downloadRegistry,
    DownloadSessionStore? sessionStore,
  }) : _downloader =
           fileDownloader ??
           (customDownloadExecution != null ? null : bg.FileDownloader()),
       _customMerger = ffmpegMerger != null,
       _dio = dio,
       _ffmpegMerger = ffmpegMerger,
       _extractorFactory = extractorFactory,
       _customDownloadExecution = customDownloadExecution,
       _youtubeExplode = youtubeExplode,
       _downloadRegistry = downloadRegistry,
       _sessionStore = sessionStore {
    if (_downloader != null && _customDownloadExecution == null) {
      _initDownloader();
    }
  }

  /// Stream of individual task updates.
  Stream<DownloadTask> get onTaskUpdated => _taskUpdateController.stream;

  /// Stream of the full list of download tasks.
  Stream<List<DownloadTask>> get onTasksChanged => _tasksListController.stream;

  void _initDownloader() {
    _downloader?.registerCallbacks(
      taskStatusCallback: _handleBgStatusUpdate,
      taskProgressCallback: _handleBgProgressUpdate,
    );
    try {
      _downloader?.configureNotification(
        running: const bg.TaskNotification(
          'Downloading',
          '{filename} - {progress}',
        ),
        complete: const bg.TaskNotification('Download complete', '{filename}'),
        error: const bg.TaskNotification('Download failed', '{filename}'),
        progressBar: true,
      );
    } catch (_) {}
  }

  @visibleForTesting
  static List<String> audioExtractionArguments(
    String inputPath,
    String outputPath, {
    bool transcode = false,
  }) {
    final lower = outputPath.toLowerCase();
    final isMp3 = lower.endsWith('.mp3');
    final isWebm =
        lower.endsWith('.webm') ||
        lower.endsWith('.opus') ||
        lower.endsWith('.ogg');
    // Audio-only YouTube WebM already contains Opus/Vorbis. Copying it avoids
    // quality loss and does not require optional encoders in FFmpeg min.
    return [
      '-y',
      '-i',
      inputPath,
      '-vn',
      '-c:a',
      if (isMp3)
        'libmp3lame'
      else if (!transcode)
        'copy'
      else if (isWebm)
        'libopus'
      else
        'aac',
      if (isMp3) ...[
        '-q:a',
        '2',
      ] else if (transcode) ...[
        '-b:a',
        isWebm ? '160k' : '192k',
      ],
      outputPath,
    ];
  }

  /// Extracts audio from a muxed progressive MP4/WebM video file into an audio format.
  static Future<bool> extractAudioFromMuxed(
    String muxedPath,
    String outputPath, {
    CancelToken? youtubeToken,
  }) async {
    final args = audioExtractionArguments(muxedPath, outputPath);

    try {
      if (youtubeToken != null) {
        if (await _youtubeProcess(args, youtubeToken)) return true;
        return await _youtubeProcess(
          audioExtractionArguments(muxedPath, outputPath, transcode: true),
          youtubeToken,
        );
      }
      var session = await FFmpegKit.executeWithArguments(args);
      var returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        return true;
      }
      // Re-encode only when the source codec cannot be copied to the target.
      final fallbackArgs = audioExtractionArguments(
        muxedPath,
        outputPath,
        transcode: true,
      );
      session = await FFmpegKit.executeWithArguments(fallbackArgs);
      returnCode = await session.getReturnCode();
      return ReturnCode.isSuccess(returnCode);
    } catch (_) {
      return false;
    }
  }

  String _reserveOutputPath(String requestedPath) {
    final reserved = _tasks.values.map((task) => task.filePath).toSet();
    final extension = p.extension(requestedPath);
    final stem = p.withoutExtension(requestedPath);
    var candidate = requestedPath;
    var suffix = 1;
    while (reserved.contains(candidate) || File(candidate).existsSync()) {
      candidate = '$stem (${suffix++})$extension';
    }
    return candidate;
  }

  /// Initiates or queues a download for [mediaInfo] with [selectedStream].
  Future<DownloadTask> startDownload(
    MediaInfo mediaInfo,
    StreamInfo selectedStream,
    String outputPath, {
    StreamInfo? audioStream,
  }) async {
    await restoreSession();
    final taskId =
        'task_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';
    final task = DownloadTask(
      id: taskId,
      mediaInfo: mediaInfo,
      selectedStream: selectedStream,
      status: DownloadStatus.queued,
      progress: 0.0,
      filePath: _reserveOutputPath(outputPath),
      downloadedBytes: 0,
      totalBytes: selectedStream.sizeInBytes,
      speedBytesPerSecond: 0.0,
      createdAt: DateTime.now(),
    );

    _tasks[taskId] = task;
    _pendingAudioStreams[taskId] = audioStream;
    await checkpointSession();

    if (_activeTaskIds.length < maxConcurrentDownloads) {
      _activeTaskIds.add(taskId);
      final activeTask = task.copyWith(status: DownloadStatus.downloading);
      _tasks[taskId] = activeTask;
      _notifyTaskChanged(activeTask);
      _executeTask(activeTask);
      return activeTask;
    } else {
      _queuedTaskIds.add(taskId);
      _notifyTaskChanged(task);
      return task;
    }
  }

  /// Pauses an active or queued download.
  Future<bool> pauseDownload(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return false;

    if (_activeTaskIds.contains(taskId)) {
      _activeTaskIds.remove(taskId);
      _taskSpeedTrackers.remove(taskId);
      _dioCancelTokens[taskId]?.cancel('Paused by user');
      _mergeTokens[taskId]?.cancel('Paused by user');
      _dioCancelTokens.remove(taskId);
      final bgTask = _bgTasks[taskId];
      if (bgTask != null) {
        try {
          await _downloader?.pause(bgTask);
        } catch (_) {}
      }
      final pausedTask = task.copyWith(
        status: DownloadStatus.paused,
        speedBytesPerSecond: 0.0,
      );
      _tasks[taskId] = pausedTask;
      DownloadNotificationService.instance.cancel(taskId);
      _notifyTaskChanged(pausedTask);
      await _youtubeRuns[taskId];
      await _mergeRuns[taskId];
      _processQueue();
      return true;
    } else if (_queuedTaskIds.contains(taskId)) {
      _queuedTaskIds.remove(taskId);
      _taskSpeedTrackers.remove(taskId);
      final pausedTask = task.copyWith(
        status: DownloadStatus.paused,
        speedBytesPerSecond: 0.0,
      );
      _tasks[taskId] = pausedTask;
      DownloadNotificationService.instance.cancel(taskId);
      _notifyTaskChanged(pausedTask);
      return true;
    } else if (task.status.isActive || task.status == DownloadStatus.queued) {
      _taskSpeedTrackers.remove(taskId);
      final pausedTask = task.copyWith(
        status: DownloadStatus.paused,
        speedBytesPerSecond: 0.0,
      );
      _tasks[taskId] = pausedTask;
      DownloadNotificationService.instance.cancel(taskId);
      _notifyTaskChanged(pausedTask);
      return true;
    }
    return false;
  }

  /// Resumes a paused download.
  Future<bool> resumeDownload(String taskId) async {
    await _mergeRuns[taskId];
    if (_youtubeRuns.containsKey(taskId) &&
        (_tasks[taskId]?.status == DownloadStatus.paused ||
            _tasks[taskId]?.status == DownloadStatus.cancelled ||
            _tasks[taskId]?.status == DownloadStatus.failed)) {
      await _youtubeRuns[taskId];
    }
    final task = _tasks[taskId];
    if (task == null || task.status != DownloadStatus.paused) return false;

    if (_activeTaskIds.length < maxConcurrentDownloads) {
      _activeTaskIds.add(taskId);
      final resumingTask = task.copyWith(status: DownloadStatus.downloading);
      _tasks[taskId] = resumingTask;
      _notifyTaskChanged(resumingTask);

      final bgTask = _bgTasks[taskId];
      if (bgTask != null) {
        try {
          final resumed = await _downloader?.resume(bgTask) ?? false;
          if (!resumed) {
            _executeTask(resumingTask);
          }
        } catch (_) {
          _executeTask(resumingTask);
        }
      } else {
        _executeTask(resumingTask);
      }
      return true;
    } else {
      _queuedTaskIds.add(taskId);
      final queuedTask = task.copyWith(status: DownloadStatus.queued);
      _tasks[taskId] = queuedTask;
      _notifyTaskChanged(queuedTask);
      return true;
    }
  }

  /// Cancels an active, queued, or paused download.
  Future<bool> cancelDownload(String taskId) async {
    final task = _tasks[taskId];
    if (task == null || task.status == DownloadStatus.completed) return false;

    _activeTaskIds.remove(taskId);
    _queuedTaskIds.remove(taskId);
    _taskSpeedTrackers.remove(taskId);
    _dioCancelTokens[taskId]?.cancel('Cancelled by user');
    _mergeTokens[taskId]?.cancel('Cancelled by user');
    _dioCancelTokens.remove(taskId);

    final bgTask = _bgTasks[taskId];
    if (bgTask != null) {
      try {
        await _downloader?.cancelTasksWithIds([bgTask.taskId]);
      } catch (_) {}
    }

    final cancelledTask = task.copyWith(
      status: DownloadStatus.cancelled,
      speedBytesPerSecond: 0.0,
    );
    _tasks[taskId] = cancelledTask;
    if (_isYoutube(task) && _customDownloadExecution == null) {
      final running = _youtubeRuns[taskId];
      late Future<void> cleanup;
      cleanup = (() async {
        await running;
        for (final suffix in [
          '_video.tmp',
          '_audio.tmp',
          '_muxed.tmp',
          '.youtube.part',
          '.youtube.work${p.extension(task.filePath ?? '')}',
        ]) {
          for (final ending in ['', '.native']) {
            final file = File('${task.filePath}$suffix$ending');
            if (await file.exists()) await file.delete();
          }
        }
      })().whenComplete(() {
        if (identical(_youtubeRuns[taskId], cleanup)) {
          _youtubeRuns.remove(taskId);
        }
      });
      _youtubeRuns[taskId] = cleanup;
    }
    DownloadNotificationService.instance.cancel(taskId);
    _notifyTaskChanged(cancelledTask);
    await _youtubeRuns[taskId];
    await _mergeRuns[taskId];
    _processQueue();
    return true;
  }

  /// Retries a failed or cancelled download.
  Future<bool> retryDownload(String taskId) async {
    await _mergeRuns[taskId];
    if (_youtubeRuns.containsKey(taskId) &&
        (_tasks[taskId]?.status == DownloadStatus.paused ||
            _tasks[taskId]?.status == DownloadStatus.cancelled ||
            _tasks[taskId]?.status == DownloadStatus.failed)) {
      await _youtubeRuns[taskId];
    }
    final task = _tasks[taskId];
    if (task == null || !(task.status.isFailed || task.status.isCancelled)) {
      return false;
    }

    final resetTask = task.copyWith(
      status: DownloadStatus.queued,
      progress: 0.0,
      downloadedBytes: 0,
      speedBytesPerSecond: 0.0,
      clearErrorMessage: true,
      clearCompletedAt: true,
    );
    _tasks[taskId] = resetTask;

    if (_activeTaskIds.length < maxConcurrentDownloads) {
      _activeTaskIds.add(taskId);
      final activeTask = resetTask.copyWith(status: DownloadStatus.downloading);
      _tasks[taskId] = activeTask;
      _notifyTaskChanged(activeTask);
      _executeTask(activeTask);
      return true;
    } else {
      _queuedTaskIds.add(taskId);
      _notifyTaskChanged(resetTask);
      return true;
    }
  }

  /// Removes a task from the engine record and optionally deletes the output file.
  Future<void> removeTask(String taskId, {bool deleteFile = false}) async {
    var task = _tasks[taskId];
    if (task == null && _downloadRegistry != null) {
      final records = await _downloadRegistry.getCompletedRecords(
        verifyFileExists: false,
      );
      task =
          records.firstWhereOrNull((record) => record.id == taskId)?.toTask();
    }
    if (task != null && task.status != DownloadStatus.completed) {
      await cancelDownload(taskId);
    }
    if (deleteFile) {
      final filePath = task?.filePath;
      if (filePath == null || filePath.isEmpty) {
        if (task == null || task.status == DownloadStatus.completed) {
          throw FileSystemException('No saved file path available');
        }
      } else {
        await deleteMediaFile(filePath);
      }
    }
    _tasks.remove(taskId);
    _activeTaskIds.remove(taskId);
    _queuedTaskIds.remove(taskId);
    _pendingAudioStreams.remove(taskId);
    _bgTasks.remove(taskId);
    _taskSpeedTrackers.remove(taskId);
    await _downloadRegistry?.remove(taskId);

    _tasksListController.add(getAllDownloads());
    await checkpointSession();
  }

  /// Hydrates completed tasks into the in-memory engine from the persistent download registry.
  Future<void> loadCompletedFromRegistry() async {
    if (_downloadRegistry == null) return;
    try {
      final records = await _downloadRegistry.getCompletedRecords(
        verifyFileExists: true,
      );
      bool changed = false;
      for (final record in records) {
        if (!_tasks.containsKey(record.id)) {
          _tasks[record.id] = record.toTask();
          changed = true;
        }
      }
      if (changed) {
        _tasksListController.add(getAllDownloads());
      }
    } catch (_) {}
  }

  /// Pauses all active downloads.
  Future<void> pauseAll() async {
    final targets =
        _tasks.values
            .where(
              (t) => t.status.isActive || t.status == DownloadStatus.queued,
            )
            .map((t) => t.id)
            .toList();
    for (final id in targets) {
      await pauseDownload(id);
    }
  }

  /// Resumes all paused downloads.
  Future<void> resumeAll() async {
    final pausedIds =
        _tasks.values
            .where((t) => t.status == DownloadStatus.paused)
            .map((t) => t.id)
            .toList();
    for (final id in pausedIds) {
      await resumeDownload(id);
    }
  }

  /// Clears completed downloads history, optionally deleting local files.
  Future<void> clearCompleted({bool deleteFiles = false}) async {
    final completedIds =
        _tasks.values
            .where((t) => t.status == DownloadStatus.completed)
            .map((t) => t.id)
            .toList();
    for (final id in completedIds) {
      await removeTask(id, deleteFile: deleteFiles);
    }
  }

  /// Returns all currently active downloads (downloading, merging, converting).
  List<DownloadTask> getActiveDownloads() {
    return _tasks.values.where((t) => t.status.isActive).toList();
  }

  /// Returns all queued downloads.
  List<DownloadTask> getQueuedDownloads() {
    return _tasks.values
        .where((t) => t.status == DownloadStatus.queued)
        .toList();
  }

  /// Returns all completed downloads.
  List<DownloadTask> getCompletedDownloads() {
    return _tasks.values
        .where((t) => t.status == DownloadStatus.completed)
        .toList();
  }

  /// Returns all downloads recorded by the engine.
  List<DownloadTask> getAllDownloads() {
    return _tasks.values.toList();
  }

  /// Retrieves a task by its ID.
  DownloadTask? getTask(String taskId) => _tasks[taskId];

  /// Dynamically updates the concurrency limit and initiates queued tasks if slots opened.
  void updateMaxConcurrentDownloads(int count) {
    if (count > 0 && maxConcurrentDownloads != count) {
      maxConcurrentDownloads = count;
      _processQueue();
    }
  }

  void _processQueue() {
    while (_activeTaskIds.length < maxConcurrentDownloads &&
        _queuedTaskIds.isNotEmpty) {
      final nextTaskId = _queuedTaskIds.removeAt(0);
      final nextTask = _tasks[nextTaskId];
      if (nextTask != null && nextTask.status == DownloadStatus.queued) {
        _activeTaskIds.add(nextTaskId);
        final activeTask = nextTask.copyWith(
          status: DownloadStatus.downloading,
        );
        _tasks[nextTaskId] = activeTask;
        _notifyTaskChanged(activeTask);
        _executeTask(activeTask);
      }
    }
  }

  final Map<String, DateTime> _lastProgressEmission = {};

  void _notifyTaskChanged(DownloadTask task) {
    if (_taskUpdateController.isClosed) return;
    final now = DateTime.now();
    final last = _lastProgressEmission[task.id];
    // Network chunks can arrive hundreds of times per second. Bound UI rebuilds
    // and platform notification calls while retaining every byte in _tasks.
    if (task.status == DownloadStatus.downloading &&
        last != null &&
        now.difference(last).inMilliseconds < 200 &&
        task.progress < 1) {
      return;
    }
    if (task.status == DownloadStatus.downloading) {
      _lastProgressEmission[task.id] = now;
    } else {
      _lastProgressEmission.remove(task.id);
    }
    if (_sessionStore != null) {
      if (task.status != DownloadStatus.downloading) {
        unawaited(checkpointSession());
      } else {
        _checkpointTimer ??= Timer(const Duration(seconds: 1), () {
          _checkpointTimer = null;
          unawaited(checkpointSession());
        });
      }
    }
    _taskUpdateController.add(task);
    _tasksListController.add(getAllDownloads());
    onProgressCallback?.call(task);
    if (task.status.isActive &&
        (task.status == DownloadStatus.downloading ||
            task.status == DownloadStatus.merging ||
            task.status == DownloadStatus.converting)) {
      DownloadNotificationService.instance.showProgress(
        taskId: task.id,
        title: task.mediaInfo.title,
        progress: task.progress,
        speedBytesPerSecond: task.speedBytesPerSecond ?? 0.0,
      );
    }
  }

  void updateTaskDirectly(DownloadTask task) {
    _tasks[task.id] = task;
    _notifyTaskChanged(task);
  }

  Future<String> _ensureWritableTargetPath(String targetPath) async {
    if (await PermissionUtils.isFolderWritable(File(targetPath).parent.path)) {
      return targetPath;
    }

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final mediaGrabDir = Directory('${docDir.path}/MediaGrab');
      if (!await mediaGrabDir.exists()) {
        await mediaGrabDir.create(recursive: true);
      }
      final filename = targetPath.split(Platform.pathSeparator).last;
      return '${mediaGrabDir.path}/$filename';
    } catch (_) {
      return targetPath;
    }
  }

  static bool _isYoutube(DownloadTask task) =>
      task.mediaInfo.platform == PlatformType.youtube;

  Future<void> _executeTask(DownloadTask task) {
    if (!_isYoutube(task) || _customDownloadExecution != null) {
      return _runTask(task);
    }
    final token = CancelToken();
    _dioCancelTokens[task.id] = token;
    late Future<void> run;
    run = _runTask(task).whenComplete(() {
      if (identical(_youtubeRuns[task.id], run)) _youtubeRuns.remove(task.id);
      if (identical(_dioCancelTokens[task.id], token)) {
        _dioCancelTokens.remove(task.id);
      }
    });
    _youtubeRuns[task.id] = run;
    return run;
  }

  Future<void> _runTask(DownloadTask task) async {
    final rawTargetPath = task.filePath ?? 'download_${task.id}';

    if (_customDownloadExecution != null) {
      final isVideoOnly = task.selectedStream.isVideoOnly;
      final downloadPath =
          isVideoOnly ? '${rawTargetPath}_video.tmp' : rawTargetPath;
      await _customDownloadExecution(
        task: task,
        stream: task.selectedStream,
        targetPath: downloadPath,
        onProgress: (progress, downloadedBytes, totalBytes, speed) {
          final current = _tasks[task.id];
          if (current != null && current.status.isActive) {
            final effectiveSpeed = _calculateSpeed(
              task.id,
              downloadedBytes,
              speed,
            );
            final updated = current.copyWith(
              progress: progress,
              downloadedBytes: downloadedBytes,
              totalBytes: totalBytes > 0 ? totalBytes : current.totalBytes,
              speedBytesPerSecond: effectiveSpeed,
            );
            _tasks[task.id] = updated;
            _notifyTaskChanged(updated);
          }
        },
        onComplete: () async {
          await _onDownloadSuccessful(task);
        },
        onError: (error) {
          _failTask(task, error);
        },
      );
      return;
    }

    var targetPath = await _ensureWritableTargetPath(rawTargetPath);
    if (_isYoutube(task) && (_dioCancelTokens[task.id]?.isCancelled ?? true)) {
      return;
    }
    if (task.filePath != targetPath) {
      // Storage fallback changes the directory after the original reservation.
      // Reserve again there before deriving any final or temporary file paths.
      targetPath = _reserveOutputPath(targetPath);
      task = task.copyWith(filePath: targetPath);
      _tasks[task.id] = task;
      _notifyTaskChanged(task);
    }

    final isVideoOnly = task.selectedStream.isVideoOnly;
    final downloadPath = isVideoOnly ? '${targetPath}_video.tmp' : targetPath;

    final isYouTube =
        task.mediaInfo.platform == PlatformType.youtube ||
        task.selectedStream.url.contains('googlevideo.com');

    if (isYouTube) {
      await _executeYouTubeTask(task, downloadPath, targetPath);
      return;
    }

    try {
      final downloadFile = File(downloadPath);
      if (!await downloadFile.parent.exists()) {
        await downloadFile.parent.create(recursive: true);
      }

      final bgTask = await _createBgTask(
        task.id,
        task.selectedStream.url,
        downloadPath,
      );
      _bgTasks[task.id] = bgTask;
      await checkpointSession();

      final accepted = await _downloader?.enqueue(bgTask) ?? false;
      if (!accepted) {
        throw StateError('Native download enqueue was rejected');
      }
    } catch (e) {
      debugPrint(
        'Background download enqueue failed: $e, falling back to direct stream',
      );
      _bgTasks.remove(task.id);
      try {
        final cancelToken = CancelToken();
        _dioCancelTokens[task.id] = cancelToken;
        await _streamToFile(
          dio: _dio ?? Dio(),
          url: task.selectedStream.url,
          destPath: downloadPath,
          totalBytes: task.selectedStream.sizeInBytes ?? 0,
          cancelToken: cancelToken,
          onProgress: (downloaded, total) {
            final current = _tasks[task.id];
            if (current != null && current.status.isActive) {
              final effectiveSpeed = _calculateSpeed(task.id, downloaded);
              final progress =
                  total > 0 ? (downloaded / total) : current.progress;
              final updated = current.copyWith(
                progress: progress.clamp(0.0, 1.0),
                downloadedBytes: downloaded,
                totalBytes: total > 0 ? total : current.totalBytes,
                speedBytesPerSecond: effectiveSpeed,
              );
              _tasks[task.id] = updated;
              _notifyTaskChanged(updated);
            }
          },
        );
        await _onDownloadSuccessful(task);
        return;
      } catch (streamError) {
        _failTask(task, streamError.toString());
      } finally {
        _dioCancelTokens.remove(task.id);
      }
    }
  }

  Future<StreamInfo?> _findMuxedStream(String videoId) async {
    if (_extractorFactory != null) {
      try {
        final mediaUrl =
            videoId.length == 11
                ? 'https://www.youtube.com/watch?v=$videoId'
                : videoId;
        final extractor = _extractorFactory.getExtractor(mediaUrl);
        if (extractor != null) {
          final streams = await extractor.getStreams(mediaUrl);
          final muxed = streams.firstWhereOrNull(
            (s) => !s.isAudioOnly && !s.isVideoOnly,
          );
          if (muxed != null) return muxed;
        }
      } catch (_) {}
    }

    final yt = _youtubeExplode ?? yt_exp.YoutubeExplode();
    try {
      String cleanId = videoId.trim();
      try {
        cleanId = yt_exp.VideoId.fromString(cleanId).value;
      } catch (_) {}
      final manifest = await yt.videos.streamsClient.getManifest(
        cleanId,
        ytClients: [
          yt_exp.YoutubeApiClient.androidSdkless,
          yt_exp.YoutubeApiClient.android,
          yt_exp.YoutubeApiClient.ios,
        ],
        requireWatchPage: false,
      );
      final m = manifest.muxed.firstOrNull;
      if (m != null) {
        return StreamInfo(
          url: m.url.toString(),
          qualityLabel: m.qualityLabel,
          codec: m.videoCodec,
          container: m.container.name,
          sizeInBytes: m.size.totalBytes,
          isAudioOnly: false,
          bitrate: m.bitrate.bitsPerSecond,
          videoWidth: m.videoResolution.width,
          videoHeight: m.videoResolution.height,
          isVideoOnly: false,
        );
      }
    } catch (_) {
    } finally {
      if (_youtubeExplode == null) {
        yt.close();
      }
    }
    return null;
  }

  Future<void> _executeYouTubeTask(
    DownloadTask task,
    String downloadPath,
    String targetPath,
  ) async {
    final cancelToken = _dioCancelTokens[task.id] ?? CancelToken();
    final log = _youtubeLogs.putIfAbsent(
      task.id,
      () => YoutubeDiagnostics(task.id),
    );
    log.record('start', {
      'videoId': task.mediaInfo.id,
      'extractor': 'youtube_explode_dart 3.1.0',
      'ytDlp': 'not installed',
      'quality': task.selectedStream.qualityLabel,
      'itag': Uri.tryParse(task.selectedStream.url)?.queryParameters['itag'],
    });
    final workPath = '$targetPath.youtube.work${p.extension(targetPath)}';

    final isAudioOnly = task.selectedStream.isAudioOnly;
    final isVideoOnly = task.selectedStream.isVideoOnly;
    final tempVideoPath = '${targetPath}_video.tmp';
    final tempAudioPath = '${targetPath}_audio.tmp';
    final tempMuxedPath = '${targetPath}_muxed.tmp';

    try {
      if (isAudioOnly) {
        void reportAudioProgress(int downloaded, int total) {
          if (cancelToken.isCancelled) return;
          final current = _tasks[task.id];
          if (current == null || !current.status.isActive) return;
          final updated = current.copyWith(
            progress:
                total > 0 ? (downloaded / total * 0.90).clamp(0.0, 0.90) : 0,
            downloadedBytes: downloaded,
            totalBytes: total > 0 ? total : current.totalBytes,
            speedBytesPerSecond: _calculateSpeed(task.id, downloaded),
          );
          _tasks[task.id] = updated;
          _notifyTaskChanged(updated);
        }

        String audioInputPath = tempAudioPath;
        try {
          // Fetch only the selected audio track. Downloading a progressive video
          // first wastes bandwidth and time for every successful audio request.
          await _downloadYouTubeStreamToFile(
            diagnostic: log.record,
            videoId: task.mediaInfo.id,
            streamInfo: task.selectedStream,
            destPath: tempAudioPath,
            cancelToken: cancelToken,
            onProgress: reportAudioProgress,
          );
        } catch (error) {
          if (cancelToken.isCancelled) rethrow;
          // Storage failures cannot be repaired by downloading another format.
          if (error is! DioException &&
              error is! HttpException &&
              error is! SocketException) {
            rethrow;
          }
          final muxedStream = await _findMuxedStream(task.mediaInfo.id);
          if (cancelToken.isCancelled) return;
          if (muxedStream == null) rethrow;
          audioInputPath = tempMuxedPath;
          await _downloadYouTubeStreamToFile(
            diagnostic: log.record,
            videoId: task.mediaInfo.id,
            streamInfo: muxedStream,
            destPath: tempMuxedPath,
            cancelToken: cancelToken,
            onProgress: reportAudioProgress,
          );
        }
        if (cancelToken.isCancelled) return;
        final convertingTask = (_tasks[task.id] ?? task).copyWith(
          status: DownloadStatus.converting,
          progress: 0.92,
          speedBytesPerSecond: 0,
        );
        _tasks[task.id] = convertingTask;
        _notifyTaskChanged(convertingTask);
        try {
          // Remux/transcode into the requested output container, also removing
          // the video track if the recovery source was a progressive video.
          final extracted = await extractAudioFromMuxed(
            audioInputPath,
            workPath,
            youtubeToken: cancelToken,
          );
          if (cancelToken.isCancelled) return;
          if (!extracted) throw StateError('Audio extraction failed');
          await _completeYoutube(convertingTask, workPath, cancelToken, log);
        } finally {
          for (final path
              in _tasks[task.id]?.status == DownloadStatus.completed
                  ? [tempAudioPath, tempMuxedPath]
                  : <String>[]) {
            try {
              final file = File(path);
              if (await file.exists()) await file.delete();
            } catch (_) {}
          }
        }
        return;
      }

      if (isVideoOnly) {
        // Step 1: Download video stream (0% -> 75% progress)
        try {
          await _downloadYouTubeStreamToFile(
            diagnostic: log.record,
            videoId: task.mediaInfo.id,
            streamInfo: task.selectedStream,
            destPath: tempVideoPath,
            cancelToken: cancelToken,
            onProgress: (downloaded, total) {
              if (cancelToken.isCancelled) return;
              final current = _tasks[task.id];
              if (current != null && current.status.isActive) {
                final effectiveSpeed = _calculateSpeed(task.id, downloaded);
                final normProgress =
                    total > 0 ? (downloaded / total) * 0.75 : 0.0;
                final updated = current.copyWith(
                  progress: normProgress.clamp(0.0, 0.75),
                  downloadedBytes: downloaded,
                  totalBytes: total > 0 ? total : current.totalBytes,
                  speedBytesPerSecond: effectiveSpeed,
                );
                _tasks[task.id] = updated;
                _notifyTaskChanged(updated);
              }
            },
          );
        } catch (videoError) {
          log.record('video_failed', {
            'type': videoError.runtimeType.toString(),
          });
          rethrow;
        }

        if (cancelToken.isCancelled ||
            _tasks[task.id]?.status == DownloadStatus.cancelled ||
            _tasks[task.id]?.status == DownloadStatus.paused) {
          return;
        }

        // Step 2: Download companion audio stream (75% -> 90% progress)
        // Prefer the selected audio track; use progressive audio only if absent.
        StreamInfo? audioStream = _pendingAudioStreams[task.id];
        audioStream ??= await _findMuxedStream(task.mediaInfo.id);
        if (audioStream != null && audioStream.isAudioOnly) {
          final audioClient = yt_exp.YoutubeExplode();
          unawaited(cancelToken.whenCancel.then((_) => audioClient.close()));
          try {
            audioStream = await Future.any([
              YoutubeRecovery.companion(
                audioClient,
                task.mediaInfo.id,
                audioStream,
                task.selectedStream.container,
                diagnostic: log.record,
              ).timeout(const Duration(seconds: 45)),
              cancelToken.whenCancel.then<StreamInfo>((e) => throw e),
            ]);
            _pendingAudioStreams[task.id] = audioStream;
          } catch (error) {
            cancelToken.throwIfCancellationRequested();
            log.record('companion_fallback', {
              'type': error.runtimeType.toString(),
            });
          } finally {
            audioClient.close();
          }
        }

        if (audioStream != null) {
          final videoDownloaded =
              (await File(tempVideoPath).exists())
                  ? await File(tempVideoPath).length()
                  : 0;

          await _downloadYouTubeStreamToFile(
            diagnostic: log.record,
            videoId: task.mediaInfo.id,
            streamInfo: audioStream,
            destPath: tempAudioPath,
            cancelToken: cancelToken,
            onProgress: (audioDownloaded, audioTot) {
              if (cancelToken.isCancelled) return;
              final current = _tasks[task.id];
              if (current != null && current.status.isActive) {
                final effectiveSpeed = _calculateSpeed(
                  task.id,
                  videoDownloaded + audioDownloaded,
                );
                final audioNorm =
                    audioTot > 0 ? (audioDownloaded / audioTot) * 0.15 : 0.0;
                final updated = current.copyWith(
                  progress: (0.75 + audioNorm).clamp(0.75, 0.90),
                  downloadedBytes: videoDownloaded + audioDownloaded,
                  totalBytes: videoDownloaded + audioTot,
                  speedBytesPerSecond: effectiveSpeed,
                );
                _tasks[task.id] = updated;
                _notifyTaskChanged(updated);
              }
            },
          );

          if (cancelToken.isCancelled ||
              _tasks[task.id]?.status == DownloadStatus.cancelled ||
              _tasks[task.id]?.status == DownloadStatus.paused) {
            return;
          }

          // Step 3: FFmpeg Merge
          final mergingTask = (_tasks[task.id] ?? task).copyWith(
            status: DownloadStatus.merging,
            progress: 0.92,
            speedBytesPerSecond: 0.0,
          );
          _tasks[task.id] = mergingTask;
          _notifyTaskChanged(mergingTask);

          final mergeSuccess =
              _customMerger
                  ? await _ffmpegMerger!(tempVideoPath, tempAudioPath, workPath)
                  : await _mergeYoutube(
                    tempVideoPath,
                    tempAudioPath,
                    workPath,
                    cancelToken,
                    log,
                  );

          if (cancelToken.isCancelled ||
              _tasks[task.id]?.status == DownloadStatus.cancelled ||
              _tasks[task.id]?.status == DownloadStatus.paused) {
            return;
          }

          if (mergeSuccess) {
            await _completeYoutube(mergingTask, workPath, cancelToken, log);
            if (_tasks[task.id]?.status == DownloadStatus.completed) {
              for (final path in [tempVideoPath, tempAudioPath]) {
                final file = File(path);
                if (await file.exists()) await file.delete();
              }
            }
          } else {
            _failTask(_tasks[task.id] ?? mergingTask, 'FFmpeg merge failed');
          }
        } else {
          throw StateError(
            'No companion audio is available for the selected YouTube video',
          );
        }
      } else {
        // Direct download (Muxed progressive video e.g. 360p)
        await _downloadYouTubeStreamToFile(
          diagnostic: log.record,
          videoId: task.mediaInfo.id,
          streamInfo: task.selectedStream,
          destPath: '$targetPath.youtube.part',
          cancelToken: cancelToken,
          onProgress: (downloaded, tot) {
            if (cancelToken.isCancelled) return;
            final current = _tasks[task.id];
            if (current != null && current.status.isActive) {
              final effectiveSpeed = _calculateSpeed(task.id, downloaded);
              final progress = tot > 0 ? (downloaded / tot) : current.progress;
              final updated = current.copyWith(
                progress: progress.clamp(0.0, 1.0),
                downloadedBytes: downloaded,
                totalBytes: tot > 0 ? tot : current.totalBytes,
                speedBytesPerSecond: effectiveSpeed,
              );
              _tasks[task.id] = updated;
              _notifyTaskChanged(updated);
            }
          },
        );

        if (cancelToken.isCancelled ||
            _tasks[task.id]?.status == DownloadStatus.cancelled ||
            _tasks[task.id]?.status == DownloadStatus.paused) {
          return;
        }

        await _completeYoutube(
          task,
          '$targetPath.youtube.part',
          cancelToken,
          log,
        );
      }
    } catch (e) {
      if (cancelToken.isCancelled) return;
      if (cancelToken.isCancelled ||
          _tasks[task.id]?.status == DownloadStatus.cancelled ||
          _tasks[task.id]?.status == DownloadStatus.paused) {
        return;
      }
      log.record('failed', {'type': e.runtimeType.toString()});
      _failTask(
        _tasks[task.id] ?? task,
        e
            .toString()
            .replaceAll(RegExp(r'https?://[^\s]+'), '[media URL]')
            .replaceFirst('Exception: ', ''),
      );
    } finally {
      if (_tasks[task.id]?.status == DownloadStatus.cancelled) {
        for (final path in [
          tempVideoPath,
          tempAudioPath,
          tempMuxedPath,
          '$targetPath.youtube.part',
          workPath,
        ]) {
          final file = File(path);
          if (await file.exists()) await file.delete();
          final native = File('$path.native');
          if (await native.exists()) await native.delete();
        }
      }
      log.record('stopped', {'status': _tasks[task.id]?.status.name});
      await log.flush();
      if (identical(_dioCancelTokens[task.id], cancelToken)) {
        _dioCancelTokens.remove(task.id);
      }
    }
  }

  static Future<bool> _youtubeProcess(
    List<String> args,
    CancelToken token, [
    YoutubeDiagnostics? log,
  ]) => MediaMerger.execute(args, token, log?.record);

  Future<bool> _mergeYoutube(
    String video,
    String audio,
    String output,
    CancelToken token,
    YoutubeDiagnostics log,
  ) => const MediaMerger().merge(
    video,
    audio,
    output,
    cancelToken: token,
    diagnostic: log.record,
  );

  Future<void> _completeYoutube(
    DownloadTask task,
    String workPath,
    CancelToken token,
    YoutubeDiagnostics log,
  ) async {
    token.throwIfCancellationRequested();
    log.record('validating', {});
    final session = await FFprobeKit.getMediaInformation(workPath);
    token.throwIfCancellationRequested();
    final properties = session.getMediaInformation()?.getAllProperties();
    if (properties == null) {
      throw StateError('YouTube output could not be probed');
    }
    YoutubeMediaValidation.validate(
      probe: properties,
      audioOnly: task.selectedStream.isAudioOnly,
      width: task.selectedStream.videoWidth,
      height: task.selectedStream.videoHeight,
      quality: task.selectedStream.qualityLabel,
      expectedDuration: task.mediaInfo.duration,
    );
    final readable = await _youtubeProcess(
      [
        '-v',
        'error',
        '-xerror',
        '-i',
        workPath,
        '-map',
        '0:a:0',
        if (!task.selectedStream.isAudioOnly) ...['-map', '0:v:0'],
        '-c',
        'copy',
        '-f',
        'null',
        '-',
      ],
      token,
      log,
    );
    if (!readable) {
      throw StateError('YouTube output failed its media integrity scan');
    }
    token.throwIfCancellationRequested();
    log.record('validated', {
      'streams':
          (properties['streams'] as List)
              .map(
                (s) => {
                  'type': s['codec_type'],
                  'codec': s['codec_name'],
                  'width': s['width'],
                  'height': s['height'],
                  'fps': s['avg_frame_rate'],
                  'duration': s['duration'],
                },
              )
              .toList(),
      'format':
          properties['format'] is Map
              ? {
                'duration': properties['format']['duration'],
                'size': properties['format']['size'],
              }
              : null,
    });
    // Avoid filename/tags in diagnostic output. Only validation fields are logged.
    await File(workPath).rename(task.filePath!);
    token.throwIfCancellationRequested();
    await _finishTaskSuccess(task, validatedProbe: properties);
    log.record('final', {'status': _tasks[task.id]?.status.name});
    await log.flush();
  }

  Future<void> _downloadYouTubeStreamToFile({
    YoutubeDiagnostic? diagnostic,
    required String videoId,
    required StreamInfo streamInfo,
    required String destPath,
    CancelToken? cancelToken,
    void Function(int downloaded, int total)? onProgress,
    int backoffBaseMs = 500,
    int chunkSize = 1024 * 1024,
  }) async {
    final token = cancelToken ?? CancelToken();
    final yt = _youtubeExplode ?? yt_exp.YoutubeExplode();
    var closed = false;
    void close() {
      if (!closed && _youtubeExplode == null) {
        closed = true;
        yt.close();
      }
    }

    unawaited(token.whenCancel.then((_) => close()));
    Future<yt_exp.StreamInfo> resolve() async {
      token.throwIfCancellationRequested();
      return Future.any([
        YoutubeRecovery.resolve(
          yt,
          videoId,
          streamInfo,
          diagnostic: diagnostic,
        ).timeout(
          const Duration(seconds: 45),
          onTimeout: () {
            close();
            throw TimeoutException('YouTube extraction timed out');
          },
        ),
        token.whenCancel.then<yt_exp.StreamInfo>((e) => throw e),
      ]);
    }

    final ownDio = _dio == null;
    final dio =
        _dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 20)));
    try {
      try {
        await YoutubeTransfer(
          diagnostic: diagnostic,
          dio: dio,
          backoff: Duration(milliseconds: backoffBaseMs),
          chunkSize: chunkSize,
        ).download(
          selected: streamInfo,
          path: destPath,
          token: token,
          refresh:
              () async => refreshedYoutubeEntity(await resolve(), streamInfo),
          onProgress: onProgress,
        );
      } catch (error) {
        token.throwIfCancellationRequested();
        if (closed) rethrow;
        if (error is! DioException &&
            error is! HttpException &&
            error is! SocketException &&
            error is! TimeoutException) {
          rethrow;
        }
        // The upstream native adapter handles DASH/HLS fragments. Start afresh;
        // it cannot safely append an arbitrary direct-transfer partial file.
        diagnostic?.call('native_fallback', {
          'type': error.runtimeType.toString(),
        });
        final native = await resolve();
        final file = File('$destPath.native');
        final sink = await file.open(mode: FileMode.write);
        var current = 0;
        final total = native.size.totalBytes;
        try {
          final bytes = YoutubeTransfer.controlledStream(
            yt.videos.streamsClient.get(native),
            token,
            const Duration(seconds: 20),
            onStop: close,
          );
          await for (final chunk in bytes) {
            await sink.writeFrom(chunk);
            final previous = current;
            current += chunk.length;
            if (total > 0 && current > total) {
              throw const HttpException(
                'Native YouTube stream exceeded its expected size',
              );
            }
            if (current ~/ (1024 * 1024) != previous ~/ (1024 * 1024)) {
              diagnostic?.call('bytes', {
                'downloaded': current,
                'total': total,
                'method': 'native',
              });
            }
            onProgress?.call(current, total);
          }
          token.throwIfCancellationRequested();
          if (total <= 0 || current != total) {
            throw const HttpException('Native YouTube stream is incomplete');
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        await file.rename(destPath);
      }
    } finally {
      if (ownDio) dio.close(force: true);
      close();
    }
  }

  Future<void> _streamToFile({
    required Dio dio,
    required String url,
    required String destPath,
    required int totalBytes,
    CancelToken? cancelToken,
    void Function(int downloaded, int total)? onProgress,
    Future<String?> Function()? onTokenExpired,
    int backoffBaseMs = 500,
    int chunkSize = 1024 * 1024,
  }) async {
    final file = File(destPath);
    await file.parent.create(recursive: true);

    int currentBytes = 0;
    if (await file.exists()) {
      currentBytes = await file.length();
    }

    if (totalBytes > 0 && currentBytes >= totalBytes) {
      onProgress?.call(currentBytes, totalBytes);
      return;
    }

    var sink = file.openWrite(mode: FileMode.append);
    String currentUrl = url;

    try {
      while (totalBytes <= 0 || currentBytes < totalBytes) {
        if (cancelToken?.isCancelled ?? false) {
          throw Exception('Download cancelled');
        }

        int retryAttempt = 0;
        const maxRetries = 3;
        bool chunkSuccess = false;
        int chunkReceived = 0;

        while (!chunkSuccess) {
          if (cancelToken?.isCancelled ?? false) {
            throw Exception('Download cancelled');
          }

          final int end;
          if (totalBytes > 0) {
            end = math.min(currentBytes + chunkSize - 1, totalBytes - 1);
          } else {
            end = currentBytes + chunkSize - 1;
          }

          final isYouTubeUrl =
              currentUrl.contains('googlevideo.com') ||
              currentUrl.contains('youtube.com');
          final isAndroidClient =
              currentUrl.contains('&c=ANDROID') ||
              currentUrl.contains('?c=ANDROID');

          final headers = <String, String>{
            'User-Agent':
                (isYouTubeUrl && isAndroidClient)
                    ? 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip'
                    : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': '*/*',
            'Range': 'bytes=$currentBytes-$end',
          };

          try {
            final response = await dio.get<ResponseBody>(
              currentUrl,
              options: Options(
                responseType: ResponseType.stream,
                headers: headers,
                validateStatus:
                    (status) =>
                        status != null &&
                        (status == 200 ||
                            status == 206 ||
                            (status == 416 && currentBytes > 0)),
              ),
              cancelToken: cancelToken,
            );

            if (response.statusCode == 416) {
              // Server returned 416 Range Not Satisfiable because currentBytes reached EOF.
              totalBytes = currentBytes;
              chunkSuccess = true;
              break;
            }

            // A server may ignore Range and return the whole file. Restart the
            // output instead of appending duplicate bytes to a partial file.
            if (response.statusCode == 200 && currentBytes > 0) {
              await sink.close();
              sink = file.openWrite();
              currentBytes = 0;
            }
            final contentRange = response.headers.value(
              HttpHeaders.contentRangeHeader,
            );
            final rangeStart =
                contentRange == null
                    ? null
                    : RegExp(r'bytes (\d+)-').firstMatch(contentRange);
            if (rangeStart != null &&
                int.parse(rangeStart.group(1)!) != currentBytes) {
              throw const HttpException(
                'Server returned an unexpected byte range',
              );
            }
            int resolvedTotal = totalBytes;
            if (resolvedTotal <= 0) {
              final contentRange = response.headers.value(
                HttpHeaders.contentRangeHeader,
              );
              if (contentRange != null && contentRange.contains('/')) {
                final totalStr = contentRange.split('/').last.trim();
                resolvedTotal = int.tryParse(totalStr) ?? 0;
              } else if (response.statusCode == 200) {
                final cl = response.headers.value(
                  HttpHeaders.contentLengthHeader,
                );
                if (cl != null) {
                  resolvedTotal = (int.tryParse(cl) ?? 0) + currentBytes;
                }
              }
            }

            chunkReceived = 0;
            await for (final chunk in response.data!.stream) {
              if (cancelToken?.isCancelled ?? false) {
                throw Exception('Download cancelled');
              }
              sink.add(chunk);
              chunkReceived += chunk.length;
              currentBytes += chunk.length;
              onProgress?.call(
                currentBytes,
                resolvedTotal > 0 ? resolvedTotal : currentBytes,
              );
            }

            if (resolvedTotal > 0 && totalBytes <= 0) {
              totalBytes = resolvedTotal;
            }

            if (chunkReceived == 0 &&
                (resolvedTotal <= 0 || currentBytes < resolvedTotal)) {
              throw const HttpException(
                'Media stream ended without receiving the requested bytes',
              );
            }
            chunkSuccess = true;
          } on DioException catch (e) {
            if (cancelToken?.isCancelled ??
                false || e.type == DioExceptionType.cancel) {
              throw Exception('Download cancelled');
            }

            final statusCode = e.response?.statusCode;
            if (statusCode == 416 && currentBytes > 0) {
              // Server returned 416 Range Not Satisfiable because currentBytes reached EOF.
              totalBytes = currentBytes;
              chunkSuccess = true;
              break;
            }
            if (statusCode == 403 || statusCode == 410) {
              if (onTokenExpired != null && retryAttempt < maxRetries) {
                retryAttempt++;
                try {
                  final newUrl = await onTokenExpired();
                  if (newUrl != null && newUrl.isNotEmpty) {
                    currentUrl = newUrl;
                    await Future.delayed(
                      Duration(milliseconds: backoffBaseMs * retryAttempt),
                    );
                    continue; // Retry with new URL from currentBytes
                  }
                } catch (_) {}
              }
              rethrow;
            }

            // Client errors (4xx except 408 Request Timeout / 429 Too Many Requests) should not retry
            if (statusCode != null &&
                statusCode >= 400 &&
                statusCode < 500 &&
                statusCode != 408 &&
                statusCode != 429) {
              rethrow;
            }

            retryAttempt++;
            if (retryAttempt > maxRetries) {
              rethrow;
            }
            await Future.delayed(
              Duration(milliseconds: backoffBaseMs * retryAttempt),
            );
          } catch (e) {
            if (cancelToken?.isCancelled ?? false) {
              throw Exception('Download cancelled');
            }
            if (e is SocketException ||
                e is HttpException ||
                e is IOException) {
              retryAttempt++;
              if (retryAttempt > maxRetries) {
                rethrow;
              }
              await Future.delayed(
                Duration(milliseconds: backoffBaseMs * retryAttempt),
              );
            } else {
              rethrow;
            }
          }
        }

        if (chunkReceived == 0) {
          break;
        }
      }

      if (totalBytes <= 0 || currentBytes > totalBytes) {
        totalBytes = currentBytes;
      }
      onProgress?.call(currentBytes, totalBytes);
    } finally {
      await sink.close();
    }
  }

  @visibleForTesting
  Future<void> streamToFile({
    required Dio dio,
    required String url,
    required String destPath,
    required int totalBytes,
    CancelToken? cancelToken,
    void Function(int downloaded, int total)? onProgress,
    Future<String?> Function()? onTokenExpired,
    int backoffBaseMs = 500,
    int chunkSize = 1024 * 1024,
  }) => _streamToFile(
    dio: dio,
    url: url,
    destPath: destPath,
    totalBytes: totalBytes,
    cancelToken: cancelToken,
    onProgress: onProgress,
    onTokenExpired: onTokenExpired,
    backoffBaseMs: backoffBaseMs,
    chunkSize: chunkSize,
  );

  @visibleForTesting
  Future<void> downloadYouTubeStreamToFile({
    required String videoId,
    required StreamInfo streamInfo,
    required String destPath,
    CancelToken? cancelToken,
    void Function(int downloaded, int total)? onProgress,
    int backoffBaseMs = 500,
    int chunkSize = 1024 * 1024,
  }) => _downloadYouTubeStreamToFile(
    videoId: videoId,
    streamInfo: streamInfo,
    destPath: destPath,
    cancelToken: cancelToken,
    onProgress: onProgress,
    backoffBaseMs: backoffBaseMs,
    chunkSize: chunkSize,
  );

  final Set<String> _finalizing = {};

  Future<void> _onDownloadSuccessful(DownloadTask task) async {
    if (!(_tasks[task.id]?.status.isActive ?? false) ||
        !_finalizing.add(task.id)) {
      return;
    }
    try {
      await _finalizeDownloadedTask(task);
    } finally {
      _finalizing.remove(task.id);
    }
  }

  Future<void> _finalizeDownloadedTask(DownloadTask task) async {
    final isVideoOnly = task.selectedStream.isVideoOnly;

    if (!isVideoOnly) {
      await _finishTaskSuccess(task);
      return;
    }

    // Video-only stream requires audio stream and FFmpeg merging
    final targetPath = task.filePath ?? 'download_${task.id}';
    final tempVideoPath = '${targetPath}_video.tmp';
    final tempAudioPath = '${targetPath}_audio.tmp';

    String actualVideoPath = tempVideoPath;
    final bgTask = _bgTasks[task.id];
    if (bgTask != null) {
      try {
        final bgPath = await bgTask.filePath();
        if (await File(bgPath).exists()) {
          actualVideoPath = bgPath;
        }
      } catch (_) {}
    }

    StreamInfo? audioStream = _pendingAudioStreams[task.id];

    // If audioStream is not provided, try to resolve from ExtractorFactory
    if (audioStream == null && _extractorFactory != null) {
      try {
        final mediaUrl =
            task.mediaInfo.id.length == 11
                ? 'https://www.youtube.com/watch?v=${task.mediaInfo.id}'
                : task.mediaInfo.id;
        final extractor = _extractorFactory.getExtractor(mediaUrl);
        if (extractor != null) {
          final streams = await extractor.getStreams(mediaUrl);
          final audioStreams = streams.where((s) => s.isAudioOnly).toList();
          if (audioStreams.isNotEmpty) {
            audioStream = audioStreams.first;
          }
        }
      } catch (_) {}
    }

    if (audioStream == null) {
      _failTask(
        task,
        'No companion audio stream is available for the selected video quality.',
      );
      return;
    }
    if (!(_tasks[task.id]?.status.isActive ?? false)) return;

    String actualAudioPath = tempAudioPath;

    // Download audio stream then merge
    try {
      if (_customDownloadExecution != null) {
        String? audioError;
        final audioCompleter = Completer<void>();
        await _customDownloadExecution(
          task: task,
          stream: audioStream,
          targetPath: tempAudioPath,
          onProgress: (progress, downloadedBytes, totalBytes, speed) {},
          onComplete: () async {
            if (!audioCompleter.isCompleted) {
              audioCompleter.complete();
            }
          },
          onError: (error) {
            audioError = error;
            if (!audioCompleter.isCompleted) {
              audioCompleter.complete();
            }
          },
        );
        await audioCompleter.future;
        if (audioError != null) {
          throw Exception(audioError);
        }
      } else if (_downloader != null) {
        final audioBgTask = await _createBgTask(
          '${task.id}_audio',
          audioStream.url,
          tempAudioPath,
        );
        try {
          final update = await _downloader.download(audioBgTask);
          if (update.status == bg.TaskStatus.complete) {
            final bgAudioPath = await audioBgTask.filePath();
            if (await File(bgAudioPath).exists()) {
              actualAudioPath = bgAudioPath;
            }
          } else {
            // Fallback to Dio if background downloader had an issue
            final dio = _dio ?? Dio();
            await dio.download(audioStream.url, tempAudioPath);
            actualAudioPath = tempAudioPath;
          }
        } catch (_) {
          // Fallback to Dio on exception
          final dio = _dio ?? Dio();
          await dio.download(audioStream.url, tempAudioPath);
          actualAudioPath = tempAudioPath;
        }
      } else {
        final dio = _dio ?? Dio();
        await dio.download(audioStream.url, tempAudioPath);
      }

      if (!(_tasks[task.id]?.status.isActive ?? false)) return;
      await _mergeDownloadedTracks(
        task,
        actualVideoPath,
        actualAudioPath,
        targetPath,
      );
    } catch (e) {
      // Failed processing retains recoverable source tracks.
      if (!(_tasks[task.id]?.status.isActive ?? false)) return;
      _failTask(task, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _mergeDownloadedTracks(
    DownloadTask task,
    String video,
    String audio,
    String output,
  ) {
    final token = CancelToken();
    _mergeTokens[task.id] = token;
    late Future<void> run;
    run = (() async {
      try {
        final mergingTask = (_tasks[task.id] ?? task).copyWith(
          status: DownloadStatus.merging,
          progress: .95,
          speedBytesPerSecond: 0,
        );
        _tasks[task.id] = mergingTask;
        _notifyTaskChanged(mergingTask);
        final success =
            _customMerger
                ? await _ffmpegMerger!(video, audio, output)
                : await const MediaMerger().merge(
                  video,
                  audio,
                  output,
                  cancelToken: token,
                  aacBitrateKbps: 192,
                  allowVideoTranscode: true,
                  diagnostic:
                      (event, values) => debugPrint(
                        'Media merge ${jsonEncode({'taskId': task.id, 'platform': task.mediaInfo.platform.name, 'event': event, ...values})}',
                      ),
                );
        if (token.isCancelled || !(_tasks[task.id]?.status.isActive ?? false)) {
          return;
        }
        if (success) {
          await _finishTaskSuccess(mergingTask);
        } else {
          _failTask(mergingTask, 'FFmpeg merge failed');
        }
        // Probe/registry completion must succeed before deleting source tracks.
        if (_tasks[task.id]?.status == DownloadStatus.completed) {
          for (final path in [video, audio]) {
            try {
              final file = File(path);
              if (await file.exists()) await file.delete();
            } on FileSystemException {
              // A cleanup failure must not downgrade already registered media.
            }
          }
        }
      } catch (e) {
        if (!token.isCancelled && (_tasks[task.id]?.status.isActive ?? false)) {
          _failTask(task, e.toString().replaceFirst('Exception: ', ''));
        }
      } finally {
        if (_tasks[task.id]?.status == DownloadStatus.cancelled) {
          for (final path in [video, audio, output]) {
            try {
              final file = File(path);
              if (await file.exists()) await file.delete();
            } on FileSystemException {
              // Cancellation cleanup is limited to this task's owned files.
            }
          }
        }
      }
    })().whenComplete(() {
      if (identical(_mergeRuns[task.id], run)) _mergeRuns.remove(task.id);
      if (identical(_mergeTokens[task.id], token)) _mergeTokens.remove(task.id);
    });
    _mergeRuns[task.id] = run;
    return run;
  }

  String _sanitizeErrorMessage(String error) {
    final lower = error.toLowerCase();
    if (lower.contains('filenotfoundexception') ||
        lower.contains('permission denied')) {
      return 'Storage permission denied. Please grant storage access in Settings.';
    }
    if (lower.contains('statuscode: 404') ||
        lower.contains('status code of 404')) {
      return 'Media not found on remote server.';
    }
    if (lower.contains('bad response') ||
        lower.contains('dioexception') ||
        lower.contains('statuscode: 403') ||
        lower.contains('status code of 403') ||
        lower.contains('statuscode: 410') ||
        lower.contains('status code of 410')) {
      return 'Media stream expired or access denied by server. Please retry.';
    }
    if (lower.contains('socketexception:') ||
        lower.contains('connection timed out') ||
        lower.contains('connection refused')) {
      return 'Network unavailable. Please reconnect to Wi-Fi or cellular.';
    }
    if (error.startsWith('Exception: ')) {
      return error.substring(11);
    }
    return error;
  }

  Future<void> _finishTaskSuccess(
    DownloadTask task, {
    Map<dynamic, dynamic>? validatedProbe,
  }) async {
    final latest = _tasks[task.id];
    if (latest == null || !latest.status.isActive) return;
    task = latest;
    final filePath = task.filePath;

    int? finalSize;
    if (filePath != null) {
      try {
        finalSize = await File(filePath).length();
      } on FileSystemException {
        // Custom execution used by tests may not write a physical output.
        if (_customDownloadExecution == null) {
          _failTask(task, 'Downloaded file could not be found on device.');
          return;
        }
      }
    }
    if (finalSize != null && finalSize <= 0) {
      _failTask(task, 'Downloaded file is empty. Please retry.');
      return;
    }
    if (_customDownloadExecution == null) {
      try {
        if (filePath == null) throw StateError('Missing output path');
        // Reuse the strict YouTube probe after its atomic rename. For generic
        // completion one output probe supplies both track and height checks.
        final properties =
            validatedProbe ??
            (await FFprobeKit.getMediaInformation(
              filePath,
            )).getMediaInformation()?.getAllProperties();
        final streams =
            (properties?['streams'] as List? ?? const [])
                .whereType<Map>()
                .toList();
        final expected = task.selectedStream.isAudioOnly ? 'audio' : 'video';
        if (!streams.any((s) => s['codec_type'] == expected) ||
            (task.selectedStream.isVideoOnly &&
                !streams.any((s) => s['codec_type'] == 'audio'))) {
          throw StateError('Missing required media stream');
        }
        final requiredHeight = task.selectedStream.videoHeight;
        if (!task.selectedStream.isAudioOnly &&
            requiredHeight != null &&
            requiredHeight > 360) {
          final video = streams.firstWhere((s) => s['codec_type'] == 'video');
          final verifiedHeight = int.tryParse('${video['height']}');
          if (!(_tasks[task.id]?.status.isActive ?? false)) return;
          if (verifiedHeight != null && verifiedHeight < requiredHeight * .85) {
            try {
              await File(filePath).delete();
            } on FileSystemException {
              /* Keep the validation error. */
            }
            _failTask(
              task,
              'Quality verification failed: expected ${task.selectedStream.qualityLabel}, received ${verifiedHeight}p.',
            );
            return;
          }
        }
      } catch (error) {
        if (_tasks[task.id]?.status.isActive ?? false) {
          _failTask(
            task,
            'Downloaded media could not be verified. Please retry.',
          );
        }
        return;
      }
    }
    // Cancellation/pause can occur while FFprobe or filesystem calls await.
    final current = _tasks[task.id];
    if (current == null || !current.status.isActive) return;
    task = current;
    _activeTaskIds.remove(task.id);
    _pendingAudioStreams.remove(task.id);
    _bgTasks.remove(task.id);
    _taskSpeedTrackers.remove(task.id);

    final completedTask = task.copyWith(
      status: DownloadStatus.completed,
      progress: 1.0,
      downloadedBytes: finalSize ?? task.totalBytes ?? task.downloadedBytes,
      totalBytes: finalSize ?? task.totalBytes,
      speedBytesPerSecond: 0.0,
      completedAt: DateTime.now(),
    );
    _tasks[task.id] = completedTask;
    await _downloadRegistry?.register(DownloadRecord.fromTask(completedTask));
    DownloadNotificationService.instance.showCompleted(
      taskId: task.id,
      title: task.mediaInfo.title,
    );
    _notifyTaskChanged(completedTask);
    _processQueue();
  }

  void _failTask(DownloadTask task, String error) {
    if (!(_tasks[task.id]?.status.isActive ?? false)) return;

    _activeTaskIds.remove(task.id);
    _bgTasks.remove(task.id);
    _taskSpeedTrackers.remove(task.id);

    final cleanMessage = _sanitizeErrorMessage(error);
    final failedTask = task.copyWith(
      status: DownloadStatus.failed,
      errorMessage: cleanMessage,
      speedBytesPerSecond: 0.0,
    );
    _tasks[task.id] = failedTask;
    DownloadNotificationService.instance.showFailed(
      taskId: task.id,
      title: task.mediaInfo.title,
      error: cleanMessage,
    );
    _notifyTaskChanged(failedTask);
    _processQueue();
  }

  void _handleBgProgressUpdate(bg.TaskProgressUpdate update) {
    final task = _tasks[update.task.taskId];
    if (task == null || !task.status.isActive) return;

    final total =
        update.expectedFileSize > 0
            ? update.expectedFileSize
            : (task.totalBytes ?? 0);
    final downloaded =
        (total > 0 && update.progress >= 0)
            ? (total * update.progress).round()
            : task.downloadedBytes;
    final speed =
        update.networkSpeed > 0 ? (update.networkSpeed * 1024 * 1024) : 0.0;
    final effectiveSpeed = _calculateSpeed(task.id, downloaded ?? 0, speed);

    final updated = task.copyWith(
      progress: update.progress.clamp(0.0, 1.0),
      downloadedBytes: downloaded,
      totalBytes: total > 0 ? total : task.totalBytes,
      speedBytesPerSecond: effectiveSpeed,
    );
    _tasks[task.id] = updated;
    _notifyTaskChanged(updated);
  }

  void _handleBgStatusUpdate(bg.TaskStatusUpdate update) {
    final task = _tasks[update.task.taskId];
    // Native events can arrive after a control action or finalization. The
    // engine's current state owns the lifecycle; do not resurrect stopped jobs
    // or downgrade completed records when a late paused/canceled event arrives.
    if (task == null || !task.status.isActive) return;

    switch (update.status) {
      case bg.TaskStatus.complete:
        _onDownloadSuccessful(task);
        break;
      case bg.TaskStatus.failed:
      case bg.TaskStatus.notFound:
        _failTask(task, update.exception?.description ?? 'Download failed');
        break;
      case bg.TaskStatus.canceled:
        _activeTaskIds.remove(task.id);
        final cancelled = task.copyWith(
          status: DownloadStatus.cancelled,
          speedBytesPerSecond: 0.0,
        );
        _tasks[task.id] = cancelled;
        _notifyTaskChanged(cancelled);
        _processQueue();
        break;
      case bg.TaskStatus.paused:
        _activeTaskIds.remove(task.id);
        final paused = task.copyWith(
          status: DownloadStatus.paused,
          speedBytesPerSecond: 0.0,
        );
        _tasks[task.id] = paused;
        _notifyTaskChanged(paused);
        _processQueue();
        break;
      default:
        break;
    }
  }

  Future<bg.DownloadTask> _createBgTask(
    String taskId,
    String url,
    String filePath,
  ) async {
    if (filePath.contains('/') || filePath.contains('\\')) {
      try {
        final (baseDir, dir, filename) = await bg.Task.split(
          filePath: filePath,
        );
        return bg.DownloadTask(
          taskId: taskId,
          url: url,
          baseDirectory: baseDir,
          directory: dir,
          filename: filename,
          updates: bg.Updates.statusAndProgress,
          allowPause: true,
        );
      } catch (_) {}
    }

    final filename = filePath.split(Platform.pathSeparator).last;
    return bg.DownloadTask(
      taskId: taskId,
      url: url,
      baseDirectory: bg.BaseDirectory.applicationDocuments,
      filename: filename,
      updates: bg.Updates.statusAndProgress,
      allowPause: true,
    );
  }

  double _calculateSpeed(
    String taskId,
    int currentBytes, [
    double? reportedSpeed,
  ]) {
    final now = DateTime.now();
    final tracker = _taskSpeedTrackers.putIfAbsent(
      taskId,
      () => _SpeedTracker(
        lastBytes: currentBytes,
        lastTimestamp: now,
        smoothedSpeed:
            (reportedSpeed != null && reportedSpeed > 0) ? reportedSpeed : 0.0,
      ),
    );

    final ms = now.difference(tracker.lastTimestamp).inMilliseconds;
    if (ms >= 250) {
      final deltaBytes = currentBytes - tracker.lastBytes;
      if (deltaBytes >= 0) {
        final instantSpeed = (deltaBytes / ms) * 1000.0;
        if (reportedSpeed != null && reportedSpeed > 0) {
          tracker.smoothedSpeed =
              0.75 * tracker.smoothedSpeed + 0.25 * reportedSpeed;
        } else if (tracker.smoothedSpeed <= 0) {
          tracker.smoothedSpeed = instantSpeed;
        } else {
          tracker.smoothedSpeed =
              0.75 * tracker.smoothedSpeed + 0.25 * instantSpeed;
        }
      }
      tracker.lastBytes = currentBytes;
      tracker.lastTimestamp = now;
    } else if (reportedSpeed != null &&
        reportedSpeed > 0 &&
        tracker.smoothedSpeed <= 0) {
      tracker.smoothedSpeed = reportedSpeed;
    }

    if (reportedSpeed != null &&
        reportedSpeed > 0 &&
        tracker.smoothedSpeed <= 0) {
      return reportedSpeed;
    }
    return tracker.smoothedSpeed;
  }

  void dispose() {
    _checkpointTimer?.cancel();
    unawaited(checkpointSession());
    for (final token in _mergeTokens.values) {
      token.cancel('Engine disposed');
    }
    for (final token in _dioCancelTokens.values) {
      token.cancel('Engine disposed');
    }
    _dioCancelTokens.clear();
    _youtubeExplode?.close();
    _taskUpdateController.close();
    _tasksListController.close();
  }
}

class _SpeedTracker {
  int lastBytes;
  DateTime lastTimestamp;
  double smoothedSpeed;

  _SpeedTracker({
    required this.lastBytes,
    required this.lastTimestamp,
    this.smoothedSpeed = 0.0,
  });
}
