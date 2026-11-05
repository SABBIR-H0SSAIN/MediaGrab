import '../features/extractor/presentation/screens/batch_download_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/extractor/presentation/screens/media_info_screen.dart';
import '../features/player/presentation/screens/video_player_screen.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../features/downloads/presentation/screens/downloads_screen.dart';
import '../features/library/presentation/screens/library_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../shared/widgets/app_scaffold.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/batch-download',
        builder: (context, state) => const BatchDownloadScreen(),
      ),
      GoRoute(
        path: '/media-info',
        builder: (context, state) {
          final url =
              state.uri.queryParameters['url'] ??
              (state.extra as String? ?? '');
          return MediaInfoScreen(url: url);
        },
      ),
      GoRoute(
        path: '/player',
        builder: (context, state) {
          final filePath = state.uri.queryParameters['filePath'] ?? '';
          final title = state.uri.queryParameters['title'] ?? 'Video Player';
          return VideoPlayerScreen(filePath: filePath, title: title);
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppScaffold(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/downloads',
                builder:
                    (context, state) => DownloadsScreen(
                      initialTab: state.uri.queryParameters['tab'],
                    ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (context, state) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
