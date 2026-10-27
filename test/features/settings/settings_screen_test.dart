import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/constants/app_constants.dart';
import 'package:mediagrab/features/settings/presentation/providers/settings_provider.dart';
import 'package:mediagrab/features/settings/presentation/screens/settings_screen.dart';
import 'package:mediagrab/features/settings/presentation/widgets/settings_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeFilePicker extends FilePicker {
  String? resultPath;
  int getDirectoryPathCallCount = 0;
  String? lastDialogTitle;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async {
    getDirectoryPathCallCount++;
    lastDialogTitle = dialogTitle;
    return resultPath;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFilePicker fakeFilePicker;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeFilePicker = FakeFilePicker();
    FilePicker.platform = fakeFilePicker;
  });

  Widget buildSettingsScreen(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsScreen()),
    );
  }

  void setTestViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('SettingsScreen renders AppBar and all four sections', (
    tester,
  ) async {
    setTestViewport(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(buildSettingsScreen(container));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.byType(SettingsSection), findsNWidgets(4));
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
  });

  testWidgets(
    'Theme mode tile opens theme dialog and selecting updates state',
    (tester) async {
      setTestViewport(tester);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(buildSettingsScreen(container));
      await tester.pumpAndSettle();

      // Default theme mode subtitle is System
      expect(find.text('Theme mode'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);

      // Tap theme mode tile
      await tester.tap(find.text('Theme mode'));
      await tester.pumpAndSettle();

      // Dialog is visible
      expect(find.text('Theme Mode'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);

      // Select Dark
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      // State is updated
      expect(container.read(settingsProvider).themeMode, ThemeMode.dark);
      expect(find.text('Dark'), findsOneWidget);
    },
  );

  testWidgets('AMOLED switch is disabled when Light theme is selected', (
    tester,
  ) async {
    setTestViewport(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(buildSettingsScreen(container));
    await tester.pumpAndSettle();

    // Initially in system mode, switch is enabled
    var amoledTile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'AMOLED Dark Mode'),
    );
    expect(amoledTile.onChanged, isNotNull);

    // Switch theme to light
    await container
        .read(settingsProvider.notifier)
        .setThemeMode(ThemeMode.light);
    await tester.pumpAndSettle();

    // Switch is now disabled
    amoledTile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'AMOLED Dark Mode'),
    );
    expect(amoledTile.onChanged, isNull);

    // Switch theme to dark
    await container
        .read(settingsProvider.notifier)
        .setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();

    // Switch is enabled again
    amoledTile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'AMOLED Dark Mode'),
    );
    expect(amoledTile.onChanged, isNotNull);

    // Tapping toggles AMOLED dark mode
    await tester.tap(find.widgetWithText(SwitchListTile, 'AMOLED Dark Mode'));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).amoledDark, isTrue);
  });

  testWidgets('Dynamic Colors switch toggles state', (tester) async {
    setTestViewport(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(buildSettingsScreen(container));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).dynamicColors, isTrue);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Dynamic Colors'));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).dynamicColors, isFalse);
  });

  testWidgets('Video Quality dialog opens and updates selected quality', (
    tester,
  ) async {
    setTestViewport(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(buildSettingsScreen(container));
    await tester.pumpAndSettle();

    expect(find.text('Default Video Quality'), findsOneWidget);
    expect(find.text('Best'), findsOneWidget);

    await tester.tap(find.text('Default Video Quality'));
    await tester.pumpAndSettle();

    // Dialog is visible with all options
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('720p'), findsOneWidget);
    expect(find.text('480p'), findsOneWidget);
    expect(find.text('360p'), findsOneWidget);

    await tester.tap(find.text('720p'));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).defaultVideoQuality, '720p');
    expect(find.text('720p'), findsOneWidget);
  });

  testWidgets('Audio Format dialog opens and updates selected format', (
    tester,
  ) async {
    setTestViewport(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(buildSettingsScreen(container));
    await tester.pumpAndSettle();

    expect(find.text('Default Audio Format'), findsOneWidget);
    expect(find.text('MP3'), findsOneWidget);

    await tester.tap(find.text('Default Audio Format'));
    await tester.pumpAndSettle();

    // Dialog is visible
    expect(find.text('M4A'), findsOneWidget);
    expect(find.text('OPUS'), findsOneWidget);

    await tester.tap(find.text('M4A'));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).defaultAudioFormat, 'M4A');
    expect(find.text('M4A'), findsOneWidget);
  });

  testWidgets('Slider updates max concurrent downloads', (tester) async {
    setTestViewport(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(buildSettingsScreen(container));
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsOneWidget);
    final sliderFinder = find.byType(Slider);

    // Initially 3
    expect(container.read(settingsProvider).maxConcurrentDownloads, 3);

    // Slide to the right
    await tester.drag(sliderFinder, const Offset(100, 0));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).maxConcurrentDownloads, isNot(1));
  });

  testWidgets('Download over cellular switch toggles', (tester) async {
    setTestViewport(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(buildSettingsScreen(container));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).downloadOverCellular, isTrue);

    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Download over cellular'),
    );
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).downloadOverCellular, isFalse);
  });

  testWidgets(
    'Storage location tile triggers native folder picker and updates directory',
    (tester) async {
      setTestViewport(tester);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      fakeFilePicker.resultPath = '/custom/download/folder';

      await tester.pumpWidget(buildSettingsScreen(container));
      await tester.pumpAndSettle();

      expect(find.text('Storage Location'), findsOneWidget);
      expect(
        find.text('Default (${AppConstants.defaultDownloadDirectory})'),
        findsOneWidget,
      );

      // Verify folder open icon
      expect(find.byIcon(Icons.folder_open_rounded), findsOneWidget);

      // Tap Storage Location
      await tester.tap(find.text('Storage Location'));
      await tester.pumpAndSettle();

      expect(fakeFilePicker.getDirectoryPathCallCount, 1);
      expect(fakeFilePicker.lastDialogTitle, 'Select Download Folder');

      expect(
        container.read(settingsProvider).downloadDirectory,
        '/custom/download/folder',
      );
      expect(find.text('/custom/download/folder'), findsOneWidget);
      expect(
        find.text('Download folder updated: /custom/download/folder'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Storage location does not update when folder picker is cancelled',
    (tester) async {
      setTestViewport(tester);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      fakeFilePicker.resultPath = null; // User cancelled

      await tester.pumpWidget(buildSettingsScreen(container));
      await tester.pumpAndSettle();

      // Tap Storage Location
      await tester.tap(find.text('Storage Location'));
      await tester.pumpAndSettle();

      expect(fakeFilePicker.getDirectoryPathCallCount, 1);
      expect(container.read(settingsProvider).downloadDirectory, '');
      expect(
        find.text('Default (${AppConstants.defaultDownloadDirectory})'),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'Storage location reset button restores default download directory',
    (tester) async {
      setTestViewport(tester);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(settingsProvider.notifier)
          .setDownloadDirectory('/my/custom/path');

      await tester.pumpWidget(buildSettingsScreen(container));
      await tester.pumpAndSettle();

      expect(find.text('/my/custom/path'), findsOneWidget);

      // Tap reset button
      await tester.tap(find.byTooltip('Reset Default'));
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).downloadDirectory, '');
      expect(
        find.text('Default (${AppConstants.defaultDownloadDirectory})'),
        findsOneWidget,
      );
      expect(find.text('Download folder reset to default'), findsOneWidget);
    },
  );

  testWidgets('About section displays app version and interactive tiles', (
    tester,
  ) async {
    setTestViewport(tester);
    final container = ProviderContainer(
      overrides: [appVersionProvider.overrideWith((ref) => 'v1.0.0 (1)')],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(buildSettingsScreen(container));
    await tester.pumpAndSettle();

    expect(find.text('App version'), findsOneWidget);
    expect(find.text('v1.0.0 (1)'), findsOneWidget);

    // Tap GitHub tile (does not throw)
    expect(find.text('GitHub'), findsOneWidget);
    await tester.tap(find.text('GitHub'));
    await tester.pumpAndSettle();

    // Tap Licenses tile (opens LicensePage)
    expect(find.text('Licenses'), findsOneWidget);
    await tester.tap(find.text('Licenses'));
    await tester.pumpAndSettle();

    // Verify LicensePage opened
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text(AppConstants.appName), findsWidgets);
  });
}
