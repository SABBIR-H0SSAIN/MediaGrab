import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';

void main() {
  group('StreamInfo Entity', () {
    test('supports value equality via Equatable', () {
      const stream1 = StreamInfo(
        url: 'https://video.googlevideo.com/videoplayback?id=123',
        qualityLabel: '1080p',
        codec: 'avc1.640028',
        container: 'mp4',
        sizeInBytes: 52428800,
        bitrate: 4500000,
        videoWidth: 1920,
        videoHeight: 1080,
        isVideoOnly: true,
      );

      const stream2 = StreamInfo(
        url: 'https://video.googlevideo.com/videoplayback?id=123',
        qualityLabel: '1080p',
        codec: 'avc1.640028',
        container: 'mp4',
        sizeInBytes: 52428800,
        bitrate: 4500000,
        videoWidth: 1920,
        videoHeight: 1080,
        isVideoOnly: true,
      );

      expect(stream1, equals(stream2));
    });

    test('formats stream sizes accurately', () {
      const kbStream = StreamInfo(
        url: 'http://stream.url',
        qualityLabel: '144p',
        codec: 'mp4',
        container: 'mp4',
        sizeInBytes: 512 * 1024,
      );
      expect(kbStream.formattedSize, '512.0 KB');

      const mbStream = StreamInfo(
        url: 'http://stream.url',
        qualityLabel: '720p',
        codec: 'mp4',
        container: 'mp4',
        sizeInBytes: 25 * 1024 * 1024,
      );
      expect(mbStream.formattedSize, '25.0 MB');

      const gbStream = StreamInfo(
        url: 'http://stream.url',
        qualityLabel: '4K',
        codec: 'mp4',
        container: 'mp4',
        sizeInBytes: 1610612736,
      );
      expect(gbStream.formattedSize, '1.50 GB');

      const unknownStream = StreamInfo(
        url: 'http://stream.url',
        qualityLabel: 'Unknown',
        codec: 'mp4',
        container: 'mp4',
      );
      expect(unknownStream.formattedSize, 'Unknown size');
    });

    test('formats bitrate correctly', () {
      const audioStream = StreamInfo(
        url: 'http://stream.url',
        qualityLabel: 'Audio',
        codec: 'mp4a.40.2',
        container: 'm4a',
        isAudioOnly: true,
        bitrate: 128000,
      );
      expect(audioStream.formattedBitrate, '128 kbps');

      const noBitrate = StreamInfo(
        url: 'http://stream.url',
        qualityLabel: 'Audio',
        codec: 'mp4',
        container: 'mp4',
      );
      expect(noBitrate.formattedBitrate, '');
    });
  });
}
