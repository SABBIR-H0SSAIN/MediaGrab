import 'package:go_router/go_router.dart';
import 'package:mediagrab/core/theme/app_theme.dart';
import 'package:mediagrab/features/extractor/presentation/screens/batch_download_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/home/presentation/widgets/quick_actions_row.dart';

void main() {
  group('QuickActionsRow', () {
    testWidgets('renders all platform buttons and feature action cards', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: QuickActionsRow())),
        ),
      );

      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('Facebook'), findsOneWidget);
      expect(find.text('Instagram'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);

      expect(find.text('Batch Download'), findsOneWidget);
      expect(find.text('Download multiple links'), findsOneWidget);
      expect(find.text('Playlists'), findsOneWidget);
      expect(find.text('Download entire playlists'), findsOneWidget);
    });

    testWidgets(
      'supported platforms has one handle and scrolls in landscape with large text',
      (tester) async {
        tester.view.physicalSize = const Size(844, 390);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.dark(),
              builder:
                  (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(1.6)),
                    child: child!,
                  ),
              home: const Scaffold(
                body: SingleChildScrollView(child: QuickActionsRow()),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Facebook'));
        await tester.pumpAndSettle();
        expect(find.text('Supported Platforms'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.constraints?.maxHeight == 4 &&
                  widget.constraints!.maxWidth > 20,
            ),
          ),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.text('Got It'),
          150,
          scrollable: find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.tap(find.text('Got It'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('triggers callbacks when provided or opens dialogs', (
      tester,
    ) async {
      bool batchTapped = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: QuickActionsRow(onBatch: () => batchTapped = true),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Batch Download'));
      expect(batchTapped, isTrue);
    });

    testWidgets('routes to batch preparation on default Batch Download tap', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: QuickActionsRow()),
          ),
          GoRoute(
            path: '/batch-download',
            builder: (_, _) => const BatchDownloadScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );

      await tester.tap(find.text('Batch Download'));
      await tester.pumpAndSettle();

      expect(find.text('Check links'), findsNothing);
      expect(find.text('Paste Multiple'), findsNothing);
      expect(find.text('Auto Add'), findsOneWidget);
      expect(find.text('Download 0 videos'), findsOneWidget);
    });

    testWidgets(
      'playlist field uses one outlined border with a visible focused state',
      (tester) async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: Scaffold(body: QuickActionsRow())),
          ),
        );
        await tester.tap(find.text('Playlists'));
        await tester.pumpAndSettle();
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.decoration?.enabledBorder, isA<OutlineInputBorder>());
        expect(field.decoration?.focusedBorder, isA<OutlineInputBorder>());
        expect(
          (field.decoration!.focusedBorder! as OutlineInputBorder)
              .borderSide
              .width,
          2,
        );
        await tester.enterText(
          find.byType(TextField),
          'https://youtube.com/playlist?list=PL_test',
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets('opens More supported sites dialog on More button tap', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: QuickActionsRow())),
        ),
      );

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();

      expect(find.text('Supported Platforms'), findsOneWidget);
      expect(find.text('YouTube'), findsNWidgets(2));
      expect(find.text('Facebook'), findsNWidgets(2));
      expect(find.text('Instagram'), findsNWidgets(2));
    });
  });
}
