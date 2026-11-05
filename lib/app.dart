import 'dart:async';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/presentation/providers/settings_provider.dart';
import 'routing/app_router.dart';
import 'shared/widgets/app_startup.dart';
import 'features/downloads/presentation/providers/download_manager_provider.dart';
import 'features/extractor/presentation/providers/batch_preparation_provider.dart';

class MediaGrabApp extends ConsumerWidget {
  const MediaGrabApp({super.key, this.onReady});

  final VoidCallback? onReady;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final settings = ref.watch(settingsProvider);

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final lightScheme = settings.dynamicColors ? lightDynamic : null;
        final darkScheme = settings.dynamicColors ? darkDynamic : null;

        return MaterialApp.router(
          title: 'MediaGrab',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.getTheme(
            Brightness.light,
            dynamicScheme: lightScheme,
          ),
          darkTheme: AppTheme.getTheme(
            Brightness.dark,
            amoled: settings.amoledDark,
            dynamicScheme: darkScheme,
          ),
          themeMode: settings.themeMode,
          routerConfig: router,
          builder:
              (context, child) => AppStartup(
                onReady: onReady,
                onBackground: () {
                  // Flush only initialized subsystems. Backgrounding must not
                  // create a new engine or begin restoring an unused batch.
                  if (ref.exists(downloadEngineProvider)) {
                    unawaited(
                      ref.read(downloadEngineProvider).checkpointSession(),
                    );
                  }
                  if (ref.exists(batchPreparationProvider)) {
                    unawaited(
                      ref.read(batchPreparationProvider.notifier).flushDraft(),
                    );
                  }
                },
                child: child ?? const SizedBox.shrink(),
              ),
        );
      },
    );
  }
}
