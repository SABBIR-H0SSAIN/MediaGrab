import 'package:equatable/equatable.dart';
import '../../../extractor/domain/entities/media_info.dart';
import '../../../extractor/domain/entities/stream_info.dart';
import '../enums/download_status.dart';

/// Immutable entity representing a media download task and its execution state.
class DownloadTask extends Equatable {
  final String id;
  final MediaInfo mediaInfo;
  final StreamInfo selectedStream;
  final DownloadStatus status;
  final double progress;
  final String? filePath;
  final int? downloadedBytes;
  final int? totalBytes;
  final double? speedBytesPerSecond;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? errorMessage;

  const DownloadTask({
    required this.id,
    required this.mediaInfo,
    required this.selectedStream,
    required this.status,
    this.progress = 0.0,
    this.filePath,
    this.downloadedBytes,
    this.totalBytes,
    this.speedBytesPerSecond,
    required this.createdAt,
    this.completedAt,
    this.errorMessage,
  });

  /// Formatted download speed string, e.g. "1.2 MB/s" or "350 KB/s".
  String get formattedSpeed {
    if (speedBytesPerSecond == null || speedBytesPerSecond! <= 0) {
      return '';
    }
    final speed = speedBytesPerSecond!;
    if (speed >= 1024 * 1024) {
      return '${(speed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    } else {
      return '${(speed / 1024).toStringAsFixed(0)} KB/s';
    }
  }

  /// Estimated time remaining formatted as "Xm Xs remaining", or empty string if unknown.
  String get formattedEta {
    if (speedBytesPerSecond == null || speedBytesPerSecond! <= 0) {
      return '';
    }
    final remBytes = _remainingBytes;
    if (remBytes == null || remBytes <= 0) {
      return '';
    }

    final totalSeconds = (remBytes / speedBytesPerSecond!).round();
    if (totalSeconds <= 0) {
      return '0s remaining';
    }
    if (totalSeconds < 60) {
      return '${totalSeconds}s remaining';
    }

    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes < 60) {
      return '${minutes}m ${seconds}s remaining';
    }

    final hours = minutes ~/ 60;
    final remMinutes = minutes % 60;
    return '${hours}h ${remMinutes}m remaining';
  }

  int? get _remainingBytes {
    if (totalBytes != null && downloadedBytes != null) {
      return totalBytes! - downloadedBytes!;
    }
    if (totalBytes != null) {
      return (totalBytes! * (1.0 - progress.clamp(0.0, 1.0))).round();
    }
    return null;
  }

  /// Formatted percentage progress, e.g. "45.0%".
  String get formattedProgress {
    final pct = (progress * 100).clamp(0.0, 100.0);
    return '${pct.toStringAsFixed(1)}%';
  }

  DownloadTask copyWith({
    String? id,
    MediaInfo? mediaInfo,
    StreamInfo? selectedStream,
    DownloadStatus? status,
    double? progress,
    String? filePath,
    int? downloadedBytes,
    int? totalBytes,
    double? speedBytesPerSecond,
    DateTime? createdAt,
    DateTime? completedAt,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool clearCompletedAt = false,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      mediaInfo: mediaInfo ?? this.mediaInfo,
      selectedStream: selectedStream ?? this.selectedStream,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      filePath: filePath ?? this.filePath,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      speedBytesPerSecond: speedBytesPerSecond ?? this.speedBytesPerSecond,
      createdAt: createdAt ?? this.createdAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
    id,
    mediaInfo,
    selectedStream,
    status,
    progress,
    filePath,
    downloadedBytes,
    totalBytes,
    speedBytesPerSecond,
    createdAt,
    completedAt,
    errorMessage,
  ];
}
