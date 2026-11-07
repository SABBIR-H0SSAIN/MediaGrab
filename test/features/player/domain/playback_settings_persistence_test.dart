import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediagrab/features/settings/presentation/providers/settings_provider.dart';
import 'package:mediagrab/features/player/domain/playback_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'old settings survive playback edits and ordered writes restore on restart',
    () async {
      SharedPreferences.setMockInitialValues({
        SettingsNotifier.keyDownloadDirectory: '/keep/downloads',
        'mediagrab_download_registry_v1': 'untouched',
      });
      final prefs = await SharedPreferences.getInstance();
      final notifier = SettingsNotifier(prefs: prefs);
      expect(notifier.state.playback, const PlaybackPreferences());
      final first = notifier.setPlayback(
        notifier.state.playback.update('seekSeconds', 15),
      );
      final second = notifier.setPlayback(
        notifier.state.playback.update('background', false),
      );
      await Future.wait([first, second]);
      notifier.dispose();
      final restored = SettingsNotifier(prefs: prefs);
      expect(restored.state.playback.seekSeconds, 15);
      expect(restored.state.playback.background, false);
      expect(restored.state.downloadDirectory, '/keep/downloads');
      expect(prefs.getString('mediagrab_download_registry_v1'), 'untouched');
      await restored.resetToDefaults();
      expect(prefs.containsKey(SettingsNotifier.keyPlayback), false);
      expect(prefs.getString('mediagrab_download_registry_v1'), 'untouched');
      restored.dispose();
    },
  );
  test(
    'malformed playback preferences do not break existing settings',
    () async {
      SharedPreferences.setMockInitialValues({
        SettingsNotifier.keyPlayback: '{bad',
        SettingsNotifier.keyDefaultVideoQuality: '720p',
      });
      final prefs = await SharedPreferences.getInstance();
      final notifier = SettingsNotifier(prefs: prefs);
      expect(notifier.state.defaultVideoQuality, '720p');
      expect(notifier.state.playback, const PlaybackPreferences());
      await notifier.setPlayback(const PlaybackPreferences(lastSpeed: 1.75));
      expect(
        jsonDecode(prefs.getString(SettingsNotifier.keyPlayback)!)['lastSpeed'],
        1.75,
      );
      notifier.dispose();
    },
  );
}
