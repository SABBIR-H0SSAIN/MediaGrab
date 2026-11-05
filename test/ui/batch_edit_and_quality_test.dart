import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediagrab/features/extractor/data/extractor_factory.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';
import 'package:mediagrab/features/extractor/presentation/providers/extractor_provider.dart';
import 'package:mediagrab/features/extractor/presentation/providers/batch_preparation_provider.dart';
import 'package:mediagrab/features/extractor/presentation/screens/batch_download_screen.dart';
import 'package:mediagrab/features/extractor/presentation/widgets/quality_selector_sheet.dart';
import '../features/extractor/batch_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'bottom item edits stay local; cancel and duplicate validation preserve the draft',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final container = ProviderContainer(
        overrides: [
          extractorFactoryProvider.overrideWithValue(
            ExtractorFactory(extractors: [BatchTestExtractor()]),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: BatchDownloadScreen()),
        ),
      );
      final controller = container.read(batchPreparationProvider.notifier);
      controller.paste(
        List.generate(
          8,
          (i) =>
              'https://youtube.com/watch?v=video${i.toString().padLeft(6, '0')}',
        ).join(' '),
      );
      await controller.check();
      await tester.pumpAndSettle();
      final addInput =
          tester.widget<TextField>(find.byType(TextField)).controller!;
      addInput.text = 'unfinished add draft';
      final target = controller.state.items.last;
      final edit = find.descendant(
        of: find.byKey(ValueKey('batch_item_${target.id}')),
        matching: find.byTooltip('Edit link'),
      );
      await tester.scrollUntilVisible(
        edit,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final scroll =
          tester
              .widget<CustomScrollView>(find.byType(CustomScrollView))
              .controller!;
      final offset = scroll.offset;
      expect(offset, greaterThan(0));
      await tester.tap(edit);
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('batch_edit_url'));
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.widgetWithText(FilledButton, 'Save')).bottom,
        lessThanOrEqualTo(520),
      );

      await tester.enterText(field, 'https://youtu.be/video999999');
      await tester.pump(const Duration(milliseconds: 700));
      expect(controller.state.items.last.url, target.url);
      expect(addInput.text, 'unfinished add draft');
      await tester.tap(find.text('Cancel'));
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(offset, 1));
      expect(controller.state.items.last.url, target.url);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(field, 'https://youtu.be/video000000');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('This video is already in the batch.'), findsOneWidget);
      expect(find.text('Edit video link'), findsOneWidget);
      await tester.enterText(field, 'https://youtu.be/video999999');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(controller.state.items.last.url, 'https://youtu.be/video999999');
      expect(
        controller.state.items.first.url,
        'https://youtube.com/watch?v=video000000',
      );
      expect(addInput.text, 'unfinished add draft');
      expect(scroll.offset, closeTo(offset, 1));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 300));
    },
  );

  for (final scale in [1.0, 1.6]) {
    testWidgets(
      'quality sheets scroll and select safely at 320dp / text scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final longLabel =
            '1080p ${List.filled(12, 'original quality').join(' ')}';
        final extractor =
            BatchTestExtractor()
              ..streams = [
                StreamInfo(
                  url: 'https://cdn.example/1080',
                  qualityLabel: longLabel,
                  codec: 'h264',
                  container: 'mp4',
                  videoHeight: 1080,
                ),
                batchVideo,
                batchAudio,
              ];
        final container = ProviderContainer(
          overrides: [
            extractorFactoryProvider.overrideWithValue(
              ExtractorFactory(extractors: [extractor]),
            ),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
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
        );
        final controller = container.read(batchPreparationProvider.notifier);
        controller.paste('https://youtube.com/watch?v=video000000');
        await controller.check();
        await tester.pumpAndSettle();
        final quality = find.descendant(
          of: find.byKey(const ValueKey('batch_item_0')),
          matching: find.byKey(const ValueKey('batch_item_quality_0')),
        );
        await tester.scrollUntilVisible(
          quality,
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(quality);
        await tester.pumpAndSettle();
        expect(find.byType(QualitySelectorSheet), findsOneWidget);
        expect(find.text('Choose quality'), findsOneWidget);
        expect(tester.getRect(find.byType(BottomSheet)).height, lessThan(600));
        await tester.scrollUntilVisible(
          find.text('720p'),
          100,
          scrollable: find.descendant(
            of:
                find
                    .descendant(
                      of: find.byType(BottomSheet),
                      matching: find.byType(ListView),
                    )
                    .first,
            matching: find.byType(Scrollable),
          ),
        );
        await tester.tap(find.text('720p'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use quality'));
        await tester.pumpAndSettle();
        expect(controller.state.items.single.selected, batchVideo);
        expect(controller.state.items.single.overridden, isTrue);
        final defaultQuality = find.byTooltip('Default quality');
        await tester.ensureVisible(defaultQuality);
        await tester.pumpAndSettle();
        await tester.tap(defaultQuality);
        await tester.pumpAndSettle();
        expect(find.text('Default quality'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Audio'),
          150,
          scrollable: find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.tap(find.text('Audio'));
        await tester.pumpAndSettle();
        expect(controller.state.quality, 'Audio');
        expect(controller.state.items.single.selected, batchVideo);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(milliseconds: 300));
      },
    );
  }
}
