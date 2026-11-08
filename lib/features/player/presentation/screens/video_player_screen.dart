import 'package:open_filex/open_filex.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/utils/file_utils.dart';
import '../../../../shared/widgets/media_options_sheet.dart';
import '../../data/playback_backend.dart';
import '../../domain/playback_preferences.dart';
import '../../domain/playback_state.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../providers/playback_provider.dart';
import '../widgets/playback_surface.dart';

enum VideoFitMode {
  fit('Fit to screen'),
  fill('Zoom to fill'),
  widescreen('16:9 Wide');

  const VideoFitMode(this.label);
  final String label;
}

/// Route-compatible presentation of the app-scoped session. Leaving this route
/// never disposes the production controller; only an explicit Close does that.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    super.key,
    required this.filePath,
    required this.title,
    this.queue,
    @visibleForTesting this.controller,
    @visibleForTesting this.onOpenExternal,
  });
  final String filePath, title;
  final PlaybackQueue? queue;
  final VideoPlayerController? controller;
  final Future<void> Function(String)? onOpenExternal;
  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final PlaybackBackend? _injected =
      widget.controller == null
          ? null
          : VideoPlayerPlaybackBackend(controller: widget.controller);
  @override
  Widget build(BuildContext context) {
    final child = _PlayerPresentation(request: widget);
    if (_injected != null) {
      return ProviderScope(
        overrides: [
          playbackProvider.overrideWith((ref) => PlaybackManager(_injected)),
        ],
        child: child,
      );
    }
    try {
      ProviderScope.containerOf(context, listen: false);
    } catch (_) {
      return ProviderScope(child: child);
    }
    return child;
  }
}

class _PlayerPresentation extends ConsumerStatefulWidget {
  const _PlayerPresentation({required this.request});
  final VideoPlayerScreen request;
  @override
  ConsumerState<_PlayerPresentation> createState() =>
      _PlayerPresentationState();
}

