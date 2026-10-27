import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/theme/hero_wave_palette.dart';
import 'package:mediagrab/core/widgets/hero_background.dart';

void main() {
  test('repaints only when visible palette values change', () {
    const painter = HeroWavePainter();
    expect(painter.shouldRepaint(const HeroWavePainter()), isFalse);
    expect(
      painter.shouldRepaint(
        HeroWavePainter(
          palette: HeroWavePalette.reference.copyWith(base: Colors.black),
        ),
      ),
      isTrue,
    );
    expect(
      painter.shouldRepaint(
        HeroWavePainter(palette: HeroWavePalette.reference.copyWith()),
      ),
      isFalse,
    );
  });
  testWidgets('decoration preserves foreground hit testing', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HeroBackground(
            child: SizedBox(
              width: 320,
              height: 220,
              child: TextButton(
                onPressed: () => tapped = true,
                child: const Text('Foreground action'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Foreground action'));
    expect(tapped, isTrue);
  });
  testWidgets('normalized curves render at wide, compact and portrait sizes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final size in [
        const Size(1280, 719),
        const Size(320, 240),
        const Size(412, 420),
        const Size(360, 800),
        Size.zero,
      ]) {
        final recorder = ui.PictureRecorder();
        const HeroWavePainter().paint(Canvas(recorder), size);
        final picture = recorder.endRecording();
        if (!size.isEmpty) {
          final image = await picture.toImage(
            size.width.toInt(),
            size.height.toInt(),
          );
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          expect(bytes, isNotNull);
          final data = bytes!.buffer.asUint8List();
          expect(data[3], 255);
          expect(data[0] + data[1] + data[2], lessThan(90));
          if (Platform.environment['MEDIAGRAB_CAPTURE_HERO'] == '1') {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final dir = await Directory(
              '/tmp/mediagrab-hero',
            ).create(recursive: true);
            await File(
              '${dir.path}/${size.width.toInt()}x${size.height.toInt()}.png',
            ).writeAsBytes(png!.buffer.asUint8List());
          }
          image.dispose();
        }
        picture.dispose();
      }
    });
  });
}
