import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/downloads/data/services/download_engine.dart';
import 'package:mediagrab/features/downloads/data/services/download_session_store.dart';
import 'package:mediagrab/features/downloads/domain/entities/download_task.dart';
import 'package:mediagrab/features/downloads/domain/enums/download_status.dart';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import '../../../extractor/batch_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'restart restores byte counts and failed jobs; interrupted work resumes once',
    () async {
      final store = DownloadSessionStore();
      final task = DownloadTask(
        id: 'session-task',
        mediaInfo: const MediaInfo(
          id: 'video000000',
          title: 'Checkpoint',
          thumbnailUrl: '',
          duration: Duration(seconds: 40),
          uploader: 'Author',
          platform: PlatformType.youtube,
        ),
        selectedStream: batchAdaptive,
        status: DownloadStatus.downloading,
        progress: .4,
        downloadedBytes: 400,
        totalBytes: 1000,
        filePath: '/tmp/checkpoint.mp4',
        createdAt: DateTime(2026),
      );
      await store.save([
        {
          ...DownloadSessionStore.taskJson(task),
          'audio': DownloadSessionStore.streamJson(batchAudio),
        },
        DownloadSessionStore.taskJson(
          task.copyWith(
            id: 'failed',
            status: DownloadStatus.failed,
            errorMessage: 'Connection lost',
          ),
        ),
      ]);
      var runs = 0;
      final engine = DownloadEngine(
        sessionStore: store,
        customDownloadExecution: ({
          required task,
          required stream,
          required targetPath,
          required onProgress,
          required onComplete,
          required onError,
        }) async {
          runs++;
        },
      );
      addTearDown(engine.dispose);
      await engine.restoreSession();
      expect(engine.getTask(task.id)!.status, DownloadStatus.paused);
      expect(engine.getTask(task.id)!.downloadedBytes, 400);
      expect(engine.getTask('failed')!.errorMessage, 'Connection lost');
      expect(runs, 0);
      expect(await engine.resumeDownload(task.id), isTrue);
      expect(await engine.resumeDownload(task.id), isFalse);
      expect(await engine.retryDownload(task.id), isFalse);
      expect(runs, 1);
      await engine.checkpointSession();
      final saved = (await store.load()).firstWhere((e) => e['id'] == task.id);
      expect(
        DownloadSessionStore.readStream(saved['audio']).url,
        batchAudio.url,
      );
    },
  );
}
