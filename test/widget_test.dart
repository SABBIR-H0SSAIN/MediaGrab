import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/app.dart';

void main() {
  testWidgets('MediaGrabApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MediaGrabApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('MediaGrab'), findsWidgets);
  });
}
