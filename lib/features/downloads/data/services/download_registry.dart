import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/utils/file_utils.dart';
import '../../../../core/utils/url_parser.dart';
import '../../../extractor/domain/entities/media_info.dart';
import '../../../extractor/domain/entities/stream_info.dart';
import '../../domain/entities/download_task.dart';
import '../../domain/enums/download_status.dart';

/// Persistent record representing a completed MediaGrab download in the app-owned registry.
class DownloadRecord {
  final String id;
  final String originalUrl;
  final PlatformType platform;
  final String title;
  final String? thumbnailUrl;
  final String? thumbnailPath;
  final FileType mediaType;
  final String? qualityLabel;
  final String fileFormat;
  final int fileSize;
  final String filePath;
  final DateTime completedAt;
  final String status;
  final String? uploader;
  final Duration duration;
  final Map<String, dynamic> metadata;

  const DownloadRecord({
    required this.id,
    required this.originalUrl,
    required this.platform,
    required this.title,
    this.thumbnailUrl,
    this.thumbnailPath,
    required this.mediaType,
    this.qualityLabel,
    required this.fileFormat,
    required this.fileSize,
    required this.filePath,
    required this.completedAt,
    this.status = 'completed',
    this.uploader,
    this.duration = Duration.zero,
    this.metadata = const {},
  });

  /// Creates a [DownloadRecord] from an active or completed [DownloadTask].
  factory DownloadRecord.fromTask(DownloadTask task) {
    final filePath = task.filePath ?? '';
    final cleanPath = filePath.split('?').first.split('#').first;
    final dotIdx = cleanPath.lastIndexOf('.');
    final ext =
        dotIdx != -1 ? cleanPath.substring(dotIdx + 1).toLowerCase() : 'mp4';

    FileType mediaType;
    if (task.selectedStream.isAudioOnly) {
      mediaType = FileType.audio;
    } else {
      final detected = getFileType(filePath);
      mediaType = detected == FileType.other ? FileType.video : detected;
    }

    var cleanTitle = task.mediaInfo.title.trim();
    if (cleanTitle.contains('/') || cleanTitle.contains('\\')) {
      cleanTitle = cleanTitle.split(RegExp(r'[/\\]')).last.trim();
    }
    if (cleanTitle.isEmpty) {
      cleanTitle = 'MediaGrab Download';
    }

    final size =
        (task.totalBytes != null && task.totalBytes! > 0)
            ? task.totalBytes!
            : (task.downloadedBytes ?? 0);

    return DownloadRecord(
      id: task.id,
      originalUrl: task.selectedStream.url,
      platform: task.mediaInfo.platform,
      title: cleanTitle,
      thumbnailUrl: task.mediaInfo.thumbnailUrl,
      thumbnailPath: null,
      mediaType: mediaType,
      qualityLabel: task.selectedStream.qualityLabel,
      fileFormat: ext,
      fileSize: size,
      filePath: filePath,
      completedAt: task.completedAt ?? DateTime.now(),
      status: 'completed',
      uploader: task.mediaInfo.uploader,
      duration: task.mediaInfo.duration,
      metadata: {
        'codec': task.selectedStream.codec,
        'container': task.selectedStream.container,
        'width': task.selectedStream.videoWidth,
        'height': task.selectedStream.videoHeight,
      },
    );
  }

  /// Converts this [DownloadRecord] back into a completed [DownloadTask] for display.
  DownloadTask toTask() {
    return DownloadTask(
      id: id,
      mediaInfo: MediaInfo(
        id: id,
        title: title,
        thumbnailUrl: thumbnailUrl ?? '',
        platform: platform,
        uploader: uploader ?? 'Unknown',
        duration: duration,
      ),
      selectedStream: StreamInfo(
        url: originalUrl,
        qualityLabel: qualityLabel ?? '${fileSize ~/ 1024} KB',
        codec: (metadata['codec'] as String?) ?? fileFormat,
        container: (metadata['container'] as String?) ?? fileFormat,
        sizeInBytes: fileSize,
        isAudioOnly: mediaType == FileType.audio,
        isVideoOnly: false,
        videoWidth: metadata['width'] as int?,
        videoHeight: metadata['height'] as int?,
      ),
      filePath: filePath,
      status: DownloadStatus.completed,
      progress: 1.0,
      downloadedBytes: fileSize,
      totalBytes: fileSize,
      speedBytesPerSecond: 0.0,
      createdAt: completedAt,
      completedAt: completedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'originalUrl': originalUrl,
      'platform': platform.name,
      'title': title,
      'thumbnailUrl': thumbnailUrl,
      'thumbnailPath': thumbnailPath,
      'mediaType': mediaType.name,
      'qualityLabel': qualityLabel,
      'fileFormat': fileFormat,
      'fileSize': fileSize,
      'filePath': filePath,
      'completedAt': completedAt.toIso8601String(),
      'status': status,
      'uploader': uploader,
      'durationMs': duration.inMilliseconds,
      'metadata': metadata,
    };
  }

