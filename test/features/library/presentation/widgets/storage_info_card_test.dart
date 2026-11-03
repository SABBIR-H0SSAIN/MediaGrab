import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/file_utils.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/library/presentation/providers/library_provider.dart';
import 'package:mediagrab/features/library/presentation/widgets/storage_info_card.dart';

void main() {
  Widget buildTestableWidget({
    List<LibraryMediaItem>? initialItems,
    VoidCallback? onRefresh,
  }) {
    return ProviderScope(
      overrides: [
        if (initialItems != null)
          libraryProvider.overrideWith((ref) => LibraryNotifier(initialItems)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: StorageInfoCard(onRefresh: onRefresh),
          ),
        ),
      ),
    );
  }

  testWidgets('displays App Storage and 0 B used • 0 items when empty', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestableWidget(initialItems: []));
    await tester.pumpAndSettle();

    expect(find.text('App Storage'), findsOneWidget);
    expect(find.text('0 B used • 0 items'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
  });

  testWidgets('displays formatted count and total size when multiple items present', (
    tester,
  ) async {
    final sampleItem1 = LibraryMediaItem(
      id: '1',
      title: 'Video 1',
      filePath: '/path/1.mp4',
      fileSize: 100 * 1024 * 1024, // 100 MB
      fileType: FileType.video,
      downloadedAt: DateTime.now(),
      platform: PlatformType.youtube,
    );
    final sampleItem2 = LibraryMediaItem(
      id: '2',
      title: 'Song 1',
      filePath: '/path/1.mp3',
      fileSize: 50 * 1024 * 1024, // 50 MB
      fileType: FileType.audio,
      downloadedAt: DateTime.now(),
      platform: PlatformType.youtube,
    );

    await tester.pumpWidget(
      buildTestableWidget(initialItems: [sampleItem1, sampleItem2]),
    );
    await tester.pumpAndSettle();

    expect(find.text('App Storage'), findsOneWidget);
    expect(find.text('150 MB used • 2 items'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('displays singular item label when single item is present', (
    tester,
  ) async {
    final sampleItem = LibraryMediaItem(
      id: '1',
      title: 'Video 1',
      filePath: '/path/1.mp4',
      fileSize: 100 * 1024 * 1024, // 100 MB
      fileType: FileType.video,
      downloadedAt: DateTime.now(),
      platform: PlatformType.youtube,
    );

    await tester.pumpWidget(
      buildTestableWidget(initialItems: [sampleItem]),
    );
    await tester.pumpAndSettle();

    expect(find.text('App Storage'), findsOneWidget);
    expect(find.text('100 MB used • 1 item'), findsOneWidget);
  });

  testWidgets('tapping card triggers onRefresh callback', (tester) async {
    bool refreshed = false;

    await tester.pumpWidget(
      buildTestableWidget(
        initialItems: [],
        onRefresh: () {
          refreshed = true;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('app_storage_card')));
    await tester.pumpAndSettle();

    expect(refreshed, isTrue);
  });
}
