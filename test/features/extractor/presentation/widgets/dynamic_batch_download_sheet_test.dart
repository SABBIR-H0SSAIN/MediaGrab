import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/extractor/presentation/widgets/dynamic_batch_download_sheet.dart';

void main() {
  group('DynamicBatchDownloadSheet', () {
    testWidgets('renders initial single link row and Add another link button', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: DynamicBatchDownloadSheet())),
        ),
      );

      expect(find.text('Batch Download'), findsOneWidget);
      expect(find.text('Add another link'), findsOneWidget);
      expect(find.text('Start Download'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('rejects unsupported links before dismissing the dialog', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: DynamicBatchDownloadSheet())),
        ),
      );
      await tester.enterText(
        find.byType(TextField),
        'https://example.com/file',
      );
      await tester.tap(find.text('Start Download'));
      await tester.pump();
      expect(
        find.text('Enter supported YouTube, Facebook or Instagram links.'),
        findsOneWidget,
      );
      expect(find.byType(DynamicBatchDownloadSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('adds a new link row on tap Add another link', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: DynamicBatchDownloadSheet())),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);

      await tester.tap(find.text('Add another link'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('deletes a row when delete button is pressed', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: DynamicBatchDownloadSheet())),
        ),
      );

      // Add second row
      await tester.tap(find.text('Add another link'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));

      // Tap remove on second row
      final deleteButtons = find.byTooltip('Remove');
      expect(deleteButtons, findsNWidgets(2));
      await tester.tap(deleteButtons.last);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
