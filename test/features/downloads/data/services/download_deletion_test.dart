import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediagrab/core/utils/file_utils.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/downloads/data/services/download_engine.dart';
import 'package:mediagrab/features/downloads/data/services/download_registry.dart';
import 'package:mediagrab/features/library/presentation/providers/library_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late DownloadRegistry registry;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    registry = DownloadRegistry(prefs: await SharedPreferences.getInstance());
    directory = await Directory.systemTemp.createTemp('mediagrab_deletion_');
  });
  tearDown(() => directory.delete(recursive: true));

  Future<void> register(String path) => registry.register(
    DownloadRecord(
      id: 'saved',
      originalUrl: 'https://example.com/video',
      platform: PlatformType.facebook,
      title: 'Saved video',
      mediaType: FileType.video,
      fileFormat: 'mp4',
      fileSize: 3,
      filePath: path,
      completedAt: DateTime.now(),
    ),
  );
  DownloadEngine engine() => DownloadEngine(
    downloadRegistry: registry,
    customDownloadExecution:
        ({
          required task,
          required stream,
          required targetPath,
          required onProgress,
          required onComplete,
          required onError,
        }) async {},
  );

  test(
    'registry-only download deletes storage and stays deleted after restart',
    () async {
      final file = await File(
        '${directory.path}/video.mp4',
      ).writeAsBytes([1, 2, 3]);
      await register(file.path);
      final downloader = engine();
      addTearDown(downloader.dispose);
      await downloader.removeTask('saved', deleteFile: true);
      expect(await file.exists(), isFalse);
      final restored = DownloadRegistry(
        prefs: await SharedPreferences.getInstance(),
      );
      expect(
        await restored.getCompletedRecords(verifyFileExists: false),
        isEmpty,
      );
    },
  );

  test('failed storage deletion preserves engine and registry records', () async {
    // A directory cannot be deleted with File.delete: deterministic I/O failure.
    await register(directory.path);
    final downloader = engine();
    addTearDown(downloader.dispose);
    await expectLater(
      downloader.removeTask('saved', deleteFile: true),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      await registry.getCompletedRecords(verifyFileExists: false),
      hasLength(1),
    );
  });

  test('library deletes physical media before removing its record', () async {
    final file = await File(
      '${directory.path}/video.webm',
    ).writeAsBytes([1, 2, 3]);
    await register(file.path);
    final library = LibraryNotifier([], null, registry);
    addTearDown(library.dispose);
    await library.refresh();
    await library.removeItem('saved', deletePhysicalFile: true);
    expect(await file.exists(), isFalse);
    expect(library.state, isEmpty);
    expect(
      await registry.getCompletedRecords(verifyFileExists: false),
      isEmpty,
    );
  });

  test('library retains item when physical deletion fails', () async {
    await register(directory.path);
    final library = LibraryNotifier(
      [
        LibraryMediaItem(
          id: 'saved',
          title: 'Saved video',
          filePath: directory.path,
          fileSize: 3,
          fileType: FileType.video,
          downloadedAt: DateTime.now(),
        ),
      ],
      null,
      registry,
    );
    addTearDown(library.dispose);
    await expectLater(
      library.removeItem('saved', deletePhysicalFile: true),
      throwsA(isA<FileSystemException>()),
    );
    expect(library.state, hasLength(1));
    expect(
      await registry.getCompletedRecords(verifyFileExists: false),
      hasLength(1),
    );
  });
}
