import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_parser/http_parser.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'package:mediagrab/features/extractor/data/extractors/youtube_stream_selection.dart';
import 'package:mediagrab/features/extractor/data/extractors/youtube_recovery.dart';
import 'package:mediagrab/features/extractor/domain/entities/stream_info.dart';

class RecoveryStreams extends yt.StreamClient {
  final bool rejectMaintained;
  final List<List<String>> calls = [];
  RecoveryStreams({this.rejectMaintained = false})
    : super(yt.YoutubeHttpClient());
  @override
  Future<yt.StreamManifest> getManifest(
    dynamic id, {
    bool fullManifest = false,
    List<yt.YoutubeApiClient>? ytClients,
    bool requireWatchPage = true,
  }) async {
    if (ytClients!.first == YoutubeRecovery.visionOs) {
      expect(requireWatchPage, isTrue);
    }
    calls.add(
      ytClients
          .map((c) => c.payload['context']['client']['clientName'] as String)
          .toList(),
    );
    if (rejectMaintained && calls.length == 1) {
      throw StateError('Unsupported video');
    }
    return yt.StreamManifest([video(299)]);
  }
}

class RecoveryVideos extends yt.VideoClient {
  final RecoveryStreams _streams;
  RecoveryVideos(this._streams) : super(yt.YoutubeHttpClient());
  @override
  yt.StreamClient get streamsClient => _streams;
}

class RecoveryYoutube extends yt.YoutubeExplode {
  final RecoveryVideos client;
  RecoveryYoutube(RecoveryStreams streams) : client = RecoveryVideos(streams);
  @override
  yt.VideoClient get videos => client;
}

yt.VideoOnlyStreamInfo video(
  int tag, {
  int height = 1080,
  int fps = 60,
  String codec = 'avc1',
}) => yt.VideoOnlyStreamInfo(
  yt.VideoId('aqz-KE-bpKQ'),
  tag,
  Uri.parse('https://test.googlevideo.com/play?itag=$tag'),
  yt.StreamContainer.mp4,
  const yt.FileSize(100),
  const yt.Bitrate(10000),
  codec,
  '${height}p',
  yt.VideoQuality.high1080,
  yt.VideoResolution(1920, height),
  yt.Framerate(fps),
  [],
  MediaType('video', 'mp4'),
);

yt.AudioOnlyStreamInfo audio(
  int tag, {
  String codec = 'mp4a.40.2',
  yt.StreamContainer container = yt.StreamContainer.mp4,
  int bitrate = 128000,
  String? tags,
  bool? trackDefault,
}) {
  final stream = yt.AudioOnlyStreamInfo(
    yt.VideoId('aqz-KE-bpKQ'),
    tag,
    Uri.https('test.googlevideo.com', '/play', {
      'itag': '$tag',
      if (tags != null) 'xtags': tags,
    }),
    container,
    const yt.FileSize(101),
    yt.Bitrate(bitrate),
    codec,
    '${bitrate ~/ 1000} kbps',
    [],
    MediaType('audio', container.name),
    null,
  );
  if (trackDefault == null) return stream;
  final data = jsonDecode(jsonEncode(stream)) as Map<String, dynamic>;
  data['audioTrack'] = {
    'displayName': 'Bangla',
    'id': 'bn.10',
    'audioIsDefault': trackDefault,
  };
  return yt.AudioOnlyStreamInfo.fromJson(data);
}

