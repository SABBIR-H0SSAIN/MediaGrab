import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mediagrab/features/downloads/presentation/providers/download_manager_provider.dart';
import 'package:mediagrab/shared/widgets/app_scaffold.dart';

void main() {
  GoRouter createTestRouter() {
    return GoRouter(
      initialLocation: '/home',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return AppScaffold(navigationShell: navigationShell);
          },
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/home',
                  builder: (context, state) => const Text('HomeScreen'),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/downloads',
                  builder: (context, state) => const Text('DownloadsScreen'),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/library',
                  builder: (context, state) => const Text('LibraryScreen'),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/settings',
                  builder: (context, state) => const Text('SettingsScreen'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  group('AppScaffold', () {
    testWidgets('renders all 4 navigation destinations without badges when activeDownloads = 0', (
      tester,
    ) async {
      final router = createTestRouter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeDownloadsCountProvider.overrideWithValue(0),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Downloads'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.byType(Badge), findsNothing);
    });

    testWidgets('renders badge on Downloads tab when activeDownloads > 0', (
      tester,
    ) async {
      final router = createTestRouter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeDownloadsCountProvider.overrideWithValue(3),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Downloads'), findsOneWidget);
      expect(find.byType(Badge), findsWidgets);
      expect(find.text('3'), findsWidgets);
    });

    testWidgets('navigates to branch when destination is tapped', (
      tester,
    ) async {
      final router = createTestRouter();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('HomeScreen'), findsOneWidget);

      await tester.tap(find.text('Downloads'));
      await tester.pumpAndSettle();

      expect(find.text('DownloadsScreen'), findsOneWidget);
    });
  });
}
