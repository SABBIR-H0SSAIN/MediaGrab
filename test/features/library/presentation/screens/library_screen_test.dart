import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/file_utils.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/library/presentation/providers/library_provider.dart';
import 'package:mediagrab/features/library/presentation/screens/library_screen.dart';
import 'package:mediagrab/features/library/presentation/widgets/filter_chips_bar.dart';
import 'package:mediagrab/features/library/presentation/widgets/media_grid_item.dart';
import 'package:mediagrab/features/library/presentation/widgets/storage_info_card.dart';

void main() {
  final sampleVideo = LibraryMediaItem(
    id: 'vid-1',
    title: 'Flutter Advanced Architecture',
    filePath: '/storage/downloads/flutter_arch.mp4',
    fileSize: 85 * 1024 * 1024,
    fileType: FileType.video,
    duration: const Duration(minutes: 25, seconds: 12),
    platform: PlatformType.youtube,
    downloadedAt: DateTime(2026, 1, 1),
    qualityLabel: '1080p',
    uploader: 'Flutter Devs',
  );

  final sampleAudio = LibraryMediaItem(
    id: 'aud-1',
    title: 'Synthwave Chill Mix',
    filePath: '/storage/downloads/synthwave.mp3',
    fileSize: 12 * 1024 * 1024,
    fileType: FileType.audio,
    duration: const Duration(minutes: 4, seconds: 50),
    platform: PlatformType.youtube,
    downloadedAt: DateTime(2026, 1, 2),
    qualityLabel: '320kbps',
    uploader: 'Chilled Lofi',
  );

  Widget buildTestableScreen({List<LibraryMediaItem>? items}) {
    return ProviderScope(
      overrides: [
        if (items != null)
          libraryProvider.overrideWith((ref) => LibraryNotifier(items)),
      ],
      child: const MaterialApp(home: LibraryScreen()),
    );
  }

  testWidgets('shows empty state when library is empty', (tester) async {
    await tester.pumpWidget(buildTestableScreen(items: []));
    await tester.pumpAndSettle();

    expect(find.byType(StorageInfoCard), findsOneWidget);
    expect(find.byType(FilterChipsBar), findsOneWidget);
    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.text('Downloaded files will appear here'), findsOneWidget);
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
  });

  testWidgets(
    'renders GridView with MediaGridItem for videos when items present',
    (tester) async {
      await tester.pumpWidget(buildTestableScreen(items: [sampleVideo]));
      await tester.pumpAndSettle();

      expect(find.byType(StorageInfoCard), findsOneWidget);
      expect(find.byType(FilterChipsBar), findsOneWidget);
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(MediaGridItem), findsOneWidget);
      expect(find.text('Flutter Advanced Architecture'), findsOneWidget);
    },
  );

  testWidgets('switches to ListView.builder when Audio filter is active', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestableScreen(items: [sampleVideo, sampleAudio]),
    );
    await tester.pumpAndSettle();

    // Tap Audio filter
    await tester.tap(find.text('Audio'));
    await tester.pumpAndSettle();

    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('Synthwave Chill Mix'), findsOneWidget);
    expect(find.text('Flutter Advanced Architecture'), findsNothing);
  });

  testWidgets(
    'toggling view mode switcher switches between GridView and ListView',
    (tester) async {
      await tester.pumpWidget(
        buildTestableScreen(items: [sampleVideo, sampleAudio]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsOneWidget);

      // Switch to list view
      await tester.tap(find.byTooltip('Sort by'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch to list view'));
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOneWidget);
      expect(find.text('Flutter Advanced Architecture'), findsOneWidget);

      // Switch back to grid view
      await tester.tap(find.byTooltip('Sort by'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch to grid view'));
      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsOneWidget);
    },
  );

  testWidgets('search toggle filters results and displays empty search state', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestableScreen(items: [sampleVideo, sampleAudio]),
    );
    await tester.pumpAndSettle();

    // Tap search icon
    await tester.tap(find.byTooltip('Search media'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);

    // Enter matching query
    await tester.enterText(find.byType(TextField), 'Synthwave');
    await tester.pumpAndSettle();

    expect(find.text('Synthwave Chill Mix'), findsOneWidget);
    expect(find.text('Flutter Advanced Architecture'), findsNothing);

    // Enter non-matching query
    await tester.enterText(find.byType(TextField), 'UnknownQuery123');
    await tester.pumpAndSettle();

    expect(find.text('No results found'), findsOneWidget);
    expect(
      find.text('No downloaded files matched "UnknownQuery123"'),
      findsOneWidget,
    );

    // Close search
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Flutter Advanced Architecture'), findsOneWidget);
    expect(find.text('Synthwave Chill Mix'), findsOneWidget);
  });

  testWidgets('sort menu opens and allows selecting sort options', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestableScreen(items: [sampleVideo, sampleAudio]),
    );
    await tester.pumpAndSettle();

    // Open sort menu
    await tester.tap(find.byTooltip('Sort by'));
    await tester.pumpAndSettle();

    expect(find.text('Newest'), findsOneWidget);
    expect(find.text('Oldest'), findsOneWidget);
    expect(find.text('Largest'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);

    // Select Name
    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();

    // Menu should be closed
    expect(find.text('Largest'), findsNothing);
  });

  testWidgets('pull to refresh triggers without crashing', (tester) async {
    await tester.pumpWidget(buildTestableScreen(items: [sampleVideo]));
    await tester.pumpAndSettle();

    expect(find.byType(RefreshIndicator), findsOneWidget);

    // Pull down to trigger refresh
    await tester.fling(find.byType(GridView), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Flutter Advanced Architecture'), findsOneWidget);
  });
}
