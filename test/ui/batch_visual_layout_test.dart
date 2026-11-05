import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediagrab/core/theme/app_theme.dart';
import 'package:mediagrab/features/extractor/data/extractor_factory.dart';
import 'package:mediagrab/features/downloads/presentation/providers/download_manager_provider.dart';
import 'package:mediagrab/features/extractor/presentation/providers/extractor_provider.dart';
import 'package:mediagrab/features/extractor/presentation/providers/batch_preparation_provider.dart';
import 'package:mediagrab/features/extractor/presentation/screens/batch_download_screen.dart';
import '../features/extractor/batch_test_support.dart';

void main() {
  // Optional real-font renders for visual review; ordinary tests keep Flutter's test font.
  setUpAll(() async {
    final directory = Platform.environment['UI_FONT_DIR'];
    if (directory == null) return;
    for (final entry
        in {
          'Roboto': 'Roboto-Regular.ttf',
          'MaterialIcons': 'MaterialIcons-Regular.otf',
        }.entries) {
      await (FontLoader(entry.key)..addFont(
        File(
          '$directory/${entry.value}',
        ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      )).load();
    }
  });
  for (final width in [320.0, 360.0, 393.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('compact batch layout fits ${width}dp at text scale $scale', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final container = ProviderContainer(
          overrides: [
            connectivityProvider.overrideWithValue(null),
            extractorFactoryProvider.overrideWithValue(
              ExtractorFactory(extractors: [BatchTestExtractor()]),
            ),
          ],
        );
        addTearDown(container.dispose);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.dark(),
                builder:
                    (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                home: const BatchDownloadScreen(),
              ),
            ),
          ),
        );
        final controller = container.read(batchPreparationProvider.notifier);
        controller.paste(
          'https://youtu.be/video000000 https://youtu.be/video111111',
        );
        await controller.check();
        await tester.pumpAndSettle();
        if (scale == 1.0) {
          final label = tester.getRect(find.text('Auto Add'));
          final toggle = tester.getRect(
            find.byKey(const ValueKey('batch_auto_add')),
          );
          expect((label.center.dy - toggle.center.dy).abs(), lessThan(1));
          expect(label.right, lessThanOrEqualTo(toggle.left));
          expect(tester.getRect(find.byType(TextField)).top, lessThan(150));
        }
        expect(find.byType(FilterChip), findsNothing);
        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('Download 2 videos'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('batch_item_0')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final output = Platform.environment['BATCH_PREVIEW'];
        if (output != null && scale == 1.0) {
          tester
              .widget<CustomScrollView>(find.byType(CustomScrollView))
              .controller!
              .jumpTo(0);
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              output.replaceFirst('.png', '-${width.toInt()}.png'),
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pump(const Duration(milliseconds: 300));
      });
    }
  }
}
