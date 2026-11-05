import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/home/presentation/widgets/platform_chip.dart';
import 'package:mediagrab/features/home/presentation/widgets/url_input_card.dart';

void main() {
  Widget buildTestWidget({
    void Function(String)? onDownload,
    List<Override> overrides = const [],
  }) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: Scaffold(body: UrlInputCard(onDownload: onDownload)),
      ),
    );
  }

  group('UrlInputCard', () {
    testWidgets(
      'renders TextField, prefix icon, and disabled button initially without paste/clear icon',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsOneWidget);
        expect(find.byIcon(Icons.link), findsOneWidget);
        expect(find.byIcon(Icons.content_paste), findsNothing);
        expect(find.byIcon(Icons.close), findsNothing);

        final buttonFinder = find.widgetWithText(
          FilledButton,
          'Analyze & Download',
        );
        expect(buttonFinder, findsOneWidget);

        final button = tester.widget<FilledButton>(buttonFinder);
        expect(button.onPressed, isNull);
      },
    );

    testWidgets(
      'shows PlatformChip, clear icon and enables Download button on valid YouTube URL',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField),
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.close), findsOneWidget);
        expect(find.byType(PlatformChip), findsOneWidget);
        expect(find.text('YouTube'), findsOneWidget);

        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Analyze & Download'),
        );
        expect(button.onPressed, isNotNull);
      },
    );

    testWidgets('shows Instagram PlatformChip on Instagram reel URL', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField),
        'https://www.instagram.com/reel/Cxyz123/',
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byType(PlatformChip), findsOneWidget);
      expect(find.text('Instagram'), findsOneWidget);
    });

    testWidgets('clears text and disables button when clear icon is pressed', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.text('YouTube'), findsNothing);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Analyze & Download'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('invokes onDownload callback when Download button is pressed', (
      tester,
    ) async {
      String? downloadedUrl;
      await tester.pumpWidget(
        buildTestWidget(
          onDownload: (url) {
            downloadedUrl = url;
          },
        ),
      );
      await tester.pumpAndSettle();

      const testUrl = 'https://youtu.be/dQw4w9WgXcQ';
      await tester.enterText(find.byType(TextField), testUrl);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Analyze & Download'));
      await tester.pumpAndSettle();

      expect(downloadedUrl, testUrl);
    });
  });
}