class _PlayerPresentationState extends ConsumerState<_PlayerPresentation>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _dismiss = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  bool _controls = true,
      _scrubbing = false,
      _fullscreen = false,
      _locked = false,
      _sheet = false;
  double _scrubMs = 0, _brightness = .5, _restoreVolume = 1;
  int _skipDirection = 0, _skipSeconds = 0;
  Timer? _hideTimer, _skipTimer, _orientationTimer;
  VideoFitMode _fit = VideoFitMode.fit;
  Offset? _panStart;
  Offset? _burstTapStart;
  int? _burstPointer;
  Offset _panDelta = Offset.zero;
  Duration _panPosition = Duration.zero;
  double _panVolume = 1;
  double _panDismiss = 0;
  String? _gestureLabel;
  String? _panAxis;
  int _gestureSide = -1;
  final _surfaceKey = GlobalKey();
  bool _leaving = false, _minimizing = false;
  bool _holding = false, _orientationPending = false;
  Size? _viewSize;
  bool get _focused =>
      _skipSeconds > 0 ||
      _scrubbing ||
      _gestureLabel != null ||
      _holding ||
      _panAxis == 'vertical';
  int _systemRequest = 0;
  Rect? _lastBounds;
  late final PlaybackManager _owner;
  PlaybackManager get manager => _owner;
  PlaybackState get playback => ref.read(playbackProvider);
  PlaybackPreferences get preferences => manager.preferences;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _owner = ref.read(playbackProvider.notifier);
    unawaited(
      manager.readBrightness().then((value) {
        if (mounted && _panStart == null) _brightness = value;
      }),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fullscreen = MediaQuery.orientationOf(context) == Orientation.landscape;
      unawaited(
        _systemFullscreen(
          _fullscreen,
          requestOrientation: false,
          releaseOrientation: true,
        ),
      );
      final request = widget.request;
      unawaited(
        manager.open(
          request.queue ??
              PlaybackQueue([
                PlaybackItem(
                  id: request.filePath,
                  filePath: request.filePath,
                  title: request.title,
                  isAudio: getFileType(request.filePath) == FileType.audio,
                ),
              ]),
        ),
      );
      _armHide();
      _reportBounds();
    });
  }

  void _armHide() {
    _hideTimer?.cancel();
    if (_sheet || _focused || _locked) return;
    _hideTimer = Timer(Duration(seconds: preferences.hideSeconds), () {
      if (mounted && playback.playing && !_sheet && !_scrubbing) {
        setState(() => _controls = false);
      }
    });
  }

  void _touch() {
    if (mounted) setState(() => _controls = true);
    _armHide();
  }

  void _toggleControls() {
    if (_locked) return;
    setState(() => _controls = !_controls);
    if (_controls) {
      _armHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _skip(int direction) {
    if (_locked || _holding || _scrubbing) return;
    final seconds = manager.skip(direction);
    _skipTimer?.cancel();
    setState(() {
      _skipDirection = direction;
      _skipSeconds = seconds;
    });
    _skipTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _skipDirection = 0;
          _skipSeconds = 0;
          manager.seekBurst.reset();
          _controls = true;
        });
        _armHide();
      }
    });
    _hideTimer?.cancel();
  }

  void _videoTap(int side) {
    if (_skipTimer?.isActive == true) return;
    _toggleControls();
  }

  void _burstDown(PointerDownEvent event) {
    if (_locked || _holding || _scrubbing || _skipTimer?.isActive != true) {
      return;
    }
    _burstPointer = event.pointer;
    _burstTapStart = event.position;
  }

  void _burstUp(PointerUpEvent event, int side) {
    if (event.pointer != _burstPointer) return;
    final start = _burstTapStart;
    _burstPointer = null;
    _burstTapStart = null;
    if (start != null &&
        (event.position - start).distance < kTouchSlop &&
        _skipTimer?.isActive == true &&
        side == _skipDirection) {
      _skip(side);
    }
  }

  void _clearSeekFeedback() {
    _skipTimer?.cancel();
    _skipSeconds = 0;
    _skipDirection = 0;
    manager.seekBurst.reset();
  }

  void _holdBegin() {
    if (_locked ||
        _sheet ||
        _minimizing ||
        _panStart != null ||
        !playback.playing ||
        !playback.initialized) {
      return;
    }
    _hideTimer?.cancel();
    setState(() {
      _clearSeekFeedback();
      _holding = true;
    });
    unawaited(manager.beginSpeedHold());
  }

  void _holdEnd() {
    unawaited(manager.endSpeedHold());
    if (!_holding || !mounted) return;
    setState(() {
      _holding = false;
      _controls = true;
    });
    _armHide();
  }

  void _cancelInteraction() {
    _holdEnd();
    _panStart = null;
    _burstPointer = null;
    _burstTapStart = null;
    _panAxis = null;
    if (!mounted) return;
    setState(() {
      _scrubbing = false;
      _gestureLabel = null;
      _clearSeekFeedback();
    });
    if (!_minimizing) {
      unawaited(_dismiss.animateBack(0, curve: Curves.easeOutCubic));
    }
    _armHide();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cancelInteraction();
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _leaving || _minimizing) return;
      final size = MediaQuery.sizeOf(context);
      if (_viewSize == size) return;
      _viewSize = size;
      _cancelInteraction();
      _orientationTimer?.cancel();
      setState(() {
        _fullscreen = size.width > size.height;
        _orientationPending = false;
      });
      unawaited(manager.followSystemRotation());
      unawaited(_systemFullscreen(_fullscreen, requestOrientation: false));
    });
  }

  Future<void> _external() async {
    await manager.pause();
    final path = playback.item?.filePath ?? widget.request.filePath;
    if (widget.request.onOpenExternal != null) {
      await widget.request.onOpenExternal!(path);
    } else {
      final result = await openMediaFile(path);
      if (mounted && result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: ${result.message}')),
        );
      }
    }
  }

  Future<void> _systemFullscreen(
    bool enabled, {
    bool requestOrientation = true,
    bool releaseOrientation = false,
  }) async {
    final request = ++_systemRequest;
    bool current() =>
        mounted && request == _systemRequest && !_minimizing && !_leaving;
    try {
      if (requestOrientation || releaseOrientation) {
        await manager.prepareOrientation(requestOrientation ? enabled : null);
        if (!current()) return;
      }
      if (enabled) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        if (!current()) return;
        if (requestOrientation) {
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        } else if (releaseOrientation) {
          await SystemChrome.setPreferredOrientations(const []);
        }
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        if (!current()) return;
        if (requestOrientation) {
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
          ]);
        } else if (releaseOrientation) {
          await SystemChrome.setPreferredOrientations(const []);
        }
      }
    } catch (_) {
      /* Rotation restrictions do not change the session. */
    }
  }

  void _toggleFullscreen() {
    if (_orientationPending) return;
    _cancelInteraction();
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    setState(() {
      _fullscreen = !(_fullscreen || landscape);
      _orientationPending = true;
    });
    unawaited(_systemFullscreen(_fullscreen));
    _orientationTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        _orientationPending = false;
        _fullscreen =
            MediaQuery.orientationOf(context) == Orientation.landscape;
      });
    });
    _touch();
  }

  Future<void> _back() async {
    if (_minimizing) return;
    if (_locked) {
      setState(() {
        _locked = false;
        _controls = true;
      });
      _armHide();
      return;
    }
    if (playback.hasSession &&
        (_fullscreen ||
            MediaQuery.orientationOf(context) == Orientation.landscape)) {
      setState(() => _fullscreen = false);
      await _systemFullscreen(false);
      return;
    }
    if (_leaving) return;
    setState(() => _leaving = true);
    manager.minimize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _popPlayer();
    });
  }

  Future<void> _minimizeDirect() async {
    if (_leaving || _minimizing || _locked) return;
    _hideTimer?.cancel();
    _holdEnd();
    setState(() => _minimizing = true);
    if (!MediaQuery.disableAnimationsOf(context)) {
      try {
        await _dismiss.animateTo(1, curve: Curves.easeOutCubic).orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted) return;
    // The live frame is already contracted. Rotate the destination, never a
    // full-size portrait video, before handing it to the docked player.
    unawaited(_portraitDock());
    setState(() => _leaving = true);
    manager.minimize();
    _popPlayer();
  }

  Future<void> _portraitDock() async {
    ++_systemRequest;
    try {
      await Future.wait([
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
      ]);
    } catch (_) {
      /* A platform restriction must never block minimizing. */
    }
  }

  void _popPlayer() {
    if (!mounted) return;
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      if (router.canPop()) {
        router.pop();
      } else {
        router.go('/home');
      }
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _fitMode() {
    setState(
      () =>
          _fit =
              VideoFitMode.values[(_fit.index + 1) %
                  VideoFitMode.values.length],
    );
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_fit.label),
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
    _armHide();
  }

  Future<T?> _showSheet<T>(
    String title,
    List<Widget> Function(BuildContext) contents,
  ) async {
    _hideTimer?.cancel();
    _cancelInteraction();
    setState(() {
      _sheet = true;
      _controls = true;
    });
    final container = ProviderScope.containerOf(context, listen: false);
    final result = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder:
          (context) => UncontrolledProviderScope(
            container: container,
            child: Consumer(
              builder: (context, ref, _) {
                ref.watch(
                  playbackProvider.select(
                    (s) => (
                      s.speed,
                      s.loop,
                      s.audioOnly,
                      s.volume,
                      s.item?.isAudio,
                      s.pipSupported,
                      s.timerRemaining.inSeconds,
                    ),
                  ),
                );
                return MediaOptionsSheet(
                  title: title,
                  showCloseButton: false,
                  children: contents(context),
                );
              },
            ),
          ),
    );
    if (mounted) {
      setState(() => _sheet = false);
      _armHide();
    }
    return result;
  }

  Future<void> _speeds() async {
    await _showSheet<void>(
      'Playback Speed',
      (context) => [
        for (final speed in PlaybackPreferences.speeds)
          ListTile(
            title: Text(speed == 1 ? 'Normal' : '${speed}x'),
            selected: manager.selectedSpeed == speed,
            selectedColor: playbackRed,
            trailing:
                manager.selectedSpeed == speed
                    ? const Icon(Icons.check_rounded)
                    : null,
            onTap: () {
              unawaited(manager.setSpeed(speed));
              Navigator.pop(context);
            },
          ),
      ],
    );
  }

  Future<void> _timer() async {
    final selection = await _showSheet<int>(
      'Sleep timer',
      (context) => [
        if (playback.timerRemaining > Duration.zero)
          ListTile(
            title: Text('Remaining ${playbackTime(playback.timerRemaining)}'),
            trailing: TextButton(
              onPressed: () => Navigator.pop(context, 0),
              child: const Text('Cancel timer'),
            ),
          ),
        for (final minutes in [5, 10, 15, 30, 45, 60])
          ListTile(
            title: Text('$minutes minutes'),
            onTap: () => Navigator.pop(context, minutes),
          ),
        ListTile(
          title: const Text('Custom duration'),
          onTap: () => Navigator.pop(context, -1),
        ),
      ],
    );
    if (!mounted || selection == null) return;
    var minutes = selection;
    if (minutes == -1) {
      final input = TextEditingController(
        text:
            '${preferences.rememberTimer ? preferences.lastTimerMinutes : 30}',
      );
      minutes =
          await showDialog<int>(
            context: context,
            builder:
                (context) => AlertDialog(
                  title: const Text('Custom sleep timer'),
                  content: TextField(
                    controller: input,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Minutes (1–1440)',
                    ),
                  ),
                  actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        final value = int.tryParse(input.text);
                        if (value != null && value >= 1 && value <= 1440) {
                          Navigator.pop(context, value);
                        }
                      },
                      child: const Text('Start'),
                    ),
                  ],
                ),
          ) ??
          -1;
      // The route may still animate with its text field mounted.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      input.dispose();
    }
    if (!mounted || minutes < 0) return;
    await manager.setTimer(minutes);
    if (!mounted || minutes == 0) return;
    final settings = ref.read(settingsProvider.notifier);
    await settings.setPlayback(
      ref.read(settingsProvider).playback.update('lastTimerMinutes', minutes),
    );
  }

  Future<void> _settings() async {
    final result = await _showSheet<String>(
      'Playback Settings',
      (context) => [
        ListTile(
          leading: const Icon(Icons.speed_rounded),
          title: const Text('Playback speed'),
          trailing: Text(playback.speed == 1 ? 'Normal' : '${playback.speed}x'),
          onTap: () => Navigator.pop(context, 'speed'),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.repeat_rounded),
          title: const Text('Loop video'),
          value: playback.loop,
          onChanged: (v) => manager.setLoop(v),
        ),
        if (preferences.audioOnly && playback.item?.isAudio != true)
          SwitchListTile(
            secondary: const Icon(Icons.headphones_rounded),
            title: const Text('Audio-only mode'),
            value: playback.audioOnly,
            onChanged: (v) => manager.setAudioOnly(v),
          ),
        ListTile(
          leading: const Icon(Icons.bedtime_outlined),
          title: const Text('Sleep timer'),
          subtitle:
              playback.timerRemaining > Duration.zero
                  ? Text(playbackTime(playback.timerRemaining))
                  : const Text('Off'),
          onTap: () => Navigator.pop(context, 'timer'),
        ),
        ListTile(
          leading: Icon(
            playback.volume == 0
                ? Icons.volume_off_rounded
                : Icons.volume_up_rounded,
          ),
          title: const Text('Volume'),
          subtitle: Slider(
            value: playback.volume,
            onChanged: (v) => manager.setVolume(v),
          ),
        ),
        if (preferences.screenLock)
          ListTile(
            leading: const Icon(Icons.lock_outline_rounded),
            title: const Text('Lock screen controls'),
            onTap: () => Navigator.pop(context, 'lock'),
          ),
        if (preferences.pip && playback.pipSupported && !playback.audioOnly)
          ListTile(
            leading: const Icon(Icons.picture_in_picture_alt_rounded),
            title: const Text('Picture-in-picture'),
            onTap: () => Navigator.pop(context, 'pip'),
          ),
        ListTile(
          leading: const Icon(Icons.aspect_ratio_rounded),
          title: Text('Aspect ratio (${_fit.label})'),
          onTap: () => Navigator.pop(context, 'fit'),
        ),
        ListTile(
          key: const Key('video_player_external_button'),
          leading: const Icon(Icons.open_in_new_rounded),
          title: const Text('Open in external player'),
          onTap: () => Navigator.pop(context, 'external'),
        ),
        ListTile(
          leading: const Icon(Icons.stop_circle_outlined),
          title: const Text('Stop playback'),
          onTap: () => Navigator.pop(context, 'stop'),
        ),
      ],
    );
    if (!mounted) return;
    switch (result) {
      case 'fit':
        _fitMode();
      case 'external':
        await _external();
      case 'speed':
        await _speeds();
      case 'timer':
        await _timer();
      case 'lock':
        setState(() {
          _locked = true;
          _controls = false;
        });
        _hideTimer?.cancel();
      case 'pip':
        final entered = await manager.enterPip();
        if (!entered && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Picture-in-picture is unavailable or disabled in Android settings.',
              ),
            ),
          );
        }
      case 'stop':
        await manager.close();
        if (mounted) await _back();
    }
  }

  void _reportBounds() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _surfaceKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        final rect = box.localToGlobal(Offset.zero) & box.size;
        if (_lastBounds == rect) return;
        _lastBounds = rect;
        unawaited(
          manager.videoBounds(
            box.localToGlobal(Offset.zero) & box.size,
            MediaQuery.devicePixelRatioOf(context),
          ),
        );
      }
    });
  }

  void _panBegin(DragStartDetails details) {
    if (_locked || _minimizing) return;
    _hideTimer?.cancel();
    _dismiss.stop();
    _holdEnd();
    _clearSeekFeedback();
    _panStart = details.globalPosition;
    final width = MediaQuery.sizeOf(context).width;
    // A center lane remains available for minimizing when both optional side
    // adjustments are enabled. Lock the lane for the whole pointer sequence.
    if (details.globalPosition.dx > width * .38 &&
        details.globalPosition.dx < width * .62) {
      _gestureSide = 0;
    }
    _panDelta = Offset.zero;
    _panAxis = null;
    _panPosition = playback.position;
    _panVolume = playback.volume;
    _panDismiss = _dismiss.value;
  }

  void _panUpdate(DragUpdateDetails details) {
    if (_locked || _panStart == null) return;
    final previous = _panDelta;
    _panDelta = details.globalPosition - _panStart!;
    if (_panAxis == null && _panDelta.distance > 18) {
      _panAxis =
          _panDelta.dx.abs() > _panDelta.dy.abs() * 1.3
              ? 'seek'
              : _panDelta.dy.abs() > _panDelta.dx.abs() * 1.3
              ? 'vertical'
              : null;
      if (_panAxis != null) setState(() {});
    }
    if (_panAxis == 'seek' && playback.initialized) {
      final width = MediaQuery.sizeOf(context).width;
      final maxSeek = playback.duration.inMilliseconds.toDouble().clamp(
        0,
        120000,
      );
      setState(() {
        _scrubbing = true;
        _scrubMs =
            (_panPosition.inMilliseconds + _panDelta.dx / width * maxSeek)
                .clamp(0, playback.duration.inMilliseconds)
                .toDouble();
        _gestureLabel = null;
      });
    } else if (_panAxis == 'vertical') {
      final right = _gestureSide > 0;
      final adjust = -(_panDelta.dy - previous.dy) / 250;
      if (right && preferences.volumeGesture) {
        _panVolume = (_panVolume + adjust).clamp(0, 1);
        unawaited(manager.setVolume(_panVolume));
        setState(() => _gestureLabel = 'Volume ${(_panVolume * 100).round()}%');
      } else if (_gestureSide < 0 && preferences.brightnessGesture) {
        _brightness = (_brightness + adjust).clamp(0, 1);
        unawaited(manager.setBrightness(_brightness));
        setState(
          () => _gestureLabel = 'Brightness ${(_brightness * 100).round()}%',
        );
      } else if (_panDelta.dy > 0) {
        final media = MediaQuery.of(context);
        // Interpolate the live video's center, rather than the top of its
        // letterboxed viewport, so its visible motion tracks the finger.
        final travel = (media.size.height / 2 - media.padding.bottom - 113)
            .clamp(1.0, double.infinity);
        _dismiss.value = (_panDismiss + _panDelta.dy / travel).clamp(0, 1);
      }
    }
  }

  void _panEnd(DragEndDetails details) {
    if (_locked || _panStart == null) return;
    final right = _gestureSide > 0;
    if (_panAxis == 'seek' && _scrubbing) {
      unawaited(manager.seek(Duration(milliseconds: _scrubMs.round())));
    } else if (_panAxis == 'vertical' &&
        (_panDelta.dy >
                (MediaQuery.sizeOf(context).height * .16).clamp(48, 160) ||
            (_panDelta.dy > 24 && details.velocity.pixelsPerSecond.dy > 800)) &&
        !(_gestureSide == 0
            ? false
            : right
            ? preferences.volumeGesture
            : preferences.brightnessGesture)) {
      unawaited(_minimizeDirect());
    } else {
      unawaited(_dismiss.animateBack(0, curve: Curves.easeOutCubic));
    }
    setState(() {
      _scrubbing = false;
      _gestureLabel = null;
      _panAxis = null;
      _controls = true;
    });
    _panStart = null;
    _armHide();
  }

  Widget _button(
    IconData icon,
    String label,
    VoidCallback? action, {
    Key? key,
    double size = 24,
    bool circular = false,
  }) => IconButton(
    key: key,
    iconSize: size,
    color: Colors.white,
    disabledColor: Colors.white30,
    tooltip: label,
    style:
        circular
            ? IconButton.styleFrom(
              backgroundColor: const Color(0x88000000),
              disabledBackgroundColor: const Color(0x55000000),
              shape: const CircleBorder(),
            )
            : null,
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    icon: Icon(icon),
    onPressed:
        action == null
            ? null
            : () {
              action();
              _armHide();
            },
  );

  Widget _top(PlaybackState state) => SafeArea(
    bottom: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          _button(
            Icons.keyboard_arrow_down_rounded,
            'Back',
            () => unawaited(_minimizeDirect()),
            key: const Key('video_player_back_button'),
          ),
          Expanded(
            child: Text(
              state.item?.title ?? widget.request.title,
              key: const Key('video_player_title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (state.pipSupported && preferences.pip && !state.audioOnly)
            _button(
              Icons.picture_in_picture_alt_outlined,
              'Picture-in-picture',
              () => unawaited(manager.enterPip()),
            ),
          _button(
            Icons.settings_outlined,
            'Playback settings',
            () => unawaited(_settings()),
          ),
        ],
      ),
    ),
  );

  Widget _center(PlaybackState state) => Center(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(
          Icons.skip_previous_rounded,
          'Previous',
          state.hasPrevious ? () => unawaited(manager.previous()) : null,
          size: 28,
          circular: true,
        ),
        const SizedBox(width: 32),
        DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0x55000000),
            shape: BoxShape.circle,
          ),
          child: _button(
            state.finished
                ? Icons.replay_rounded
                : state.playing
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            state.playing ? 'Pause' : 'Play',
            () {
              unawaited(manager.togglePlay());
              _touch();
            },
            size: 36,
            key: const Key('video_player_play_pause_button'),
          ),
        ),
        const SizedBox(width: 32),
        _button(
          Icons.skip_next_rounded,
          'Next',
          state.hasNext ? () => unawaited(manager.next()) : null,
          size: 28,
          circular: true,
        ),
      ],
    ),
  );

  Widget _pill(Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0x66000000),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: child,
    ),
  );

  Widget _bottom(PlaybackState state) {
    final durationMs = state.duration.inMilliseconds.toDouble();
    final position =
        _scrubbing
            ? Duration(milliseconds: _scrubMs.round())
            : _skipSeconds > 0
            ? manager.seekBurst.target ?? state.position
            : state.position;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 12, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_scrubbing)
              Align(
                alignment: Alignment.center,
                child: _pill(
                  Text(
                    playbackTime(position),
                    key: const Key('seek_preview_timestamp'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3.5,
                padding: const EdgeInsets.symmetric(vertical: 18),
                thumbShape: RoundSliderThumbShape(
                  enabledThumbRadius: _scrubbing ? 7 : 6,
                ),
                activeTrackColor: playbackRed,
                inactiveTrackColor: Colors.white38,
                thumbColor: playbackRed,
                overlayColor: Colors.transparent,
              ),
              child: Slider(
                key: const Key('video_player_scrub_slider'),
                min: 0,
                max: durationMs > 0 ? durationMs : 1,
                value: position.inMilliseconds.toDouble().clamp(
                  0,
                  durationMs > 0 ? durationMs : 1,
                ),
                onChangeStart: (v) {
                  _hideTimer?.cancel();
                  setState(() {
                    _clearSeekFeedback();
                    _scrubbing = true;
                    _scrubMs = v;
                  });
                },
                onChanged:
                    durationMs > 0
                        ? (v) => setState(() {
                          _scrubbing = true;
                          _scrubMs = v;
                        })
                        : null,
                onChangeEnd:
                    durationMs > 0
                        ? (v) {
                          unawaited(
                            manager.seek(Duration(milliseconds: v.round())),
                          );
                          setState(() {
                            _scrubbing = false;
                            _controls = true;
                          });
                          _armHide();
                        }
                        : null,
              ),
            ),
            IgnorePointer(
              ignoring: _focused,
              child: AnimatedOpacity(
                opacity: _focused ? 0 : 1,
                duration:
                    _focused
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${playbackTime(position)} / ${playbackTime(state.duration)}',
                            key: const Key('video_player_timestamp'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                    ),
                    _button(
                      state.volume == 0
                          ? Icons.volume_off_outlined
                          : Icons.volume_up_outlined,
                      'Mute / unmute',
                      () {
                        if (state.volume > 0) {
                          _restoreVolume = state.volume;
                          unawaited(manager.setVolume(0));
                        } else {
                          unawaited(manager.setVolume(_restoreVolume));
                        }
                      },
                    ),
                    SizedBox(
                      width: 48,
                      child: TextButton(
                        key: const Key('playback_speed_button'),
                        onPressed: _speeds,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          minimumSize: const Size(48, 48),
                          padding: EdgeInsets.zero,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            state.speed == 1 ? '1x' : '${state.speed}x',
                          ),
                        ),
                      ),
                    ),
                    _button(
                      _fullscreen ||
                              MediaQuery.orientationOf(context) ==
                                  Orientation.landscape
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      _fullscreen ||
                              MediaQuery.orientationOf(context) ==
                                  Orientation.landscape
                          ? 'Exit Fullscreen'
                          : 'Fullscreen',
                      _toggleFullscreen,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seekIndicator() => IgnorePointer(
    child: Align(
      alignment:
          _skipDirection < 0 ? const Alignment(-.6, 0) : const Alignment(.6, 0),
      child: AnimatedOpacity(
        opacity: _skipSeconds == 0 ? 0 : 1,
        duration: const Duration(milliseconds: 100),
        child: TweenAnimationBuilder<double>(
          key: ValueKey((_skipDirection, _skipSeconds)),
          tween: Tween(begin: 0, end: 1),
          duration:
              MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
          builder:
              (context, value, child) => Transform.translate(
                offset: Offset(_skipDirection * (1 - value) * -8, 0),
                child: child,
              ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_skipDirection < 0)
                const Icon(
                  Icons.fast_rewind_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              Text(
                '${_skipDirection < 0 ? '−' : '+'}$_skipSeconds',
                key: const Key('cumulative_seek_feedback'),
                semanticsLabel:
                    '$_skipSeconds seconds ${_skipDirection < 0 ? 'backward' : 'forward'}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
                ),
              ),
              if (_skipDirection > 0)
                const Icon(
                  Icons.fast_forward_rounded,
                  color: Colors.white,
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _adjustmentFeedback() {
    final volume = _panAxis == 'vertical' && _gestureSide > 0;
    final adjustment = _panAxis == 'vertical';
    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: 150,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (adjustment)
                Icon(
                  volume ? Icons.volume_up_rounded : Icons.brightness_6_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              const SizedBox(height: 8),
              Text(
                _gestureLabel!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
                ),
              ),
              if (adjustment) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: volume ? _panVolume : _brightness,
                  color: Colors.white,
                  backgroundColor: Colors.white24,
                  minHeight: 3,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Hidden controls do not rebuild for every native position tick. The video
    // texture renders independently; interactions always read the live session.
    ref.watch(
      playbackProvider.select(
        (s) => (
          s.item,
          s.index,
          s.items.length,
          s.initialized,
          s.playing,
          s.loading,
          s.speed,
          s.volume,
          s.loop,
          s.audioOnly,
          s.pip,
          s.textureId,
          s.rotation,
          s.width,
          s.height,
          s.error,
          s.fullPlayer,
          s.duration,
        ),
      ),
    );
    final state = ref.read(playbackProvider);
    ref.watch(settingsProvider.select((s) => s.playback));
    if (!preferences.screenLock) _locked = false;
    ref.listen(
      playbackProvider.select((s) => (s.playing, s.finished, s.index)),
      (old, next) {
        if (old?.$3 != next.$3) {
          if (_holding || _panStart != null) _cancelInteraction();
          manager.seekBurst.reset();
          _skipTimer?.cancel();
          _skipSeconds = 0;
        }
        if (!next.$1 || next.$2) {
          _controls = true;
          _hideTimer?.cancel();
        } else {
          _armHide();
        }
      },
    );
    ref.listen(playbackProvider.select((s) => s.hasSession), (
      previous,
      hasSession,
    ) {
      if (previous == true && !hasSession && !_leaving) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_back());
        });
      }
    });
    ref.listen(playbackProvider.select((s) => s.error), (_, error) {
      if (error == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && playback.initialized) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error)));
        }
      });
    });
    _reportBounds();
    _viewSize ??= MediaQuery.sizeOf(context);
    final controls = state.initialized;
    final primaryVisible = _controls && !_focused;
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AnimatedBuilder(
          animation: _dismiss,
          builder:
              (context, _) => LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.biggest;
                  final progress = _dismiss.value;
                  final bottom = MediaQuery.paddingOf(context).bottom + 80;
                  final frame =
                      Rect.lerp(
                        Offset.zero & size,
                        Rect.fromLTWH(
                          0,
                          (size.height - bottom - 66).clamp(0, size.height),
                          96,
                          66,
                        ),
                        progress,
                      )!;
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 1 - progress),
                        ),
                      ),
                      Positioned.fromRect(
                        rect: frame,
                        child: ClipRRect(
                          key: const Key('player_minimize_frame'),
                          borderRadius: BorderRadius.circular(progress * 10),
                          child: ColoredBox(
                            color: Colors.black,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (state.error == null || controls)
                                  Center(
                                    child: SizedBox(
                                      key: _surfaceKey,
                                      child:
                                          _fit == VideoFitMode.fill
                                              ? PlaybackSurface(
                                                state: state,
                                                fit: BoxFit.cover,
                                                showVideo: state.fullPlayer,
                                              )
                                              : AspectRatio(
                                                aspectRatio:
                                                    _fit ==
                                                            VideoFitMode
                                                                .widescreen
                                                        ? 16 / 9
                                                        : state.aspectRatio,
                                                child: PlaybackSurface(
                                                  state: state,
                                                  showVideo: state.fullPlayer,
                                                ),
                                              ),
                                    ),
                                  ),
                                if (!state.pip)
                                  SafeArea(
                                    child: Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        MediaQuery.systemGestureInsetsOf(
                                          context,
                                        ).left,
                                        56,
                                        MediaQuery.systemGestureInsetsOf(
                                          context,
                                        ).right,
                                        100,
                                      ),
                                      child: Row(
                                        children: [
                                          for (final side in [-1, 1])
                                            Expanded(
                                              child: GestureDetector(
                                                dragStartBehavior:
                                                    DragStartBehavior.down,
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                onTap:
                                                    _locked
                                                        ? null
                                                        : () => _videoTap(side),
                                                onDoubleTap:
                                                    !_locked &&
                                                            preferences
                                                                .doubleTapSeek
                                                        ? () {
                                                          if (_skipTimer
                                                                      ?.isActive !=
                                                                  true ||
                                                              _skipDirection !=
                                                                  side) {
                                                            _skip(side);
                                                          }
                                                        }
                                                        : null,
                                                onPanStart:
                                                    _locked
                                                        ? null
                                                        : (details) {
                                                          _gestureSide = side;
                                                          _panBegin(details);
                                                        },
                                                onPanUpdate:
                                                    _locked ? null : _panUpdate,
                                                onPanEnd:
                                                    _locked ? null : _panEnd,
                                                onPanCancel: () {
                                                  if (_panStart != null) {
                                                    _cancelInteraction();
                                                  }
                                                },
                                                onLongPressStart:
                                                    _locked
                                                        ? null
                                                        : (_) => _holdBegin(),
                                                onLongPressEnd:
                                                    (_) => _holdEnd(),
                                                onLongPressCancel: _holdEnd,
                                                onLongPressUp: _holdEnd,
                                                child: Listener(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onPointerDown: _burstDown,
                                                  onPointerUp:
                                                      (event) =>
                                                          _burstUp(event, side),
                                                  onPointerCancel: (_) {
                                                    _burstPointer = null;
                                                    _burstTapStart = null;
                                                  },
                                                  child:
                                                      const SizedBox.expand(),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (_dismiss.value == 0 &&
                                    !state.pip &&
                                    !_locked)
                                  IgnorePointer(
                                    ignoring: !primaryVisible,
                                    child: AnimatedOpacity(
                                      key: const Key('player_controls_opacity'),
                                      opacity: primaryVisible ? 1 : 0,
                                      duration:
                                          _focused ||
                                                  MediaQuery.disableAnimationsOf(
                                                    context,
                                                  )
                                              ? Duration.zero
                                              : const Duration(
                                                milliseconds: 180,
                                              ),
                                      child: Stack(
                                        children: [
                                          const Positioned.fill(
                                            child: IgnorePointer(
                                              child: ColoredBox(
                                                color: Color(0x33000000),
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            top: 0,
                                            left: 0,
                                            right: 0,
                                            child: ColoredBox(
                                              color: Colors.transparent,
                                              child: _top(state),
                                            ),
                                          ),
                                          if (controls) _center(state),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (_dismiss.value == 0 &&
                                    !state.pip &&
                                    !_locked &&
                                    controls)
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: IgnorePointer(
                                      ignoring:
                                          !(_controls ||
                                              _scrubbing ||
                                              _skipSeconds > 0) ||
                                          (_focused &&
                                              !_scrubbing &&
                                              _skipSeconds == 0),
                                      child: Opacity(
                                        opacity:
                                            ((_controls && !_focused) ||
                                                    _scrubbing ||
                                                    _skipSeconds > 0)
                                                ? 1
                                                : 0,
                                        child: Consumer(
                                          builder: (context, ref, _) {
                                            if ((_controls && !_sheet) ||
                                                _scrubbing ||
                                                _skipSeconds > 0) {
                                              ref.watch(
                                                playbackProvider.select(
                                                  (s) => s.position,
                                                ),
                                              );
                                            }
                                            return _bottom(
                                              ref.read(playbackProvider),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                if (_dismiss.value == 0 &&
                                    _locked &&
                                    !state.pip)
                                  SafeArea(
                                    child: Align(
                                      alignment: Alignment.topRight,
                                      child: _button(
                                        Icons.lock_rounded,
                                        'Unlock controls',
                                        () {
                                          setState(() {
                                            _locked = false;
                                            _controls = true;
                                          });
                                          _armHide();
                                        },
                                      ),
                                    ),
                                  ),
                                if (_dismiss.value == 0 &&
                                    !controls &&
                                    state.error == null)
                                  const Center(
                                    child: CircularProgressIndicator(
                                      color: playbackRed,
                                    ),
                                  ),
                                if (_dismiss.value == 0 &&
                                    state.error != null &&
                                    !controls)
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(32),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.error_outline_rounded,
                                            color: Colors.white70,
                                            size: 48,
                                          ),
                                          const SizedBox(height: 12),
                                          const Text(
                                            'Failed to play video',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            state.error!,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          FilledButton.icon(
                                            onPressed: _external,
                                            icon: const Icon(
                                              Icons.open_in_new_rounded,
                                            ),
                                            label: const Text(
                                              'Open in External App',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (_dismiss.value == 0 && !state.pip)
                                  _seekIndicator(),
                                if (_dismiss.value == 0 &&
                                    _gestureLabel != null)
                                  _adjustmentFeedback(),
                                if (_holding && !state.pip)
                                  SafeArea(
                                    child: Align(
                                      alignment: Alignment.topCenter,
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 64),
                                        child: _pill(
                                          const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.fast_forward_rounded,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                              SizedBox(width: 6),
                                              Text(
                                                '2× speed',
                                                key: Key(
                                                  'temporary_speed_feedback',
                                                ),
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _skipTimer?.cancel();
    _orientationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(manager.endSpeedHold());
    _dismiss.dispose();
    ++_systemRequest;
    final owner = manager;
    if (!_leaving) Future<void>.microtask(owner.minimize);
    unawaited(Future<void>.microtask(owner.resetBrightness));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }
}
