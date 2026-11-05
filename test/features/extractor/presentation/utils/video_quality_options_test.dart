import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';
import 'package:mediagrab/features/extractor/presentation/utils/video_quality_options.dart';

StreamInfo video(
  String id,
  String label, {
  int? height,
  int? width,
  int? bitrate,
  bool videoOnly = true,
  String container = 'mp4',
  String codec = 'avc1',
}) => StreamInfo(
  url: 'https://example.com/$id',
  qualityLabel: label,
  codec: codec,
  container: container,
  videoWidth: width,
  videoHeight: height,
  bitrate: bitrate,
  isVideoOnly: videoOnly,
);

void main() {
  test('one option per resolution retains highest frame rate then bitrate', () {
    final low = video('low', '1080p', height: 1080, bitrate: 5000000);
    final highFps = video('60', '1080p60', height: 1080, bitrate: 3000000);
    final best = video('best', '1080p60', height: 1080, bitrate: 4500000);
    final smaller = video('720', '720p', height: 720);
    expect(bestVideoQualityOptions([low, highFps, smaller, best]), [
      best,
      smaller,
    ]);
  });
  test('360p prefers progressive even when adaptive bitrate is higher', () {
    final muxed = video(
      'muxed',
      '360p',
      height: 360,
      videoOnly: false,
      bitrate: 500000,
    );
    final adaptive = video('adaptive', '360p', height: 360, bitrate: 1000000);
    expect(bestVideoQualityOptions([adaptive, muxed]), [muxed]);
  });
  test(
    'portrait and landscape versions share their display-resolution category',
    () {
      final portrait = video(
        'portrait',
        '1080p',
        height: 1920,
        width: 1080,
        bitrate: 2000000,
      );
      final landscape = video(
        'landscape',
        '1080p',
        height: 1080,
        width: 1920,
        bitrate: 3000000,
      );
      expect(bestVideoQualityOptions([portrait, landscape]), [landscape]);
      expect(videoResolution(portrait), 1080);
    },
  );
  test('4K alias groups with 2160p without modifying source streams', () {
    final alias = video('4k', '4K', bitrate: 5000000);
    final numeric = video('2160', '2160p', height: 2160, bitrate: 6000000);
    final original = [alias, numeric];
    expect(bestVideoQualityOptions(original), [numeric]);
    expect(original, [alias, numeric]);
  });
  test('equal evidence prefers compatible MP4 and excludes audio', () {
    final mp4 = video('mp4', '720p', height: 720);
    final webm = video(
      'webm',
      '720p',
      height: 720,
      container: 'webm',
      codec: 'vp9',
    );
    const audio = StreamInfo(
      url: 'https://example.com/audio',
      qualityLabel: '128 kbps',
      codec: 'aac',
      container: 'm4a',
      isAudioOnly: true,
    );
    expect(bestVideoQualityOptions([audio, webm, mp4]), [mp4]);
  });
  test('unknown dimensions remain distinct named qualities', () {
    final hd = video('hd', 'HD', videoOnly: false);
    final original = video('original', 'Original', videoOnly: false);
    expect(bestVideoQualityOptions([hd, hd, original]), [hd, original]);
    expect(videoResolution(hd), isNull);
  });
}
