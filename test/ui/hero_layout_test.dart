import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediagrab/app.dart';
import 'package:mediagrab/core/widgets/hero_background.dart';
import 'package:mediagrab/features/home/presentation/widgets/url_input_card.dart';
import 'package:mediagrab/features/downloads/data/services/download_engine.dart';
import 'package:mediagrab/features/downloads/presentation/providers/download_manager_provider.dart';
import 'package:mediagrab/features/settings/presentation/providers/settings_provider.dart';
import 'package:mediagrab/routing/app_router.dart';

void main() {
  for (final size in [
    const Size(320, 640),
    const Size(412, 915),
    const Size(800, 400),
  ]) {
    testWidgets('hero foreground remains reachable at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        SettingsNotifier.keyThemeMode: 'dark',
        SettingsNotifier.keyDynamicColors: false,
      });
      final prefs = await SharedPreferences.getInstance();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
      final engine = DownloadEngine(
        customDownloadExecution:
            ({
              required task,
              required stream,
              required targetPath,
              required onProgress,
              required onComplete,
              required onError,
            }) async {},
      );
      addTearDown(engine.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            downloadEngineProvider.overrideWithValue(engine),
            connectivityProvider.overrideWithValue(null),
          ],
          child: const MediaGrabApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HeroBackground), findsOneWidget);
      final hero = tester.getRect(find.byType(HeroBackground));
      final input = tester.getRect(find.byType(UrlInputCard));
      expect(hero.top, 0);
      expect(hero.left, 0);
      expect(hero.right, size.width);
      expect(input.left, 20);
      expect(input.right, size.width - 20);
      expect(hero.bottom, lessThanOrEqualTo(input.top));
      await tester.ensureVisible(find.text('Analyze & Download'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final action = tester.getRect(find.text('Analyze & Download'));
      expect(action.overlaps(Offset.zero & size), isTrue);
    });
  }
  testWidgets('startup renders the requested route without another splash', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final engine = DownloadEngine(
      customDownloadExecution:
          ({
            required task,
            required stream,
            required targetPath,
            required onProgress,
            required onComplete,
            required onError,
          }) async {},
    );
    addTearDown(engine.dispose);
    final container = ProviderContainer(
      overrides: [
        downloadEngineProvider.overrideWithValue(engine),
        connectivityProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MediaGrabApp(),
      ),
    );
    container.read(appRouterProvider).go('/downloads?tab=completed');
    await tester.pumpAndSettle();
    expect(find.text('No completed downloads'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
