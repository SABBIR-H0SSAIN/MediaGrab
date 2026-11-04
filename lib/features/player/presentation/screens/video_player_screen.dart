import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../../shared/widgets/media_options_sheet.dart';
import '../../../../core/utils/file_utils.dart';

enum VideoFitMode {
  fit('Fit to screen'),
  fill('Zoom to fill'),
  widescreen('16:9 Wide');

  const VideoFitMode(this.label);
  final String label;
}

/// Screen for hardware-accelerated in-app video playback modeled after the modern YouTube player.
///
/// Features include:
/// - Quick -10s rewind and +10s forward buttons in center controls
/// - Double-tap left/right zones to seek ±10 seconds with animated indicators
/// - YouTube playback speed selector (0.25x to 2.0x) and loop video toggle modal sheet
/// - Aspect ratio switcher (Fit, Fill/Zoom, 16:9)
/// - Fullscreen landscape orientation toggle
/// - Sleek YouTube scrubber with red/accent progress line and auto-hiding controls
/// - Handoff to external player via [openMediaFile].
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    super.key,
    required this.filePath,
    required this.title,
    @visibleForTesting this.controller,
    @visibleForTesting this.onOpenExternal,
  });

  /// Absolute file system path to the media file.
  final String filePath;

  /// Display title for the top app bar.
  final String title;

  /// Optional pre-configured controller for testing.
  final VideoPlayerController? controller;

  /// Optional external player callback override for testing.
  final Future<void> Function(String filePath)? onOpenExternal;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with WidgetsBindingObserver {
  bool _lastPlaying = false;
  DateTime _lastControlsUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  VideoPlayerController? _activeController;
  VideoPlayerController get _controller => _activeController!;
  bool _isInitialized = false;
  bool _hasError = false;
  String? _errorMessage;

  bool _showControls = true;
  Timer? _hideTimer;

  bool _isDragging = false;
  double _dragPositionMs = 0.0;

  double _playbackSpeed = 1.0;
  bool _isLooping = false;
  VideoFitMode _fitMode = VideoFitMode.fit;

  // Double-tap seek visual feedback
  bool _showRewindIndicator = false;
  bool _showForwardIndicator = false;
  Timer? _rewindIndicatorTimer;
  Timer? _forwardIndicatorTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    if (widget.controller != null) {
      _activeController = widget.controller;
    } else {
      if (widget.filePath.trim().isEmpty) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = 'Empty file path provided';
          });
        }
        return;
      }

      final file = File(widget.filePath);
      if (!file.existsSync()) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = 'File not found on device: ${widget.filePath}';
          });
        }
        return;
      }

      _activeController = VideoPlayerController.file(file);
    }

    final c = _activeController;
    if (c == null) return;
    c.addListener(_onControllerUpdate);

    if (c.value.isInitialized) {
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isLooping = c.value.isLooping;
        });
        _startHideTimer();
      }
      return;
    }

    try {
      await c.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isLooping = c.value.isLooping;
        });
        c.play();
        _startHideTimer();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _activeController?.pause();
      _hideTimer?.cancel();
    }
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    final c = _activeController;
    if (c != null && c.value.hasError) {
      setState(() {
        _hasError = true;
        _errorMessage = c.value.errorDescription ?? 'Video playback error';
      });
      return;
    }
    if (c == null) return;
    final playingChanged = _lastPlaying != c.value.isPlaying;
    _lastPlaying = c.value.isPlaying;
    final finished =
        c.value.duration > Duration.zero &&
        c.value.position >= c.value.duration;
    if (finished) _showControls = true;
    // The native video texture continues rendering independently. Hidden
    // controls need no periodic widget rebuilds during playback.
    final now = DateTime.now();
    if (!playingChanged &&
        !finished &&
        (!_showControls ||
            now.difference(_lastControlsUpdate).inMilliseconds < 200)) {
      return;
    }
    _lastControlsUpdate = now;
    setState(() {});
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying && !_isDragging) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _togglePlayPause() {
    if (!_isInitialized) return;
    if (_controller.value.isPlaying) {
      _controller.pause();
      _hideTimer?.cancel();
      setState(() {});
    } else {
      if (_controller.value.duration > Duration.zero &&
          _controller.value.position >= _controller.value.duration) {
        _controller.seekTo(Duration.zero);
      }
      _controller.play();
      _startHideTimer();
      setState(() {});
    }
  }

  void _seekRelative(Duration delta) {
    if (!_isInitialized) return;
    final duration = _controller.value.duration;
    final currentPos = _controller.value.position;
    final newPos = currentPos + delta;
    final clamped =
        newPos < Duration.zero
            ? Duration.zero
            : (newPos > duration ? duration : newPos);
    _controller.seekTo(clamped);
    if (_controller.value.isPlaying) {
      _startHideTimer();
    }
  }

  void _handleDoubleTapLeft() {
    _seekRelative(const Duration(seconds: -10));
    _rewindIndicatorTimer?.cancel();
    setState(() {
      _showRewindIndicator = true;
    });
    _rewindIndicatorTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) {
        setState(() => _showRewindIndicator = false);
      }
    });
  }

  void _handleDoubleTapRight() {
    _seekRelative(const Duration(seconds: 10));
    _forwardIndicatorTimer?.cancel();
    setState(() {
      _showForwardIndicator = true;
    });
    _forwardIndicatorTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) {
        setState(() => _showForwardIndicator = false);
      }
    });
  }

  void _onSliderChanged(double value) {
    setState(() {
      _isDragging = true;
      _dragPositionMs = value;
    });
    _hideTimer?.cancel();
  }

  void _onSliderChangeEnd(double value) {
    _controller.seekTo(Duration(milliseconds: value.toInt()));
    setState(() {
      _isDragging = false;
    });
    if (_controller.value.isPlaying) {
      _startHideTimer();
    }
  }

  Future<void> _handleOpenExternal() async {
    if (widget.onOpenExternal != null) {
      await widget.onOpenExternal!(widget.filePath);
    } else {
      await openMediaFile(widget.filePath);
    }
  }

  void _toggleFitMode() {
    setState(() {
      switch (_fitMode) {
        case VideoFitMode.fit:
          _fitMode = VideoFitMode.fill;
          break;
        case VideoFitMode.fill:
          _fitMode = VideoFitMode.widescreen;
          break;
        case VideoFitMode.widescreen:
          _fitMode = VideoFitMode.fit;
          break;
      }
    });

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_fitMode.label),
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _toggleOrientation() async {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    try {
      await SystemChrome.setPreferredOrientations(
        landscape
            ? [DeviceOrientation.portraitUp]
            : [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
      );
    } catch (_) {}
  }

  Future<void> _showSettingsSheet() async {
    _hideTimer?.cancel();
    final pickSpeed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder:
          (sheetContext) => StatefulBuilder(
            builder:
                (context, setSheetState) => MediaOptionsSheet(
                  title: 'Playback Settings',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.speed_rounded),
                      title: const Text('Playback speed'),
                      trailing: Text(
                        _playbackSpeed == 1.0 ? 'Normal' : '${_playbackSpeed}x',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      onTap: () => Navigator.pop(sheetContext, true),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.repeat_rounded),
                      title: const Text('Loop video'),
                      value: _isLooping,
                      onChanged: (value) {
                        setSheetState(() => _isLooping = value);
                        setState(() => _isLooping = value);
                        _controller.setLooping(value);
                      },
                    ),
                  ],
                ),
          ),
    );
    if (!mounted) return;
    if (pickSpeed == true) {
      await _showSpeedPicker();
    } else if (_controller.value.isPlaying) {
      _startHideTimer();
    }
  }

  Future<void> _showSpeedPicker() async {
    _hideTimer?.cancel();
    const speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder:
          (context) => MediaOptionsSheet(
            title: 'Playback Speed',
            children: [
              for (final speed in speeds)
                ListTile(
                  selected: (_playbackSpeed - speed).abs() < .01,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  selectedTileColor:
                      Theme.of(context).colorScheme.surfaceContainerHigh,
                  title: Text(speed == 1.0 ? 'Normal' : '${speed}x'),
                  trailing:
                      (_playbackSpeed - speed).abs() < .01
                          ? const Icon(Icons.check_rounded)
                          : null,
                  onTap: () {
                    setState(() => _playbackSpeed = speed);
                    _controller.setPlaybackSpeed(speed);
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
    );
    if (mounted && _controller.value.isPlaying) _startHideTimer();
  }

  String _formatTimestamp(Duration d) {
    if (d.isNegative) return '00:00';
    final totalSeconds = d.inSeconds;
    final minutes = (totalSeconds ~/ 60)
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final hours = d.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _rewindIndicatorTimer?.cancel();
    _forwardIndicatorTimer?.cancel();
    try {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } catch (_) {}
    final c = _activeController;
    if (c != null) {
      c.removeListener(_onControllerUpdate);
      if (widget.controller == null) {
        c.dispose();
      }
    }
    super.dispose();
  }

  Widget _buildTopBar(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 4,
        left: MediaQuery.paddingOf(context).left + 4,
        right: MediaQuery.paddingOf(context).right + 4,
        bottom: 12,
      ),
      child: Row(
        children: [
          IconButton(
            key: const Key('video_player_back_button'),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            tooltip: 'Back',
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              widget.title,
              key: const Key('video_player_title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.aspect_ratio_rounded, color: Colors.white),
            tooltip: 'Aspect ratio (${_fitMode.label})',
            onPressed: _toggleFitMode,
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded, color: Colors.white),
            tooltip: 'Playback settings',
            onPressed: _showSettingsSheet,
          ),
          IconButton(
            key: const Key('video_player_external_button'),
            icon: const Icon(Icons.open_in_new_rounded, color: Colors.white),
            tooltip: 'Open in external player',
            onPressed: _handleOpenExternal,
          ),
        ],
      ),
    );
  }

  Widget _buildCenterControls(BuildContext context) {
    final isPlaying = _controller.value.isPlaying;
    final isFinished =
        _controller.value.duration > Duration.zero &&
        _controller.value.position >= _controller.value.duration;

    final IconData iconData;
    if (isFinished) {
      iconData = Icons.replay_rounded;
    } else if (isPlaying) {
      iconData = Icons.pause_rounded;
    } else {
      iconData = Icons.play_arrow_rounded;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Rewind 10s button
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            iconSize: 36,
            color: Colors.white,
            tooltip: 'Rewind 10 seconds',
            icon: const Icon(Icons.replay_10_rounded),
            onPressed: () => _seekRelative(const Duration(seconds: -10)),
          ),
        ),
        const SizedBox(width: 32),
        // Play / Pause center button
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            key: const Key('video_player_play_pause_button'),
            iconSize: 58,
            color: Colors.white,
            tooltip: isPlaying ? 'Pause' : 'Play',
            icon: Icon(iconData),
            onPressed: _togglePlayPause,
          ),
        ),
        const SizedBox(width: 32),
        // Forward 10s button
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            iconSize: 36,
            color: Colors.white,
            tooltip: 'Forward 10 seconds',
            icon: const Icon(Icons.forward_10_rounded),
            onPressed: () => _seekRelative(const Duration(seconds: 10)),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomControls(BuildContext context) {
    final duration = _controller.value.duration;
    final durationMs = duration.inMilliseconds.toDouble();
    final position =
        _isDragging
            ? Duration(milliseconds: _dragPositionMs.toInt())
            : _controller.value.position;
    final positionMs = position.inMilliseconds.toDouble().clamp(
      0.0,
      durationMs > 0 ? durationMs : 0.0,
    );

    final positionStr = _formatTimestamp(position);
    final durationStr = _formatTimestamp(duration);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: EdgeInsets.only(
        left: MediaQuery.paddingOf(context).left + 16,
        right: MediaQuery.paddingOf(context).right + 16,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Scrub Slider (YouTube sleek red/violet bar)
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.2,
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: _isDragging ? 7 : 5,
              ),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: Theme.of(context).colorScheme.primary,
              inactiveTrackColor: Colors.white24,
              thumbColor: Theme.of(context).colorScheme.primary,
              overlayColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: .25),
            ),
            child: Slider(
              key: const Key('video_player_scrub_slider'),
              value: positionMs,
              min: 0.0,
              max: durationMs > 0 ? durationMs : 1.0,
              onChanged: durationMs > 0 ? _onSliderChanged : null,
              onChangeEnd: durationMs > 0 ? _onSliderChangeEnd : null,
            ),
          ),
          Row(
            children: [
              Text(
                '$positionStr / $durationStr',
                key: const Key('video_player_timestamp'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _showSpeedPicker,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  minimumSize: const Size(48, 48),
                ),
                child: Text(
                  _playbackSpeed == 1.0 ? '1x' : '${_playbackSpeed}x',
                ),
              ),
              const SizedBox(width: 8),
              // Fullscreen toggle
              IconButton(
                iconSize: 22,
                color: Colors.white,
                tooltip:
                    MediaQuery.orientationOf(context) == Orientation.landscape
                        ? 'Exit Fullscreen'
                        : 'Fullscreen',
                icon: Icon(
                  MediaQuery.orientationOf(context) == Orientation.landscape
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                ),
                onPressed: _toggleOrientation,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSeekOverlay({required bool isLeft, required bool isVisible}) {
    if (!isVisible) return const SizedBox.shrink();
    return Align(
      alignment: isLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        width: 140,
        height: 140,
        margin: EdgeInsets.only(left: isLeft ? 24 : 0, right: isLeft ? 0 : 24),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          shape: BoxShape.circle,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isLeft ? Icons.replay_10_rounded : Icons.forward_10_rounded,
              color: Colors.white,
              size: 38,
            ),
            const SizedBox(height: 4),
            Text(
              isLeft ? '-10 sec' : '+10 sec',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_hasError) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          title: Text(
            widget.title,
            key: const Key('video_player_title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              key: const Key('video_player_external_button'),
              icon: const Icon(Icons.open_in_new_rounded),
              tooltip: 'Open in external player',
              onPressed: _handleOpenExternal,
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 64,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Failed to play video',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage ?? 'The video format could not be played.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const Key('video_player_error_external_button'),
                  onPressed: _handleOpenExternal,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open in External App'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          title: Text(
            widget.title,
            key: const Key('video_player_title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              key: const Key('video_player_external_button'),
              icon: const Icon(Icons.open_in_new_rounded),
              tooltip: 'Open in external player',
              onPressed: _handleOpenExternal,
            ),
          ],
        ),
        body: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }

    final naturalAspect =
        _controller.value.aspectRatio > 0
            ? _controller.value.aspectRatio
            : 16 / 9;

    final effectiveAspect =
        _fitMode == VideoFitMode.widescreen ? 16 / 9 : naturalAspect;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Video Canvas
          Center(
            child:
                _fitMode == VideoFitMode.fill
                    ? SizedBox.expand(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width:
                              _controller.value.size.width > 0
                                  ? _controller.value.size.width
                                  : 1920,
                          height:
                              _controller.value.size.height > 0
                                  ? _controller.value.size.height
                                  : 1080,
                          child: VideoPlayer(_controller),
                        ),
                      ),
                    )
                    : AspectRatio(
                      aspectRatio: effectiveAspect,
                      child: VideoPlayer(_controller),
                    ),
          ),

          // Double tap zones & gestures
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: _handleDoubleTapLeft,
                  onTap: _toggleControls,
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: _handleDoubleTapRight,
                  onTap: _toggleControls,
                ),
              ),
            ],
          ),

          // Double tap seek visual feedback
          _buildSeekOverlay(isLeft: true, isVisible: _showRewindIndicator),
          _buildSeekOverlay(isLeft: false, isVisible: _showForwardIndicator),

          // Controls Overlay
          IgnorePointer(
            ignoring: !_showControls,
            child: AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _buildTopBar(context),
                  ),
                  Center(child: _buildCenterControls(context)),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildBottomControls(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
