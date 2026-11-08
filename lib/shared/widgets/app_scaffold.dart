import '../../features/player/presentation/widgets/mini_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/downloads/presentation/providers/download_manager_provider.dart';

/// Top-level app navigation shell wrapping the persistent [NavigationBar].
///
/// Features dynamic badge indicators (e.g. active downloads counter) and
/// smooth Material 3 destination indicators.
class AppScaffold extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const AppScaffold({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeDownloadsCount = ref.watch(activeDownloadsCountProvider);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (index) {
              navigationShell.goBranch(
                index,
                initialLocation: index == navigationShell.currentIndex,
              );
            },
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                icon:
                    activeDownloadsCount > 0
                        ? Badge.count(
                          count: activeDownloadsCount,
                          child: const Icon(Icons.download_outlined),
                        )
                        : const Icon(Icons.download_outlined),
                selectedIcon:
                    activeDownloadsCount > 0
                        ? Badge.count(
                          count: activeDownloadsCount,
                          child: const Icon(Icons.download_rounded),
                        )
                        : const Icon(Icons.download_rounded),
                label: 'Downloads',
              ),
              const NavigationDestination(
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder_rounded),
                label: 'Library',
              ),
              const NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: 'Settings',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
