import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediagrab/features/extractor/data/extractor_factory.dart';
import 'package:mediagrab/features/extractor/presentation/providers/extractor_provider.dart';
import 'package:mediagrab/features/extractor/presentation/providers/batch_preparation_provider.dart';
import 'package:mediagrab/features/extractor/presentation/screens/batch_download_screen.dart';
import '../features/extractor/batch_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'one field accepts multiline paste, skips canonical duplicates and supports auto-add toggle',
    (tester) async {
      var clipboard =
          'https://youtu.be/video000000\thttps://youtube.com/shorts/video000000\nhttps://youtu.be/video111111';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async =>
                call.method == 'Clipboard.getData' ? {'text': clipboard} : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
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
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Add Link'), findsNothing);
      expect(find.text('Paste Multiple'), findsNothing);
      await tester.tap(find.byTooltip('Paste from clipboard'));
      await tester.pumpAndSettle();
      expect(container.read(batchPreparationProvider).selected, hasLength(2));
      expect(find.textContaining('2 videos added to batch.'), findsOneWidget);
      expect(find.text('Added 2 videos'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.textContaining('1 duplicate link skipped.'), findsOneWidget);
      expect(find.byType(FilterChip), findsNothing);
      expect(find.byIcon(Icons.more_horiz), findsNothing);
      await tester.tap(find.byTooltip('Batch download help'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(
        container.read(batchPreparationProvider).autoRemoveCompleted,
        isFalse,
      );
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.more_vert), findsNothing);
      await tester.scrollUntilVisible(
        find.descendant(
          of: find.byKey(const ValueKey('batch_item_0')),
          matching: find.byTooltip('Edit link'),
        ),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byTooltip('Edit link'), findsWidgets);
      expect(find.byTooltip('Delete video'), findsWidgets);
      await tester.ensureVisible(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      clipboard = 'https://youtu.be/video222222';
      await Scrollable.ensureVisible(
        tester.element(find.byType(TextField)),
        alignment: .3,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Paste from clipboard'));
      await tester.pumpAndSettle();
      expect(container.read(batchPreparationProvider).selected, hasLength(2));
      expect(find.text(clipboard), findsOneWidget);
      await tester.tap(find.byType(TextField));
      await tester.showKeyboard(find.byType(TextField));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(container.read(batchPreparationProvider).selected, hasLength(3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'incomplete input stays editable and completed comma-separated links are added',
    (tester) async {
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
      await tester.enterText(
        find.byType(TextField),
        'https://youtube.com/watch?v=video000',
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(container.read(batchPreparationProvider).selected, isEmpty);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        endsWith('video000'),
      );
      await tester.enterText(
        find.byType(TextField),
        'https://youtu.be/video000000,https://youtube.com/shorts/video000000?si=test,https://youtu.be/video111111',
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(container.read(batchPreparationProvider).selected, hasLength(2));
      expect(find.textContaining('1 duplicate link skipped.'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 300));
    },
  );

  testWidgets(
    'editing uses a local dialog with explicit save and preserves the add field',
    (tester) async {
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
      controller.paste('https://youtu.be/video000000');
      await controller.check();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('Edit link'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit link'));
      await tester.pumpAndSettle();
      expect(find.text('Edit video link'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('batch_edit_url')),
        'https://youtu.be/video111111',
      );
      await tester.pump(const Duration(milliseconds: 650));
      expect(
        controller.state.selected.single.url,
        'https://youtu.be/video000000',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        controller.state.selected.single.url,
        'https://youtu.be/video111111',
      );
      await tester.ensureVisible(find.byTooltip('Delete video'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete video'));
      await tester.pumpAndSettle();
      expect(controller.state.selected, isEmpty);
      expect(find.text('Your videos will appear here'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
