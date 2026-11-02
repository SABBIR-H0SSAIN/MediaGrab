import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/file_utils.dart';

/// Service managing persistent Android foreground notifications for active downloads.
///
/// Starts a real dataSync foreground service while work is user-perceptible.
/// Android start restrictions, service time limits, force-stop and OEM battery
/// policy still apply; notifications do not guarantee process survival.
class DownloadNotificationService {
  DownloadNotificationService._();
  static final DownloadNotificationService instance =
      DownloadNotificationService._();

  FlutterLocalNotificationsPlugin? _plugin;
  bool _initialized = false;
  final Map<String, String> _activeTasks = {};
  final Map<String, DateTime> _lastProgress = {};
  Future<void> _foregroundQueue = Future.value();
  static const int _foregroundId = 100001;

  // Android requires a real foreground service; an ongoing notification alone
  // does not promote the process. Serialize starts/stops across concurrent tasks.
  Future<void> _syncForeground() {
    _foregroundQueue = _foregroundQueue.catchError((Object _) {}).then((
      _,
    ) async {
      if (!Platform.isAndroid) return;
      final android =
          _plugin
              ?.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
      if (_activeTasks.isEmpty) {
        await android?.stopForegroundService();
      } else {
        await android?.startForegroundService(
          _foregroundId,
          'MediaGrab downloads',
          '${_activeTasks.length} active • ${_activeTasks.values.first}',
          startType: AndroidServiceStartType.startNotSticky,
          foregroundServiceTypes: {
            AndroidServiceForegroundType.foregroundServiceTypeDataSync,
          },
          notificationDetails: const AndroidNotificationDetails(
            channelId,
            channelName,
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            onlyAlertOnce: true,
            playSound: false,
          ),
        );
      }
    });
    return _foregroundQueue;
  }

  Future<void> _removeActiveTask(String taskId) async {
    _activeTasks.remove(taskId);
    _lastProgress.remove(taskId);
    await _syncForeground();
  }

  static const String channelId = 'mediagrab_downloads';
  static const String channelName = 'MediaGrab Downloads';
  static const String channelDescription =
      'Real-time progress notifications for active media downloads';

  /// Initializes the local notifications plugin and notification channel.
  Future<void> init({
    FlutterLocalNotificationsPlugin? plugin,
    bool requestPermission = true,
  }) async {
    if (_initialized && plugin == null) return;
    _plugin = plugin ?? FlutterLocalNotificationsPlugin();

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        const androidInit = AndroidInitializationSettings(
          '@drawable/ic_notification',
        );
        const iosInit = DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );
        const initSettings = InitializationSettings(
          android: androidInit,
          iOS: iosInit,
        );

        await _plugin?.initialize(initSettings);

        if (Platform.isAndroid) {
          final androidPlugin =
              _plugin
                  ?.resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin
                  >();
          if (requestPermission) {
            await androidPlugin?.requestNotificationsPermission();
          }
          await androidPlugin?.createNotificationChannel(
            const AndroidNotificationChannel(
              channelId,
              channelName,
              description: channelDescription,
              importance: Importance.low,
              playSound: false,
              enableVibration: false,
              showBadge: false,
            ),
          );
        }
        _initialized = true;
      } catch (e) {
        debugPrint('DownloadNotificationService init error: $e');
      }
    } else {
      _initialized = true;
    }
  }

  /// Ask only after the startup reveal has yielded to the interactive app.
  Future<void> requestPermission() async {
    if (kIsWeb || !Platform.isAndroid || _plugin == null) return;
    try {
      await _plugin
          ?.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (error) {
      debugPrint('Notification permission request failed: $error');
    }
  }

  int _notificationId(String taskId) {
    return taskId.hashCode.abs() % 100000;
  }

  /// Displays or updates an ongoing notification with progress and speed.
  Future<void> showProgress({
    required String taskId,
    required String title,
    required double progress,
    required double speedBytesPerSecond,
  }) async {
    if (!_initialized || _plugin == null) return;
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    try {
      _activeTasks[taskId] = title;
      final now = DateTime.now();
      final last = _lastProgress[taskId];
      if (last != null && now.difference(last) < const Duration(seconds: 1)) {
        return;
      }
      _lastProgress[taskId] = now;
      await _syncForeground();
      if (!_activeTasks.containsKey(taskId)) return;
      final notifId = _notificationId(taskId);
      final percent = (progress * 100).clamp(0, 100).toInt();
      final speedText =
          speedBytesPerSecond > 0
              ? '${formatFileSize(speedBytesPerSecond.toInt())}/s'
              : '';
      final body =
          speedText.isNotEmpty ? '$percent% • $speedText' : '$percent%';

      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.low,
        priority: Priority.low,
        showProgress: true,
        maxProgress: 100,
        progress: percent,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
        category: AndroidNotificationCategory.progress,
      );

      final notifDetails = NotificationDetails(android: androidDetails);
      await _plugin?.show(notifId, title, body, notifDetails);
    } catch (e) {
      debugPrint('Error updating download notification: $e');
    }
  }

  /// Shows a completed download notification and clears ongoing status.
  Future<void> showCompleted({
    required String taskId,
    required String title,
  }) async {
    if (!_initialized || _plugin == null) return;
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    try {
      await _removeActiveTask(taskId);
      final notifId = _notificationId(taskId);
      final androidDetails = const AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        autoCancel: true,
        ongoing: false,
      );

      final notifDetails = NotificationDetails(android: androidDetails);
      await _plugin?.show(notifId, 'Download complete', title, notifDetails);
    } catch (e) {
      debugPrint('Error showing complete notification: $e');
    }
  }

  /// Shows a failed download notification.
  Future<void> showFailed({
    required String taskId,
    required String title,
    required String error,
  }) async {
    if (!_initialized || _plugin == null) return;
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    try {
      await _removeActiveTask(taskId);
      final notifId = _notificationId(taskId);
      final androidDetails = const AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        autoCancel: true,
        ongoing: false,
      );

      final notifDetails = NotificationDetails(android: androidDetails);
      await _plugin?.show(
        notifId,
        'Download failed',
        '$title • $error',
        notifDetails,
      );
    } catch (e) {
      debugPrint('Error showing failed notification: $e');
    }
  }

  /// Cancels any notification for [taskId].
  Future<void> cancel(String taskId) async {
    if (!_initialized || _plugin == null) return;
    try {
      await _removeActiveTask(taskId);
      await _plugin?.cancel(_notificationId(taskId));
    } catch (_) {}
  }

  /// Cancels all active notifications.
  Future<void> cancelAll() async {
    if (!_initialized || _plugin == null) return;
    try {
      _activeTasks.clear();
      _lastProgress.clear();
      await _syncForeground();
      await _plugin?.cancelAll();
    } catch (_) {}
  }
}
