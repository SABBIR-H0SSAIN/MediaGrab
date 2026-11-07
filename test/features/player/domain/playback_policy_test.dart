import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/player/domain/playback_preferences.dart';
import 'package:mediagrab/features/player/domain/playback_state.dart';

void main() {
  test(
    'rapid skips accumulate from pending targets and clamp at both bounds',
    () {
      final burst = SeekBurst();
      final now = DateTime(2026);
      Duration skip(int direction, int ms, {int position = 30}) => burst.skip(
        direction: direction,
        seconds: 10,
        position: Duration(seconds: position),
        duration: const Duration(seconds: 55),
        now: now.add(Duration(milliseconds: ms)),
      );
      expect(skip(1, 0), const Duration(seconds: 40));
      expect(skip(1, 100), const Duration(seconds: 50));
      expect(skip(1, 200), const Duration(seconds: 55));
      expect(burst.cumulativeSeconds, 30);
      // Direction reversal uses the requested 55s target, not a stale 5s event.
      expect(skip(-1, 300, position: 5), const Duration(seconds: 45));
      expect(burst.cumulativeSeconds, 10);
      expect(skip(1, 1200, position: 10), const Duration(seconds: 20));
      expect(skip(-1, 2200, position: 5), Duration.zero);
      expect(burst.cumulativeSeconds, 10);
    },
  );
  test('all configurable increments use the same cumulative policy', () {
    for (final increment in [5, 10, 15, 30]) {
      final burst = SeekBurst();
      for (var i = 0; i < 3; i++) {
        expect(
          burst.skip(
            direction: 1,
            seconds: increment,
            position: Duration.zero,
            duration: const Duration(minutes: 10),
            now: DateTime(2026).add(Duration(milliseconds: i * 50)),
          ),
          Duration(seconds: increment * (i + 1)),
        );
      }
    }
  });
  test(
    'invalid preferences preserve safe defaults without corrupting other fields',
    () {
      final prefs = PlaybackPreferences.fromJson({
        'defaultSpeed': 99,
        'hideSeconds': -1,
        'seekSeconds': 8,
        'lastTimerMinutes': -20,
        'background': false,
        'notifications': false,
      });
      expect(prefs.defaultSpeed, 1);
      expect(prefs.hideSeconds, 3);
      expect(prefs.seekSeconds, 10);
      expect(prefs.lastTimerMinutes, 1);
      expect(prefs.effectiveNotifications, false);
      expect(PlaybackPreferences.fromJson(prefs.toJson()), prefs);
      expect(prefs.update('background', true).effectiveNotifications, true);
    },
  );
  test('queue validates its selected item and owns an immutable snapshot', () {
    final items = [const PlaybackItem(id: 'a', filePath: '/a.mp4', title: 'A')];
    final queue = PlaybackQueue(items);
    items.clear();
    expect(queue.items, hasLength(1));
    expect(() => queue.items.clear(), throwsUnsupportedError);
    expect(() => PlaybackQueue([]), throwsArgumentError);
    expect(() => PlaybackQueue(queue.items, index: 1), throwsArgumentError);
  });
}
