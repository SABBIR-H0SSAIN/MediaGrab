import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediagrab/core/theme/app_theme.dart';
import 'package:mediagrab/features/player/presentation/screens/video_player_screen.dart';
import 'package:mediagrab/routing/app_router.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    hide VideoAudioTrack, VideoTrack;

class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  @override
  Future<void> init() async {}

  @override
  Widget buildView(int textureId) =>
      const SizedBox(key: Key('fake_video_view'));

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox(key: Key('fake_video_view'));
}

class FakeVideoPlayerController extends ValueNotifier<VideoPlayerValue>
    implements VideoPlayerController {
  FakeVideoPlayerController({VideoPlayerValue? initialValue})
    : super(
        initialValue ??
            const VideoPlayerValue(
              duration: Duration(minutes: 2, seconds: 15),
              isInitialized: true,
              size: Size(1920, 1080),
            ),
      );

  @override
  int playerId = 0;

  @override
  Future<void> dispose() async {
    super.dispose();
  }

  int get textureId => 0;

  @override
  String get dataSource => 'test.mp4';

  @override
  DataSourceType get dataSourceType => DataSourceType.file;

  @override
  Map<String, String> get httpHeaders => const {};

  @override
  String get package => '';

  @override
  VideoFormat? get formatHint => null;

  @override
  VideoViewType get viewType => VideoViewType.textureView;

  @override
  VideoPlayerOptions? get videoPlayerOptions => null;

  @override
  Future<ClosedCaptionFile> get closedCaptionFile =>
      Completer<ClosedCaptionFile>().future;

  @override
  Future<Duration> get position async => value.position;

  @override
  Future<void> initialize() async {
    value = value.copyWith(isInitialized: true);
  }

  @override
  Future<void> play() async {
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration moment) async {
    value = value.copyWith(position: moment);
  }

  @override
  Future<void> setLooping(bool looping) async {
    value = value.copyWith(isLooping: looping);
  }

  @override
  Future<void> setVolume(double volume) async {
    value = value.copyWith(volume: volume);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    value = value.copyWith(playbackSpeed: speed);
  }

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    bool prevents,
  ) async {}

  @override
  void setCaptionOffset(Duration delay) {}

  @override
  Future<void> setClosedCaptionFile(
    Future<ClosedCaptionFile>? closedCaptionFile,
  ) async {}

  @override
  Future<List<VideoTrack>> getVideoTracks() async => <VideoTrack>[];

  @override
  Future<void> selectVideoTrack(VideoTrack? track) async {}

  @override
  bool isVideoTrackSupportAvailable() => false;

  @override
  Future<List<VideoAudioTrack>> getAudioTracks() async => <VideoAudioTrack>[];

  @override
  Future<void> selectAudioTrack(String trackId) async {}

  @override
  bool isAudioTrackSupportAvailable() => false;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    VideoPlayerPlatform.instance = FakeVideoPlayerPlatform();
  });

  group('VideoPlayerScreen', () {
    testWidgets('pauses playback when the app enters the background', (
      tester,
    ) async {
      final controller = FakeVideoPlayerController();
      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerScreen(
            filePath: 'test.mp4',
            title: 'Lifecycle',
            controller: controller,
          ),
        ),
      );
      await controller.play();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(controller.value.isPlaying, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      await controller.dispose();
    });

    testWidgets('shows error state when file does not exist', (tester) async {
      String? openedPath;

      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerScreen(
            filePath: '/non/existent/path/test.mp4',
            title: 'Sample Video',
            onOpenExternal: (path) async {
              openedPath = path;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Sample Video'), findsOneWidget);
      expect(find.text('Failed to play video'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text('Open in External App'), findsOneWidget);

      // Tap the Open in External App button
      await tester.tap(find.text('Open in External App'));
      await tester.pump();

      expect(openedPath, '/non/existent/path/test.mp4');

      // External opening is kept in the playback settings menu.
      openedPath = null;
      await tester.tap(find.byTooltip('Playback settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('video_player_external_button')),
        200,
        scrollable:
            find
                .descendant(
                  of: find.byType(BottomSheet),
                  matching: find.byType(Scrollable),
                )
                .first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('video_player_external_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('video_player_external_button')));
      await tester.pump();

      expect(openedPath, '/non/existent/path/test.mp4');
    });

    testWidgets(
      'renders video player, title, controls, timestamp, and responds to actions',
      (tester) async {
        final controller = FakeVideoPlayerController();
        String? externalOpenedPath;

        await tester.pumpWidget(
          MaterialApp(
            home: VideoPlayerScreen(
              filePath: '/test/path/sample.mp4',
              title: 'Epic Big Buck Bunny',
              controller: controller,
              onOpenExternal: (path) async {
                externalOpenedPath = path;
              },
            ),
          ),
        );
        await tester.pump();

        // Title should be visible
        expect(find.text('Epic Big Buck Bunny'), findsOneWidget);

        // Center Play / Pause button is visible
        expect(
          find.byKey(const Key('video_player_play_pause_button')),
          findsOneWidget,
        );

        // Scrub slider is visible
        expect(
          find.byKey(const Key('video_player_scrub_slider')),
          findsOneWidget,
        );

        // Timestamp display is visible and formatted mm:ss / mm:ss
        expect(find.byKey(const Key('video_player_timestamp')), findsOneWidget);
        expect(find.text('00:00 / 02:15'), findsOneWidget);

        // Tapping Play/Pause button toggles play/pause
        await tester.tap(
          find.byKey(const Key('video_player_play_pause_button')),
        );
        await tester.pump();
        expect(controller.value.isPlaying, isTrue);

        await tester.tap(
          find.byKey(const Key('video_player_play_pause_button')),
        );
        await tester.pump();
        expect(controller.value.isPlaying, isFalse);

        // Tapping top bar external button triggers callback
        await tester.tap(find.byTooltip('Playback settings'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('video_player_external_button')),
          200,
          scrollable:
              find
                  .descendant(
                    of: find.byType(BottomSheet),
                    matching: find.byType(Scrollable),
                  )
                  .first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('video_player_external_button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('video_player_external_button')));
        await tester.pump();
        expect(externalOpenedPath, '/test/path/sample.mp4');

        // Unmount widget
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('auto-hides controls after 3 seconds of playing', (
      tester,
    ) async {
      final controller = FakeVideoPlayerController();
      await controller.play();

      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerScreen(
            filePath: '/test/path/sample.mp4',
            title: 'Playing Video',
            controller: controller,
          ),
        ),
      );
      await tester.pump();

      // Initially controls are visible
      final animatedOpacityFinder = find.byKey(
        const Key('player_controls_opacity'),
      );
      expect(animatedOpacityFinder, findsOneWidget);
      AnimatedOpacity opacityWidget = tester.widget(animatedOpacityFinder);
      expect(opacityWidget.opacity, 1.0);

      // Advance by 3 seconds
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));

      opacityWidget = tester.widget(animatedOpacityFinder);
      expect(opacityWidget.opacity, 0.0);

      // Unmount widget
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('navigating back via back button pops screen', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = FakeVideoPlayerController();
      bool popped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            onDidRemovePage: (page) {
              popped = true;
            },
            pages: [
              const MaterialPage(child: Scaffold(body: Text('Home'))),
              MaterialPage(
                child: VideoPlayerScreen(
                  filePath: '/test/path/sample.mp4',
                  title: 'Back Test',
                  controller: controller,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Back Test'), findsOneWidget);
      await tester.tap(find.byKey(const Key('video_player_back_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(popped, isTrue);

      // Unmount widget
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('GoRouter navigates to /player with filePath and title', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      router.push(
        '/player?filePath=${Uri.encodeComponent('/storage/videos/test.mp4')}&title=${Uri.encodeComponent('My Video')}',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(VideoPlayerScreen), findsOneWidget);
      expect(find.text('My Video'), findsOneWidget);

      // Unmount router widget
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('taps screen to toggle controls and scrubs slider to seek', (
      tester,
    ) async {
      final controller = FakeVideoPlayerController();

      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerScreen(
            filePath: '/test/path/sample.mp4',
            title: 'Controls Test',
            controller: controller,
          ),
        ),
      );
      await tester.pump();

      // Tap screen background (away from center play button) to toggle controls off
      await tester.tapAt(const Offset(50, 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      AnimatedOpacity opacityWidget = tester.widget(
        find.byKey(const Key('player_controls_opacity')),
      );
      expect(opacityWidget.opacity, 0.0);

      // Tap screen again to toggle controls on
      await tester.tapAt(const Offset(50, 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      opacityWidget = tester.widget(
        find.byKey(const Key('player_controls_opacity')),
      );
      expect(opacityWidget.opacity, 1.0);

      // Drag scrub slider
      final sliderFinder = find.byKey(const Key('video_player_scrub_slider'));
      expect(sliderFinder, findsOneWidget);
      await tester.drag(sliderFinder, const Offset(50, 0));
      await tester.pump();

      // Unmount
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'left and right double taps seek without visible skip buttons',
      (tester) async {
        final controller = FakeVideoPlayerController(
          initialValue: const VideoPlayerValue(
            duration: Duration(minutes: 5),
            position: Duration(seconds: 30),
            isInitialized: true,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: VideoPlayerScreen(
              filePath: '/test/path/sample.mp4',
              title: 'Seek 10s Test',
              controller: controller,
            ),
          ),
        );
        await tester.pump();

        await tester.tapAt(const Offset(100, 200));
        await tester.pump(const Duration(milliseconds: 70));
        await tester.tapAt(const Offset(100, 200));
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.value.position, const Duration(seconds: 20));

        await tester.tapAt(const Offset(700, 200));
        await tester.pump(const Duration(milliseconds: 70));
        await tester.tapAt(const Offset(700, 200));
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.value.position, const Duration(seconds: 30));

        // Unmount
        await tester.pumpWidget(const SizedBox());
      },
    );

    for (final scale in [1.0, 1.6]) {
      testWidgets(
        'landscape sheets scroll with one handle at text scale $scale',
        (tester) async {
          tester.view.physicalSize = const Size(844, 390);
          tester.view.devicePixelRatio = 1;
          tester.view.padding = const FakeViewPadding(
            left: 28,
            right: 12,
            top: 24,
            bottom: 16,
          );
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPadding);
          final controller = FakeVideoPlayerController();
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              builder:
                  (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
              home: VideoPlayerScreen(
                filePath: 'test.mp4',
                title: 'Landscape',
                controller: controller,
              ),
            ),
          );
          await tester.pumpAndSettle();
          // Physical rotation is reflected even when fullscreen wasn't tapped.
          expect(find.byTooltip('Exit Fullscreen'), findsOneWidget);
          expect(
            tester
                .getRect(find.byKey(const Key('video_player_back_button')))
                .left,
            greaterThanOrEqualTo(28),
          );
          await tester.tap(find.byTooltip('Playback settings'));
          await tester.pumpAndSettle();
          void expectSingleHandle() {
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
          }

          expectSingleHandle();
          final scrollable = find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          );
          await tester.scrollUntilVisible(
            find.descendant(
              of: find.widgetWithText(SwitchListTile, 'Loop video'),
              matching: find.byType(Switch),
            ),
            80,
            scrollable: scrollable,
          );
          await tester.tap(
            find.descendant(
              of: find.widgetWithText(SwitchListTile, 'Loop video'),
              matching: find.byType(Switch),
            ),
          );
          await tester.pumpAndSettle();
          expect(controller.value.isLooping, isTrue);
          await tester.scrollUntilVisible(
            find.text('Playback speed'),
            -80,
            scrollable: scrollable,
          );
          await tester.tap(find.text('Playback speed'));
          await tester.pumpAndSettle();
          expectSingleHandle();
          await tester.scrollUntilVisible(
            find.text('2.0x'),
            100,
            scrollable: find.descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('2.0x'));
          await tester.pumpAndSettle();
          expect(controller.value.playbackSpeed, 2.0);
          expect(find.byType(BottomSheet), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }

    testWidgets('settings gear opens playback settings sheet', (tester) async {
      final controller = FakeVideoPlayerController();

      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerScreen(
            filePath: '/test/path/sample.mp4',
            title: 'Settings Test',
            controller: controller,
          ),
        ),
      );
      await tester.pump();

      // Tap settings gear
      await tester.tap(find.byTooltip('Playback settings'));
      await tester.pumpAndSettle();

      expect(find.text('Playback Settings'), findsOneWidget);
      expect(find.text('Playback speed'), findsOneWidget);
      expect(find.text('Loop video'), findsOneWidget);

      // Tap loop switch
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(SwitchListTile, 'Loop video'),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.value.isLooping, isTrue);

      // Unmount
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'aspect ratio button cycles video fit mode with snackbar feedback',
      (tester) async {
        final controller = FakeVideoPlayerController();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VideoPlayerScreen(
                filePath: '/test/path/sample.mp4',
                title: 'Aspect Ratio Test',
                controller: controller,
              ),
            ),
          ),
        );
        await tester.pump();

        // Tap aspect ratio button
        await tester.tap(find.byTooltip('Playback settings'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Aspect ratio (Fit to screen)'),
          200,
          scrollable:
              find
                  .descendant(
                    of: find.byType(BottomSheet),
                    matching: find.byType(Scrollable),
                  )
                  .first,
        );
        await tester.tap(find.text('Aspect ratio (Fit to screen)'));
        await tester.pumpAndSettle();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Zoom to fill'), findsOneWidget);

        // Unmount
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