  factory DownloadRecord.fromJson(Map<String, dynamic> json) {
    PlatformType platform = PlatformType.unknown;
    try {
      final pName = json['platform'] as String?;
      if (pName != null) {
        platform = PlatformType.values.firstWhere(
          (p) => p.name.toLowerCase() == pName.toLowerCase(),
          orElse: () => PlatformType.unknown,
        );
      }
    } catch (_) {}

    FileType mediaType = FileType.video;
    try {
      final mName = json['mediaType'] as String?;
      if (mName != null) {
        mediaType = FileType.values.firstWhere(
          (m) => m.name.toLowerCase() == mName.toLowerCase(),
          orElse: () => FileType.video,
        );
      }
    } catch (_) {}

    DateTime completed = DateTime.now();
    try {
      final cStr = json['completedAt'] as String?;
      if (cStr != null) {
        completed = DateTime.parse(cStr);
      }
    } catch (_) {}

    Duration duration = Duration.zero;
    try {
      final dMs = json['durationMs'] as int?;
      if (dMs != null) {
        duration = Duration(milliseconds: dMs);
      }
    } catch (_) {}

    return DownloadRecord(
      id: json['id'] as String? ?? '',
      originalUrl: json['originalUrl'] as String? ?? '',
      platform: platform,
      title: json['title'] as String? ?? 'Untitled',
      thumbnailUrl: json['thumbnailUrl'] as String?,
      thumbnailPath: json['thumbnailPath'] as String?,
      mediaType: mediaType,
      qualityLabel: json['qualityLabel'] as String?,
      fileFormat: json['fileFormat'] as String? ?? 'mp4',
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      filePath: json['filePath'] as String? ?? '',
      completedAt: completed,
      status: json['status'] as String? ?? 'completed',
      uploader: json['uploader'] as String?,
      duration: duration,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
    );
  }
}

/// Authoritative, persistent registry of all downloads completed within MediaGrab.
///
/// Prevents the Library from acting like a general-purpose Android gallery or scanning
/// the device's shared folders.
class DownloadRegistry {
  static const String prefsKey = 'mediagrab_download_registry_v1';
  static const String registryFileName = 'mediagrab_registry.json';

  final SharedPreferences? _prefs;
  final Map<String, DownloadRecord> _cache = {};
  bool _initialized = false;
  Future<void>? _initializing;
  Future<void> _pendingWrite = Future.value();

  DownloadRegistry({SharedPreferences? prefs}) : _prefs = prefs;

  /// Initializes the registry from persistent storage.
  Future<void> init() {
    if (_initialized) return Future.value();
    return _initializing ??= _load();
  }

  Future<void> _load() async {
    var loadedPreferences = false;

    // 1. Load from SharedPreferences
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(prefsKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        loadedPreferences = true;
        final List<dynamic> list = json.decode(jsonStr);
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final record = DownloadRecord.fromJson(item);
            if (record.id.isNotEmpty) {
              _cache[record.id] = record;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('DownloadRegistry: Error loading from SharedPreferences: $e');
    }

    // 2. Fallback / Merge from documents file
    try {
      if (!loadedPreferences &&
          !Platform.environment.containsKey('FLUTTER_TEST')) {
        final docDir = await getApplicationDocumentsDirectory();
        final file = File('${docDir.path}/$registryFileName');
        if (await file.exists()) {
          final fileContent = await file.readAsString();
          final List<dynamic> list = json.decode(fileContent);
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final record = DownloadRecord.fromJson(item);
              if (record.id.isNotEmpty && !_cache.containsKey(record.id)) {
                _cache[record.id] = record;
              }
            }
          }
        }
      }
    } catch (_) {}

    _initialized = true;
  }

  /// Registers a newly completed download task.
  Future<void> register(DownloadRecord record) async {
    await init();
    _cache[record.id] = record;
    await _persist();
  }

  /// Removes a record from the registry (e.g. after deletion).
  Future<void> remove(String id) async {
    await init();
    if (_cache.remove(id) != null) {
      await _persist();
    }
  }

  /// Clears all records from the registry.
  Future<void> clear() async {
    await init();
    _cache.clear();
    await _persist();
  }

  /// Returns all registered completed records.
  ///
  /// If [verifyFileExists] is true, checks `File(record.filePath).existsSync()`
  /// and excludes any records whose physical files were deleted or moved externally.
  Future<List<DownloadRecord>> getCompletedRecords({
    bool verifyFileExists = true,
  }) async {
    await init();
    final records = _cache.values.toList();
    if (!verifyFileExists) return records;

    final valid = <DownloadRecord>[];
    for (final r in records) {
      if (r.filePath.isEmpty || r.status != 'completed') continue;
      try {
        final f = File(r.filePath);
        final stat = await f.stat();
        if (stat.type == FileSystemEntityType.file && stat.size > 0) {
          valid.add(r);
        }
      } catch (_) {}
    }
    return valid;
  }

  /// Calculates total size in bytes occupied by registered MediaGrab files that exist on disk.
  Future<int> getTotalStorageBytes() async {
    final records = await getCompletedRecords(verifyFileExists: true);
    return records.fold<int>(0, (sum, r) => sum + r.fileSize);
  }

  /// Calculates total count of registered MediaGrab files that exist on disk.
  Future<int> getCompletedCount() async {
    final records = await getCompletedRecords(verifyFileExists: true);
    return records.length;
  }

  /// Persists current in-memory cache to SharedPreferences and local JSON file.
  Future<void> _persist() {
    // Serialize writes so an older snapshot cannot overwrite a later deletion.
    final write = _pendingWrite.then((_) => _writeSnapshot());
    _pendingWrite = write.catchError((Object _) {});
    return write;
  }

  Future<void> _writeSnapshot() async {
    final recordsList = _cache.values.map((r) => r.toJson()).toList();
    final jsonStr = json.encode(recordsList);

    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, jsonStr);
    } catch (e) {
      debugPrint('DownloadRegistry: Error writing to SharedPreferences: $e');
    }

    try {
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        final docDir = await getApplicationDocumentsDirectory();
        final file = File('${docDir.path}/$registryFileName');
        await file.writeAsString(jsonStr, flush: true);
      }
    } catch (_) {}
  }
}

/// Riverpod provider for the singleton [DownloadRegistry].
final downloadRegistryProvider = Provider<DownloadRegistry>((ref) {
  return DownloadRegistry();
});
