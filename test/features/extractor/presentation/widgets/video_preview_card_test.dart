import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/presentation/widgets/video_preview_card.dart';
import 'package:mediagrab/features/home/presentation/widgets/platform_chip.dart';

void main() {
  final sampleMedia = MediaInfo(
    id: 'dQw4w9WgXcQ',
    title: 'Rick Astley - Never Gonna Give You Up',
    thumbnailUrl: 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
    duration: const Duration(minutes: 3, seconds: 32),
    uploader: 'Rick Astley',
    platform: PlatformType.youtube,
    uploadDate: DateTime(2009, 10, 25),
    viewCount: 1400000000,
  );

  testWidgets(
    'VideoPreviewCard displays metadata and platform chip correctly',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VideoPreviewCard(mediaInfo: sampleMedia)),
        ),
      );
      await tester.pump();

      // Verify title
      expect(
        find.text('Rick Astley - Never Gonna Give You Up'),
        findsOneWidget,
      );

      // Verify uploader
      expect(find.text('Rick Astley'), findsOneWidget);

      // Verify duration badge
      expect(find.text('3:32'), findsOneWidget);

      // Verify views and upload date
      expect(find.text('1.4B views'), findsOneWidget);
      expect(find.text('Oct 25, 2009'), findsOneWidget);

      // Verify PlatformChip
      expect(find.byType(PlatformChip), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
    },
  );
}
