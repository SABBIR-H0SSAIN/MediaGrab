import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediagrab/app.dart';
import 'package:mediagrab/features/player/presentation/providers/playback_provider.dart';
import 'package:mediagrab/features/settings/presentation/providers/settings_provider.dart';
import 'package:mediagrab/main.dart' as app;
import 'package:mediagrab/routing/app_router.dart';

// Run only on a dedicated emulator/device with a generated local fixture copied
// to the app cache. This uses the normal app, routes and real Android backend.
// It never clears preferences, downloads or registry records.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native player gestures, rendering and full/mini continuity', (
    tester,
  ) async {
    const path = String.fromEnvironment(
      'PLAYER_UX_FIXTURE',
      defaultValue:
          '/data/user/0/com.mediagrab.mediagrab/cache/player-ux-fixture.mp4',
    );
    expect(
      await File(path).exists(),
      true,
      reason: 'Copy the generated fixture into app cache before running.',
    );
    app.main();
    Future<void> until(bool Function() ready, String reason) async {
      for (var i = 0; i < 100 && !ready(); i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(ready(), true, reason: reason);
    }

    await until(
      () => find.byType(MediaGrabApp).evaluate().isNotEmpty,
      'normal app startup',
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MediaGrabApp)),
    );
    final settings = container.read(settingsProvider.notifier);
    await settings.ready;
    final original = container.read(settingsProvider).playback;
    final owner = container.read(playbackProvider.notifier);
    try {
      await settings.setPlayback(
        original.update('rememberPosition', false).update('pip', false),
      );
      container
          .read(appRouterProvider)
          .push(
            Uri(
              path: '/player',
              queryParameters: {'filePath': path, 'title': '720p UX fixture'},
            ).toString(),
          );
      await until(
        () => container.read(playbackProvider).initialized,
        'Media3 initialized',
      );
      final first = container.read(playbackProvider);
      expect(first.error, isNull);
      expect(first.width, 1280);
      expect(first.height, 720);
      expect(first.textureId, isNotNull);
      final texture = first.textureId;
      final generation = first.generation;
      await until(
        () => container.read(playbackProvider).position.inMilliseconds > 500,
        'decoded playback advances',
      );

      Offset videoArea() {
        final size = MediaQuery.sizeOf(
          tester.element(find.byType(Scaffold).last),
        );
        return Offset(size.width * .8, size.height * .28);
      }

      for (final speed in [1.0, 1.5, 1.75, 2.0]) {
        await owner.setSpeed(speed);
        await until(
          () => container.read(playbackProvider).speed == speed,
          'selected rate $speed',
        );
        final gesture = await tester.startGesture(videoArea());
        await tester.pump(const Duration(milliseconds: 600));
        await until(
          () => container.read(playbackProvider).speed == 2,
          'temporary 2x',
        );
        expect(
          find.byKey(const Key('temporary_speed_feedback')),
          findsOneWidget,
        );
        expect(owner.selectedSpeed, speed);
        await gesture.up();
        await until(
          () => container.read(playbackProvider).speed == speed,
          'restored rate $speed',
        );
        expect(owner.selectedSpeed, speed);
      }
      await owner.setSpeed(1);
      await owner.pause();
      await owner.seek(const Duration(seconds: 30));
      await until(
        () => container.read(playbackProvider).position.inSeconds == 30,
        'seek to 30s',
      );
      final area = videoArea();
      final taps = Stopwatch()..start();
      for (var i = 0; i < 4; i++) {
        await tester.tapAt(area);
        // Real touch input does not wait for a rendered frame between taps.
        // Keep the input burst independent of emulator frame-pump latency.
        await Future<void>.delayed(const Duration(milliseconds: 70));
      }
      debugPrint(
        'UX four-tap burst: ${taps.elapsedMilliseconds}ms, requested=${owner.seekBurst.target}',
      );
      expect(taps.elapsedMilliseconds, lessThan(800));
      await tester.pump(const Duration(milliseconds: 100));
      await until(
        () => container.read(playbackProvider).position.inSeconds == 60,
        'rapid cumulative 30s seek',
      );
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const Key('player_controls_opacity')),
            )
            .opacity,
        0,
      );
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 200));

      await settings.setPlayback(
        container
            .read(settingsProvider)
            .playback
            .update('volumeGesture', true)
            .update('brightnessGesture', true),
      );
      await owner.setVolume(.5);
      final brightness = await owner.readBrightness();
      for (final right in [false, true]) {
        final size = MediaQuery.sizeOf(
          tester.element(find.byType(Scaffold).last),
        );
        final gesture = await tester.startGesture(
          Offset(size.width * (right ? .8 : .2), size.height * .28),
        );
        await gesture.moveBy(const Offset(0, -60));
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          find.textContaining(right ? 'Volume' : 'Brightness'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<AnimatedOpacity>(
                find.byKey(const Key('player_controls_opacity')),
              )
              .opacity,
          0,
        );
        if (right) {
          await until(
            () => container.read(playbackProvider).volume > .5,
            'native volume changed',
          );
        } else {
          expect(await owner.readBrightness(), greaterThan(brightness));
        }
        await gesture.cancel();
        await tester.pump(const Duration(milliseconds: 250));
      }
      await settings.setPlayback(
        container
            .read(settingsProvider)
            .playback
            .update('volumeGesture', false)
            .update('brightnessGesture', false),
      );
      await tester.tap(find.byTooltip('Fullscreen'));
      await until(
        () =>
            MediaQuery.orientationOf(
              tester.element(find.byType(Scaffold).last),
            ) ==
            Orientation.landscape,
        'actual landscape rotation',
      );
      await tester.pump(const Duration(milliseconds: 800));
      expect(
        MediaQuery.orientationOf(tester.element(find.byType(Scaffold).last)),
        Orientation.landscape,
      );
      await tester.tap(find.byTooltip('Exit Fullscreen'));
      await until(
        () =>
            MediaQuery.orientationOf(
              tester.element(find.byType(Scaffold).last),
            ) ==
            Orientation.portrait,
        'actual portrait rotation',
      );
      await tester.pump(const Duration(milliseconds: 400));
      if (const bool.fromEnvironment('PLAYER_UX_SENSOR_ROTATION')) {
        await owner.setSpeed(1.75);
        await owner.togglePlay();
        await until(
          () => container.read(playbackProvider).playing,
          'play for rotation interruption',
        );
        final hold = await tester.startGesture(videoArea());
        await tester.pump(const Duration(milliseconds: 600));
        await until(
          () => container.read(playbackProvider).speed == 2,
          'hold before sensor rotation',
        );
        debugPrint('UX_SENSOR_ENABLE_LANDSCAPE');
        await until(
          () =>
              MediaQuery.orientationOf(
                tester.element(find.byType(Scaffold).last),
              ) ==
              Orientation.landscape,
          'system auto-rotate enabled and sensor landscape',
        );
        await until(
          () => container.read(playbackProvider).speed == 1.75,
          'rotation interrupted hold',
        );
        await hold.cancel();
        debugPrint('UX_SENSOR_PORTRAIT');
        await until(
          () =>
              MediaQuery.orientationOf(
                tester.element(find.byType(Scaffold).last),
              ) ==
              Orientation.portrait,
          'sensor portrait',
        );
        await owner.pause();
        await owner.seek(const Duration(seconds: 60));
        await until(
          () => container.read(playbackProvider).position.inSeconds == 60,
          'restore paused test position',
        );
        await tester.pump(const Duration(milliseconds: 300));
      }
      final before = tester.getRect(
        find.byKey(const Key('player_minimize_frame')),
      );
      final size = MediaQuery.sizeOf(
        tester.element(find.byType(Scaffold).last),
      );
      final downward = await tester.startGesture(
        Offset(size.width * .2, size.height * .25),
      );
      await downward.moveBy(Offset(0, size.height * .25));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getRect(find.byKey(const Key('player_minimize_frame'))).top,
        greaterThan(before.top),
      );
      await downward.up();
      await until(
        () =>
            find.byKey(const Key('playback_mini_player')).evaluate().isNotEmpty,
        'minimized',
      );
      expect(container.read(playbackProvider).textureId, texture);
      expect(container.read(playbackProvider).width, 1280);
      await tester.pump(const Duration(milliseconds: 300));
      debugPrint('UX_MINI_READY');
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('playback_mini_player')));
      await until(
        () =>
            find
                .byKey(const Key('video_player_back_button'))
                .evaluate()
                .isNotEmpty,
        'expanded',
      );
      expect(container.read(playbackProvider).generation, generation);
      expect(container.read(playbackProvider).textureId, texture);
      expect(container.read(playbackProvider).position.inSeconds, 60);
      expect(container.read(playbackProvider).error, isNull);
      debugPrint('UX_FULL_READY');
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    } finally {
      await owner.close();
      await settings.setPlayback(original);
      await tester.pump(const Duration(milliseconds: 500));
    }
  });
}
