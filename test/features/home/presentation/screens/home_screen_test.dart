import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/constants/app_constants.dart';
import 'package:mediagrab/features/home/presentation/providers/home_provider.dart';
import 'package:mediagrab/features/home/presentation/screens/home_screen.dart';
import 'package:mediagrab/features/home/presentation/widgets/quick_actions_row.dart';
import 'package:mediagrab/features/home/presentation/widgets/recent_downloads_section.dart';
import 'package:mediagrab/features/home/presentation/widgets/url_input_card.dart';

void main() {
  String? mockClipboardText;

  setUp(() {
    mockClipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall methodCall,
        ) async {
          if (methodCall.method == 'Clipboard.getData') {
            return {'text': mockClipboardText};
          }
          return null;
        });
  });

  group('HomeScreen', () {
    testWidgets(
      'renders header, hero URL card, quick actions, and recent downloads',
      (tester) async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: Scaffold(body: HomeScreen())),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.text(AppConstants.appName), findsOneWidget);
        expect(find.byType(UrlInputCard), findsOneWidget);
        expect(find.byType(QuickActionsRow), findsOneWidget);
        expect(find.byType(RecentDownloadsSection), findsOneWidget);

        final scrollViews = tester.widgetList<SingleChildScrollView>(
          find.byType(SingleChildScrollView),
        );
        // Horizontal insets belong to foreground content, not the artwork.
        final outerScrollView = scrollViews.firstWhere(
          (view) => view.scrollDirection == Axis.vertical,
        );
        expect(outerScrollView.padding, const EdgeInsets.only(bottom: 20));
      },
    );

    testWidgets('auto-pastes valid YouTube URL from clipboard on app launch', (
      tester,
    ) async {
      const youtubeUrl = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
      mockClipboardText = youtubeUrl;

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: HomeScreen())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(container.read(urlInputProvider), youtubeUrl);
      expect(find.text(youtubeUrl), findsOneWidget);
    });

    testWidgets(
      'auto-pastes valid Instagram reel URL from clipboard on app launch',
      (tester) async {
        const instaUrl = 'https://www.instagram.com/reel/Cxyz123/';
        mockClipboardText = instaUrl;

        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: Scaffold(body: HomeScreen())),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(container.read(urlInputProvider), instaUrl);
        expect(find.text(instaUrl), findsOneWidget);
      },
    );

    testWidgets(
      'does NOT auto-paste unsupported or non-media text from clipboard on launch',
      (tester) async {
        mockClipboardText = 'https://google.com/search?q=flutter';

        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: Scaffold(body: HomeScreen())),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(container.read(urlInputProvider), '');
      },
    );

    testWidgets(
      'new valid clipboard link replaces previous input but unchanged clipboard preserves edits',
      (tester) async {
        mockClipboardText = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: Scaffold(body: HomeScreen())),
          ),
        );
        await tester.pumpAndSettle();
        mockClipboardText = 'https://www.instagram.com/reel/NEW123/';
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(container.read(urlInputProvider), mockClipboardText);
        expect(find.text(mockClipboardText!), findsOneWidget);
        container.read(urlInputProvider.notifier).state =
            'editing another link';
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(container.read(urlInputProvider), 'editing another link');
        mockClipboardText = 'not a supported video link';
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(container.read(urlInputProvider), 'editing another link');
      },
    );

    testWidgets(
      'auto-pastes valid media URL when app lifecycle state resumes',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: Scaffold(body: HomeScreen())),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(container.read(urlInputProvider), '');

        // Copy Facebook video URL to clipboard and simulate app resume
        const fbUrl = 'https://www.facebook.com/watch/?v=987654321';
        mockClipboardText = fbUrl;

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(container.read(urlInputProvider), fbUrl);
      },
    );
  });
}
