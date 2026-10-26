import 'dart:io';
import 'dart:math' as math;
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../constants/app_constants.dart';

/// Represents categories of media files supported by MediaGrab.
enum FileType {
  video,
  audio,
  image,
  other;

  String get displayName {
    switch (this) {
      case FileType.video:
        return 'Videos';
      case FileType.audio:
        return 'Audio';
      case FileType.image:
        return 'Images';
      case FileType.other:
        return 'Other';
    }
  }
}

/// Formats a byte count into a human-readable string.
///
/// Examples:
/// - `0` -> "0 B"
/// - `1536` -> "1.5 KB"
/// - `367001600` -> "350 MB"
/// - `1288490188` -> "1.2 GB"
String formatFileSize(int bytes) {
  if (bytes <= 0) return '0 B';

  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  final digitGroups = (math.log(bytes) / math.log(1024)).floor();
  final clampedIndex = digitGroups.clamp(0, units.length - 1);

  if (clampedIndex == 0) {
    return '$bytes B';
  }

  final value = bytes / math.pow(1024, clampedIndex);
  final formatted = value.toStringAsFixed(1);
  final trimmed =
      formatted.endsWith('.0')
          ? formatted.substring(0, formatted.length - 2)
          : formatted;

  return '$trimmed ${units[clampedIndex]}';
}

/// Formats a [Duration] into "h:mm:ss" or "m:ss" format.
///
/// Examples:
/// - 45 seconds -> "0:45"
/// - 5 minutes 30 seconds -> "5:30"
/// - 1 hour 23 minutes 45 seconds -> "1:23:45"
String formatDuration(Duration d) {
  if (d.isNegative) return '0:00';

  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);

  final secondsStr = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    final minutesStr = minutes.toString().padLeft(2, '0');
    return '$hours:$minutesStr:$secondsStr';
  } else {
    return '$minutes:$secondsStr';
  }
}

/// Video file extensions (lowercased without leading dot).
const Set<String> _videoExtensions = {
  'mp4',
  'mkv',
  'webm',
  'avi',
  'mov',
  'flv',
  '3gp',
  'm4v',
  'wmv',
  'ts',
  'mpg',
  'mpeg',
};

/// Audio file extensions (lowercased without leading dot).
const Set<String> _audioExtensions = {
  'mp3',
  'm4a',
  'aac',
  'opus',
  'ogg',
  'flac',
  'wav',
  'wma',
};

/// Image file extensions (lowercased without leading dot).
const Set<String> _imageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'bmp',
  'svg',
};

/// Detects the [FileType] from a file path, filename, or URL based on its extension.
FileType getFileType(String path) {
  if (path.trim().isEmpty) return FileType.other;

  // Strip query parameters and hash fragments if present
  final cleanPath = path.split('?').first.split('#').first.trim();

  final dotIndex = cleanPath.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == cleanPath.length - 1) {
    return FileType.other;
  }

  final ext = cleanPath.substring(dotIndex + 1).toLowerCase();
  if (_videoExtensions.contains(ext)) {
    return FileType.video;
  }
  if (_audioExtensions.contains(ext)) {
    return FileType.audio;
  }
  if (_imageExtensions.contains(ext)) {
    return FileType.image;
  }

  return FileType.other;
}

/// Sanitizes a filename by removing illegal filesystem characters,
/// trimming whitespaces and periods, and capping length at [maxLength].
String sanitizeFilename(
  String name, {
  int maxLength = AppConstants.maxFilenameLength,
}) {
  // Remove illegal characters: <>:"/\|?* and control characters (0-31)
  var sanitized = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '').trim();

  // Remove leading dots and spaces to prevent creating hidden Unix/Android files
  sanitized = sanitized.replaceAll(RegExp(r'^[. ]+'), '');

  // Remove trailing dots and spaces (invalid on Windows and some Android filesystems)
  sanitized = sanitized.replaceAll(RegExp(r'[. ]+$'), '');

  if (sanitized.isEmpty) {
    return 'media_file';
  }

  if (sanitized.length > maxLength) {
    final dotIndex = sanitized.lastIndexOf('.');
    // If there is an extension and it's reasonably short (<= 10 chars)
    if (dotIndex != -1 && dotIndex > sanitized.length - 10) {
      final ext = sanitized.substring(dotIndex);
      final base = sanitized.substring(0, dotIndex);
      final allowedBaseLength = maxLength - ext.length;
      if (allowedBaseLength > 0) {
        sanitized = base.substring(0, allowedBaseLength) + ext;
      } else {
        sanitized = sanitized.substring(0, maxLength);
      }
    } else {
      sanitized = sanitized.substring(0, maxLength);
    }
  }

  return sanitized;
}

/// Safely opens a media file using [OpenFilex] to avoid FileUriExposedException on Android 7+.
/// Returns an [OpenResult] indicating success, fileNotFound, or error.
Future<OpenResult> openMediaFile(String filePath, {String? type}) async {
  try {
    final file = File(filePath);
    if (!await file.exists()) {
      return OpenResult(
        type: ResultType.fileNotFound,
        message: 'File not found at $filePath',
      );
    }
    return await OpenFilex.open(filePath, type: type);
  } catch (e) {
    return OpenResult(type: ResultType.error, message: e.toString());
  }
}

/// Safely shares a media file via [Share.shareXFiles].
/// Returns a [ShareResult] if successful, or null if the file does not exist or fails.
Future<ShareResult?> shareMediaFile(
  String filePath, {
  String? text,
  String? subject,
}) async {
  try {
    final file = File(filePath);
    if (!await file.exists()) {
      return null;
    }
    return await Share.shareXFiles(
      [XFile(filePath)],
      text: text,
      subject: subject,
    );
  } catch (_) {
    return null;
  }
}

/// Deletes the physical file before callers remove its saved record.
/// Missing files are already deleted; permission and I/O failures must surface.
Future<void> deleteMediaFile(String filePath) async {
  if (filePath.trim().isEmpty) {
    throw FileSystemException('No saved file path available');
  }
  final file = File(filePath);
  try {
    await file.delete();
  } on FileSystemException catch (error) {
    if (error.osError?.errorCode != 2) rethrow;
  }
  if (await file.exists()) {
    throw FileSystemException('File still exists after deletion', filePath);
  }
}
