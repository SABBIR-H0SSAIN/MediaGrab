import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/home/presentation/widgets/quick_actions_row.dart';
import 'package:mediagrab/shared/widgets/media_link_field.dart';

void main() {
  testWidgets('playlist uses compact home field with Paste and Clear', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async =>
              call.method == 'Clipboard.getData'
                  ? {'text': 'https://youtube.com/playlist?list=PL_demo'}
                  : null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: QuickActionsRow())),
        ),
      ),
    );
    await tester.tap(find.text('Playlists'));
    await tester.pumpAndSettle();
    expect(find.byType(MediaLinkField), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.maxLines, 1);
    expect(field.decoration?.labelText, isNull);
    expect(
      tester.getSize(find.byType(TextField)).height,
      lessThanOrEqualTo(60),
    );
    await tester.tap(find.byTooltip('Paste from clipboard'));
    await tester.pumpAndSettle();
    expect(
      find.text('https://youtube.com/playlist?list=PL_demo'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(field.controller!.text, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
