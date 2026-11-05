import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediagrab/features/downloads/domain/entities/download_task.dart';
import 'package:mediagrab/features/downloads/domain/enums/download_status.dart';
import 'dart:io';
import 'package:mediagrab/features/extractor/domain/entities/media_info.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/extractor/data/extractor_factory.dart';
import 'package:mediagrab/features/extractor/presentation/providers/batch_preparation_provider.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';
import '../../batch_test_support.dart';

String url(int n) => 'https://youtube.com/watch?v=video$n';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BatchTestExtractor extractor;
  late BatchPreparationController controller;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    extractor = BatchTestExtractor();
    controller = BatchPreparationController(
      ExtractorFactory(extractors: [extractor]),
    );
  });
  tearDown(() async {
    await controller.flushDraft();
    controller.dispose();
  });

  test(
    'explicit flush saves the latest draft without waiting for debounce',
    () async {
      controller.edit(0, url(0));
      final earlier = controller.flushDraft();
      controller.edit(0, url(1));
      controller.setAutoAdd(false);
      controller.include(0, false);
      await Future.wait([earlier, controller.flushDraft()]);
      final restored = BatchPreparationController(
        ExtractorFactory(extractors: [extractor]),
      );
      addTearDown(restored.dispose);
      await restored.restore();
      expect(restored.state.items.single.url, url(1));
      expect(restored.state.items.single.included, isFalse);
      expect(restored.state.autoAdd, isFalse);
    },
  );

  test(
    'disposal flushes pending edits instead of discarding the debounce',
    () async {
      final draft = BatchPreparationController(
        ExtractorFactory(extractors: [extractor]),
      );
      draft.edit(0, url(2));
      draft.setAutoRemoveCompleted(false);
      draft.dispose();
      // Joining a flush after disposal waits for the already captured snapshot.
      await draft.flushDraft();
      final restored = BatchPreparationController(
        ExtractorFactory(extractors: [extractor]),
      );
      addTearDown(restored.dispose);
      await restored.restore();
      expect(restored.state.items.single.url, url(2));
      expect(restored.state.autoRemoveCompleted, isFalse);
    },
  );

  test(
    'auto-remove requires finalization and a nonempty file, keeps media and failures',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'batch-completion',
      );
      addTearDown(() => directory.delete(recursive: true));
      controller.edit(0, url(0));
      await controller.check();
      final item = controller.state.items.single;
      final file = File('${directory.path}/saved.mp4');
      await file.writeAsBytes([1, 2, 3, 4]);
      final task = DownloadTask(
        id: 'finished',
        mediaInfo: item.media!,
        selectedStream: batchVideo,
        status: DownloadStatus.downloading,
        progress: 1,
        filePath: file.path,
        createdAt: DateTime.now(),
      );
      controller.attachTask(item.id, task);
      controller.syncTasks([task], (_) async => false);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.items.single.taskId, task.id);
      final completed = task.copyWith(
        status: DownloadStatus.completed,
        completedAt: DateTime.now(),
      );
      controller.setAutoRemoveCompleted(false);
      controller.syncTasks([completed], (_) async => false);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.items.single.taskId, task.id);
      controller.setAutoRemoveCompleted(true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.state.items.where((i) => i.taskId != null), isEmpty);
      expect(await file.exists(), isTrue);
      expect(await file.length(), 4);

      controller.edit(controller.state.items.first.id, url(1));
      await controller.check();
      final next = controller.state.items.single;
      controller.attachTask(
        next.id,
        completed.copyWith(
          id: 'missing',
          filePath: '${directory.path}/missing.mp4',
        ),
      );
      controller.syncTasks([
        next.task ??
            completed.copyWith(
              id: 'missing',
              filePath: '${directory.path}/missing.mp4',
            ),
      ], (_) async => false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.state.items.single.taskId, 'missing');
    },
  );

  test(
    'commas deduplicate and clear never removes active or paused tasks',
    () async {
      controller.paste('${url(0)},https://youtu.be/video0,${url(1)}');
      await controller.check();
      expect(controller.state.selected, hasLength(2));
      final first = controller.state.items.first;
      final task = DownloadTask(
        id: 'paused',
        mediaInfo: first.media!,
        selectedStream: batchVideo,
        status: DownloadStatus.paused,
        createdAt: DateTime.now(),
      );
      controller.attachTask(first.id, task);
      controller.clearPreparation();
      expect(controller.state.items.single.taskId, 'paused');
      controller.edit(first.id, url(2));
      controller.choose(first.id, batchAdaptive, batchAudio);
      controller.remove(first.id);
      expect(controller.state.items.single.url, url(0));
      expect(controller.state.items.single.selected, batchVideo);
    },
  );

  test(
    'removing a linked task in Downloads leaves a recoverable interrupted entry',
    () async {
      controller.edit(0, url(0));
      await controller.check();
      final item = controller.state.items.single;
      controller.attachTask(
        item.id,
        DownloadTask(
          id: 'removed',
          mediaInfo: item.media!,
          selectedStream: batchVideo,
          status: DownloadStatus.downloading,
          createdAt: DateTime.now(),
        ),
      );
      controller.syncTasks([], (_) async => false);
      expect(controller.state.items.single.task, isNull);
      controller.resetInterrupted(item.id);
      await controller.check(onlyId: item.id);
      expect(controller.state.selected, hasLength(1));
      expect(controller.state.items.single.taskId, isNull);
    },
  );

  test('canonical IDs deduplicate social aliases and tracking parameters', () {
    expect(
      batchUrlKey('https://instagram.com/reel/ABC123/?igsh=abc'),
      batchUrlKey('https://www.instagram.com/p/ABC123/'),
    );
    expect(
      batchUrlKey('https://facebook.com/reel/123456789/'),
      batchUrlKey('https://www.facebook.com/watch/?v=123456789'),
    );
    expect(
      batchUrlKey('https://facebook.com/share/v/example/?fbclid=abc'),
      batchUrlKey('https://facebook.com/share/v/example/'),
    );
  });

  test(
    'restoration keeps inclusion, custom quality, and linked completed tasks ineligible',
    () async {
      controller.edit(0, url(0));
      await controller.check();
      controller.choose(0, batchVideo, null);
      controller.include(0, false);
      controller.setAutoAdd(false);
      final item = controller.state.items.single;
      final task = DownloadTask(
        id: 'completed',
        mediaInfo: item.media!,
        selectedStream: batchVideo,
        createdAt: DateTime.now(),
        status: DownloadStatus.completed,
      );
      controller.attachTask(0, task);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final restored = BatchPreparationController(
        ExtractorFactory(extractors: [extractor]),
      );
      addTearDown(restored.dispose);
      await restored.restore();
      await restored.check();
      restored.syncTasks([task], (_) async => false);
      expect(restored.state.autoAdd, isFalse);
      expect(restored.state.items.single.included, isFalse);
      expect(restored.state.items.single.overridden, isTrue);
      expect(restored.state.items.single.selected, batchVideo);
      expect(
        restored.state.items.single.task?.status,
        DownloadStatus.completed,
      );
      expect(restored.state.selected, isEmpty);
    },
  );

  test(
    'typing checks automatically and an edit during an in-flight request is checked next',
    () async {
      controller.edit(0, url(0));
      extractor.gates[url(0)] = Completer<void>();
      await Future<void>.delayed(const Duration(milliseconds: 550));
      expect(extractor.metadataCalls, [url(0)]);
      controller.edit(0, url(1));
      await Future<void>.delayed(const Duration(milliseconds: 550));
      extractor.gates[url(0)]!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(controller.state.items.single.media?.id, 'video1');
      expect(extractor.metadataCalls, [url(0), url(1)]);
    },
  );
  test(
    'temporary errors retry twice and stop without blocking another video',
    () async {
      final temporary = _TemporaryExtractor();
      final batch = BatchPreparationController(
        ExtractorFactory(extractors: [temporary]),
      );
      addTearDown(batch.dispose);
      batch.paste('${url(0)} ${url(1)}');
      await batch.check();
      expect(temporary.attempts, 3);
      expect(batch.state.items.first.status, BatchItemStatus.failed);
      expect(batch.state.items.last.status, BatchItemStatus.ready);
      expect(batch.state.items.first.error, contains('connection'));
    },
  );
  test(
    'permanent failures are not checked again when a new link is added',
    () async {
      extractor.failures.add(url(0));
      controller.edit(0, url(0));
      await controller.check();
      controller.add(url(1));
      await controller.check();
      expect(
        extractor.metadataCalls.where((value) => value == url(0)),
        hasLength(1),
      );
      expect(controller.state.items.last.status, BatchItemStatus.ready);
    },
  );

  test(
    'checks at most three items at once and publishes individual results',
    () async {
      controller.edit(0, url(0));
      for (var n = 0; n < 6; n++) {
        extractor.gates[url(n)] = Completer<void>();
        if (n > 0) controller.add(url(n));
      }
      final checking = controller.check();
      expect(extractor.metadataCalls.length, 3);
      expect(controller.state.checking, isTrue);
      extractor.gates[url(0)]!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.items.first.status, BatchItemStatus.ready);
      expect(extractor.metadataCalls.length, 4);
      for (var n = 1; n < 6; n++) {
        extractor.gates[url(n)]!.complete();
      }
      await checking;
      expect(extractor.maxActive, 3);
      expect(controller.state.selected.length, 6);
      expect(controller.state.checking, isFalse);
    },
  );
  test(
    'failures do not block valid links and retry only checks failed row',
    () async {
      controller.edit(0, url(0));
      controller.add(url(1));
      extractor.failures.add(url(1));
      await controller.check();
      expect(controller.state.selected.length, 1);
      expect(controller.state.items.last.error, contains('private'));
      extractor.failures.clear();
      await controller.check(onlyId: controller.state.items.last.id);
      expect(controller.state.selected.length, 2);
      expect(extractor.metadataCalls.where((u) => u == url(0)).length, 1);
    },
  );
  test(
    'paste deduplicates YouTube aliases and invalid rows stay inline',
    () async {
      controller.paste(
        '${url(0)} https://youtu.be/video0?si=abc\nnot-a-url ${url(1)}',
      );
      expect(controller.state.items.length, 3);
      await controller.check();
      expect(controller.state.selected.length, 2);
      expect(controller.state.items[1].error, contains('supported'));
    },
  );
  test('manual duplicates cannot duplicate an already ready row', () async {
    controller.add(url(0));
    await controller.check();
    controller.edit(0, url(0));
    await controller.check();
    expect(controller.state.selected.length, 1);
    expect(controller.state.items.first.error, contains('Duplicate'));
  });
  test('editing and removal ignore stale results', () async {
    controller.edit(0, url(0));
    controller.add(url(1));
    extractor.gates[url(0)] = Completer<void>();
    extractor.gates[url(1)] = Completer<void>();
    final checking = controller.check();
    controller.edit(0, url(2));
    controller.remove(controller.state.items.last.id);
    extractor.gates[url(0)]!.complete();
    extractor.gates[url(1)]!.complete();
    await checking;
    expect(controller.state.items.single.url, url(2));
    expect(controller.state.items.single.status, BatchItemStatus.draft);
    expect(extractor.streamCalls, isEmpty);
  });
  test('disposal ignores active extraction results', () async {
    final other = BatchPreparationController(
      ExtractorFactory(extractors: [extractor]),
    );
    other.edit(0, url(0));
    extractor.gates[url(0)] = Completer<void>();
    final checking = other.check();
    other.dispose();
    extractor.gates[url(0)]!.complete();
    await checking;
    expect(extractor.streamCalls, isEmpty);
  });
  test(
    'batch preference changes preserve individual override and companion audio',
    () async {
      controller.edit(0, url(0));
      controller.add(url(1));
      await controller.check();
      expect(controller.state.items.first.audio, batchAudio);
      controller.choose(0, batchVideo, null);
      controller.setQuality('480p');
      expect(controller.state.items.first.selected, batchVideo);
      expect(controller.state.items.first.overridden, isTrue);
      expect(controller.state.items.last.notice, contains('480p unavailable'));
      controller.setQuality('Audio');
      expect(controller.state.items.last.selected, batchAudio);
      expect(controller.state.items.first.selected, batchVideo);
    },
  );
  test(
    'cropped video with the requested quality label has no unavailable notice',
    () async {
      const cropped = StreamInfo(
        url: 'https://cdn.example/cropped',
        qualityLabel: '360p',
        codec: 'h264',
        container: 'mp4',
        videoWidth: 640,
        videoHeight: 268,
      );
      extractor.streams = [cropped];
      controller.setQuality('360p');
      controller.edit(0, url(0));
      await controller.check();
      final item = controller.state.items.single;
      expect(item.selected, cropped);
      expect(item.selected!.videoHeight, 268);
      expect(item.notice, isNull);
      controller.setQuality('720p');
      expect(
        controller.state.items.single.notice,
        '720p unavailable; using 360p.',
      );
    },
  );

  test(
    'progressive wins at equal resolution; adaptive without audio fails',
    () async {
      const progressive = StreamInfo(
        url: 'https://cdn.example/muxed',
        qualityLabel: '1080p',
        codec: 'h264',
        container: 'mp4',
        videoHeight: 1080,
      );
      extractor.streams = [batchAdaptive, progressive, batchAudio];
      controller.edit(0, url(0));
      await controller.check();
      expect(controller.state.items.single.selected, progressive);
      controller.edit(0, url(1));
      extractor.streams = [batchAdaptive];
      await controller.check();
      expect(controller.state.items.single.status, BatchItemStatus.failed);
    },
  );
}

class _TemporaryExtractor extends BatchTestExtractor {
  int attempts = 0;
  @override
  Future<MediaInfo> extractInfo(String source) async {
    if (source == url(0)) {
      attempts++;
      throw const SocketException('Network unavailable');
    }
    return super.extractInfo(source);
  }
}
