import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/player/data/playback_backend.dart';
import 'package:mediagrab/features/player/domain/playback_preferences.dart';
import 'package:mediagrab/features/player/domain/playback_state.dart';
import 'package:mediagrab/features/player/presentation/providers/playback_provider.dart';

class ControlledBackend implements PlaybackBackend {
  final events = StreamController<PlaybackState>.broadcast(sync: true);
  final loads = <int>[];
  final commands = <(String, Map<String, Object?>)>[];
  Completer<void>? loadGate, seekGate, speedGate;
  int generation = 0;
  List<PlaybackItem> items = const [];
  @override
  Stream<PlaybackState> get states => events.stream;
  @override
  Future<PlaybackState?> connect() async => null;
  @override
  Future<void> load(
    PlaybackQueue queue,
    int generation,
    PlaybackPreferences preferences,
  ) async {
    loads.add(generation);
    this.generation = generation;
    items = queue.items;
    await loadGate?.future;
    emit();
  }

  void emit({int? token, Duration position = Duration.zero}) => events.add(
    PlaybackState(
      items: items,
      generation: token ?? generation,
      initialized: true,
      duration: const Duration(minutes: 5),
      position: position,
    ),
  );
  @override
  Future<void> command(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async {
    commands.add((name, arguments));
    if (name == 'seek') await seekGate?.future;
    if (name == 'speed') await speedGate?.future;
  }

  @override
  Widget buildVideo(PlaybackState state) => const SizedBox();
  @override
  Future<void> dispose() => events.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PlaybackQueue queue(String name) => PlaybackQueue([
    PlaybackItem(id: name, filePath: '/$name.mp4', title: name),
  ]);
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test(
    'close during initialization rejects late loaded state and closes native session',
    () async {
      final backend = ControlledBackend()..loadGate = Completer<void>();
      final manager = PlaybackManager(backend);
      final opening = manager.open(queue('a'));
      await settle();
      final closing = manager.close();
      backend.loadGate!.complete();
      await Future.wait([opening, closing]);
      expect(manager.state.hasSession, false);
      expect(backend.commands.last.$1, 'close');
      manager.dispose();
    },
  );
  test(
    'replacement serializes loads and ignores previous generations',
    () async {
      final backend = ControlledBackend()..loadGate = Completer<void>();
      final manager = PlaybackManager(backend);
      final first = manager.open(queue('a'));
      await settle();
      final second = manager.open(queue('b'));
      await settle();
      backend.loadGate!.complete();
      await Future.wait([first, second]);
      expect(backend.loads, [1, 2]);
      expect(manager.state.item!.title, 'b');
      backend.emit(token: 1, position: const Duration(seconds: 99));
      expect(manager.state.position, Duration.zero);
      manager.dispose();
    },
  );
  test(
    'short speed holds serialize restoration without saving a temporary rate',
    () async {
      final backend = ControlledBackend();
      final remembered = <double>[];
      final manager = PlaybackManager(
        backend,
        rememberSpeed: (speed) async {
          remembered.add(speed);
        },
      );
      await manager.open(queue('a'));
      for (final rate in [0.25, 0.5, 1.0, 1.25, 1.5, 1.75, 2.0]) {
        backend.events.add(
          PlaybackState(
            items: backend.items,
            generation: backend.generation,
            initialized: true,
            playing: true,
            speed: rate,
          ),
        );
        backend.speedGate = Completer<void>();
        final start = manager.beginSpeedHold();
        await settle();
        final end = manager.endSpeedHold();
        backend.speedGate!.complete();
        await Future.wait([start, end]);
        final speeds = backend.commands.where((c) => c.$1 == 'speed').toList();
        expect(speeds[speeds.length - 2].$2['speed'], 2);
        expect(speeds.last.$2['speed'], rate);
        expect(speeds.last.$2['temporary'], true);
      }
      expect(remembered, isEmpty);
      manager.dispose();
    },
  );

  test('automatic next item cannot inherit a held rate restoration', () async {
    final backend = ControlledBackend();
    final manager = PlaybackManager(backend);
    await manager.open(
      PlaybackQueue([
        const PlaybackItem(id: 'a', filePath: '/a.mp4', title: 'A'),
        const PlaybackItem(id: 'b', filePath: '/b.mp4', title: 'B'),
      ]),
    );
    backend.events.add(
      PlaybackState(
        items: backend.items,
        generation: backend.generation,
        initialized: true,
        playing: true,
        speed: 1.75,
      ),
    );
    await manager.beginSpeedHold();
    final commands = backend.commands.length;
    backend.events.add(
      PlaybackState(
        items: backend.items,
        index: 1,
        generation: backend.generation,
        initialized: true,
        playing: true,
        speed: 1,
      ),
    );
    await manager.endSpeedHold();
    expect(manager.selectedSpeed, 1);
    expect(backend.commands.length, commands);
    manager.dispose();
  });

  test('same item expansion does not reload the active backend', () async {
    final backend = ControlledBackend();
    final manager = PlaybackManager(backend);
    await manager.open(queue('a'));
    backend.emit(position: const Duration(seconds: 41));
    manager.minimize();
    await manager.open(queue('a'));
    expect(backend.loads, [1]);
    expect(manager.state.position, const Duration(seconds: 41));
    expect(manager.state.fullPlayer, true);
    manager.dispose();
  });
  test(
    'rapid seek commands coalesce while acknowledgements are delayed',
    () async {
      final backend = ControlledBackend();
      final manager = PlaybackManager(backend);
      await manager.open(queue('a'));
      backend.seekGate = Completer<void>();
      final now = DateTime(2026);
      manager.skip(1, now: now);
      manager.skip(1, now: now.add(const Duration(milliseconds: 50)));
      manager.skip(1, now: now.add(const Duration(milliseconds: 100)));
      expect(backend.commands.where((c) => c.$1 == 'seek').length, 1);
      backend.seekGate!.complete();
      await settle();
      final seeks = backend.commands.where((c) => c.$1 == 'seek').toList();
      expect(seeks.map((c) => c.$2['position']), [10000, 30000]);
      manager.dispose();
    },
  );
  test(
    'mini-player disabled closes on leaving and shade does not send pause',
    () async {
      final backend = ControlledBackend();
      final manager = PlaybackManager(
        backend,
        preferences: const PlaybackPreferences(miniPlayer: false),
      );
      await manager.open(queue('a'));
      backend.commands.clear();
      manager.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(backend.commands, isEmpty);
      manager.minimize();
      await settle();
      expect(manager.state.hasSession, false);
      expect(backend.commands.any((c) => c.$1 == 'close'), true);
      manager.dispose();
    },
  );
  test(
    'replacement does not restart the default timer over an active deadline',
    () async {
      final backend = ControlledBackend();
      final manager = PlaybackManager(
        backend,
        preferences: const PlaybackPreferences(defaultTimerMinutes: 30),
      );
      await manager.open(queue('a'));
      backend.events.add(
        PlaybackState(
          items: backend.items,
          generation: backend.generation,
          initialized: true,
          timerRemaining: const Duration(minutes: 12),
        ),
      );
      await manager.open(queue('b'));
      expect(
        backend.commands.where((command) => command.$1 == 'timer').length,
        1,
      );
      manager.dispose();
    },
  );
}
