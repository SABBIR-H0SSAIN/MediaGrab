import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/downloads/domain/enums/download_status.dart';

void main() {
  group('DownloadStatus Enum', () {
    test('contains all expected status values', () {
      expect(DownloadStatus.values, [
        DownloadStatus.queued,
        DownloadStatus.downloading,
        DownloadStatus.merging,
        DownloadStatus.converting,
        DownloadStatus.paused,
        DownloadStatus.completed,
        DownloadStatus.failed,
        DownloadStatus.cancelled,
      ]);
    });

    test('isActive returns true for downloading, merging, converting', () {
      expect(DownloadStatus.downloading.isActive, isTrue);
      expect(DownloadStatus.merging.isActive, isTrue);
      expect(DownloadStatus.converting.isActive, isTrue);

      expect(DownloadStatus.queued.isActive, isFalse);
      expect(DownloadStatus.paused.isActive, isFalse);
      expect(DownloadStatus.completed.isActive, isFalse);
      expect(DownloadStatus.failed.isActive, isFalse);
      expect(DownloadStatus.cancelled.isActive, isFalse);
    });

    test('individual status flags return expected booleans', () {
      expect(DownloadStatus.queued.isQueued, isTrue);
      expect(DownloadStatus.downloading.isQueued, isFalse);

      expect(DownloadStatus.paused.isPaused, isTrue);
      expect(DownloadStatus.downloading.isPaused, isFalse);

      expect(DownloadStatus.completed.isCompleted, isTrue);
      expect(DownloadStatus.failed.isCompleted, isFalse);

      expect(DownloadStatus.failed.isFailed, isTrue);
      expect(DownloadStatus.completed.isFailed, isFalse);

      expect(DownloadStatus.cancelled.isCancelled, isTrue);
      expect(DownloadStatus.downloading.isCancelled, isFalse);
    });

    test('displayName returns formatted string for each status', () {
      expect(DownloadStatus.queued.displayName, 'Queued');
      expect(DownloadStatus.downloading.displayName, 'Downloading');
      expect(DownloadStatus.merging.displayName, 'Merging...');
      expect(DownloadStatus.converting.displayName, 'Converting...');
      expect(DownloadStatus.paused.displayName, 'Paused');
      expect(DownloadStatus.completed.displayName, 'Completed');
      expect(DownloadStatus.failed.displayName, 'Failed');
      expect(DownloadStatus.cancelled.displayName, 'Cancelled');
    });
  });
}
