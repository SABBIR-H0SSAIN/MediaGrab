import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/shared/widgets/completed_media_tile.dart';

void main() {
  testWidgets(
    'saved media fits narrow screens with large text and tap-to-open without play controls',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var plays = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: CompletedMediaTile(
                  title:
                      'A long downloaded video title that should wrap neatly across lines',
                  isAudio: false,
                  platform: 'Facebook',
                  format: '2160p • WEBM',
                  size: '125.8 MB',
                  duration: '1:07:38',
                  onPlay: () => plays++,
                  onMenu: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.more_vert_rounded),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('1:07:38'), findsOneWidget);
      expect(find.byTooltip('Play'), findsNothing);
      await tester.tap(find.textContaining('A long downloaded'));
      expect(plays, 1);
    },
  );
}
