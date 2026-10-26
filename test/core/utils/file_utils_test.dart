import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/file_utils.dart';

void main() {
  group('formatFileSize', () {
    test('handles 0 and negative bytes', () {
      expect(formatFileSize(0), '0 B');
      expect(formatFileSize(-10), '0 B');
    });

    test('formats small byte sizes', () {
      expect(formatFileSize(1), '1 B');
      expect(formatFileSize(500), '500 B');
      expect(formatFileSize(1023), '1023 B');
    });

    test('formats kilobytes correctly', () {
      expect(formatFileSize(1024), '1 KB');
      expect(formatFileSize(1536), '1.5 KB');
      expect(formatFileSize(2048), '2 KB');
    });

    test('formats megabytes correctly', () {
      expect(formatFileSize(1024 * 1024), '1 MB');
      expect(formatFileSize(350 * 1024 * 1024), '350 MB');
      expect(formatFileSize((1.5 * 1024 * 1024).round()), '1.5 MB');
    });

    test('formats gigabytes correctly', () {
      expect(formatFileSize((1.2 * 1024 * 1024 * 1024).round()), '1.2 GB');
      expect(formatFileSize(1024 * 1024 * 1024), '1 GB');
    });

    test('formats terabytes correctly', () {
      expect(formatFileSize(1024 * 1024 * 1024 * 1024), '1 TB');
    });
  });

  group('formatDuration', () {
    test('formats zero and negative durations', () {
      expect(formatDuration(Duration.zero), '0:00');
      expect(formatDuration(const Duration(seconds: -5)), '0:00');
    });

    test('formats seconds only (< 1 minute)', () {
      expect(formatDuration(const Duration(seconds: 5)), '0:05');
      expect(formatDuration(const Duration(seconds: 45)), '0:45');
    });

    test('formats minutes and seconds (< 1 hour)', () {
      expect(formatDuration(const Duration(minutes: 5, seconds: 30)), '5:30');
      expect(formatDuration(const Duration(minutes: 12, seconds: 4)), '12:04');
    });

    test('formats hours, minutes, and seconds (>= 1 hour)', () {
      expect(
        formatDuration(const Duration(hours: 1, minutes: 23, seconds: 45)),
        '1:23:45',
      );
      expect(
        formatDuration(const Duration(hours: 10, minutes: 2, seconds: 9)),
        '10:02:09',
      );
    });
  });

  group('getFileType', () {
    test('identifies video files', () {
      expect(getFileType('video.mp4'), FileType.video);
      expect(getFileType('clip.mkv'), FileType.video);
      expect(getFileType('movie.webm'), FileType.video);
      expect(getFileType('stream.avi'), FileType.video);
      expect(getFileType('video.mov'), FileType.video);
      expect(getFileType('file.flv'), FileType.video);
      expect(getFileType('mobile.3gp'), FileType.video);
      expect(getFileType('/path/to/downloaded/movie.m4v'), FileType.video);
    });

    test('identifies audio files', () {
      expect(getFileType('song.mp3'), FileType.audio);
      expect(getFileType('track.m4a'), FileType.audio);
      expect(getFileType('audio.opus'), FileType.audio);
      expect(getFileType('sound.aac'), FileType.audio);
      expect(getFileType('lossless.flac'), FileType.audio);
      expect(getFileType('sample.wav'), FileType.audio);
      expect(getFileType('record.ogg'), FileType.audio);
    });

    test('identifies image files', () {
      expect(getFileType('thumb.jpg'), FileType.image);
      expect(getFileType('photo.jpeg'), FileType.image);
      expect(getFileType('picture.png'), FileType.image);
      expect(getFileType('banner.webp'), FileType.image);
      expect(getFileType('animation.gif'), FileType.image);
      expect(getFileType('vector.svg'), FileType.image);
    });

    test('handles case insensitivity', () {
      expect(getFileType('VIDEO.MP4'), FileType.video);
      expect(getFileType('TRACK.MP3'), FileType.audio);
      expect(getFileType('PHOTO.PNG'), FileType.image);
    });

    test('handles query parameters and hashes in paths', () {
      expect(
        getFileType('https://example.com/video.mp4?source=web#t=10'),
        FileType.video,
      );
      expect(getFileType('/downloads/song.mp3?v=1'), FileType.audio);
    });

    test('identifies unknown/other file types', () {
      expect(getFileType('document.pdf'), FileType.other);
      expect(getFileType('archive.zip'), FileType.other);
      expect(getFileType('code.dart'), FileType.other);
      expect(getFileType('no_extension'), FileType.other);
      expect(getFileType(''), FileType.other);
    });
  });

  group('sanitizeFilename', () {
    test('removes illegal filesystem characters', () {
      const input = 'My Video: "Best" <Quality> / Part 1 * test? | cool';
      final sanitized = sanitizeFilename(input);
      expect(sanitized, isNot(contains(':')));
      expect(sanitized, isNot(contains('"')));
      expect(sanitized, isNot(contains('<')));
      expect(sanitized, isNot(contains('>')));
      expect(sanitized, isNot(contains('/')));
      expect(sanitized, isNot(contains('*')));
      expect(sanitized, isNot(contains('?')));
      expect(sanitized, isNot(contains('|')));
    });

    test('removes control characters and trims spaces/dots', () {
      const input = '   hello world\t\n...   ';
      expect(sanitizeFilename(input), 'hello world');
    });

    test('strips leading periods and spaces to prevent hidden files on Android', () {
      expect(sanitizeFilename('...hidden_file.mp4'), 'hidden_file.mp4');
      expect(sanitizeFilename('.secret_song.mp3'), 'secret_song.mp3');
      expect(sanitizeFilename(' . .my_video.mp4'), 'my_video.mp4');
    });

    test('returns fallback if name becomes empty', () {
      expect(sanitizeFilename(''), 'media_file');
      expect(sanitizeFilename('???***///'), 'media_file');
    });

    test('limits length to 200 characters while preserving extension', () {
      final longTitle = 'a' * 250;
      final withExt = '$longTitle.mp4';
      final result = sanitizeFilename(withExt);
      expect(result.length, lessThanOrEqualTo(200));
      expect(result.endsWith('.mp4'), isTrue);
    });

    test('limits length without extension', () {
      final longTitle = 'b' * 300;
      final result = sanitizeFilename(longTitle);
      expect(result.length, lessThanOrEqualTo(200));
    });
  });
}