void main() {
  const selected = StreamInfo(
    url: 'https://test.googlevideo.com/play?itag=299',
    qualityLabel: '1080p60',
    codec: 'avc1',
    container: 'mp4',
    videoWidth: 1920,
    videoHeight: 1080,
    isVideoOnly: true,
  );

  test('retains high-frame-rate labels during extraction', () {
    expect(youtubeQuality(video(299)), '1080p60');
    expect(youtubeQuality(video(137, fps: 30)), '1080p');
  });
  test('recovery selects exact itag among same-resolution variants', () {
    final exact = video(299);
    expect(
      selectYoutubeStream(
        yt.StreamManifest([video(137, fps: 30), exact]),
        selected,
      ),
      exact,
    );
  });
  test('missing selected format fails instead of silently downgrading', () {
    expect(
      () => selectYoutubeStream(
        yt.StreamManifest([video(137, fps: 30), video(136, height: 720)]),
        selected,
      ),
      throwsStateError,
    );
  });
  test('changed codec on selected format fails before appending bytes', () {
    expect(
      () => selectYoutubeStream(
        yt.StreamManifest([video(299, codec: 'vp9')]),
        selected,
      ),
      throwsStateError,
    );
  });

  test(
    '403 recovery uses experimentally verified maintained profile',
    () async {
      final streams = RecoveryStreams();
      final client = RecoveryYoutube(streams);
      final result = await YoutubeRecovery.resolve(
        client,
        'aqz-KE-bpKQ',
        selected,
      );
      expect(result.tag, 299);
      expect(streams.calls, [
        ['VISIONOS'],
      ]);
      client.close();
    },
  );

  test(
    'unavailable maintained profile retains required legacy client cascade',
    () async {
      final streams = RecoveryStreams(rejectMaintained: true);
      final client = RecoveryYoutube(streams);
      expect(
        (await YoutubeRecovery.resolve(client, 'aqz-KE-bpKQ', selected)).tag,
        299,
      );
      expect(streams.calls.last, ['ANDROID', 'IOS', 'TVHTML5']);
      client.close();
    },
  );
  test('audio recovery keeps original language while restarting a DRC variant', () {
    const selectedAudio = StreamInfo(
      url:
          'https://test.googlevideo.com/play?itag=140&xtags=acont%3Doriginal%3Adrc%3D1%3Alang%3Den-US',
      qualityLabel: '128 kbps',
      codec: 'mp4a.40.2',
      container: 'mp4',
      isAudioOnly: true,
    );
    yt.AudioOnlyStreamInfo audio(
      String lang,
      String role,
    ) => yt.AudioOnlyStreamInfo(
      yt.VideoId('aqz-KE-bpKQ'),
      140,
      Uri.parse(
        'https://test.googlevideo.com/play?itag=140&xtags=acont%3D$role%3Alang%3D$lang',
      ),
      yt.StreamContainer.mp4,
      const yt.FileSize(101),
      const yt.Bitrate(128000),
      'mp4a.40.2',
      '128 kbps',
      [],
      MediaType('audio', 'mp4'),
      null,
    );
    final original = audio('en-US', 'original');
    expect(
      selectYoutubeStream(
        yt.StreamManifest([audio('bn', 'dubbed-auto'), original]),
        selectedAudio,
      ),
      original,
    );
    expect(
      () => selectYoutubeStream(
        yt.StreamManifest([audio('bn', 'dubbed-auto')]),
        selectedAudio,
      ),
      throwsStateError,
    );
  });

  group('automatic video companion audio', () {
    const preferred = StreamInfo(
      url: 'https://test.googlevideo.com/play?itag=258',
      qualityLabel: '381 kbps',
      codec: 'mp4a.40.2',
      container: 'mp4',
      isAudioOnly: true,
    );
    test(
      'uses available original AAC when the surround variant is omitted',
      () {
        final stereo = audio(140);
        final manifest = yt.StreamManifest([stereo]);
        expect(
          YoutubeRecovery.selectCompanion(manifest, preferred, 'mp4'),
          stereo,
        );
        // An explicit standalone audio selection is still exact.
        expect(
          () => selectYoutubeStream(manifest, preferred),
          throwsStateError,
        );
      },
    );
    test('retains the preferred available format', () {
      final surround = audio(258, bitrate: 381000);
      expect(
        YoutubeRecovery.selectCompanion(
          yt.StreamManifest([audio(140), surround]),
          preferred,
          'mp4',
        ),
        surround,
      );
    });
    test('WebM selects Opus rather than AAC', () {
      final opus = audio(
        251,
        codec: 'opus',
        container: yt.StreamContainer.webM,
      );
      expect(
        YoutubeRecovery.selectCompanion(
          yt.StreamManifest([audio(258), opus]),
          preferred,
          'webm',
        ),
        opus,
      );
    });
    test('rejects a dubbed default track when the original is unavailable', () {
      final dubbed = audio(
        140,
        tags: 'acont=dubbed-auto:lang=bn',
        trackDefault: true,
      );
      expect(
        () => YoutubeRecovery.selectCompanion(
          yt.StreamManifest([dubbed]),
          preferred,
          'mp4',
        ),
        throwsStateError,
      );
    });
  });
}
