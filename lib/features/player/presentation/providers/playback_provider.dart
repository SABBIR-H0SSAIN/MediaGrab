import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/playback_backend.dart';
import '../../domain/playback_preferences.dart';
import '../../domain/playback_state.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

final playbackBackendProvider = Provider<PlaybackBackend>(
  (ref) =>
      Platform.isAndroid
          ? AndroidPlaybackBackend()
          : VideoPlayerPlaybackBackend(),
);

final playbackProvider = StateNotifierProvider<PlaybackManager, PlaybackState>((
  ref,
) {
  final manager = PlaybackManager(
    ref.read(playbackBackendProvider),
    preferences: ref.read(settingsProvider).playback,
    settingsReady: ref.read(settingsProvider.notifier).ready,
    rememberSpeed: (speed) {
      final notifier = ref.read(settingsProvider.notifier);
      return notifier.setPlayback(
        ref.read(settingsProvider).playback.update('lastSpeed', speed),
      );
    },
  );
  ref.listen(
    settingsProvider.select((s) => s.playback),
    (_, next) => manager.applyPreferences(next),
  );
  return manager;
});

class PlaybackManager extends StateNotifier<PlaybackState>
    with WidgetsBindingObserver {
  PlaybackManager(
    this.backend, {
    PlaybackPreferences preferences = const PlaybackPreferences(),
    this.rememberSpeed,
    Future<void>? settingsReady,
  }) : _preferences = preferences,
       super(const PlaybackState()) {
    WidgetsBinding.instance.addObserver(this);
    _subscription = backend.states.listen(
      _receive,
      onError: (Object error) {
        if (mounted && state.hasSession) {
          _setError('Playback connection failed: $error');
        }
      },
    );
    _connection = _connect(settingsReady);
  }
  final PlaybackBackend backend;
  final Future<void> Function(double)? rememberSpeed;
  late final StreamSubscription<PlaybackState> _subscription;
  late final Future<void> _connection;
  PlaybackPreferences _preferences;
  PlaybackPreferences get preferences => _preferences;
  int _generation = 0;
  Future<void> _operations = Future<void>.value();
  Duration? _pendingSeek;
  bool _seeking = false;
  bool _visible = true;
  double? _heldSpeed;
  Future<void> _speedOperations = Future<void>.value();
  int _speedRevision = 0;
  double get selectedSpeed => _heldSpeed ?? state.speed;
  bool get holdingSpeed => _heldSpeed != null;
  final seekBurst = SeekBurst();

  Future<void> _connect(Future<void>? settingsReady) async {
    try {
      await settingsReady;
      if (!mounted) return;
      final restored = await backend.connect();
      if (!mounted || _generation != 0 || restored == null) return;
      _generation = restored.generation;
      _receive(restored);
      if (restored.hasSession) {
        await _command('preferences', _preferences.toJson());
      }
    } catch (_) {
      // Desktop/widget environments may not have native channels. A selected
      // item still exposes an actionable error if its load actually fails.
    }
  }

  void _receive(PlaybackState incoming) {
    if (!mounted || incoming.generation < _generation) return;
    if (incoming.index != state.index || incoming.generation != _generation) {
      // The new item already has its own native/default rate. An old hold must
      // not restore the previous item's selection over that rate.
      _heldSpeed = null;
      ++_speedRevision;
    }
    _generation = incoming.generation;
    final next = incoming.presentation(
      fullPlayer: state.fullPlayer,
      restoreRequested: incoming.restoreRequested || state.restoreRequested,
    );
    if (next != state) state = next;
  }

  void _setError(String message) {
    state = PlaybackState(
      items: state.items,
      index: state.index,
      generation: _generation,
      error: message,
      fullPlayer: state.fullPlayer,
    );
  }

  Future<void> open(PlaybackQueue queue) async {
    await _connection;
    if (!mounted) return;
    if (state.item?.filePath == queue.items[queue.index].filePath &&
        state.hasSession &&
        state.error == null) {
      showFullPlayer();
      return;
    }
    final hadTimer = state.timerRemaining > Duration.zero;
    await endSpeedHold();
    final generation = ++_generation;
    seekBurst.reset();
    _pendingSeek = null;
    state = PlaybackState(
      items: queue.items,
      index: queue.index,
      generation: generation,
      loading: true,
      fullPlayer: true,
    );
    unawaited(_command('presentation', {'fullPlayer': true}));
    _operations = _operations.then((_) async {
      if (!mounted || generation != _generation) return;
      try {
        await backend.load(queue, generation, _preferences);
        if (mounted &&
            generation == _generation &&
            !hadTimer &&
            _preferences.defaultTimerMinutes > 0) {
          await _command('timer', {
            'minutes': _preferences.defaultTimerMinutes,
            'onlyIfInactive': true,
          });
        }
        if (mounted && generation == _generation && !_visible) {
          await _command('visible', {'visible': false});
        }
      } catch (e) {
        if (mounted && generation == _generation) {
          _setError('Could not play this local file: $e');
        }
      }
    });
    await _operations;
  }

  Future<void> _command(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async {
    try {
      await backend.command(name, {'generation': _generation, ...arguments});
    } catch (e) {
      if (mounted && state.hasSession) _setError('Playback command failed: $e');
    }
  }

  Future<void> togglePlay() => state.playing ? pause() : _command('play');
  Future<void> pause() {
    unawaited(endSpeedHold());
    return _command('pause');
  }

  Future<void> next() {
    unawaited(endSpeedHold());
    seekBurst.reset();
    return _command('next');
  }

  Future<void> previous() {
    unawaited(endSpeedHold());
    seekBurst.reset();
    return _command('previous');
  }

  Future<void> setLoop(bool loop) => _command('loop', {'loop': loop});
  Future<void> setVolume(double value) =>
      _command('volume', {'volume': value.clamp(0, 1)});
  Future<void> setAudioOnly(bool enabled) =>
      _command('audioOnly', {'enabled': enabled && _preferences.audioOnly});
  Future<void> setSpeed(double speed) async {
    if (!PlaybackPreferences.speeds.contains(speed)) return;
    _heldSpeed = null;
    await _sendSpeed(speed, temporary: false);
    await rememberSpeed?.call(speed);
  }

  // Transient rate changes never write preferences or the native queue's rate.
  // Serialize activation/restoration so even a release before acknowledgement
  // leaves the backend at the exact selected rate.
  Future<void> _sendSpeed(
    double speed, {
    required bool temporary,
    bool holding = false,
  }) {
    final generation = _generation;
    final revision = _speedRevision;
    _speedOperations = _speedOperations.then((_) async {
      if (!mounted || generation != _generation || revision != _speedRevision) {
        return;
      }
      await _command('speed', {
        'speed': speed,
        'temporary': temporary,
        'holding': holding,
      });
    });
    return _speedOperations;
  }

  Future<void> beginSpeedHold() {
    if (_heldSpeed != null || !state.initialized || !state.playing) {
      return Future<void>.value();
    }
    _heldSpeed = state.speed;
    return _sendSpeed(2, temporary: true, holding: true);
  }

  Future<void> endSpeedHold() {
    final speed = _heldSpeed;
    _heldSpeed = null;
    return speed == null
        ? _speedOperations
        : _sendSpeed(speed, temporary: true);
  }

  Future<void> setTimer(int minutes) =>
      _command('timer', {'minutes': minutes.clamp(0, 1440)});
  Future<bool> enterPip() async {
    if (!state.pipSupported) return false;
    try {
      await backend.command('pip', {'generation': _generation});
      return true;
    } catch (_) {
      // A denied PiP request must not invalidate otherwise healthy playback.
      return false;
    }
  }

  Future<void> setBrightness(double value) =>
      _command('brightness', {'brightness': value.clamp(0, 1)});
  Future<double> readBrightness() async {
    try {
      final current = backend;
      return current is AndroidPlaybackBackend
          ? await current.readBrightness()
          : .5;
    } catch (_) {
      return .5;
    }
  }

  Future<void> resetBrightness() =>
      _command('brightness', {'brightness': -1.0});
  Future<void> followSystemRotation() => _command('followSystemRotation');
  Future<void> prepareOrientation(bool? landscape) =>
      _command('orientationRequest', {'landscape': landscape});
  Future<void> videoBounds(Rect rect, double ratio) => _command('bounds', {
    'left': (rect.left * ratio).round(),
    'top': (rect.top * ratio).round(),
    'right': (rect.right * ratio).round(),
    'bottom': (rect.bottom * ratio).round(),
  });

  int skip(int direction, {DateTime? now}) {
    if (!state.initialized) return 0;
    final target = seekBurst.skip(
      direction: direction,
      seconds: _preferences.seekSeconds,
      position: state.position,
      duration: state.duration,
      now: now ?? DateTime.now(),
    );
    unawaited(_seek(target));
    return seekBurst.cumulativeSeconds;
  }

  Future<void> seek(Duration position) {
    seekBurst.reset();
    return _seek(position);
  }

  Future<void> _seek(Duration position) async {
    _pendingSeek = Duration(
      milliseconds: position.inMilliseconds.clamp(
        0,
        state.duration.inMilliseconds,
      ),
    );
    if (_seeking) return;
    _seeking = true;
    final generation = _generation;
    try {
      while (mounted && _pendingSeek != null && generation == _generation) {
        final target = _pendingSeek!;
        _pendingSeek = null;
        await _command('seek', {'position': target.inMilliseconds});
      }
    } finally {
      _seeking = false;
      if (mounted && _pendingSeek != null) unawaited(_seek(_pendingSeek!));
    }
  }

  void showFullPlayer() {
    if (mounted) {
      unawaited(_command('presentation', {'fullPlayer': true}));
      state = state.presentation(fullPlayer: true, restoreRequested: false);
    }
  }

  void consumeRestore() {
    if (mounted) state = state.presentation(restoreRequested: false);
  }

  void minimize() {
    if (!mounted) return;
    unawaited(_command('presentation', {'fullPlayer': false}));
    unawaited(endSpeedHold());
    unawaited(resetBrightness());
    if (!_preferences.miniPlayer) {
      unawaited(close());
      return;
    }
    state = state.presentation(fullPlayer: false);
  }

  Future<void> close() async {
    _heldSpeed = null;
    unawaited(_command('presentation', {'fullPlayer': false}));
    ++_generation;
    _pendingSeek = null;
    seekBurst.reset();
    state = PlaybackState(generation: _generation);
    // Close must also invalidate a load still waiting in the command queue.
    _operations = _operations.then((_) async {
      await _command('close');
    });
    await _operations;
  }

  void applyPreferences(PlaybackPreferences preferences) {
    _preferences = preferences;
    if (!state.hasSession) return;
    unawaited(_command('preferences', preferences.toJson()));
    if (!preferences.audioOnly &&
        state.audioOnly &&
        state.item?.isAudio != true) {
      unawaited(setAudioOnly(false));
    }
    if (!preferences.miniPlayer && !state.fullPlayer) unawaited(close());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(endSpeedHold());
    if (state == AppLifecycleState.inactive) return;
    _visible = state == AppLifecycleState.resumed;
    if (!this.state.hasSession) return;
    unawaited(_command('visible', {'visible': _visible}));
    if (!_visible) unawaited(resetBrightness());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ++_generation;
    unawaited(_subscription.cancel());
    unawaited(backend.dispose());
    super.dispose();
  }
}
