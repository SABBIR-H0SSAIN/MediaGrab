import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/downloads/presentation/widgets/empty_downloads_view.dart';

void main() {
  group('EmptyDownloadsView Widget', () {
    testWidgets('renders default title, subtitle, and download icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: EmptyDownloadsView())),
      );

      expect(find.byIcon(Icons.download_outlined), findsOneWidget);
      expect(find.text('No active downloads'), findsOneWidget);
      expect(
        find.text('Start a download to see the progress here'),
        findsOneWidget,
      );
      expect(find.text('Paste Link to Download'), findsOneWidget);
    });

    testWidgets('renders custom title, subtitle, and icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyDownloadsView(
              title: 'No active downloads',
              subtitle: 'Active items will appear here',
              icon: Icons.hourglass_empty,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
      expect(find.text('No active downloads'), findsOneWidget);
      expect(find.text('Active items will appear here'), findsOneWidget);
      expect(find.text('Paste Link to Download'), findsOneWidget);
    });

    testWidgets('triggers onActionPressed when button is tapped', (
      tester,
    ) async {
      var pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyDownloadsView(onActionPressed: () => pressed = true),
          ),
        ),
      );

      await tester.tap(find.text('Paste Link to Download'));
      expect(pressed, isTrue);
    });
  });
}
