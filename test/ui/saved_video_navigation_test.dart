import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediagrab/core/utils/file_utils.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/downloads/data/services/download_engine.dart';
import 'package:mediagrab/features/downloads/domain/entities/download_task.dart';
import 'package:mediagrab/features/downloads/domain/enums/download_status.dart';
import 'package:mediagrab/features/downloads/presentation/providers/download_manager_provider.dart';
import 'package:mediagrab/features/downloads/presentation/screens/downloads_screen.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';
import 'package:mediagrab/features/library/presentation/providers/library_provider.dart';
import 'package:mediagrab/features/library/presentation/screens/library_screen.dart';

void main() {
  for (final library in [false, true]) {
    for (final platform in [
      PlatformType.youtube,
      PlatformType.facebook,
      PlatformType.instagram,
    ]) {
      for (final playButton in [false]) {
        testWidgets(
          '${library ? 'Library' : 'Completed'} ${platform.name} ${playButton ? 'Play' : 'card tap'} opens in app',
          (tester) async {
            SharedPreferences.setMockInitialValues({
              'library_view_mode': 'list',
            });
            const title = 'Saved video';
            // Metadata identifies video even if an old saved path has no extension.
            const path = '/downloads/saved video';
            final task = DownloadTask(
              id: 'saved',
              mediaInfo: MediaInfo(
                id: 'saved',
                title: title,
                thumbnailUrl: '',
                duration: const Duration(minutes: 2),
                uploader: 'Creator',
                platform: platform,
              ),
              selectedStream: const StreamInfo(
                url: 'https://example.com/video',
                qualityLabel: '720p',
                codec: 'h264',
                container: 'mp4',
              ),
              status: DownloadStatus.completed,
              filePath: path,
              createdAt: DateTime.now(),
            );
            final engine = DownloadEngine(
              customDownloadExecution:
                  ({
                    required task,
                    required stream,
                    required targetPath,
                    required onProgress,
                    required onComplete,
                    required onError,
                  }) async {},
            );
            addTearDown(engine.dispose);
            Uri? opened;
            final router = GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder:
                      (_, _) =>
                          library
                              ? const LibraryScreen()
                              : const DownloadsScreen(initialTab: 'completed'),
                ),
                GoRoute(
                  path: '/player',
                  builder: (_, state) {
                    opened = state.uri;
                    return const Scaffold(body: Text('In-app player'));
                  },
                ),
              ],
            );
            addTearDown(router.dispose);
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  downloadEngineProvider.overrideWithValue(engine),
                  downloadManagerProvider.overrideWith(
                    (ref) => DownloadManagerNotifier(engine, [task]),
                  ),
                  libraryProvider.overrideWith(
                    (ref) => LibraryNotifier([
                      LibraryMediaItem(
                        id: 'saved',
                        title: title,
                        filePath: path,
                        fileSize: 1024,
                        fileType: FileType.video,
                        platform: platform,
                        downloadedAt: DateTime.now(),
                      ),
                    ]),
                  ),
                ],
                child: MaterialApp.router(routerConfig: router),
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(
              playButton ? find.byTooltip('Play') : find.text(title),
            );
            await tester.pumpAndSettle();
            expect(find.text('In-app player'), findsOneWidget);
            expect(opened?.queryParameters['filePath'], path);
            expect(opened?.queryParameters['title'], title);
          },
        );
      }
    }
  }
}
