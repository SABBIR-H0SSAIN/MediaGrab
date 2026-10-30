import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/file_utils.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/downloads/data/services/download_registry.dart';
import 'package:mediagrab/features/downloads/domain/entities/download_task.dart';
import 'package:mediagrab/features/downloads/domain/enums/download_status.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('mediagrab_registry_test_');
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('DownloadRecord', () {
    test('creates DownloadRecord from DownloadTask correctly', () {
      final task = DownloadTask(
        id: 'task_1',
        mediaInfo: const MediaInfo(
          id: 'vid_1',
          title: 'Test Video',
          thumbnailUrl: 'https://example.com/thumb.jpg',
          platform: PlatformType.youtube,
          uploader: 'Test Channel',
          duration: Duration(minutes: 5),
        ),
        selectedStream: const StreamInfo(
          url: 'https://example.com/stream.mp4',
          qualityLabel: '1080p',
          codec: 'avc1',
          container: 'mp4',
          sizeInBytes: 15000000,
          isAudioOnly: false,
          isVideoOnly: false,
          videoWidth: 1920,
          videoHeight: 1080,
        ),
        filePath: '/tmp/test_video.mp4',
        status: DownloadStatus.completed,
        progress: 1.0,
        downloadedBytes: 15000000,
        totalBytes: 15000000,
        createdAt: DateTime(2026, 1, 1),
        completedAt: DateTime(2026, 1, 1, 0, 5),
      );

      final record = DownloadRecord.fromTask(task);

      expect(record.id, 'task_1');
      expect(record.title, 'Test Video');
      expect(record.platform, PlatformType.youtube);
      expect(record.fileSize, 15000000);
      expect(record.filePath, '/tmp/test_video.mp4');
      expect(record.fileFormat, 'mp4');
      expect(record.mediaType, FileType.video);
      expect(record.qualityLabel, '1080p');

      final taskRestored = record.toTask();
      expect(taskRestored.id, 'task_1');
      expect(taskRestored.status, DownloadStatus.completed);
      expect(taskRestored.progress, 1.0);
      expect(taskRestored.filePath, '/tmp/test_video.mp4');
    });

    test('serializes to and from JSON', () {
      final record = DownloadRecord(
        id: 'rec_1',
        originalUrl: 'https://example.com/video',
        platform: PlatformType.facebook,
        title: 'FB Video',
        mediaType: FileType.video,
        fileFormat: 'mp4',
        fileSize: 5000000,
        filePath: '/tmp/fb.mp4',
        completedAt: DateTime(2026, 2, 1),
      );

      final json = record.toJson();
      final fromJson = DownloadRecord.fromJson(json);

      expect(fromJson.id, 'rec_1');
      expect(fromJson.platform, PlatformType.facebook);
      expect(fromJson.title, 'FB Video');
      expect(fromJson.fileSize, 5000000);
    });
  });

  group('DownloadRegistry Persistence', () {
    test(
      'concurrent registration and deletion persist the latest registry',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final registry = DownloadRegistry(prefs: prefs);
        DownloadRecord record(String id) => DownloadRecord(
          id: id,
          originalUrl: 'https://example.com/$id',
          platform: PlatformType.youtube,
          title: id,
          mediaType: FileType.video,
          fileFormat: 'mp4',
          fileSize: 1,
          filePath: '${tempDir.path}/$id.mp4',
          completedAt: DateTime(2026),
        );
        await Future.wait([
          registry.register(record('first')),
          registry.register(record('second')),
        ]);
        await Future.wait([
          registry.remove('first'),
          registry.register(record('third')),
        ]);
        final restored = DownloadRegistry(prefs: prefs);
        final records = await restored.getCompletedRecords(
          verifyFileExists: false,
        );
        expect(records.map((r) => r.id).toSet(), {'second', 'third'});
      },
    );

    test('registers and retrieves completed records', () async {
      final prefs = await SharedPreferences.getInstance();
      final registry = DownloadRegistry(prefs: prefs);
      await registry.init();

      // Create dummy file
      final file = File('${tempDir.path}/media1.mp4');
      await file.writeAsString('test media content');

      final record = DownloadRecord(
        id: 'reg_test_1',
        originalUrl: 'https://youtube.com/watch?v=123',
        platform: PlatformType.youtube,
        title: 'Registry Video 1',
        mediaType: FileType.video,
        fileFormat: 'mp4',
        fileSize: await file.length(),
        filePath: file.path,
        completedAt: DateTime.now(),
      );

      await registry.register(record);

      final allRecords = await registry.getCompletedRecords(
        verifyFileExists: false,
      );
      expect(allRecords.length, 1);
      expect(allRecords.first.id, 'reg_test_1');
      expect(await registry.getCompletedCount(), 1);
      expect(await registry.getTotalStorageBytes(), await file.length());

      // Test with verifyFileExists: true
      final verifiedRecords = await registry.getCompletedRecords(
        verifyFileExists: true,
      );
      expect(verifiedRecords.length, 1);

      // Delete the file from filesystem
      await file.delete();

      // Should now filter out the missing file when verifyFileExists: true
      final missingFiltered = await registry.getCompletedRecords(
        verifyFileExists: true,
      );
      expect(missingFiltered, isEmpty);
    });

    test('removes records from registry and persists deletion', () async {
      final prefs = await SharedPreferences.getInstance();
      final registry = DownloadRegistry(prefs: prefs);
      await registry.init();

      final file = File('${tempDir.path}/to_remove.mp4');
      await file.writeAsString('temp');

      final record1 = DownloadRecord(
        id: 'to_remove',
        originalUrl: 'https://youtube.com',
        platform: PlatformType.youtube,
        title: 'To Remove',
        mediaType: FileType.video,
        fileFormat: 'mp4',
        fileSize: 1000,
        filePath: file.path,
        completedAt: DateTime.now(),
      );

      await registry.register(record1);
      expect((await registry.getCompletedRecords()).length, 1);

      await registry.remove('to_remove');
      expect((await registry.getCompletedRecords()), isEmpty);

      // Re-init new registry instance from same prefs
      final registry2 = DownloadRegistry(prefs: prefs);
      await registry2.init();
      expect((await registry2.getCompletedRecords()), isEmpty);
    });
  });
}
