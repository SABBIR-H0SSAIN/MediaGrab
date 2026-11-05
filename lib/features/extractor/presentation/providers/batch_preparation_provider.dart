import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../downloads/domain/entities/download_task.dart';
import '../../../downloads/presentation/providers/download_manager_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/media_error_message.dart';
import '../../../../core/utils/url_parser.dart';
import '../../data/extractor_factory.dart';
import '../../domain/entities/media_info.dart';
import '../../domain/entities/prepared_download.dart';
import '../../domain/entities/stream_info.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import 'extractor_provider.dart';
import '../utils/video_quality_options.dart';

enum BatchItemStatus { draft, checking, ready, failed }

String normalizeBatchUrl(String value) {
  final text = value.trim();
  return text.isEmpty || text.contains('://') ? text : 'https://$text';
}

String batchUrlKey(String value) {
  final url = normalizeBatchUrl(value);
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  if (detectPlatform(url) == PlatformType.youtube) {
    final parts = uri.pathSegments;
    final id =
        uri.queryParameters['v'] ??
        (uri.host.endsWith('youtu.be') && parts.isNotEmpty
            ? parts.first
            : null) ??
        (parts.length > 1 &&
                ['shorts', 'embed', 'live', 'v'].contains(parts.first)
            ? parts[1]
            : null);
    if (id != null) return 'youtube:$id';
  }
  final platform = detectPlatform(url);
  if (platform == PlatformType.instagram) {
    final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    if (parts.length > 1 &&
        ['p', 'reel', 'reels', 'tv'].contains(parts.first)) {
      return 'instagram:${parts[1]}';
    }
  }
  if (platform == PlatformType.facebook) {
    final id =
        uri.queryParameters['v'] ??
        uri.queryParameters['video_id'] ??
        RegExp(r'/(?:reels?|videos)/(\d+)').firstMatch(uri.path)?.group(1);
    if (id != null) return 'facebook:$id';
  }
  final query = Map<String, String>.from(uri.queryParameters)..removeWhere(
    (key, _) =>
        key.startsWith('utm_') ||
        ['si', 'igsh', 'mibextid', 'fbclid'].contains(key),
  );
  final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  return uri
      .replace(
        host: uri.host.toLowerCase().replaceFirst(RegExp(r'^(www\.|m\.)'), ''),
        path: path,
        query: query.isEmpty ? '' : null,
        queryParameters: query.isEmpty ? null : query,
        fragment: '',
      )
      .toString();
}

/// Complete video URLs only; shared by smart adding and the local edit form.
bool isCompleteBatchVideoUrl(String value) {
  if (value.trim().isEmpty || RegExp(r'[\s,]').hasMatch(value.trim())) {
    return false;
  }
  final uri = Uri.tryParse(normalizeBatchUrl(value));
  if (uri == null || !['http', 'https'].contains(uri.scheme)) return false;
  final key = batchUrlKey(value);
  return switch (detectPlatform(value)) {
    PlatformType.youtube =>
      key.startsWith('youtube:') &&
          RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(key.substring(8)),
    PlatformType.instagram => key.startsWith('instagram:'),
    PlatformType.facebook =>
      key.startsWith('facebook:') ||
          (uri.pathSegments.where((p) => p.isNotEmpty).isNotEmpty &&
              (uri.host.endsWith('fb.watch') ||
                  uri.path.startsWith('/share/'))),
    PlatformType.unknown => false,
  };
}

class BatchItem {
  final int id;
  final String url;
  final int revision;
  final BatchItemStatus status;
  final MediaInfo? media;
  final List<StreamInfo> streams;
  final StreamInfo? selected;
  final StreamInfo? audio;
  final bool included;
  final bool overridden;
  final String? error;
  final String? notice;
  final String? overrideQuality;
  final String? taskId;
  final DownloadTask? task;

  const BatchItem({
    required this.id,
    this.url = '',
    this.revision = 0,
    this.status = BatchItemStatus.draft,
    this.media,
    this.streams = const [],
    this.selected,
    this.audio,
    this.included = true,
    this.overridden = false,
    this.error,
    this.notice,
    this.overrideQuality,
    this.taskId,
    this.task,
  });

