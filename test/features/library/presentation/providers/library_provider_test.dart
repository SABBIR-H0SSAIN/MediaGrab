import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediagrab/features/downloads/data/services/download_registry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/file_utils.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/downloads/domain/entities/download_task.dart';
import 'package:mediagrab/features/downloads/domain/enums/download_status.dart';
import 'package:mediagrab/features/downloads/presentation/providers/download_manager_provider.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';
import 'package:mediagrab/features/library/presentation/providers/library_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'registry refresh removes media after its physical file is deleted',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final registry = DownloadRegistry(prefs: prefs);
      final tempDir = await Directory.systemTemp.createTemp(
        'registry_refresh_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final file = await File(
        '${tempDir.path}/download.mp4',
      ).writeAsBytes([1, 2]);
      await registry.register(
        DownloadRecord(
          id: 'owned',
          originalUrl: 'https://example.com/video',
          platform: PlatformType.youtube,
          title: 'Owned download',
          mediaType: FileType.video,
          fileFormat: 'mp4',
          fileSize: 2,
          filePath: file.path,
          completedAt: DateTime.now(),
        ),
      );
      final notifier = LibraryNotifier([], null, registry);
      addTearDown(notifier.dispose);
      await notifier.refresh();
      expect(notifier.state.single.id, 'owned');
      await file.delete();
      await notifier.refresh();
      expect(notifier.state, isEmpty);
    },
  );

  final sampleVideo = LibraryMediaItem(
    id: 'vid-1',
    title: 'Flutter in 100 Seconds',
    filePath: '/storage/downloads/flutter.mp4',
    fileSize: 15 * 1024 * 1024, // 15 MB
    fileType: FileType.video,
    duration: const Duration(minutes: 1, seconds: 40),
    thumbnailUrl: 'https://img.youtube.com/vi/sample/maxresdefault.jpg',
    platform: PlatformType.youtube,
    downloadedAt: DateTime(2026, 1, 1),
    qualityLabel: '1080p',
    uploader: 'Fireship',
  );

  final sampleAudio = LibraryMediaItem(
    id: 'aud-1',
    title: 'Lo-Fi Chill Beat',
    filePath: '/storage/downloads/lofi.mp3',
    fileSize: 5 * 1024 * 1024, // 5 MB
    fileType: FileType.audio,
    duration: const Duration(minutes: 3, seconds: 20),
    thumbnailUrl: null,
    platform: PlatformType.youtube,
    downloadedAt: DateTime(2026, 1, 2),
    qualityLabel: '320kbps',
    uploader: 'Lofi Girl',
  );

  final sampleFacebookVideo = LibraryMediaItem(
    id: 'fb-1',
    title: 'Facebook Viral Reel',
    filePath: '/storage/downloads/facebook_reel.mp4',
    fileSize: 30 * 1024 * 1024, // 30 MB
    fileType: FileType.video,
    duration: const Duration(minutes: 0, seconds: 45),
    thumbnailUrl: 'https://facebook.com/reel/sample.jpg',
    platform: PlatformType.facebook,
    downloadedAt: DateTime(2026, 1, 3),
    qualityLabel: '720p',
    uploader: 'Meta Creator',
  );

  final sampleInstagramVideo = LibraryMediaItem(
    id: 'ig-1',
    title: 'Instagram Travel Reel',
    filePath: '/storage/downloads/insta_reel.mp4',
    fileSize: 8 * 1024 * 1024, // 8 MB
    fileType: FileType.video,
    duration: const Duration(minutes: 0, seconds: 30),
    thumbnailUrl: 'https://instagram.com/reel/sample.jpg',
    platform: PlatformType.instagram,
    downloadedAt: DateTime(2026, 1, 4),
    qualityLabel: '1080p',
    uploader: 'Traveler',
  );

  group('LibraryMediaItem', () {
    test('formatted getters return expected values', () {
      expect(sampleVideo.formattedSize, '15 MB');
      expect(sampleVideo.formattedDuration, '1:40');
      expect(sampleAudio.formattedSize, '5 MB');
      expect(sampleAudio.formattedDuration, '3:20');
      expect(sampleVideo.formatPill, '1080p • MP4');
      expect(sampleAudio.formatPill, '320kbps • MP3');
    });

    test('matchesFilter works correctly across media types and platforms', () {
      expect(sampleVideo.matchesFilter(LibraryFilter.all), isTrue);
      expect(sampleVideo.matchesFilter(LibraryFilter.videos), isTrue);
      expect(sampleVideo.matchesFilter(LibraryFilter.audio), isFalse);
      expect(sampleVideo.matchesFilter(LibraryFilter.youtube), isTrue);
      expect(sampleVideo.matchesFilter(LibraryFilter.facebook), isFalse);
      expect(sampleVideo.matchesFilter(LibraryFilter.instagram), isFalse);

      expect(sampleAudio.matchesFilter(LibraryFilter.all), isTrue);
      expect(sampleAudio.matchesFilter(LibraryFilter.videos), isFalse);
      expect(sampleAudio.matchesFilter(LibraryFilter.audio), isTrue);
      expect(sampleAudio.matchesFilter(LibraryFilter.youtube), isTrue);

      expect(sampleFacebookVideo.matchesFilter(LibraryFilter.all), isTrue);
      expect(sampleFacebookVideo.matchesFilter(LibraryFilter.videos), isTrue);
      expect(sampleFacebookVideo.matchesFilter(LibraryFilter.facebook), isTrue);
      expect(sampleFacebookVideo.matchesFilter(LibraryFilter.youtube), isFalse);

      expect(sampleInstagramVideo.matchesFilter(LibraryFilter.all), isTrue);
      expect(sampleInstagramVideo.matchesFilter(LibraryFilter.videos), isTrue);
      expect(
        sampleInstagramVideo.matchesFilter(LibraryFilter.instagram),
        isTrue,
      );
      expect(
        sampleInstagramVideo.matchesFilter(LibraryFilter.facebook),
        isFalse,
      );
    });
  });

  group('Library Providers', () {
    test('initial state is empty with default settings', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(libraryProvider), isEmpty);
      expect(container.read(totalDownloadsCountProvider), 0);
      expect(container.read(totalStorageBytesProvider), 0);
      expect(container.read(formattedTotalStorageProvider), '0 B');
      expect(container.read(libraryFilterProvider), LibraryFilter.all);
      expect(container.read(librarySearchQueryProvider), '');
      expect(container.read(librarySortProvider), LibrarySort.newest);
      expect(container.read(libraryViewModeProvider), LibraryViewMode.grid);
      expect(container.read(filteredLibraryProvider), isEmpty);
    });

    test('adding and removing items updates state and storage stats', () async {
      final container = ProviderContainer(
        overrides: [libraryProvider.overrideWith((ref) => LibraryNotifier([]))],
      );
      addTearDown(container.dispose);

      final notifier = container.read(libraryProvider.notifier);
      notifier.addItem(sampleVideo);
      notifier.addItem(sampleAudio);

      expect(container.read(libraryProvider).length, 2);
      expect(container.read(totalDownloadsCountProvider), 2);
      expect(container.read(totalStorageBytesProvider), 20 * 1024 * 1024);
      expect(container.read(formattedTotalStorageProvider), '20 MB');

      await notifier.removeItem('vid-1');
      expect(container.read(libraryProvider).length, 1);
      expect(container.read(totalDownloadsCountProvider), 1);
      expect(container.read(totalStorageBytesProvider), 5 * 1024 * 1024);
      expect(container.read(formattedTotalStorageProvider), '5 MB');
    });

    test('filtering library items by category and platform', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(libraryProvider.notifier);
      notifier.addItem(sampleVideo);
      notifier.addItem(sampleAudio);
      notifier.addItem(sampleFacebookVideo);
      notifier.addItem(sampleInstagramVideo);

      // Default: All
      expect(container.read(filteredLibraryProvider).length, 4);

      // Filter: Videos
      container.read(libraryFilterProvider.notifier).state =
          LibraryFilter.videos;
      final videos = container.read(filteredLibraryProvider);
      expect(videos.length, 3);

      // Filter: Audio
      container.read(libraryFilterProvider.notifier).state =
          LibraryFilter.audio;
      final audioList = container.read(filteredLibraryProvider);
      expect(audioList.length, 1);
      expect(audioList.first.id, 'aud-1');

      // Filter: YouTube
      container.read(libraryFilterProvider.notifier).state =
          LibraryFilter.youtube;
      final youtubeItems = container.read(filteredLibraryProvider);
      expect(youtubeItems.length, 2);

      // Filter: Facebook
      container.read(libraryFilterProvider.notifier).state =
          LibraryFilter.facebook;
      final fbItems = container.read(filteredLibraryProvider);
      expect(fbItems.length, 1);
      expect(fbItems.first.id, 'fb-1');

      // Filter: Instagram
      container.read(libraryFilterProvider.notifier).state =
          LibraryFilter.instagram;
      final igItems = container.read(filteredLibraryProvider);
      expect(igItems.length, 1);
      expect(igItems.first.id, 'ig-1');
    });

    test('search query filters by title and uploader', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(libraryProvider.notifier);
      notifier.addItem(sampleVideo);
      notifier.addItem(sampleAudio);
      notifier.addItem(sampleFacebookVideo);

      // Query by title substring
      container.read(librarySearchQueryProvider.notifier).state = 'flutter';
      var filtered = container.read(filteredLibraryProvider);
      expect(filtered.length, 1);
      expect(filtered.first.id, 'vid-1');

      // Query by uploader
      container.read(librarySearchQueryProvider.notifier).state = 'lofi';
      filtered = container.read(filteredLibraryProvider);
      expect(filtered.length, 1);
      expect(filtered.first.id, 'aud-1');

      // No match
      container.read(librarySearchQueryProvider.notifier).state = 'nonexistent';
      filtered = container.read(filteredLibraryProvider);
      expect(filtered, isEmpty);
    });

    test('sorting items works by newest, oldest, largest, and name', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(libraryProvider.notifier);
      notifier.addItem(sampleVideo); // 15 MB, Jan 1
      notifier.addItem(sampleAudio); // 5 MB, Jan 2
      notifier.addItem(sampleFacebookVideo); // 30 MB, Jan 3

      // Sort by newest
      container.read(librarySortProvider.notifier).state = LibrarySort.newest;
      var sorted = container.read(filteredLibraryProvider);
      expect(sorted.first.id, 'fb-1');

      // Sort by oldest
      container.read(librarySortProvider.notifier).state = LibrarySort.oldest;
      sorted = container.read(filteredLibraryProvider);
      expect(sorted.first.id, 'vid-1');

      // Sort by largest
      container.read(librarySortProvider.notifier).state = LibrarySort.largest;
      sorted = container.read(filteredLibraryProvider);
      expect(sorted.first.id, 'fb-1');
      expect(sorted.last.id, 'aud-1');

      // Sort by name
      container.read(librarySortProvider.notifier).state = LibrarySort.name;
      sorted = container.read(filteredLibraryProvider);
      expect(sorted.first.title, 'Facebook Viral Reel');
      expect(sorted.last.title, 'Lo-Fi Chill Beat');
    });

    test('view mode toggles cleanly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(libraryViewModeProvider), LibraryViewMode.grid);
      container.read(libraryViewModeProvider.notifier).state =
          LibraryViewMode.list;
      expect(container.read(libraryViewModeProvider), LibraryViewMode.list);
    });

    test(
      'getCandidateDownloadDirectories includes settingsDownloadDirectory',
      () async {
        const customPath = '/custom/user/downloads';
        final dirs = await getCandidateDownloadDirectories(
          settingsDownloadDirectory: customPath,
        );
        expect(dirs, contains(customPath));
        expect(dirs, contains('$customPath/MediaGrab'));
      },
    );

    test(
      'refresh never imports unrelated files from custom directories',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final tempDir = await Directory.systemTemp.createTemp(
          'mediagrab_test_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final testVideoFile = File(
          '${tempDir.path}/Scanned_YouTube_Tutorial.mp4',
        );
        await testVideoFile.writeAsBytes(List.filled(1024 * 100, 1)); // 100 KB

        final testAudioFile = File('${tempDir.path}/Scanned_Track.mp3');
        await testAudioFile.writeAsBytes(List.filled(1024 * 50, 2)); // 50 KB

        final notifier = container.read(libraryProvider.notifier);
        await notifier.refresh(directoriesToScan: [tempDir.path]);

        final items = container.read(libraryProvider);
        expect(items, isEmpty);
      },
    );

    test(
      'addDownloadedItem adds completed task to library with correct metadata',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(libraryProvider.notifier);

        final completedTask = DownloadTask(
          id: 'task-100',
          mediaInfo: const MediaInfo(
            id: 'media-100',
            title: 'Completed Download Title',
            thumbnailUrl: 'https://example.com/thumb.jpg',
            duration: Duration(minutes: 4, seconds: 20),
            uploader: 'Test Channel',
            platform: PlatformType.youtube,
          ),
          selectedStream: const StreamInfo(
            url: 'https://example.com/video.mp4',
            container: 'mp4',
            qualityLabel: '1080p',
            codec: 'h264',
            isVideoOnly: false,
            isAudioOnly: false,
          ),
          filePath: '/storage/downloads/video.mp4',
          status: DownloadStatus.completed,
          progress: 1.0,
          downloadedBytes: 25 * 1024 * 1024,
          totalBytes: 25 * 1024 * 1024,
          createdAt: DateTime(2026, 1, 1),
          completedAt: DateTime(2026, 1, 1, 0, 5),
        );

        notifier.addDownloadedItem(completedTask);

        final items = container.read(libraryProvider);
        expect(items.length, 1);
        final item = items.first;
        expect(item.id, 'task-100');
        expect(item.title, 'Completed Download Title');
        expect(item.filePath, '/storage/downloads/video.mp4');
        expect(item.fileSize, 25 * 1024 * 1024);
        expect(item.fileType, FileType.video);
        expect(item.duration, const Duration(minutes: 4, seconds: 20));
        expect(item.platform, PlatformType.youtube);
        expect(item.qualityLabel, '1080p');
        expect(item.uploader, 'Test Channel');
      },
    );

    test(
      'libraryProvider automatically syncs completed downloads from downloadManagerProvider',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final library = container.read(libraryProvider);
        expect(library, isEmpty);

        final completedTask = DownloadTask(
          id: 'task-sync-1',
          mediaInfo: const MediaInfo(
            id: 'media-sync-1',
            title: 'Synced Video',
            thumbnailUrl: 'https://example.com/sync.jpg',
            duration: Duration(minutes: 2, seconds: 15),
            uploader: 'Sync Creator',
            platform: PlatformType.facebook,
          ),
          selectedStream: const StreamInfo(
            url: 'https://example.com/sync.mp4',
            container: 'mp4',
            qualityLabel: '720p',
            codec: 'h264',
            isVideoOnly: false,
            isAudioOnly: false,
          ),
          filePath: '/storage/downloads/sync.mp4',
          status: DownloadStatus.completed,
          progress: 1.0,
          downloadedBytes: 10 * 1024 * 1024,
          totalBytes: 10 * 1024 * 1024,
          createdAt: DateTime(2026, 1, 1),
        );

        container.read(downloadManagerProvider.notifier).setTasks([
          completedTask,
        ]);

        final updatedLibrary = container.read(libraryProvider);
        expect(updatedLibrary.length, 1);
        expect(updatedLibrary.first.id, 'task-sync-1');
        expect(updatedLibrary.first.title, 'Synced Video');
        expect(updatedLibrary.first.platform, PlatformType.facebook);
      },
    );
  });
}
