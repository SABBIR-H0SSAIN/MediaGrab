import 'package:equatable/equatable.dart';

class PlaybackItem extends Equatable {
  const PlaybackItem({
    required this.id,
    required this.filePath,
    required this.title,
    this.isAudio = false,
    this.artworkPath,
  });
  final String id, filePath, title;
  final bool isAudio;
  final String? artworkPath;
  Map<String, dynamic> toJson() => {
    'id': id,
    'filePath': filePath,
    'title': title,
    'isAudio': isAudio,
    'artworkPath': artworkPath,
  };
  factory PlaybackItem.fromJson(Map<Object?, Object?> json) => PlaybackItem(
    id: json['id'] as String? ?? '',
    filePath: json['filePath'] as String? ?? '',
    title: json['title'] as String? ?? 'MediaGrab',
    isAudio: json['isAudio'] == true,
    artworkPath: json['artworkPath'] as String?,
  );
  @override
  List<Object?> get props => [id, filePath, title, isAudio, artworkPath];
}

class PlaybackQueue {
  PlaybackQueue(Iterable<PlaybackItem> items, {this.index = 0})
    : items = List.unmodifiable(items) {
    if (this.items.isEmpty || index < 0 || index >= this.items.length) {
      throw ArgumentError('Playback queue must contain its selected item');
    }
  }
  final List<PlaybackItem> items;
  final int index;
}

/// Native session state. [playing] retains playback intent during buffering so
/// Pause remains available; Media3 independently reports actual system playback.
class PlaybackState extends Equatable {
  const PlaybackState({
    this.items = const [],
    this.index = 0,
    this.generation = 0,
    this.initialized = false,
    this.playing = false,
    this.loading = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1,
    this.volume = 1,
    this.loop = false,
    this.audioOnly = false,
    this.pip = false,
    this.pipSupported = false,
    this.textureId,
    this.rotation = 0,
    this.width = 0,
    this.height = 0,
    this.timerRemaining = Duration.zero,
    this.error,
    this.fullPlayer = false,
    this.restoreRequested = false,
  });
  final List<PlaybackItem> items;
  final int index, generation;
  final bool initialized, playing, loading, loop, audioOnly, pip, pipSupported;
  final bool fullPlayer, restoreRequested;
  final Duration position, duration, timerRemaining;
  final double speed, volume, width, height;
  final int? textureId;
  final int rotation;
  final String? error;
  PlaybackItem? get item =>
      index >= 0 && index < items.length ? items[index] : null;
  bool get hasSession => item != null;
  bool get hasPrevious => index > 0;
  bool get hasNext => index + 1 < items.length;
  bool get finished => duration > Duration.zero && position >= duration;
  double get progress =>
      duration.inMilliseconds > 0
          ? (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1)
          : 0;
  double get aspectRatio => width > 0 && height > 0 ? width / height : 16 / 9;

  PlaybackState presentation({bool? fullPlayer, bool? restoreRequested}) =>
      PlaybackState(
        items: items,
        index: index,
        generation: generation,
        initialized: initialized,
        playing: playing,
        loading: loading,
        position: position,
        duration: duration,
        speed: speed,
        volume: volume,
        loop: loop,
        audioOnly: audioOnly,
        pip: pip,
        pipSupported: pipSupported,
        textureId: textureId,
        rotation: rotation,
        width: width,
        height: height,
        timerRemaining: timerRemaining,
        error: error,
        fullPlayer: fullPlayer ?? this.fullPlayer,
        restoreRequested: restoreRequested ?? this.restoreRequested,
      );

  factory PlaybackState.fromJson(Map<Object?, Object?> json) {
    double number(String key, [double fallback = 0]) =>
        (json[key] as num?)?.toDouble() ?? fallback;
    return PlaybackState(
      items: List.unmodifiable(
        (json['queue'] as List? ?? []).map(
          (e) => PlaybackItem.fromJson(Map<Object?, Object?>.from(e as Map)),
        ),
      ),
      index: (json['index'] as num?)?.toInt() ?? 0,
      generation: (json['generation'] as num?)?.toInt() ?? 0,
      initialized: json['initialized'] == true,
      playing: json['playing'] == true,
      loading: json['loading'] == true,
      loop: json['loop'] == true,
      audioOnly: json['audioOnly'] == true,
      pip: json['pip'] == true,
      pipSupported: json['pipSupported'] == true,
      position: Duration(milliseconds: number('position').toInt()),
      duration: Duration(milliseconds: number('duration').toInt()),
      timerRemaining: Duration(milliseconds: number('timerRemaining').toInt()),
      speed: number('speed', 1),
      volume: number('volume', 1),
      width: number('width'),
      height: number('height'),
      textureId: (json['textureId'] as num?)?.toInt(),
      rotation:
          [0, 90, 180, 270].contains(json['rotation'])
              ? json['rotation'] as int
              : 0,
      error: json['error'] as String?,
      restoreRequested: json['restoreRequested'] == true,
    );
  }

  @override
  List<Object?> get props => [
    items,
    index,
    generation,
    initialized,
    playing,
    loading,
    position,
    duration,
    speed,
    volume,
    loop,
    audioOnly,
    pip,
    pipSupported,
    textureId,
    rotation,
    width,
    height,
    timerRemaining,
    error,
    fullPlayer,
    restoreRequested,
  ];
}

/// Accumulates against requested positions, never against delayed seek callbacks.
class SeekBurst {
  DateTime? _last;
  int _direction = 0;
  int cumulativeSeconds = 0;
  Duration? _target;
  Duration? get target => _target;
  Duration skip({
    required int direction,
    required int seconds,
    required Duration position,
    required Duration duration,
    required DateTime now,
  }) {
    final withinBurst =
        _last != null &&
        now.difference(_last!) < const Duration(milliseconds: 800);
    final continuing = withinBurst && _direction == direction;
    cumulativeSeconds = (continuing ? cumulativeSeconds : 0) + seconds;
    final base = withinBurst ? _target! : position;
    _target = Duration(
      milliseconds: (base.inMilliseconds + direction * seconds * 1000).clamp(
        0,
        duration.inMilliseconds,
      ),
    );
    _last = now;
    _direction = direction;
    return _target!;
  }

  void reset() {
    _last = null;
    _target = null;
    cumulativeSeconds = 0;
  }
}