  BatchItem copy({
    BatchItemStatus? status,
    MediaInfo? media,
    List<StreamInfo>? streams,
    StreamInfo? selected,
    StreamInfo? audio,
    bool? included,
    bool? overridden,
    String? error,
    String? notice,
    String? taskId,
    DownloadTask? task,
    bool clearTask = false,
  }) => BatchItem(
    id: id,
    url: url,
    revision: revision,
    status: status ?? this.status,
    media: media ?? this.media,
    streams: streams ?? this.streams,
    selected: selected ?? this.selected,
    audio: audio,
    included: included ?? this.included,
    overridden: overridden ?? this.overridden,
    error: error,
    notice: notice,
    overrideQuality: selected?.qualityLabel ?? overrideQuality,
    taskId: taskId ?? this.taskId,
    task: clearTask ? null : (task ?? this.task),
  );

  PreparedDownload get prepared => PreparedDownload(
    sourceUrl: normalizeBatchUrl(url),
    media: media!,
    stream: selected!,
    audioStream: audio,
  );
}

class BatchPreparationState {
  final List<BatchItem> items;
  final bool checking;
  final String quality;
  final bool autoAdd;
  final bool autoRemoveCompleted;
  final Set<String> sessionTaskIds;
  const BatchPreparationState(
    this.items, {
    this.checking = false,
    this.autoAdd = true,
    this.autoRemoveCompleted = true,
    this.sessionTaskIds = const {},
    required this.quality,
  });
  List<BatchItem> get selected =>
      items
          .where(
            (i) =>
                i.status == BatchItemStatus.ready &&
                i.included &&
                i.taskId == null,
          )
          .toList();
}

final batchPreparationProvider =
    StateNotifierProvider<BatchPreparationController, BatchPreparationState>((
      ref,
    ) {
      final settings = ref.read(settingsProvider);
      final controller = BatchPreparationController(
        ref.read(extractorFactoryProvider),
        quality: settings.defaultVideoQuality,
        audioFormat: settings.defaultAudioFormat,
      );
      controller.restore().then((_) {
        if (controller._disposed) return;
        controller.syncTasks(
          ref.read(downloadManagerProvider),
          (id) => ref.read(downloadManagerProvider.notifier).retryDownload(id),
        );
      });
      ref.listen<List<DownloadTask>>(downloadManagerProvider, (_, tasks) {
        controller.syncTasks(
          tasks,
          (id) => ref.read(downloadManagerProvider.notifier).retryDownload(id),
        );
      });
      return controller;
    });

