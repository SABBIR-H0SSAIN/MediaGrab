import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/library/presentation/providers/library_provider.dart';
import 'package:mediagrab/features/library/presentation/widgets/filter_chips_bar.dart';

void main() {
  Widget buildTestableWidget({
    LibraryFilter initialFilter = LibraryFilter.all,
    ValueChanged<LibraryFilter>? onFilterSelected,
  }) {
    return ProviderScope(
      overrides: [libraryFilterProvider.overrideWith((ref) => initialFilter)],
      child: MaterialApp(
        home: Scaffold(
          body: FilterChipsBar(onFilterSelected: onFilterSelected),
        ),
      ),
    );
  }

  testWidgets(
    'renders all six filter chips (All, Videos, Audio, YouTube, Facebook, Instagram)',
    (tester) async {
      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Videos'), findsOneWidget);
      expect(find.text('Audio'), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('Facebook'), findsOneWidget);
      expect(find.text('Instagram'), findsOneWidget);

      final allChip = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, 'All'),
      );
      expect(allChip.selected, isTrue);

      final videosChip = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, 'Videos'),
      );
      expect(videosChip.selected, isFalse);
    },
  );

  testWidgets('tapping a chip updates the selected filter in riverpod', (
    tester,
  ) async {
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                capturedRef = ref;
                return const FilterChipsBar();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(capturedRef.read(libraryFilterProvider), LibraryFilter.all);

    // Tap Videos
    await tester.tap(find.text('Videos'));
    await tester.pumpAndSettle();
    expect(capturedRef.read(libraryFilterProvider), LibraryFilter.videos);

    // Tap Audio
    await tester.tap(find.text('Audio'));
    await tester.pumpAndSettle();
    expect(capturedRef.read(libraryFilterProvider), LibraryFilter.audio);

    // Tap YouTube
    await tester.tap(find.text('YouTube'));
    await tester.pumpAndSettle();
    expect(capturedRef.read(libraryFilterProvider), LibraryFilter.youtube);

    // Tap Facebook
    await tester.tap(find.text('Facebook'));
    await tester.pumpAndSettle();
    expect(capturedRef.read(libraryFilterProvider), LibraryFilter.facebook);

    // Tap Instagram
    await tester.tap(find.text('Instagram'));
    await tester.pumpAndSettle();
    expect(capturedRef.read(libraryFilterProvider), LibraryFilter.instagram);
  });

  testWidgets('invokes onFilterSelected callback when passed', (tester) async {
    LibraryFilter? selected;

    await tester.pumpWidget(
      buildTestableWidget(
        onFilterSelected: (filter) {
          selected = filter;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('YouTube'));
    await tester.pumpAndSettle();

    expect(selected, LibraryFilter.youtube);
  });
}
