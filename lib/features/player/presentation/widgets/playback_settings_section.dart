import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../settings/presentation/widgets/settings_section.dart';
import '../../domain/playback_preferences.dart';

class PlaybackSettingsSection extends ConsumerWidget {
  const PlaybackSettingsSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => SettingsSection(
    title: 'Playback',
    children: [
      ListTile(
        leading: const Icon(Icons.play_circle_outline_rounded),
        title: const Text('Playback preferences'),
        subtitle: const Text(
          'Background audio, mini-player, gestures and sleep timer',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap:
            () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              useSafeArea: true,
              builder:
                  (context) => const FractionallySizedBox(
                    heightFactor: .9,
                    child: _Preferences(),
                  ),
            ),
      ),
    ],
  );
}

class _Preferences extends ConsumerWidget {
  const _Preferences();
  Future<void> _choose<T extends Object>(
    BuildContext context,
    String title,
    T value,
    List<T> options,
    String Function(T) label,
    void Function(T) onSelect,
  ) async {
    await showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: RadioGroup<T>(
                  groupValue: value,
                  onChanged: (v) {
                    if (v != null) {
                      onSelect(v);
                      Navigator.pop(context);
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final option in options)
                        RadioListTile<T>(
                          title: Text(label(option)),
                          value: option,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(settingsProvider.select((s) => s.playback));
    void update(String key, Object value) {
      final current = ref.read(settingsProvider).playback;
      ref
          .read(settingsProvider.notifier)
          .setPlayback(current.update(key, value));
    }

    Widget toggle(
      String key,
      String title,
      bool value, {
      bool enabled = true,
      String? subtitle,
    }) => SwitchListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      value: value,
      onChanged: enabled ? (v) => update(key, v) : null,
    );
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ListTile(
          title: Text(
            'Playback preferences',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        heading('Playback'),
        toggle('miniPlayer', 'Automatic mini-player', p.miniPlayer),
        toggle(
          'rememberPosition',
          'Resume last playback position',
          p.rememberPosition,
          subtitle:
              'Continue a local file from its saved timestamp when reopened',
        ),
        toggle(
          'background',
          'Background playback and audio',
          p.background,
          subtitle: 'Continue playing local media when using another app',
        ),
        toggle(
          'screenOff',
          'Screen-off playback',
          p.screenOff,
          enabled: p.background,
          subtitle: 'Requires background playback',
        ),
        toggle(
          'notifications',
          'Notification media controls',
          p.effectiveNotifications,
          enabled: !p.background,
          subtitle:
              p.background
                  ? 'Required by Android during background playback'
                  : 'Show media controls for foreground playback',
        ),
        toggle(
          'pip',
          'System picture-in-picture',
          p.pip,
          subtitle: 'Available on supported Android devices',
        ),
        toggle('audioOnly', 'Allow audio-only mode', p.audioOnly),
        ListTile(
          title: const Text('Default playback speed'),
          subtitle: Text('${p.defaultSpeed}x'),
          onTap:
              () => _choose(
                context,
                'Default playback speed',
                p.defaultSpeed,
                PlaybackPreferences.speeds,
                (v) => v == 1 ? 'Normal' : '${v}x',
                (v) => update('defaultSpeed', v),
              ),
        ),
        toggle(
          'rememberSpeed',
          'Remember last playback speed',
          p.rememberSpeed,
          subtitle: 'Use the last speed instead of the default',
        ),
        heading('Controls'),
        toggle('doubleTapSeek', 'Double-tap seeking', p.doubleTapSeek),
        ListTile(
          title: const Text('Seek increment'),
          subtitle: Text('${p.seekSeconds} seconds'),
          onTap:
              () => _choose(
                context,
                'Seek increment',
                p.seekSeconds,
                [5, 10, 15, 30],
                (v) => '$v seconds',
                (v) => update('seekSeconds', v),
              ),
        ),
        ListTile(
          title: const Text('Control auto-hide'),
          subtitle: Text('${p.hideSeconds} seconds'),
          onTap:
              () => _choose(
                context,
                'Control auto-hide',
                p.hideSeconds,
                [2, 3, 5, 10],
                (v) => '$v seconds',
                (v) => update('hideSeconds', v),
              ),
        ),
        toggle('screenLock', 'Allow screen lock', p.screenLock),
        toggle(
          'volumeGesture',
          'Volume swipe gesture',
          p.volumeGesture,
          subtitle: 'Swipe vertically on the right of the video',
        ),
        toggle(
          'brightnessGesture',
          'Brightness swipe gesture',
          p.brightnessGesture,
          subtitle: 'Swipe vertically on the left of the video',
        ),
        heading('Sleep timer'),
        toggle(
          'rememberTimer',
          'Remember last timer duration',
          p.rememberTimer,
        ),
        ListTile(
          title: const Text('Default sleep timer'),
          subtitle: Text(
            p.defaultTimerMinutes == 0
                ? 'Off'
                : '${p.defaultTimerMinutes} minutes',
          ),
          onTap:
              () => _choose(
                context,
                'Default sleep timer',
                p.defaultTimerMinutes,
                [0, 5, 10, 15, 30, 45, 60],
                (v) => v == 0 ? 'Off' : '$v minutes',
                (v) => update('defaultTimerMinutes', v),
              ),
        ),
        toggle(
          'fadeOut',
          'Fade out before timer ends',
          p.fadeOut,
          subtitle: 'Fade audio over the final five seconds',
        ),
      ],
    );
  }
}
