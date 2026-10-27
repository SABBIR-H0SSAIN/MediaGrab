import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/settings/presentation/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsState', () {
    test('default values', () {
      const state = SettingsState();
      expect(state.themeMode, ThemeMode.system);
      expect(state.amoledDark, false);
      expect(state.dynamicColors, true);
      expect(state.defaultVideoQuality, 'Best');
      expect(state.defaultAudioFormat, 'MP3');
      expect(state.maxConcurrentDownloads, 3);
      expect(state.downloadOverCellular, true);
      expect(state.downloadDirectory, '');
      expect(state.themeModeLabel, 'System');
    });

    test('themeModeLabel returns correct text for all modes', () {
      expect(
        const SettingsState(themeMode: ThemeMode.system).themeModeLabel,
        'System',
      );
      expect(
        const SettingsState(themeMode: ThemeMode.light).themeModeLabel,
        'Light',
      );
      expect(
        const SettingsState(themeMode: ThemeMode.dark).themeModeLabel,
        'Dark',
      );
      expect(
        const SettingsState(
          themeMode: ThemeMode.dark,
          amoledDark: true,
        ).themeModeLabel,
        'AMOLED Pure Black',
      );
    });

    test('equality and copyWith work properly', () {
      const state1 = SettingsState();
      final state2 = state1.copyWith(
        themeMode: ThemeMode.dark,
        amoledDark: true,
        dynamicColors: false,
        defaultVideoQuality: '720p',
        defaultAudioFormat: 'OPUS',
        maxConcurrentDownloads: 5,
        downloadOverCellular: false,
        downloadDirectory: '/custom/downloads',
      );

      expect(state1 == state2, isFalse);
      expect(state2.themeMode, ThemeMode.dark);
      expect(state2.amoledDark, true);
      expect(state2.dynamicColors, false);
      expect(state2.defaultVideoQuality, '720p');
      expect(state2.defaultAudioFormat, 'OPUS');
      expect(state2.maxConcurrentDownloads, 5);
      expect(state2.downloadOverCellular, false);
      expect(state2.downloadDirectory, '/custom/downloads');

      final state3 = state2.copyWith();
      expect(state2, equals(state3));
    });
  });

  group('SettingsNotifier', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('initializes with default values when prefs are empty', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = SettingsNotifier(prefs: prefs);

      expect(notifier.state.themeMode, ThemeMode.system);
      expect(notifier.state.amoledDark, false);
      expect(notifier.state.dynamicColors, true);
      expect(notifier.state.defaultVideoQuality, 'Best');
      expect(notifier.state.defaultAudioFormat, 'MP3');
      expect(notifier.state.maxConcurrentDownloads, 3);
      expect(notifier.state.downloadOverCellular, true);
    });

    test('loads saved preferences correctly from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        SettingsNotifier.keyThemeMode: 'dark',
        SettingsNotifier.keyAmoledDark: true,
        SettingsNotifier.keyDynamicColors: false,
        SettingsNotifier.keyDefaultVideoQuality: '1080p',
        SettingsNotifier.keyDefaultAudioFormat: 'M4A',
        SettingsNotifier.keyMaxConcurrentDownloads: 4,
        SettingsNotifier.keyDownloadOverCellular: false,
        SettingsNotifier.keyDownloadDirectory: '/custom/storage',
      });

      final prefs = await SharedPreferences.getInstance();
      final notifier = SettingsNotifier(prefs: prefs);

      expect(notifier.state.themeMode, ThemeMode.dark);
      expect(notifier.state.amoledDark, true);
      expect(notifier.state.dynamicColors, false);
      expect(notifier.state.defaultVideoQuality, '1080p');
      expect(notifier.state.defaultAudioFormat, 'M4A');
      expect(notifier.state.maxConcurrentDownloads, 4);
      expect(notifier.state.downloadOverCellular, false);
      expect(notifier.state.downloadDirectory, '/custom/storage');
    });

    test(
      'setThemeMode updates state and writes to SharedPreferences',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final notifier = SettingsNotifier(prefs: prefs);

        await notifier.setThemeMode(ThemeMode.light);
        expect(notifier.state.themeMode, ThemeMode.light);
        expect(prefs.getString(SettingsNotifier.keyThemeMode), 'light');

        await notifier.setThemeMode(ThemeMode.dark);
        expect(notifier.state.themeMode, ThemeMode.dark);
        expect(prefs.getString(SettingsNotifier.keyThemeMode), 'dark');
      },
    );

    test(
      'setAmoledDark updates state and writes to SharedPreferences',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final notifier = SettingsNotifier(prefs: prefs);

        await notifier.setAmoledDark(true);
        expect(notifier.state.amoledDark, true);
        expect(prefs.getBool(SettingsNotifier.keyAmoledDark), true);

        await notifier.setAmoledDark(false);
        expect(notifier.state.amoledDark, false);
        expect(prefs.getBool(SettingsNotifier.keyAmoledDark), false);
      },
    );

    test(
      'setDynamicColors updates state and writes to SharedPreferences',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final notifier = SettingsNotifier(prefs: prefs);

        await notifier.setDynamicColors(false);
        expect(notifier.state.dynamicColors, false);
        expect(prefs.getBool(SettingsNotifier.keyDynamicColors), false);

        await notifier.setDynamicColors(true);
        expect(notifier.state.dynamicColors, true);
        expect(prefs.getBool(SettingsNotifier.keyDynamicColors), true);
      },
    );

    test(
      'setDefaultVideoQuality updates state and writes to SharedPreferences',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final notifier = SettingsNotifier(prefs: prefs);

        await notifier.setDefaultVideoQuality('720p');
        expect(notifier.state.defaultVideoQuality, '720p');
        expect(
          prefs.getString(SettingsNotifier.keyDefaultVideoQuality),
          '720p',
        );
      },
    );

    test(
      'setDefaultAudioFormat updates state and writes to SharedPreferences',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final notifier = SettingsNotifier(prefs: prefs);

        await notifier.setDefaultAudioFormat('OPUS');
        expect(notifier.state.defaultAudioFormat, 'OPUS');
        expect(prefs.getString(SettingsNotifier.keyDefaultAudioFormat), 'OPUS');
      },
    );

    test(
      'setMaxConcurrentDownloads updates state and writes to SharedPreferences',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final notifier = SettingsNotifier(prefs: prefs);

        await notifier.setMaxConcurrentDownloads(5);
        expect(notifier.state.maxConcurrentDownloads, 5);
        expect(prefs.getInt(SettingsNotifier.keyMaxConcurrentDownloads), 5);
      },
    );

    test(
      'setDownloadOverCellular updates state and writes to SharedPreferences',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final notifier = SettingsNotifier(prefs: prefs);

        await notifier.setDownloadOverCellular(false);
        expect(notifier.state.downloadOverCellular, false);
        expect(prefs.getBool(SettingsNotifier.keyDownloadOverCellular), false);
      },
    );

    test(
      'setDownloadDirectory updates state and writes to SharedPreferences',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final notifier = SettingsNotifier(prefs: prefs);

        await notifier.setDownloadDirectory('/my/download/path');
        expect(notifier.state.downloadDirectory, '/my/download/path');
        expect(
          prefs.getString(SettingsNotifier.keyDownloadDirectory),
          '/my/download/path',
        );
      },
    );

    test('resetToDefaults clears preferences and restores defaults', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = SettingsNotifier(prefs: prefs);

      await notifier.setThemeMode(ThemeMode.dark);
      await notifier.setAmoledDark(true);
      await notifier.setMaxConcurrentDownloads(1);
      await notifier.setDownloadDirectory('/my/path');

      await notifier.resetToDefaults();
      expect(notifier.state, const SettingsState());
      expect(prefs.containsKey(SettingsNotifier.keyThemeMode), isFalse);
      expect(prefs.containsKey(SettingsNotifier.keyAmoledDark), isFalse);
      expect(prefs.containsKey(SettingsNotifier.keyDownloadDirectory), isFalse);
    });
  });
}
