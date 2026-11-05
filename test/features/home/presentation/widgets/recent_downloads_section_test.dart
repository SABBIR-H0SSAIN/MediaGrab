import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/downloads/domain/entities/download_task.dart';
import 'package:mediagrab/features/downloads/domain/enums/download_status.dart';
import 'package:mediagrab/features/downloads/presentation/providers/download_manager_provider.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';
import 'package:mediagrab/features/home/presentation/widgets/recent_downloads_section.dart';

void main() {
  DownloadTask createDummyTask({
    required String id,
    required String title,
    required String quality,
    DownloadStatus status = DownloadStatus.completed,
    double progress = 1.0,
  }) {
    return DownloadTask(
      id: id,
      mediaInfo: MediaInfo(
        id: id,
        title: title,
        platform: PlatformType.youtube,
        thumbnailUrl: '',
        duration: const Duration(minutes: 3),
        uploader: 'Test Channel',
      ),
      selectedStream: StreamInfo(
        url: 'https://example.com/stream.mp4',
        qualityLabel: quality,
        codec: 'h264',
        container: 'mp4',
      ),
      status: status,
      progress: progress,
      createdAt: DateTime.now(),
    );
  }

  group('RecentDownloadsSection', () {
    testWidgets('renders title, See all button, and empty state when no downloads', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: RecentDownloadsSection())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Recent Downloads'), findsOneWidget);
      expect(find.text('See all'), findsOneWidget);
      expect(find.text('No recent downloads'), findsOneWidget);
      expect(
        find.text('Your downloaded videos will appear here'),
        findsOneWidget,
      );
    });

    testWidgets('renders download cards when recent downloads exist', (
      tester,
    ) async {
      final task1 = createDummyTask(
        id: '1',
        title: 'Flutter 3 Tutorial',
        quality: '1080p',
        status: DownloadStatus.completed,
      );
      final task2 = createDummyTask(
        id: '2',
        title: 'Riverpod State Management',
        quality: '720p',
        status: DownloadStatus.downloading,
        progress: 0.45,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recentDownloadsProvider.overrideWithValue([task1, task2]),
          ],
          child: const MaterialApp(
            home: Scaffold(body: RecentDownloadsSection()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Recent Downloads'), findsOneWidget);
      expect(find.text('Flutter 3 Tutorial'), findsOneWidget);
      expect(find.text('Riverpod State Management'), findsOneWidget);
      expect(find.text('1080p'), findsOneWidget);
      expect(find.text('720p'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('45.0%'), findsOneWidget);
    });

    testWidgets('invokes onSeeAll callback when See all is tapped', (
      tester,
    ) async {
      bool seeAllTapped = false;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: RecentDownloadsSection(onSeeAll: () => seeAllTapped = true),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.text('See all'));
      await tester.pump();
      expect(seeAllTapped, isTrue);
    });

    testWidgets('invokes onTapDownload callback when a download card is tapped', (
      tester,
    ) async {
      final task = createDummyTask(
        id: '1',
        title: 'Flutter 3 Tutorial',
        quality: '1080p',
      );
      DownloadTask? tappedTask;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recentDownloadsProvider.overrideWithValue([task]),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: RecentDownloadsSection(
                onTapDownload: (t) => tappedTask = t,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.text('Flutter 3 Tutorial'));
      await tester.pump();
      expect(tappedTask, equals(task));
    });
  });
}
