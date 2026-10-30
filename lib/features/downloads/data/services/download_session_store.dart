import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/utils/url_parser.dart';
import '../../../extractor/domain/entities/media_info.dart';
import '../../../extractor/domain/entities/stream_info.dart';
import '../../domain/entities/download_task.dart';
import '../../domain/enums/download_status.dart';

/// Restart checkpoints, separate from the authoritative completed-file registry.
class DownloadSessionStore {
  static const prefsKey = 'mediagrab_download_session_v1';
  Future<void> _writes = Future.value();

  Future<List<Map<String, dynamic>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> save(List<Map<String, dynamic>> entries) {
    final snapshot = jsonEncode(entries);
    final write = _writes.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, snapshot);
    });
    _writes = write.catchError((Object _) {});
    return write;
  }

  static Map<String, dynamic> streamJson(StreamInfo stream) => {
    'url': stream.url,
    'quality': stream.qualityLabel,
    'codec': stream.codec,
    'container': stream.container,
    'size': stream.sizeInBytes,
    'audioOnly': stream.isAudioOnly,
    'videoOnly': stream.isVideoOnly,
    'bitrate': stream.bitrate,
    'width': stream.videoWidth,
    'height': stream.videoHeight,
  };

  static StreamInfo readStream(Map<String, dynamic> json) => StreamInfo(
    url: json['url'] as String,
    qualityLabel: json['quality'] as String,
    codec: json['codec'] as String,
    container: json['container'] as String,
    sizeInBytes: json['size'] as int?,
    isAudioOnly: json['audioOnly'] as bool,
    isVideoOnly: json['videoOnly'] as bool,
    bitrate: json['bitrate'] as int?,
    videoWidth: json['width'] as int?,
    videoHeight: json['height'] as int?,
  );

  static Map<String, dynamic> taskJson(DownloadTask task) => {
    'id': task.id,
    'mediaId': task.mediaInfo.id,
    'title': task.mediaInfo.title,
    'thumbnail': task.mediaInfo.thumbnailUrl,
    'duration': task.mediaInfo.duration.inMilliseconds,
    'uploader': task.mediaInfo.uploader,
    'platform': task.mediaInfo.platform.name,
    'stream': streamJson(task.selectedStream),
    'status': task.status.name,
    'progress': task.progress,
    'path': task.filePath,
    'downloaded': task.downloadedBytes,
    'total': task.totalBytes,
    'createdAt': task.createdAt.toIso8601String(),
    'error': task.errorMessage,
  };

  static DownloadTask readTask(Map<String, dynamic> json) => DownloadTask(
    id: json['id'] as String,
    mediaInfo: MediaInfo(
      id: json['mediaId'] as String,
      title: json['title'] as String,
      thumbnailUrl: json['thumbnail'] as String,
      duration: Duration(milliseconds: json['duration'] as int),
      uploader: json['uploader'] as String,
      platform: PlatformType.values.byName(json['platform'] as String),
    ),
    selectedStream: readStream(json['stream'] as Map<String, dynamic>),
    status: DownloadStatus.values.byName(json['status'] as String),
    progress: (json['progress'] as num).toDouble(),
    filePath: json['path'] as String?,
    downloadedBytes: json['downloaded'] as int?,
    totalBytes: json['total'] as int?,
    speedBytesPerSecond: 0,
    createdAt: DateTime.parse(json['createdAt'] as String),
    errorMessage: json['error'] as String?,
  );
}
