import 'package:equatable/equatable.dart';

/// Playback-only preferences. Existing settings and download stores are untouched.
class PlaybackPreferences extends Equatable {
  const PlaybackPreferences({
    this.miniPlayer = true,
    this.rememberPosition = true,
    this.background = true,
    this.screenOff = true,
    this.pip = true,
    this.audioOnly = true,
    this.defaultSpeed = 1,
    this.rememberSpeed = true,
    this.lastSpeed = 1,
    this.doubleTapSeek = true,
    this.seekSeconds = 10,
    this.hideSeconds = 3,
    this.screenLock = true,
    this.volumeGesture = false,
    this.brightnessGesture = false,
    this.notifications = true,
    this.rememberTimer = true,
    this.lastTimerMinutes = 30,
    this.defaultTimerMinutes = 0,
    this.fadeOut = false,
  });

  static const speeds = [.25, .5, .75, 1.0, 1.25, 1.5, 1.75, 2.0];
  final bool miniPlayer,
      background,
      screenOff,
      pip,
      audioOnly,
      rememberPosition;
  final double defaultSpeed, lastSpeed;
  final bool rememberSpeed, doubleTapSeek;
  final int seekSeconds, hideSeconds;
  final bool screenLock, volumeGesture, brightnessGesture, notifications;
  final bool rememberTimer, fadeOut;
  final int lastTimerMinutes, defaultTimerMinutes;
  double get initialSpeed => rememberSpeed ? lastSpeed : defaultSpeed;
  bool get effectiveNotifications => background || notifications;

  Map<String, dynamic> toJson() => {
    'miniPlayer': miniPlayer,
    'rememberPosition': rememberPosition,
    'background': background,
    'screenOff': screenOff,
    'pip': pip,
    'audioOnly': audioOnly,
    'defaultSpeed': defaultSpeed,
    'rememberSpeed': rememberSpeed,
    'lastSpeed': lastSpeed,
    'doubleTapSeek': doubleTapSeek,
    'seekSeconds': seekSeconds,
    'hideSeconds': hideSeconds,
    'screenLock': screenLock,
    'volumeGesture': volumeGesture,
    'brightnessGesture': brightnessGesture,
    'notifications': notifications,
    'rememberTimer': rememberTimer,
    'lastTimerMinutes': lastTimerMinutes,
    'defaultTimerMinutes': defaultTimerMinutes,
    'fadeOut': fadeOut,
  };

  factory PlaybackPreferences.fromJson(Map<String, dynamic> json) {
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    int choice(String key, List<int> options, int fallback) =>
        options.contains(json[key]) ? json[key] as int : fallback;
    double speed(String key) =>
        speeds.contains(json[key]) ? (json[key] as num).toDouble() : 1;
    int minutes(String key, int fallback, int min) =>
        json[key] is int ? (json[key] as int).clamp(min, 1440) : fallback;
    return PlaybackPreferences(
      miniPlayer: flag('miniPlayer', true),
      rememberPosition: flag('rememberPosition', true),
      background: flag('background', true),
      screenOff: flag('screenOff', true),
      pip: flag('pip', true),
      audioOnly: flag('audioOnly', true),
      defaultSpeed: speed('defaultSpeed'),
      rememberSpeed: flag('rememberSpeed', true),
      lastSpeed: speed('lastSpeed'),
      doubleTapSeek: flag('doubleTapSeek', true),
      seekSeconds: choice('seekSeconds', [5, 10, 15, 30], 10),
      hideSeconds: choice('hideSeconds', [2, 3, 5, 10], 3),
      screenLock: flag('screenLock', true),
      volumeGesture: flag('volumeGesture', false),
      brightnessGesture: flag('brightnessGesture', false),
      notifications: flag('notifications', true),
      rememberTimer: flag('rememberTimer', true),
      lastTimerMinutes: minutes('lastTimerMinutes', 30, 1),
      defaultTimerMinutes: minutes('defaultTimerMinutes', 0, 0),
      fadeOut: flag('fadeOut', false),
    );
  }

  PlaybackPreferences update(String key, Object value) =>
      PlaybackPreferences.fromJson({...toJson(), key: value});

  @override
  List<Object?> get props => toJson().values.toList();
}
