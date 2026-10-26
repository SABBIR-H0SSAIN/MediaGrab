/// Represents the lifecycle state of a download task.
enum DownloadStatus {
  queued,
  downloading,
  merging,
  converting,
  paused,
  completed,
  failed,
  cancelled;

  /// Whether this task is actively processing (downloading, merging, or converting).
  bool get isActive =>
      this == DownloadStatus.downloading ||
      this == DownloadStatus.merging ||
      this == DownloadStatus.converting;

  /// Whether this task is queued and waiting for an open concurrency slot.
  bool get isQueued => this == DownloadStatus.queued;

  /// Whether this task is currently paused.
  bool get isPaused => this == DownloadStatus.paused;

  /// Whether this task has successfully finished.
  bool get isCompleted => this == DownloadStatus.completed;

  /// Whether this task encountered an error.
  bool get isFailed => this == DownloadStatus.failed;

  /// Whether this task was cancelled by the user.
  bool get isCancelled => this == DownloadStatus.cancelled;

  /// Human-readable display label for the status.
  String get displayName {
    switch (this) {
      case DownloadStatus.queued:
        return 'Queued';
      case DownloadStatus.downloading:
        return 'Downloading';
      case DownloadStatus.merging:
        return 'Merging...';
      case DownloadStatus.converting:
        return 'Converting...';
      case DownloadStatus.paused:
        return 'Paused';
      case DownloadStatus.completed:
        return 'Completed';
      case DownloadStatus.failed:
        return 'Failed';
      case DownloadStatus.cancelled:
        return 'Cancelled';
    }
  }
}
