import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mediagrab/features/player/data/playback_backend.dart';
import 'package:mediagrab/features/player/domain/playback_preferences.dart';
import 'package:mediagrab/features/player/domain/playback_state.dart';
import 'package:mediagrab/features/player/presentation/providers/playback_provider.dart';
import 'package:mediagrab/features/player/presentation/screens/video_player_screen.dart';
import 'package:mediagrab/features/player/presentation/widgets/mini_player.dart';
import 'package:mediagrab/features/settings/presentation/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    hide VideoAudioTrack, VideoTrack;
import 'video_player_screen_test.dart'
    show FakeVideoPlayerController, FakeVideoPlayerPlatform;

class CountingBackend extends VideoPlayerPlaybackBackend {
  CountingBackend(VideoPlayerController controller)
    : super(controller: controller);
  int loads = 0, videoBuilds = 0;
  @override
  Widget buildVideo(PlaybackState state) {
    videoBuilds++;
    return super.buildVideo(state);
  }

  @override
  Future<void> load(
    PlaybackQueue queue,
    int generation,
    PlaybackPreferences preferences,
  ) {
    loads++;
    return super.load(queue, generation, preferences);
  }
}

void main() {
  late FakeVideoPlayerController controller;
  late CountingBackend backend;
  late ProviderContainer container;
  late GoRouter router;
  final boundary = GlobalKey();
  setUp(() async {
    VideoPlayerPlatform.instance = FakeVideoPlayerPlatform();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    controller = FakeVideoPlayerController(
      initialValue: const VideoPlayerValue(
        duration: Duration(minutes: 5),
        position: Duration(seconds: 30),
        isInitialized: true,
        size: Size(1920, 1080),
      ),
    );
    backend = CountingBackend(controller);
    container = ProviderContainer(
      overrides: [
        playbackBackendProvider.overrideWithValue(backend),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    router = GoRouter(
      initialLocation: '/player?filePath=%2Flocal.mp4&title=Offline%20video',
      routes: [
        GoRoute(
          path: '/home',
          builder:
              (_, _) => const Scaffold(
                body: Center(child: Text('Home')),
                bottomNavigationBar: MiniPlayer(),
              ),
        ),
        GoRoute(
          path: '/player',
          builder:
              (_, _) => const VideoPlayerScreen(
                filePath: '/local.mp4',
                title: 'Offline video',
              ),
        ),
      ],
    );
  });
  tearDown(() async {
    router.dispose();
    container.dispose();
    await controller.dispose();
  });
  Future<void> show(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const previewPath = String.fromEnvironment('PLAYBACK_SCREENSHOT');
    if (previewPath.isNotEmpty) {
      await tester.runAsync(() async {
        await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        final font = File('/System/Library/Fonts/Supplemental/Arial.ttf');
        if (font.existsSync()) {
          await (FontLoader('PlaybackPreview')..addFont(
            font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          )).load();
        }
      });
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: ThemeData.dark().copyWith(
            textTheme: ThemeData.dark().textTheme.apply(
              fontFamily: previewPath.isEmpty ? null : 'PlaybackPreview',
            ),
          ),
          builder:
              (context, child) => RepaintBoundary(
                key: boundary,
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(textScale)),
                  child: child!,
                ),
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'compact controls retain sizing and double-tap burst accumulation',
    (tester) async {
      await show(tester);
      final play = tester.widget<IconButton>(
        find.byKey(const Key('video_player_play_pause_button')),
      );
      expect(play.iconSize, 36);
      expect(
        tester
            .getSize(find.byKey(const Key('video_player_play_pause_button')))
            .shortestSide,
        greaterThanOrEqualTo(48),
      );
      for (var i = 1; i <= 3; i++) {
        await tester.tapAt(const Offset(320, 200));
        if (i == 1) {
          await tester.pump(const Duration(milliseconds: 70));
          await tester.tapAt(const Offset(320, 200));
        }
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.value.position, Duration(seconds: 30 + i * 10));
        expect(find.text('+${i * 10}'), findsOneWidget);
      }
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('+30'), findsNothing);
      expect(tester.takeException(), isNull);
      const screenshot = String.fromEnvironment('PLAYBACK_SCREENSHOT');
      if (screenshot.isNotEmpty) {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 1);
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(screenshot).writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final speed in [0.25, 0.5, 1.0, 1.25, 1.5, 1.75, 2.0]) {
    testWidgets(
      'hold temporarily boosts $speed and release restores selection',
      (tester) async {
        await show(tester);
        final owner = container.read(playbackProvider.notifier);
        await owner.setSpeed(speed);
        await controller.play();
        await tester.pump();
        final gesture = await tester.startGesture(const Offset(320, 200));
        await tester.pump(const Duration(milliseconds: 550));
        expect(controller.value.playbackSpeed, 2);
        expect(owner.selectedSpeed, speed);
        expect(
          find.byKey(const Key('temporary_speed_feedback')),
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
        await gesture.up();
        await tester.pump();
        expect(controller.value.playbackSpeed, speed);
        expect(owner.selectedSpeed, speed);
        expect(find.byKey(const Key('temporary_speed_feedback')), findsNothing);
        expect(backend.loads, 1);
        await tester.tap(find.byKey(const Key('playback_speed_button')));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Close Playback Speed'), findsNothing);
        final selected =
            tester
                .widgetList<ListTile>(find.byType(ListTile))
                .where((tile) => tile.selected)
                .single;
        expect(
          (selected.title! as Text).data,
          speed == 1 ? 'Normal' : '${speed}x',
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('hold cancellation, rotation and background restore exact rate', (
    tester,
  ) async {
    await show(tester);
    await container.read(playbackProvider.notifier).setSpeed(1.75);
    await controller.play();
    for (final interrupt in ['cancel', 'rotate', 'background']) {
      await tester.pump();
      final gesture = await tester.startGesture(const Offset(100, 130));
      await tester.pump(const Duration(milliseconds: 550));
      expect(controller.value.playbackSpeed, 2);
      if (interrupt == 'cancel') {
        await gesture.cancel();
      } else if (interrupt == 'rotate') {
        tester.view.physicalSize = const Size(844, 390);
        await tester.pump();
        await gesture.up();
      } else {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        await gesture.up();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pumpAndSettle();
      expect(controller.value.playbackSpeed, 1.75);
      expect(backend.loads, 1);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'short hold does not change speed and horizontal drag takes precedence',
    (tester) async {
      await show(tester);
      await container.read(playbackProvider.notifier).setSpeed(1.5);
      await controller.play();
      final gesture = await tester.startGesture(const Offset(320, 200));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 350));
      expect(controller.value.playbackSpeed, 1.5);
      await tester.dragFrom(const Offset(100, 200), const Offset(90, 0));
      await tester.pumpAndSettle();
      expect(controller.value.playbackSpeed, 1.5);
      expect(find.byKey(const Key('temporary_speed_feedback')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('seek feedback isolates controls and leaves timeline visible', (
    tester,
  ) async {
    await show(tester);
    await tester.tapAt(const Offset(320, 200));
    await tester.pump(const Duration(milliseconds: 70));
    await tester.tapAt(const Offset(320, 200));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const Key('player_controls_opacity')),
          )
          .opacity,
      0,
    );
    expect(
      find.byKey(const Key('video_player_scrub_slider')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('video_player_play_pause_button')).hitTestable(),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const Key('player_controls_opacity')),
          )
          .opacity,
      1,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'optional adjustment gestures hide controls and respect disabled settings',
    (tester) async {
      await show(tester);
      final settings = container.read(settingsProvider.notifier);
      await settings.setPlayback(
        container
            .read(settingsProvider)
            .playback
            .update('volumeGesture', true)
            .update('brightnessGesture', true),
      );
      await tester.pump();
      for (final x in [70.0, 320.0]) {
        final gesture = await tester.startGesture(Offset(x, 250));
        await gesture.moveBy(const Offset(0, -60));
        await tester.pump();
        expect(
          find.textContaining(x < 100 ? 'Brightness' : 'Volume'),
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
        expect(
          find.byKey(const Key('video_player_play_pause_button')).hitTestable(),
          findsNothing,
        );
        await gesture.cancel();
        await tester.pumpAndSettle();
      }
      await settings.setPlayback(
        container
            .read(settingsProvider)
            .playback
            .update('volumeGesture', false),
      );
      await tester.pump();
      final gesture = await tester.startGesture(const Offset(320, 250));
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump();
      expect(find.textContaining('Volume'), findsNothing);
      await gesture.cancel();
      await tester.pumpAndSettle();
      await settings.setPlayback(
        container.read(settingsProvider).playback.update('volumeGesture', true),
      );
      await tester.pump();
      await tester.dragFrom(const Offset(195, 200), const Offset(0, 170));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('playback_mini_player')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'position ticks update timeline without rebuilding the video surface',
    (tester) async {
      await show(tester);
      final builds = backend.videoBuilds;
      for (var i = 31; i < 40; i++) {
        await controller.seekTo(Duration(seconds: i));
        await tester.pump();
      }
      expect(backend.videoBuilds, builds);
      expect(find.text('00:39 / 05:00'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'orientation button requests both directions and preserves the session',
    (tester) async {
      final orientations = <List<Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            orientations.add(List<Object?>.from(call.arguments as List));
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await show(tester);
      await tester.tap(find.byTooltip('Fullscreen'));
      await tester.pump();
      expect(orientations.last, [
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Exit Fullscreen'));
      await tester.pump();
      expect(orientations.last, ['DeviceOrientation.portraitUp']);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Fullscreen'), findsOneWidget);
      expect(backend.loads, 1);
      expect(controller.value.position, const Duration(seconds: 30));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'full to mini to full preserves position and does not reload player',
    (tester) async {
      await show(tester);
      await controller.play();
      await controller.seekTo(const Duration(seconds: 42));
      await tester.tap(find.byKey(const Key('video_player_back_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('playback_mini_player')), findsOneWidget);
      expect(controller.value.isPlaying, true);
      expect(controller.value.position, const Duration(seconds: 42));
      await tester.drag(
        find.byKey(const Key('playback_mini_player')),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(find.byType(VideoPlayerScreen), findsOneWidget);
      expect(controller.value.position, const Duration(seconds: 42));
      expect(backend.loads, 1);
      await tester.tap(find.byKey(const Key('video_player_back_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mini_player_close')));
      await tester.pumpAndSettle();
      expect(container.read(playbackProvider).hasSession, false);
      expect(controller.value.isPlaying, false);
      expect(find.byKey(const Key('playback_mini_player')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'video-area swipe minimizes and lock blocks gestures until unlocked',
    (tester) async {
      await show(tester);
      await tester.tap(find.byTooltip('Playback settings'));
      await tester.pumpAndSettle();
      final sheet = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Lock screen controls'),
        100,
        scrollable: sheet,
      );
      await tester.tap(find.text('Lock screen controls'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Unlock controls'), findsOneWidget);
      await tester.dragFrom(const Offset(60, 170), const Offset(0, 150));
      await tester.pumpAndSettle();
      expect(container.read(playbackProvider).fullPlayer, true);
      expect(controller.value.position, const Duration(seconds: 30));
      await tester.tap(find.byTooltip('Unlock controls'));
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(60, 170), const Offset(0, 150));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('playback_mini_player')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'small portrait controls support enlarged text without overflow',
    (tester) async {
      await show(tester, textScale: 2);
      tester.view.physicalSize = const Size(320, 568);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'double-tap seeks once without toggling playback or control buttons',
    (tester) async {
      await show(tester);
      const location = Offset(320, 200);
      await tester.tapAt(location);
      await tester.pump(const Duration(milliseconds: 70));
      await tester.tapAt(location);
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.value.position, const Duration(seconds: 40));
      expect(controller.value.isPlaying, false);
      expect(find.text('+10'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('seek buffering retains controls for further cumulative taps', (
    tester,
  ) async {
    await show(tester);
    controller.value = controller.value.copyWith(isBuffering: true);
    await tester.pump();
    expect(container.read(playbackProvider).loading, true);
    expect(find.byTooltip('Play'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.tapAt(const Offset(320, 200));
      if (i == 0) {
        await tester.pump(const Duration(milliseconds: 70));
        await tester.tapAt(const Offset(320, 200));
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(controller.value.position, const Duration(seconds: 60));
    expect(find.text('+30'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'failed media clears the previous video surface behind its error',
    (tester) async {
      await show(tester);
      expect(find.byKey(const Key('fake_video_view')), findsOneWidget);
      controller.value = const VideoPlayerValue.erroneous('Corrupt local file');
      await tester.pump();
      expect(find.text('Corrupt local file'), findsOneWidget);
      expect(find.byKey(const Key('fake_video_view')), findsNothing);
      expect(find.text('Open in External App'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'landscape swipe tracks the finger and docks directly without reloading',
    (tester) async {
      final orientations = <List<Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            orientations.add(List<Object?>.from(call.arguments as List));
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await show(tester);
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      const screenshot = String.fromEnvironment('PLAYBACK_SCREENSHOT');
      if (screenshot.isNotEmpty) {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 1);
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              screenshot.replaceAll('.png', '-landscape.png'),
            ).writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
      final before = tester.getRect(
        find.byKey(const Key('player_minimize_frame')),
      );
      final gesture = await tester.startGesture(const Offset(100, 100));
      await gesture.moveBy(const Offset(0, 90));
      await tester.pump();
      final dragging = tester.getRect(
        find.byKey(const Key('player_minimize_frame')),
      );
      expect(dragging.height, lessThan(before.height));
      expect(dragging.top, greaterThan(before.top));
      expect(find.byKey(const Key('fake_video_view')), findsOneWidget);
      expect(backend.loads, 1);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(VideoPlayerScreen), findsNothing);
      expect(orientations.last, ['DeviceOrientation.portraitUp']);
      expect(find.byKey(const Key('playback_mini_player')), findsOneWidget);
      expect(container.read(playbackProvider).fullPlayer, false);
      expect(controller.value.position, const Duration(seconds: 30));
      expect(backend.loads, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('cancelled downward drag restores the full player', (
    tester,
  ) async {
    await show(tester);
    final before = tester.getRect(
      find.byKey(const Key('player_minimize_frame')),
    );
    final gesture = await tester.startGesture(const Offset(80, 180));
    await gesture.moveBy(const Offset(0, 35));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const Key('player_minimize_frame'))),
      before,
    );
    expect(container.read(playbackProvider).fullPlayer, true);
    expect(backend.loads, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('bottom stays uncluttered with speed beside fullscreen', (
    tester,
  ) async {
    await show(tester);
    expect(find.byIcon(Icons.replay_10_rounded), findsNothing);
    expect(find.byIcon(Icons.forward_10_rounded), findsNothing);
    expect(find.byIcon(Icons.bedtime_outlined), findsNothing);
    expect(find.byTooltip('Lock screen controls'), findsNothing);
    final speed = tester.getRect(
      find.byKey(const Key('playback_speed_button')),
    );
    final fullscreen = tester.getRect(find.byTooltip('Fullscreen'));
    expect(speed.right, lessThanOrEqualTo(fullscreen.left));
    expect(speed.center.dy, fullscreen.center.dy);
    await tester.tap(find.byTooltip('Playback settings'));
    await tester.pumpAndSettle();
    expect(find.text('Sleep timer'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('late fullscreen initialization cannot undo the portrait dock', (
    tester,
  ) async {
    final gate = Completer<void>();
    var first = true;
    final orientations = <List<Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setEnabledSystemUIMode' && first) {
          first = false;
          await gate.future;
        }
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientations.add(List<Object?>.from(call.arguments as List));
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await show(tester);
    await tester.dragFrom(const Offset(80, 180), const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('playback_mini_player')), findsOneWidget);
    expect(orientations.last, ['DeviceOrientation.portraitUp']);
    gate.complete();
    await tester.pumpAndSettle();
    expect(orientations.last, ['DeviceOrientation.portraitUp']);
    expect(backend.loads, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
