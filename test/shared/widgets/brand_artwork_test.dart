import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/shared/widgets/brand_artwork.dart';

void main() {
  testWidgets('platform marks keep their proportions with enlarged text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Row(
              children: [
                PlatformLogo(platform: 'facebook', size: 48),
                PlatformLogo(platform: 'youtube', size: 48),
                PlatformLogo(platform: 'instagram', size: 48),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('f'), findsNothing);
    for (final element in find.byType(PlatformLogo).evaluate()) {
      expect(tester.getSize(find.byWidget(element.widget)), const Size(48, 48));
    }
    expect(tester.takeException(), isNull);
  });
}
