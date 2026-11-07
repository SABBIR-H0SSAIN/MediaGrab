import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/player/data/playback_backend.dart';
import 'package:mediagrab/features/player/domain/playback_preferences.dart';
import 'package:mediagrab/features/player/domain/playback_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(AndroidPlaybackBackend.channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'snapshot') {
        return {
          'generation': 9,
          'index': 0,
          'initialized': true,
          'playing': true,
          'queue': [
            {
              'id': 'local',
              'filePath': '/local.mp4',
              'title': 'Offline',
              'isAudio': false,
            },
          ],
          'position': 42000,
          'duration': 120000,
          'speed': 1.5,
          'textureId': 7,
          'pipSupported': true,
        };
      }
      return null;
    });
  });
  tearDown(
    () => messenger.setMockMethodCallHandler(
      AndroidPlaybackBackend.channel,
      null,
    ),
  );
  test(
    'reconnection hydrates native state and never loads another player',
    () async {
      final backend = AndroidPlaybackBackend();
      final restored = await backend.connect();
      expect(restored!.generation, 9);
      expect(restored.position, const Duration(seconds: 42));
      expect(restored.speed, 1.5);
      expect(restored.textureId, 7);
      expect(restored.item!.filePath, '/local.mp4');
      await backend.dispose();
      expect(calls.map((c) => c.method), ['snapshot', 'disconnect']);
    },
  );
  test(
    'queue loading forwards local metadata, exact selection, generation and preferences',
    () async {
      final backend = AndroidPlaybackBackend();
      final queue = PlaybackQueue([
        const PlaybackItem(id: 'v', filePath: '/v.mp4', title: 'Video'),
        const PlaybackItem(
          id: 'a',
          filePath: '/a.mp3',
          title: 'Audio',
          isAudio: true,
          artworkPath: '/art.jpg',
        ),
      ], index: 1);
      await backend.load(
        queue,
        12,
        const PlaybackPreferences(background: false, seekSeconds: 15),
      );
      final arguments = Map<Object?, Object?>.from(
        calls.single.arguments as Map,
      );
      expect(calls.single.method, 'load');
      expect(arguments['index'], 1);
      expect(arguments['generation'], 12);
      final items = arguments['queue'] as List;
      expect((items[1] as Map)['isAudio'], true);
      expect((items[1] as Map)['artworkPath'], '/art.jpg');
      expect((arguments['preferences'] as Map)['background'], false);
      expect((arguments['preferences'] as Map)['seekSeconds'], 15);
    },
  );
  test(
    'surface backends can delegate rotation or correct quarter turns without replacing playback',
    () {
      final backend = AndroidPlaybackBackend();
      for (final rotation in [0, 90, 180, 270]) {
        final state = PlaybackState.fromJson({
          'textureId': 7,
          'rotation': rotation,
          'width': 720,
          'height': 1280,
        });
        expect(state.aspectRatio, 720 / 1280);
        expect(state.presentation(fullPlayer: false).rotation, rotation);
        final view = backend.buildVideo(state);
        if (rotation == 0) {
          expect(view, isA<Texture>());
        } else {
          expect(view, isA<RotatedBox>());
          expect((view as RotatedBox).quarterTurns, rotation ~/ 90);
          expect((view.child as Texture).textureId, 7);
        }
      }
      expect(PlaybackState.fromJson({'rotation': 17}).rotation, 0);
    },
  );
}
