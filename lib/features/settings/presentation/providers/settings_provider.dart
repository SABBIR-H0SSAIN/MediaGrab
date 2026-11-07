import 'dart:convert';
import '../../../player/domain/playback_preferences.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_constants.dart';

/// State representation for user preferences and app settings.
class SettingsState extends Equatable {
  final PlaybackPreferences playback;
  final ThemeMode themeMode;
  final bool amoledDark;
  final bool dynamicColors;
  final String defaultVideoQuality;
  final String defaultAudioFormat;
  final int maxConcurrentDownloads;
  final bool downloadOverCellular;
  final String downloadDirectory;

  const SettingsState({
    this.playback = const PlaybackPreferences(),
    this.themeMode = ThemeMode.system,
    this.amoledDark = false,
    this.dynamicColors = true,
    this.defaultVideoQuality = 'Best',
    this.defaultAudioFormat = 'MP3',
    this.maxConcurrentDownloads = 3,
    this.downloadOverCellular = true,
    this.downloadDirectory = '',
  });

  /// Human-readable label for the current [themeMode].
  String get themeModeLabel {
    if (amoledDark && themeMode == ThemeMode.dark) {
      return 'AMOLED Pure Black';
    }
    switch (themeMode) {
      case ThemeMode.system:
        return 'System';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  SettingsState copyWith({
    PlaybackPreferences? playback,
    ThemeMode? themeMode,
    bool? amoledDark,
    bool? dynamicColors,
    String? defaultVideoQuality,
    String? defaultAudioFormat,
    int? maxConcurrentDownloads,
    bool? downloadOverCellular,
    String? downloadDirectory,
  }) {
    return SettingsState(
      playback: playback ?? this.playback,
      themeMode: themeMode ?? this.themeMode,
      amoledDark: amoledDark ?? this.amoledDark,
      dynamicColors: dynamicColors ?? this.dynamicColors,
      defaultVideoQuality: defaultVideoQuality ?? this.defaultVideoQuality,
      defaultAudioFormat: defaultAudioFormat ?? this.defaultAudioFormat,
      maxConcurrentDownloads:
          maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      downloadOverCellular: downloadOverCellular ?? this.downloadOverCellular,
      downloadDirectory: downloadDirectory ?? this.downloadDirectory,
    );
  }

  @override
  List<Object?> get props => [
    playback,
    themeMode,
    amoledDark,
    dynamicColors,
    defaultVideoQuality,
    defaultAudioFormat,
    maxConcurrentDownloads,
    downloadOverCellular,
    downloadDirectory,
  ];
}

/// State notifier managing [SettingsState] and persistence in [SharedPreferences].
class SettingsNotifier extends StateNotifier<SettingsState> {
  static const String keyPlayback = 'settings_playback_v1';
  Future<void> _playbackWrites = Future<void>.value();
  static const String keyThemeMode = 'settings_theme_mode';
  static const String keyAmoledDark = 'settings_amoled_dark';
  static const String keyDynamicColors = 'settings_dynamic_colors';
  static const String keyDefaultVideoQuality = 'settings_default_video_quality';
  static const String keyDefaultAudioFormat = 'settings_default_audio_format';
  static const String keyMaxConcurrentDownloads =
      'settings_max_concurrent_downloads';
  static const String keyDownloadOverCellular =
      'settings_download_over_cellular';
  static const String keyDownloadDirectory = 'settings_download_directory';

  SharedPreferences? _prefs;
  late final Future<void> ready;
  bool _playbackTouched = false;

  SettingsNotifier({SharedPreferences? prefs})
    : _prefs = prefs,
      super(const SettingsState()) {
    if (_prefs != null) {
      _loadFromPrefs(_prefs!);
      ready = Future<void>.value();
    } else {
      ready = _initAsync();
    }
  }

  void _loadFromPrefs(SharedPreferences prefs) {
    final themeStr = prefs.getString(keyThemeMode);
    final themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == themeStr,
      orElse: () => ThemeMode.system,
    );
    final amoledDark = prefs.getBool(keyAmoledDark) ?? false;
    final dynamicColors = prefs.getBool(keyDynamicColors) ?? true;
    final defaultVideoQuality =
        prefs.getString(keyDefaultVideoQuality) ?? 'Best';
    final defaultAudioFormat = prefs.getString(keyDefaultAudioFormat) ?? 'MP3';
    final maxConcurrentDownloads =
        (prefs.getInt(keyMaxConcurrentDownloads) ?? 3).clamp(1, 5);
    final downloadOverCellular = prefs.getBool(keyDownloadOverCellular) ?? true;
    final downloadDirectory = prefs.getString(keyDownloadDirectory) ?? '';

    var playback = const PlaybackPreferences();
    try {
      final json = jsonDecode(prefs.getString(keyPlayback) ?? '{}');
      if (json is Map<String, dynamic>) {
        playback = PlaybackPreferences.fromJson(json);
      }
    } catch (_) {
      // A corrupt playback preference must not prevent existing settings loading.
    }
    state = SettingsState(
      playback: _playbackTouched ? state.playback : playback,
      themeMode: themeMode,
      amoledDark: amoledDark,
      dynamicColors: dynamicColors,
      defaultVideoQuality: defaultVideoQuality,
      defaultAudioFormat: defaultAudioFormat,
      maxConcurrentDownloads: maxConcurrentDownloads,
      downloadOverCellular: downloadOverCellular,
      downloadDirectory: downloadDirectory,
    );
  }

  Future<void> _initAsync() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      if (mounted) _loadFromPrefs(_prefs!);
    } catch (_) {
      // In tests or environments without shared_preferences channel, keep default state
    }
  }

  Future<SharedPreferences?> _getPrefs() async {
    if (_prefs != null) return _prefs;
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    return _prefs;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = await _getPrefs();
    await prefs?.setString(keyThemeMode, mode.name);
  }

  Future<void> setAmoledDark(bool value) async {
    state = state.copyWith(amoledDark: value);
    final prefs = await _getPrefs();
    await prefs?.setBool(keyAmoledDark, value);
  }

  Future<void> setDynamicColors(bool value) async {
    state = state.copyWith(dynamicColors: value);
    final prefs = await _getPrefs();
    await prefs?.setBool(keyDynamicColors, value);
  }

  Future<void> setDefaultVideoQuality(String quality) async {
    state = state.copyWith(defaultVideoQuality: quality);
    final prefs = await _getPrefs();
    await prefs?.setString(keyDefaultVideoQuality, quality);
  }

  Future<void> setDefaultAudioFormat(String format) async {
    state = state.copyWith(defaultAudioFormat: format);
    final prefs = await _getPrefs();
    await prefs?.setString(keyDefaultAudioFormat, format);
  }

  Future<void> setMaxConcurrentDownloads(int count) async {
    final boundedCount = count.clamp(1, 5);
    state = state.copyWith(maxConcurrentDownloads: boundedCount);
    final prefs = await _getPrefs();
    await prefs?.setInt(keyMaxConcurrentDownloads, boundedCount);
  }

  Future<void> setDownloadOverCellular(bool value) async {
    state = state.copyWith(downloadOverCellular: value);
    final prefs = await _getPrefs();
    await prefs?.setBool(keyDownloadOverCellular, value);
  }

  Future<void> setDownloadDirectory(String directory) async {
    state = state.copyWith(downloadDirectory: directory);
    final prefs = await _getPrefs();
    await prefs?.setString(keyDownloadDirectory, directory);
  }

  Future<void> setPlayback(PlaybackPreferences preferences) {
    _playbackTouched = true;
    state = state.copyWith(playback: preferences);
    final captured = jsonEncode(preferences.toJson());
    _playbackWrites = _playbackWrites.then((_) async {
      final prefs = await _getPrefs();
      await prefs?.setString(keyPlayback, captured);
    });
    return _playbackWrites;
  }

  Future<void> resetToDefaults() async {
    state = const SettingsState();
    final prefs = await _getPrefs();
    await _playbackWrites;
    await prefs?.remove(keyPlayback);
    await prefs?.remove(keyThemeMode);
    await prefs?.remove(keyAmoledDark);
    await prefs?.remove(keyDynamicColors);
    await prefs?.remove(keyDefaultVideoQuality);
    await prefs?.remove(keyDefaultAudioFormat);
    await prefs?.remove(keyMaxConcurrentDownloads);
    await prefs?.remove(keyDownloadOverCellular);
    await prefs?.remove(keyDownloadDirectory);
  }
}

/// Optional provider for injecting an explicit [SharedPreferences] instance.
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

/// Main settings provider managing application settings state and persistence.
final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) {
    final prefs = ref.watch(sharedPreferencesProvider);
    return SettingsNotifier(prefs: prefs);
  },
);

/// Async provider for the application version string.
final appVersionProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return 'v${info.version}';
  } catch (_) {
    return 'v${AppConstants.appVersion}';
  }
});
