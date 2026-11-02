import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/services/download_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DownloadNotificationService', () {
    test('instance returns singleton', () {
      final s1 = DownloadNotificationService.instance;
      final s2 = DownloadNotificationService.instance;
      expect(s1, same(s2));
    });

    test('init and showProgress handle non-mobile or test platform without crashing', () async {
      final service = DownloadNotificationService.instance;
      await service.init();

      // Calling methods on host test platform should complete gracefully without throwing
      await service.showProgress(
        taskId: 'test_task_1',
        title: 'Test Video',
        progress: 0.5,
        speedBytesPerSecond: 1048576,
      );

      await service.showCompleted(
        taskId: 'test_task_1',
        title: 'Test Video',
      );

      await service.showFailed(
        taskId: 'test_task_1',
        title: 'Test Video',
        error: 'Network failure',
      );

      await service.cancel('test_task_1');
      await service.cancelAll();
    });
  });
}