class BatchPreparationController extends StateNotifier<BatchPreparationState> {
  final ExtractorFactory factory;
  final String audioFormat;
  int _nextId = 1;
  bool _disposed = false;
  Timer? _debounce;
  Timer? _saveTimer;
  bool _draftDirty = false;
  Future<void> _pendingSave = Future.value();
  bool _pendingCheck = false;
  bool _changed = false;
  final Set<String> _verifying = {};
  final Map<String, int> _retries = {};
  final Map<String, Timer> _retryTimers = {};

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => check());
  }

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('batch_draft_v2');
      if (_disposed || _changed || raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final items =
          (data['items'] as List).map((value) {
            final map = value as Map;
            return BatchItem(
              id: _nextId++,
              url: map['url'] as String,
              included: map['included'] as bool? ?? true,
              taskId: map['taskId'] as String?,
              overridden: map['overrideQuality'] != null,
              overrideQuality: map['overrideQuality'] as String?,
            );
          }).toList();
      _emit(
        items.isEmpty ? state.items : items,
        quality: data['quality'] as String?,
        autoAdd: data['autoAdd'] as bool?,
        autoRemoveCompleted: data['autoRemoveCompleted'] as bool?,
        sessionTaskIds:
            (data['sessionTaskIds'] as List?)?.cast<String>().toSet(),
      );
      _schedule();
    } catch (_) {}
  }

  void syncTasks(
    List<DownloadTask> tasks,
    Future<bool> Function(String) retry,
  ) {
    if (_disposed || !state.items.any((item) => item.taskId != null)) return;
    var changed = false;
    final byId = {for (final task in tasks) task.id: task};
    final items = [
      for (final item in state.items)
        item.taskId == null
            ? item
            : (() {
              final task = byId[item.taskId];
              // Progress consumers subscribe per task; only structural/status changes
              // should rebuild the preparation screen or write its saved draft.
              if (task == null) {
                if (item.task == null) return item;
                changed = true;
                return item.copy(
                  clearTask: true,
                  audio: item.audio,
                  error: item.error,
                  notice: item.notice,
                );
              }
              if (item.task?.status == task.status &&
                  item.task?.errorMessage == task.errorMessage) {
                return item;
              }
              changed = true;
              return item.copy(
                task: task,
                media: task.mediaInfo,
                selected: task.selectedStream,
                audio: item.audio,
                error: item.error,
                notice: item.notice,
              );
            })(),
    ];
    if (changed) _emit(items);
    if (state.autoRemoveCompleted) {
      for (final item in state.items) {
        final task = byId[item.taskId] ?? item.task;
        if (task?.status.isCompleted == true) _verifyAndRemove(item.id, task!);
      }
    }
    final linkedTaskIds = {
      for (final item in state.items)
        if (item.taskId != null) item.taskId!,
    };
    for (final task in tasks) {
      if (!linkedTaskIds.contains(task.id)) continue;
      if (task.status.isFailed &&
          isTemporaryBatchFailure(task.errorMessage ?? '') &&
          (_retries[task.id] ?? 0) < 2 &&
          !_retryTimers.containsKey(task.id)) {
        _retries[task.id] = (_retries[task.id] ?? 0) + 1;
        _retryTimers[task.id] = Timer(
          Duration(seconds: 2 * _retries[task.id]!),
          () async {
            try {
              if (!_disposed &&
                  state.items.any(
                    (item) =>
                        item.taskId == task.id &&
                        (item.task?.status.isFailed ?? false),
                  )) {
                await retry(task.id);
              }
            } catch (_) {}
            _retryTimers.remove(task.id);
          },
        );
      }
    }
  }

  Future<void> _verifyAndRemove(int id, DownloadTask task) async {
    if (!_verifying.add(task.id)) return;
    try {
      final path = task.filePath;
      if (task.completedAt == null || path == null) return;
      final stat = await File(path).stat();
      if (!_disposed &&
          state.autoRemoveCompleted &&
          stat.type == FileSystemEntityType.file &&
          stat.size > 0 &&
          state.items.any(
            (item) =>
                item.id == id &&
                item.taskId == task.id &&
                item.task?.status.isCompleted == true,
          )) {
        // Remove only the draft reference. The engine and registry own the file.
        remove(id);
      }
    } on FileSystemException {
      // Retain the entry if final output cannot be verified.
    } finally {
      _verifying.remove(task.id);
    }
  }

  void setAutoRemoveCompleted(bool value) {
    _emit(state.items, autoRemoveCompleted: value);
    if (value) {
      for (final item in state.items) {
        if (item.task?.status.isCompleted == true) {
          _verifyAndRemove(item.id, item.task!);
        }
      }
    }
  }

  bool _locked(BatchItem item) =>
      item.taskId != null &&
      (item.task == null ||
          !(item.task!.status.isCompleted ||
              item.task!.status.isFailed ||
              item.task!.status.isCancelled));

  void clearPreparation() => _emit([
    for (final item in state.items)
      if (_locked(item)) item,
  ], sessionTaskIds: {});

  void attachTask(int id, DownloadTask task) => _update(
    id,
    (item) => item.copy(
      taskId: task.id,
      task: task,
      media: task.mediaInfo,
      selected: task.selectedStream,
      audio: item.audio,
    ),
  );
  void resetInterrupted(int id) {
    _update(
      id,
      (item) =>
          item.task == null
              ? BatchItem(
                id: item.id,
                url: item.url,
                revision: item.revision + 1,
              )
              : item,
    );
  }

  void queueError(int id, Object error) => _update(
    id,
    (item) => item.copy(
      status: BatchItemStatus.failed,
      error: mediaErrorMessage(error),
      audio: item.audio,
    ),
  );

  BatchPreparationController(
    this.factory, {
    String quality = 'Best',
    this.audioFormat = 'MP3',
  }) : super(BatchPreparationState([const BatchItem(id: 0)], quality: quality));

  void _emit(
    List<BatchItem> items, {
    bool? checking,
    String? quality,
    bool? autoAdd,
    bool? autoRemoveCompleted,
    Set<String>? sessionTaskIds,
  }) {
    if (!_disposed) {
      _changed = true;
      state = BatchPreparationState(
        List.unmodifiable(items),
        checking: checking ?? state.checking,
        quality: quality ?? state.quality,
        autoAdd: autoAdd ?? state.autoAdd,
        autoRemoveCompleted: autoRemoveCompleted ?? state.autoRemoveCompleted,
        sessionTaskIds: {
          ...?sessionTaskIds,
          if (sessionTaskIds == null) ...state.sessionTaskIds,
          for (final item in items)
            if (item.taskId != null) item.taskId!,
        },
      );
      _saveTimer?.cancel();
      _draftDirty = true;
      _saveTimer = Timer(const Duration(milliseconds: 250), flushDraft);
    }
  }

  /// Flush the latest draft on background/disposal as well as after edits.
  /// Capture before awaiting so disposal and later edits cannot change a write.
  Future<void> flushDraft() {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_draftDirty) return _pendingSave;
    _draftDirty = false;
    final snapshot = jsonEncode({
      'quality': state.quality,
      'autoAdd': state.autoAdd,
      'autoRemoveCompleted': state.autoRemoveCompleted,
      'sessionTaskIds': state.sessionTaskIds.toList(),
      'items': [
        for (final item in state.items.where((i) => i.url.isNotEmpty))
          {
            'url': item.url,
            'included': item.included,
            'taskId': item.taskId,
            'overrideQuality':
                item.overridden
                    ? (item.selected?.qualityLabel ?? item.overrideQuality)
                    : null,
          },
      ],
    });
    _pendingSave = _pendingSave.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = await prefs.setString('batch_draft_v2', snapshot);
        if (!saved) _draftDirty = true;
      } catch (_) {
        _draftDirty = true;
      }
    });
    return _pendingSave;
  }

  void _update(int id, BatchItem Function(BatchItem) update) => _emit([
    for (final item in state.items)
      if (item.id == id) update(item) else item,
  ]);
  void add([String url = '']) {
    _emit([...state.items, BatchItem(id: _nextId++, url: url)]);
    if (url.isNotEmpty) _schedule();
  }

  void edit(int id, String url) {
    if (state.items.any((i) => i.id == id && _locked(i))) return;
    _update(
      id,
      (old) => BatchItem(id: id, url: url, revision: old.revision + 1),
    );
    _schedule();
  }

  void remove(int id, {bool removeInterrupted = false}) {
    if (state.items.any(
      (i) => i.id == id && _locked(i) && !(removeInterrupted && i.task == null),
    )) {
      return;
    }
    final taskId = state.items.where((i) => i.id == id).firstOrNull?.taskId;
    _retryTimers.remove(taskId)?.cancel();
    _retries.remove(taskId);
    final items = state.items.where((i) => i.id != id).toList();
    _emit(items.isEmpty ? [BatchItem(id: _nextId++)] : items);
  }

  int paste(String text) {
    var duplicates = 0;
    final seen =
        state.items
            .where((i) => i.url.trim().isNotEmpty)
            .map((i) => batchUrlKey(i.url))
            .toSet();
    for (final url in text
        .split(RegExp(r'[\s,]+'))
        .where((s) => s.isNotEmpty)) {
      if (!seen.add(batchUrlKey(url))) {
        duplicates++;
        continue;
      }
      final empty = state.items.where((i) => i.url.trim().isEmpty).firstOrNull;
      if (empty != null) {
        edit(empty.id, url);
      } else {
        add(url);
      }
    }
    return duplicates;
  }

  void setAutoAdd(bool value) => _emit(state.items, autoAdd: value);

  void include(int id, bool value) => _update(
    id,
    (i) => i.copy(
      included: value,
      audio: i.audio,
      error: i.error,
      notice: i.notice,
    ),
  );
  void choose(int id, StreamInfo stream, StreamInfo? audio) => _update(id, (i) {
    if (_locked(i) || !i.streams.contains(stream)) return i;
    if (stream.isVideoOnly && audio == null) return i;
    if (i.taskId != null &&
        (i.task?.status.isFailed == true ||
            i.task?.status.isCancelled == true)) {
      return BatchItem(
        id: i.id,
        url: i.url,
        revision: i.revision + 1,
        status: BatchItemStatus.ready,
        media: i.media,
        streams: i.streams,
        selected: stream,
        audio: stream.isVideoOnly ? audio : null,
        overridden: true,
      );
    }
    return i.copy(
      selected: stream,
      audio: stream.isVideoOnly ? audio : null,
      overridden: true,
    );
  });
  void setQuality(String quality) => _emit([
    for (final i in state.items)
      if (i.streams.isNotEmpty &&
          i.media != null &&
          !i.overridden &&
          i.taskId == null)
        _select(i, quality)
      else
        i,
  ], quality: quality);

  BatchItem _select(BatchItem item, String quality) {
    if (item.overridden && item.overrideQuality != null) {
      quality = item.overrideQuality!;
    }
    final audio =
        item.streams.where((s) => s.isAudioOnly).toList()
          ..sort((a, b) => (b.bitrate ?? 0).compareTo(a.bitrate ?? 0));
    final audioOnly = quality.toLowerCase().contains('audio');
    final candidates =
        item.streams
            .where(
              (s) =>
                  audioOnly
                      ? s.isAudioOnly
                      : !s.isAudioOnly && (!s.isVideoOnly || audio.isNotEmpty),
            )
            .toList();
    final target = int.tryParse(quality.replaceAll(RegExp(r'[^0-9]'), ''));
    int height(StreamInfo s) => videoResolution(s) ?? 0;
    candidates.sort((a, b) {
      if (audioOnly) {
        final af = a.container.toLowerCase().contains(
          audioFormat.toLowerCase(),
        );
        final bf = b.container.toLowerCase().contains(
          audioFormat.toLowerCase(),
        );
        if (af != bf) return af ? -1 : 1;
        return (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
      }
      final distance =
          target == null
              ? height(b).compareTo(height(a))
              : (height(a) - target).abs().compareTo(
                (height(b) - target).abs(),
              );
      if (distance != 0) return distance;
      if (a.isVideoOnly != b.isVideoOnly) return a.isVideoOnly ? 1 : -1;
      return height(b).compareTo(height(a));
    });
    if (candidates.isEmpty) {
      return item.copy(
        status: BatchItemStatus.failed,
        error:
            'No playable ${audioOnly ? 'audio' : 'video with audio'} streams available.',
      );
    }
    final selected = candidates.first;
    final companion = selected.isVideoOnly ? audio.first : null;
    return item.copy(
      status: BatchItemStatus.ready,
      selected: selected,
      audio: companion,
      notice:
          !audioOnly &&
                  target != null &&
                  height(selected) != target &&
                  selected.qualityLabel.trim().toLowerCase() !=
                      quality.trim().toLowerCase()
              ? '$quality unavailable; using ${selected.qualityLabel}.'
              : null,
    );
  }

  Future<void> check({int? onlyId}) async {
    if (_disposed) return;
    if (state.checking) {
      _pendingCheck = true;
      return;
    }
    _debounce?.cancel();
    final seen =
        state.items
            .where((i) => i.status == BatchItemStatus.ready)
            .map((i) => batchUrlKey(i.url))
            .toSet();
    final work = <BatchItem>[];
    final items = <BatchItem>[];
    for (final item in state.items) {
      final key = batchUrlKey(item.url);
      final duplicate = item.url.trim().isNotEmpty && !seen.add(key);
      if ((onlyId != null && item.id != onlyId) ||
          item.url.trim().isEmpty ||
          item.taskId != null ||
          item.status == BatchItemStatus.ready ||
          (item.status == BatchItemStatus.failed && onlyId == null)) {
        items.add(item);
        continue;
      }
      final uri = Uri.tryParse(normalizeBatchUrl(item.url));
      final error =
          duplicate
              ? 'Duplicate link. Remove this row.'
              : uri == null ||
                  !['http', 'https'].contains(uri.scheme) ||
                  detectPlatform(item.url) == PlatformType.unknown
              ? 'Enter a supported YouTube, Facebook or Instagram link.'
              : null;
      if (error != null) {
        items.add(item.copy(status: BatchItemStatus.failed, error: error));
      } else {
        final pending = item.copy(status: BatchItemStatus.checking);
        items.add(pending);
        work.add(pending);
      }
    }
    _emit(items, checking: work.isNotEmpty);
    var index = 0;
    bool current(BatchItem item) =>
        !_disposed &&
        state.items.any((i) => i.id == item.id && i.revision == item.revision);
    Future<void> worker() async {
      while (!_disposed && index < work.length) {
        final item = work[index++];
        if (!current(item)) continue;
        try {
          final url = normalizeBatchUrl(item.url);
          final extractor = factory.getExtractorOrThrow(url);
          MediaInfo? media;
          List<StreamInfo> streams = [];
          for (var attempt = 0; attempt < 3; attempt++) {
            try {
              media = await extractor
                  .extractInfo(url)
                  .timeout(const Duration(seconds: 25));
              if (!current(item)) break;
              streams = await extractor
                  .getStreams(url)
                  .timeout(const Duration(seconds: 25));
              break;
            } catch (error) {
              if (attempt == 2 || !isTemporaryBatchFailure(error)) rethrow;
              await Future<void>.delayed(
                Duration(milliseconds: 400 * (attempt + 1)),
              );
              if (!current(item)) break;
            }
          }
          if (!current(item) || media == null) continue;
          final duplicate = state.items.any(
            (other) =>
                other.id != item.id &&
                other.media?.platform == media!.platform &&
                other.media?.id == media.id,
          );
          if (duplicate) {
            remove(item.id);
            continue;
          }
          if (current(item)) {
            _update(
              item.id,
              (i) => _select(
                i.copy(media: media, streams: streams),
                state.quality,
              ),
            );
          }
        } catch (e) {
          if (current(item)) {
            _update(
              item.id,
              (i) => i.copy(
                status: BatchItemStatus.failed,
                error: mediaErrorMessage(e),
              ),
            );
          }
        }
      }
    }

    await Future.wait(List.generate(work.length.clamp(0, 3), (_) => worker()));
    if (!_disposed) {
      _emit(state.items, checking: false);
      if (_pendingCheck) {
        _pendingCheck = false;
        _schedule();
      }
    }
  }

  @override
  void dispose() {
    unawaited(flushDraft());
    _disposed = true;
    _debounce?.cancel();
    _saveTimer?.cancel();
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }
}

bool isTemporaryBatchFailure(Object error) {
  if (error is SocketException || error is TimeoutException) return true;
  if (error is DioException) {
    final code = error.response?.statusCode;
    return error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        code == 429 ||
        (code != null && code >= 500);
  }
  final text = error.toString().toLowerCase();
  if ([
    'private',
    'removed',
    'not found',
    'unsupported',
    'invalid',
    'denied',
    '403',
    '404',
  ].any(text.contains)) {
    return false;
  }
  return [
    'network',
    'connection',
    'timed out',
    'timeout',
    'socket',
    'too many requests',
    '503',
    '502',
  ].any(text.contains);
}
