import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/home/presentation/providers/home_provider.dart';
import 'package:mediagrab/features/home/presentation/widgets/clipboard_banner.dart';

void main() {
  group('ClipboardBanner', () {
    testWidgets('renders nothing when no copied link is detected', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: ClipboardBanner())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Copied link detected'), findsNothing);
      expect(find.text('Extract'), findsNothing);
    });

    testWidgets('renders banner when valid media URL is in clipboard state', (
      tester,
    ) async {
      const testUrl = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';

      final container = ProviderContainer();
      container.read(clipboardBannerProvider.notifier).setDetectedUrl(testUrl);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: ClipboardBanner())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Copied link detected'), findsOneWidget);
      expect(find.text('Extract'), findsOneWidget);
      expect(find.byIcon(Icons.content_paste_go_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
    });

    testWidgets('tapping dismiss button hides the banner', (tester) async {
      const testUrl = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';

      final container = ProviderContainer();
      container.read(clipboardBannerProvider.notifier).setDetectedUrl(testUrl);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: ClipboardBanner())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Copied link detected'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Copied link detected'), findsNothing);
      expect(container.read(clipboardBannerProvider), isNull);
    });

    testWidgets('tapping Extract button updates urlInputProvider and invokes callback', (
      tester,
    ) async {
      const testUrl = 'https://www.instagram.com/reel/Cxyz123/';
      String? extractedUrl;

      final container = ProviderContainer();
      container.read(clipboardBannerProvider.notifier).setDetectedUrl(testUrl);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: ClipboardBanner(onExtract: (url) => extractedUrl = url),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Extract'));
      await tester.pumpAndSettle();

      expect(extractedUrl, testUrl);
      expect(container.read(urlInputProvider), testUrl);
      expect(find.text('Copied link detected'), findsNothing);
    });

    testWidgets('hides when detected URL matches existing urlInputProvider value', (
      tester,
    ) async {
      const testUrl = 'https://www.facebook.com/watch/?v=123';

      final container = ProviderContainer();
      container.read(urlInputProvider.notifier).state = testUrl;
      container.read(clipboardBannerProvider.notifier).setDetectedUrl(testUrl);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: ClipboardBanner())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Copied link detected'), findsNothing);
    });
  });
}
