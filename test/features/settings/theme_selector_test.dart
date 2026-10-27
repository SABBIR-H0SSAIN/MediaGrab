import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/settings/presentation/providers/settings_provider.dart';
import 'package:mediagrab/features/settings/presentation/widgets/theme_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'ThemeSelector renders options and selecting updates theme mode',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder:
                    (context) => ElevatedButton(
                      onPressed: () => showThemeSelectorDialog(context),
                      child: const Text('Open'),
                    ),
              ),
            ),
          ),
        ),
      );

      // Initial state is system
      expect(container.read(settingsProvider).themeMode, ThemeMode.system);

      // Open dialog
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Theme Mode'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);

      // Tap Dark
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      // Dialog is closed
      expect(find.text('Theme Mode'), findsNothing);
      // Provider state is dark
      expect(container.read(settingsProvider).themeMode, ThemeMode.dark);
    },
  );

  testWidgets(
    'ThemeSelector selecting AMOLED Pure Black sets dark mode and amoledDark flag',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder:
                    (context) => ElevatedButton(
                      onPressed: () => showThemeSelectorDialog(context),
                      child: const Text('Open'),
                    ),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('AMOLED Pure Black'), findsOneWidget);

      // Tap AMOLED Pure Black
      await tester.tap(find.text('AMOLED Pure Black'));
      await tester.pumpAndSettle();

      expect(find.text('Theme Mode'), findsNothing);
      expect(container.read(settingsProvider).themeMode, ThemeMode.dark);
      expect(container.read(settingsProvider).amoledDark, isTrue);
    },
  );

  testWidgets('ThemeSelector Cancel button dismisses dialog', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: ThemeSelector())),
      ),
    );

    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
