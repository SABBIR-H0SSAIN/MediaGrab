import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Utilities for managing runtime Android storage permissions and validating directory writability.
class PermissionUtils {
  PermissionUtils._();

  /// Checks and requests storage permissions on Android.
  ///
  /// On Android 11+ (API 30+), requests [Permission.manageExternalStorage].
  /// On Android 10 and below, requests [Permission.storage].
  static Future<bool> checkAndRequestStoragePermission([BuildContext? context]) async {
    if (kIsWeb || !Platform.isAndroid) return true;

    try {
      // Android 11+ (API 30+) requires manageExternalStorage for user-selected folders
      final manageStatus = await Permission.manageExternalStorage.status;
      if (manageStatus.isGranted) return true;

      final requestResult = await Permission.manageExternalStorage.request();
      if (requestResult.isGranted) return true;

      // Fallback for Android 10 and below
      final storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) return true;

      // Media specific permissions for Android 13+ (API 33+)
      final videoStatus = await Permission.videos.request();
      final audioStatus = await Permission.audio.request();
      return videoStatus.isGranted || audioStatus.isGranted;
    } catch (e) {
      debugPrint('Permission request error: $e');
      return false;
    }
  }

  /// Tests whether a given directory path is physically writable by the application.
  static Future<bool> isFolderWritable(String dirPath) async {
    final trimmed = dirPath.trim();
    if (trimmed.isEmpty) return false;

    try {
      final dir = Directory(trimmed);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final normalized = trimmed.endsWith(Platform.pathSeparator)
          ? trimmed.substring(0, trimmed.length - 1)
          : trimmed;
      final testFile = File(
        '$normalized${Platform.pathSeparator}.mediagrab_write_test_${DateTime.now().microsecondsSinceEpoch}',
      );
      await testFile.writeAsString('test', flush: true);
      try {
        if (await testFile.exists()) {
          await testFile.delete();
        }
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  }
}
