import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';
import '../domain/playback_preferences.dart';
import '../domain/playback_state.dart';

abstract class PlaybackBackend {
  Stream<PlaybackState> get states;
  Future<PlaybackState?> connect();
  Future<void> load(
    PlaybackQueue queue,
    int generation,
    PlaybackPreferences preferences,
  );
  Future<void> command(
    String name, [
    Map<String, Object?> arguments = const {},
  ]);
  Widget buildVideo(PlaybackState state);
  Future<void> dispose();
}

class AndroidPlaybackBackend implements PlaybackBackend {
  static const channel = MethodChannel('mediagrab/playback');
  static const events = EventChannel('mediagrab/playback/events');
  @override
  late final Stream<PlaybackState> states = events.receiveBroadcastStream().map(
    (event) => PlaybackState.fromJson(Map<Object?, Object?>.from(event as Map)),
  );
  @override
  Future<PlaybackState?> connect() async {
    final value = await channel.invokeMapMethod<Object?, Object?>('snapshot');
    return value == null ? null : PlaybackState.fromJson(value);
  }

  @override
  Future<void> load(
    PlaybackQueue queue,
    int generation,
    PlaybackPreferences preferences,
  ) => command('load', {
    'queue': queue.items.map((e) => e.toJson()).toList(),
    'index': queue.index,
    'generation': generation,
    'preferences': preferences.toJson(),
  });
  @override
  Future<void> command(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async {
    await channel.invokeMethod<void>(name, arguments);
  }

  Future<double> readBrightness() async =>
      (await channel.invokeMethod<double>('getBrightness') ?? .5).clamp(0, 1);

  @override
  Widget buildVideo(PlaybackState state) {
    if (state.textureId == null) return const SizedBox();
    final texture = Texture(
      textureId: state.textureId!,
      filterQuality: FilterQuality.medium,
    );
    return state.rotation == 0
        ? texture
        : RotatedBox(quarterTurns: state.rotation ~/ 90, child: texture);
  }

  @override
  Future<void> dispose() async {
    // Disconnecting a Flutter view must not stop a native background session.
    await channel.invokeMethod<void>('disconnect');
  }
}

/// Portable adapter and compatibility injection for the existing widget tests.
/// Native background/PiP capabilities are intentionally not advertised here.
class VideoPlayerPlaybackBackend implements PlaybackBackend {
  VideoPlayerPlaybackBackend({VideoPlayerController? controller})
    : _controller = controller,
      _injected = controller != null;
  VideoPlayerController? _controller;
  final bool _injected;
  final _states = StreamController<PlaybackState>.broadcast(sync: true);
  List<PlaybackItem> _items = const [];
  int _index = 0, _generation = 0;
  bool _audioOnly = false;
  DateTime? _deadline;
  Timer? _timer;
  String? _error;
  bool _disposed = false;
  bool _visible = true;
  PlaybackPreferences _preferences = const PlaybackPreferences();
  @override
  Stream<PlaybackState> get states => _states.stream;
  PlaybackState get snapshot {
    final v = _controller?.value;
    return PlaybackState(
      items: _items,
      index: _index,
      generation: _generation,
      initialized: v?.isInitialized ?? false,
      playing: v?.isPlaying ?? false,
      loading: v?.isBuffering ?? false,
      position: v?.position ?? Duration.zero,
      duration: v?.duration ?? Duration.zero,
      speed: v?.playbackSpeed ?? 1,
      volume: v?.volume ?? 1,
      loop: v?.isLooping ?? false,
      width: v?.size.width ?? 0,
      height: v?.size.height ?? 0,
      audioOnly: _audioOnly,
      error: _error ?? v?.errorDescription,
      timerRemaining:
          _deadline == null
              ? Duration.zero
              : Duration(
                milliseconds: _deadline!
                    .difference(DateTime.now())
                    .inMilliseconds
                    .clamp(0, 86400000),
              ),
    );
  }

  bool _advancing = false;
  void _emit() {
    if (_disposed) return;
    _states.add(snapshot);
    if (!_injected &&
        snapshot.finished &&
        !snapshot.loop &&
        !_advancing &&
        _index + 1 < _items.length) {
      _advancing = true;
      unawaited(command('next').whenComplete(() => _advancing = false));
    }
  }

  @override
  Future<PlaybackState?> connect() async => snapshot;
  @override
  Future<void> load(
    PlaybackQueue queue,
    int generation,
    PlaybackPreferences preferences,
  ) async {
    _preferences = preferences;
    _generation = generation;
    _items = queue.items;
    _index = queue.index;
    _error = null;
    final old = _controller;
    old?.removeListener(_emit);
    if (!_injected) {
      await old?.dispose();
      final file = File(queue.items[queue.index].filePath);
      if (!file.existsSync()) {
        _controller = null;
        _error = 'File not found on device';
        _emit();
        return;
      }
      _controller = VideoPlayerController.file(
        file,
        videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false),
      );
    }
    final c = _controller!;
    c.addListener(_emit);
    try {
      final wasInitialized = c.value.isInitialized;
      if (!wasInitialized) await c.initialize();
      if (_disposed || generation != _generation) return;
      if (!_injected) await c.setPlaybackSpeed(preferences.initialSpeed);
      if (_visible && (!_injected || !wasInitialized)) await c.play();
      _emit();
    } catch (e) {
      _error = 'Could not play this local file: $e';
      _emit();
    }
  }

  @override
  Future<void> command(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async {
    final c = _controller;
    switch (name) {
      case 'play':
        if (snapshot.finished) await c?.seekTo(Duration.zero);
        await c?.play();
      case 'pause':
        await c?.pause();
      case 'seek':
        await c?.seekTo(Duration(milliseconds: arguments['position']! as int));
      case 'speed':
        await c?.setPlaybackSpeed((arguments['speed']! as num).toDouble());
      case 'volume':
        await c?.setVolume((arguments['volume']! as num).toDouble());
      case 'loop':
        await c?.setLooping(arguments['loop'] == true);
      case 'audioOnly':
        _audioOnly = arguments['enabled'] == true;
      case 'next':
      case 'previous':
        final next = _index + (name == 'next' ? 1 : -1);
        if (next >= 0 && next < _items.length) {
          await load(
            PlaybackQueue(_items, index: next),
            _generation,
            _preferences,
          );
        }
      case 'visible':
        _visible = arguments['visible'] == true;
        if (!_visible) await c?.pause();
      case 'timer':
        if (arguments['onlyIfInactive'] == true && _deadline != null) return;
        _timer?.cancel();
        final minutes = arguments['minutes']! as int;
        _deadline =
            minutes == 0
                ? null
                : DateTime.now().add(Duration(minutes: minutes));
        if (_deadline != null) {
          _timer = Timer.periodic(const Duration(seconds: 1), (_) {
            if (snapshot.timerRemaining == Duration.zero) {
              _deadline = null;
              _timer?.cancel();
              unawaited(_controller?.pause());
            }
            _emit();
          });
        }
      case 'close':
        _timer?.cancel();
        _deadline = null;
        await c?.pause();
        c?.removeListener(_emit);
        if (!_injected) {
          await c?.dispose();
          _controller = null;
        }
        _items = const [];
      case 'preferences':
        _preferences = PlaybackPreferences.fromJson(
          Map<String, dynamic>.from(arguments),
        );
      default:
        return;
    }
    _emit();
  }

  @override
  Widget buildVideo(PlaybackState state) =>
      _controller == null ? const SizedBox() : VideoPlayer(_controller!);
  @override
  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    _controller?.removeListener(_emit);
    if (!_injected) await _controller?.dispose();
    await _states.close();
  }
}
