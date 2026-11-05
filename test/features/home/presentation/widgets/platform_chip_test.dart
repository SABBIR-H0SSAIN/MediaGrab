import 'package:flutter/material.dart';
import 'package:mediagrab/shared/widgets/brand_artwork.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/home/presentation/widgets/platform_chip.dart';

void main() {
  group('PlatformChip', () {
    testWidgets('renders YouTube chip with label and icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PlatformChip(platform: PlatformType.youtube)),
        ),
      );

      expect(find.text('YouTube'), findsOneWidget);
      expect(find.byType(PlatformLogo), findsOneWidget);
    });

    testWidgets('renders Facebook chip with label and icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PlatformChip(platform: PlatformType.facebook)),
        ),
      );

      expect(find.text('Facebook'), findsOneWidget);
      expect(find.byIcon(Icons.facebook), findsOneWidget);
    });

    testWidgets('renders Instagram chip with label and icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PlatformChip(platform: PlatformType.instagram)),
        ),
      );

      expect(find.text('Instagram'), findsOneWidget);
      expect(find.byType(PlatformLogo), findsOneWidget);
    });

    testWidgets('renders nothing for unknown platform', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PlatformChip(platform: PlatformType.unknown)),
        ),
      );

      expect(find.byType(Container), findsNothing);
      expect(find.text('Unknown'), findsNothing);
    });
  });
}
