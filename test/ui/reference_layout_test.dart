import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediagrab/app.dart';
import 'package:mediagrab/features/downloads/data/services/download_engine.dart';
import 'package:mediagrab/features/downloads/presentation/providers/download_manager_provider.dart';
import 'package:mediagrab/features/library/presentation/providers/library_provider.dart';
import 'package:mediagrab/features/settings/presentation/providers/settings_provider.dart';

void main() {
  testWidgets('reference screens fit a phone viewport and preserve navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 884);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(top: 40, bottom: 16);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      SettingsNotifier.keyThemeMode: 'dark',
      SettingsNotifier.keyDynamicColors: false,
    });
    final prefs = await SharedPreferences.getInstance();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    if (Platform.environment['MEDIAGRAB_CAPTURE_UI'] == '1') {
      await tester.runAsync(() async {
        final loader = FontLoader('Roboto');
        for (final name in ['Regular', 'Bold']) {
          loader.addFont(
            Future.value(
              ByteData.sublistView(
                await File(
                  '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts/Roboto-$name.ttf',
                ).readAsBytes(),
              ),
            ),
          );
        }
        await loader.load();
        for (final entry
            in {
              'Ahem': 'Roboto-Regular.ttf',
              'MaterialIcons': 'MaterialIcons-Regular.otf',
            }.entries) {
          final font = FontLoader(entry.key)..addFont(
            Future.value(
              ByteData.sublistView(
                await File(
                  '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts/${entry.value}',
                ).readAsBytes(),
              ),
            ),
          );
          await font.load();
        }
      });
    }
    final engine = DownloadEngine(
      customDownloadExecution:
          ({
            required task,
            required stream,
            required targetPath,
            required onProgress,
            required onComplete,
            required onError,
          }) async {},
    );
    addTearDown(engine.dispose);
    final capture = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            downloadEngineProvider.overrideWithValue(engine),
            connectivityProvider.overrideWithValue(null),
            libraryProvider.overrideWith((ref) => LibraryNotifier([])),
          ],
          child: const MediaGrabApp(),
        ),
      ),
    );
    if (Platform.environment['MEDIAGRAB_CAPTURE_UI'] == '1') {
      // Asset decoding needs real async time before capturing the first frame.
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/icon/app_logo.png'),
          tester.element(find.byType(MediaGrabApp)),
        ),
      );
    }
    for (final tab in ['Home', 'Downloads', 'Library', 'Settings']) {
      if (tab != 'Home') await tester.tap(find.text(tab).last);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: '$tab must fit without layout errors',
      );
      if (Platform.environment['MEDIAGRAB_CAPTURE_UI'] == '1') {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = await Directory(
            '/tmp/mediagrab-reference',
          ).create(recursive: true);
          await File(
            '${dir.path}/${tab.toLowerCase()}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
}
