import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/settings/presentation/widgets/settings_section.dart';

void main() {
  testWidgets('SettingsSection renders title and children within Card', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SettingsSection(
            title: 'Test Section',
            children: [Text('Child item 1'), Text('Child item 2')],
          ),
        ),
      ),
    );

    expect(find.text('Test Section'), findsOneWidget);
    expect(find.text('Child item 1'), findsOneWidget);
    expect(find.text('Child item 2'), findsOneWidget);
    expect(find.byType(Card), findsOneWidget);
  });
}
