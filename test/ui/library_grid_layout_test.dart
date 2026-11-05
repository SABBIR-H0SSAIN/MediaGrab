import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediagrab/core/utils/file_utils.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/library/presentation/providers/library_provider.dart';
import 'package:mediagrab/features/library/presentation/screens/library_screen.dart';

void main() {
  for (final scale in [1.0, 1.8]) {
    testWidgets('library grid fits 320px screen at text scale $scale', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'library_view_mode': 'grid'});
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryProvider.overrideWith(
              (ref) => LibraryNotifier([
                LibraryMediaItem(
                  id: 'saved',
                  title:
                      'A very long video title spanning several words and languages',
                  filePath: '/video.mp4',
                  fileSize: 12000000,
                  fileType: FileType.video,
                  downloadedAt: DateTime.now(),
                  platform: PlatformType.facebook,
                  qualityLabel: '2160p',
                  duration: const Duration(hours: 1, minutes: 12),
                ),
              ]),
            ),
          ],
          child: MaterialApp(
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
            home: const LibraryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byTooltip('Action menu'), findsOneWidget);
      expect(find.byTooltip('Play'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
