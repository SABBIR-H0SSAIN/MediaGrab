import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/downloads/domain/entities/download_task.dart';
import 'package:mediagrab/features/downloads/domain/enums/download_status.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';

void main() {
  group('DownloadTask Entity', () {
    const testMediaInfo = MediaInfo(
      id: 'abc12345678',
      title: 'Flutter Crash Course',
      thumbnailUrl: 'https://example.com/thumb.jpg',
      duration: Duration(minutes: 10),
      uploader: 'Tech Channel',
      platform: PlatformType.youtube,
    );

    const testStreamInfo = StreamInfo(
      url: 'https://example.com/stream.mp4',
      qualityLabel: '1080p',
      codec: 'avc1',
      container: 'mp4',
      sizeInBytes: 104857600, // 100 MB
    );

    final now = DateTime(2026, 1, 1, 12, 0);

    test('supports value equality via Equatable', () {
      final task1 = DownloadTask(
        id: 'task-1',
        mediaInfo: testMediaInfo,
        selectedStream: testStreamInfo,
        status: DownloadStatus.downloading,
        progress: 0.5,
        createdAt: now,
      );

      final task2 = DownloadTask(
        id: 'task-1',
        mediaInfo: testMediaInfo,
        selectedStream: testStreamInfo,
        status: DownloadStatus.downloading,
        progress: 0.5,
        createdAt: now,
      );

      expect(task1, equals(task2));
    });

    test('copyWith updates properties while preserving others', () {
      final task = DownloadTask(
        id: 'task-1',
        mediaInfo: testMediaInfo,
        selectedStream: testStreamInfo,
        status: DownloadStatus.queued,
        createdAt: now,
      );

      final updated = task.copyWith(
        status: DownloadStatus.downloading,
        progress: 0.25,
        downloadedBytes: 25000000,
        speedBytesPerSecond: 1048576, // 1 MB/s
      );

      expect(updated.id, 'task-1');
      expect(updated.status, DownloadStatus.downloading);
      expect(updated.progress, 0.25);
      expect(updated.downloadedBytes, 25000000);
      expect(updated.speedBytesPerSecond, 1048576);
      expect(updated.createdAt, now);
    });

    test('formattedSpeed formats speed correctly', () {
      final taskNoSpeed = DownloadTask(
        id: 'task-1',
        mediaInfo: testMediaInfo,
        selectedStream: testStreamInfo,
        status: DownloadStatus.downloading,
        createdAt: now,
      );
      expect(taskNoSpeed.formattedSpeed, '');

      final taskKbSpeed = taskNoSpeed.copyWith(
        speedBytesPerSecond: 512 * 1024, // 512 KB/s
      );
      expect(taskKbSpeed.formattedSpeed, '512 KB/s');

      final taskMbSpeed = taskNoSpeed.copyWith(
        speedBytesPerSecond: 2.5 * 1024 * 1024, // 2.5 MB/s
      );
      expect(taskMbSpeed.formattedSpeed, '2.5 MB/s');
    });

    test('formattedEta formats remaining time correctly', () {
      final taskNoEta = DownloadTask(
        id: 'task-1',
        mediaInfo: testMediaInfo,
        selectedStream: testStreamInfo,
        status: DownloadStatus.downloading,
        createdAt: now,
      );
      expect(taskNoEta.formattedEta, '');

      // 100 MB total, 50 MB downloaded, 50 MB remaining at 25 MB/s -> 2 seconds
      final taskSeconds = taskNoEta.copyWith(
        totalBytes: 100 * 1024 * 1024,
        downloadedBytes: 50 * 1024 * 1024,
        speedBytesPerSecond: 25 * 1024 * 1024,
      );
      expect(taskSeconds.formattedEta, '2s remaining');

      // 100 MB remaining at 1 MB/s -> 100 seconds (1m 40s)
      final taskMinutes = taskNoEta.copyWith(
        totalBytes: 100 * 1024 * 1024,
        downloadedBytes: 0,
        speedBytesPerSecond: 1 * 1024 * 1024,
      );
      expect(taskMinutes.formattedEta, '1m 40s remaining');

      // 3700 seconds remaining -> 1h 1m
      final taskHours = taskNoEta.copyWith(
        totalBytes: 3700 * 1024 * 1024,
        downloadedBytes: 0,
        speedBytesPerSecond: 1 * 1024 * 1024,
      );
      expect(taskHours.formattedEta, '1h 1m remaining');
    });

    test('formattedProgress formats percentage correctly', () {
      final task = DownloadTask(
        id: 'task-1',
        mediaInfo: testMediaInfo,
        selectedStream: testStreamInfo,
        status: DownloadStatus.downloading,
        progress: 0.456,
        createdAt: now,
      );
      expect(task.formattedProgress, '45.6%');
    });
  });
}
