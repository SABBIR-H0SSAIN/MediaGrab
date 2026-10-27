import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';

/// Dialog allowing the user to select between System, Light, Dark, and AMOLED Pure Black themes.
class ThemeSelector extends ConsumerWidget {
  const ThemeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final selectedKey =
        settings.amoledDark && settings.themeMode == ThemeMode.dark
            ? 'amoled'
            : settings.themeMode.name;

    return AlertDialog(
      title: const Text('Theme Mode'),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      content: RadioGroup<String>(
        groupValue: selectedKey,
        onChanged: (mode) {
          if (mode != null) {
            final notifier = ref.read(settingsProvider.notifier);
            switch (mode) {
              case 'system':
                notifier.setThemeMode(ThemeMode.system);
                notifier.setAmoledDark(false);
                break;
              case 'light':
                notifier.setThemeMode(ThemeMode.light);
                notifier.setAmoledDark(false);
                break;
              case 'dark':
                notifier.setThemeMode(ThemeMode.dark);
                notifier.setAmoledDark(false);
                break;
              case 'amoled':
                notifier.setThemeMode(ThemeMode.dark);
                notifier.setAmoledDark(true);
                break;
            }
            Navigator.of(context).pop();
          }
        },
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(title: Text('System'), value: 'system'),
            RadioListTile<String>(title: Text('Light'), value: 'light'),
            RadioListTile<String>(title: Text('Dark'), value: 'dark'),
            RadioListTile<String>(
              title: Text('AMOLED Pure Black'),
              value: 'amoled',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// Convenience helper to display the [ThemeSelector] dialog.
Future<void> showThemeSelectorDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const ThemeSelector(),
  );
}
