import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/file_utils.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/library/presentation/providers/library_provider.dart';
import 'package:mediagrab/features/library/presentation/widgets/media_grid_item.dart';

void main() {
  final testItem = LibraryMediaItem(
    id: 'test-1',
    title: 'Amazing Flutter Tutorial 2026',
    filePath: '/storage/downloads/tutorial.mp4',
    fileSize: 42 * 1024 * 1024,
    fileType: FileType.video,
    duration: const Duration(minutes: 12, seconds: 34),
    thumbnailUrl: null,
    platform: PlatformType.youtube,
    downloadedAt: DateTime(2026, 1, 1),
    qualityLabel: '1080p',
  );

  Widget buildTestableWidget({
    required LibraryMediaItem item,
    VoidCallback? onTap,
    VoidCallback? onOpen,
    VoidCallback? onShare,
    VoidCallback? onDelete,
    VoidCallback? onInfo,
  }) {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 220,
              child: MediaGridItem(
                item: item,
                onTap: onTap,
                onOpen: onOpen,
                onShare: onShare,
                onDelete: onDelete,
                onInfo: onInfo,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('displays title, duration badge, size, and platform badge', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestableWidget(item: testItem));
    await tester.pumpAndSettle();

    expect(find.text('Amazing Flutter Tutorial 2026'), findsOneWidget);
    expect(find.text('12:34'), findsOneWidget);
    expect(find.textContaining('42 MB'), findsOneWidget);
    expect(find.textContaining('1080p • MP4'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
  });

  testWidgets('long press shows bottom sheet with Open, Share, Delete, Info', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestableWidget(item: testItem));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Amazing Flutter Tutorial 2026'));
    await tester.pumpAndSettle();

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Info'), findsOneWidget);
  });

  testWidgets(
    'tapping action menu button on card also shows bottom sheet and triggers Open',
    (tester) async {
      bool openCalled = false;

      await tester.pumpWidget(
        buildTestableWidget(
          item: testItem,
          onOpen: () {
            openCalled = true;
          },
        ),
      );
      await tester.pumpAndSettle();

      // Tap action menu button
      await tester.tap(find.byTooltip('Action menu'));
      await tester.pumpAndSettle();

      expect(find.text('Open'), findsOneWidget);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(openCalled, isTrue);
    },
  );

  testWidgets('tapping Delete in bottom sheet triggers onDelete callback', (
    tester,
  ) async {
    bool deleteCalled = false;

    await tester.pumpWidget(
      buildTestableWidget(
        item: testItem,
        onDelete: () {
          deleteCalled = true;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Amazing Flutter Tutorial 2026'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deleteCalled, isTrue);
  });

  testWidgets('tapping Info in bottom sheet opens details dialog', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestableWidget(item: testItem));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Amazing Flutter Tutorial 2026'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Info'));
    await tester.pumpAndSettle();

    expect(find.text('Media Details'), findsOneWidget);
    expect(
      find.textContaining('/storage/downloads/tutorial.mp4'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('1080p • MP4'),
      ),
      findsOneWidget,
    );
  });
}
