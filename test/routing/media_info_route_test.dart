import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/presentation/providers/extractor_provider.dart';
import 'package:mediagrab/features/extractor/presentation/screens/media_info_screen.dart';
import 'package:mediagrab/routing/app_router.dart';

Widget routerConfigApp(GoRouter router) {
  return MaterialApp.router(routerConfig: router);
}

void main() {
  const targetUrl = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';

  const mockMedia = MediaInfo(
    id: 'dQw4w9WgXcQ',
    title: 'Never Gonna Give You Up',
    thumbnailUrl: 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
    duration: Duration(minutes: 3, seconds: 32),
    uploader: 'Rick Astley',
    platform: PlatformType.youtube,
  );

  testWidgets('GoRouter navigates to /media-info with url query parameter', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        mediaInfoProvider(
          targetUrl,
        ).overrideWith((ref) => Future.value(mockMedia)),
        streamsProvider(
          targetUrl,
        ).overrideWith((ref) => Future.value([])),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routerConfigApp(router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Navigate to /media-info
    router.push('/media-info?url=${Uri.encodeComponent(targetUrl)}');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(MediaInfoScreen), findsOneWidget);
    expect(find.text('Never Gonna Give You Up'), findsOneWidget);
  });
}
