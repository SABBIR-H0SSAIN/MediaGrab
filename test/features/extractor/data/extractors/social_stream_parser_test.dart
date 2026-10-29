import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:mediagrab/features/extractor/data/extractors/facebook_extractor.dart';
import 'package:mediagrab/features/extractor/data/extractors/instagram_extractor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/features/extractor/data/extractors/social_stream_parser.dart';

const dash = '''<MPD xmlns="urn:mpeg:dash:schema:mpd:2011"><Period>
<AdaptationSet mimeType="video/mp4" codecs="avc1.640028">
<Representation id="hd" width="1920" height="1080" bandwidth="4000000"><BaseURL>https://cdn.example/video1080.mp4?a=1&amp;b=2</BaseURL><SegmentBase indexRange="1-20" /></Representation>
<Representation id="uhd" width="3840" height="2160" bandwidth="12000000"><BaseURL>https://cdn.example/video2160.mp4</BaseURL><SegmentBase /></Representation>
</AdaptationSet>
<AdaptationSet mimeType="audio/mp4" codecs="mp4a.40.2"><Representation id="audio" bandwidth="128000"><BaseURL>https://cdn.example/audio.m4a</BaseURL><SegmentBase /></Representation></AdaptationSet>
</Period></MPD>''';

void main() {
  test('Facebook extractor loads an external DASH manifest above 720p', () async {
    final dio =
        Dio()
          ..httpClientAdapter = _FixtureAdapter((options) {
            if (options.uri.path.endsWith('.mpd')) return dash;
            return '<script>${jsonEncode({'id': '1234567890', 'dash_manifest_url': 'https://cdn.example/manifest.mpd', 'browser_native_hd_url': 'https://cdn.example/hd.mp4'})}</script>';
          });
    addTearDown(dio.close);
    final streams = await FacebookExtractor(
      dio: dio,
    ).getStreams('https://facebook.com/watch/?v=1234567890');
    expect(streams.first.videoHeight, 2160);
    expect(streams.any((stream) => stream.videoHeight == 1080), isTrue);
    expect(
      streams.any((stream) => stream.isAudioOnly && stream.bitrate == 128000),
      isTrue,
    );
  });
  test(
    'Instagram checks public page for higher versions even when embed is playable',
    () async {
      final dio =
          Dio()
            ..httpClientAdapter = _FixtureAdapter((options) {
              if (options.uri.path.contains('/embed/')) {
                return '<script>${jsonEncode({
                  'shortcode': 'ABC123',
                  'video_url': 'https://cdn.example/embed.mp4',
                  'dimensions': {'width': 720, 'height': 1280},
                })}</script>';
              }
              return '<script>${jsonEncode({
                'shortcode': 'ABC123',
                'video_versions': [
                  {'url': 'https://cdn.example/full.mp4', 'width': 1080, 'height': 1920},
                ],
              })}</script>';
            });
      addTearDown(dio.close);
      final streams = await InstagramExtractor(
        dio: dio,
      ).getStreams('https://instagram.com/reel/ABC123/');
      expect(streams.first.qualityLabel, '1080p');
      expect(streams.first.videoHeight, 1920);
      expect(streams.where((stream) => !stream.isAudioOnly), hasLength(2));
    },
  );

  test('Facebook DASH exposes 1080p, 4K and real companion audio', () {
    final source =
        '<script type="application/json">${jsonEncode({'id': '123', 'dash_manifest': dash, 'browser_native_hd_url': 'https://cdn.example/progressive.mp4'})}</script>';
    final parser = SocialStreamParser()..parsePage(source, mediaId: '123');
    final streams = parser.finish();
    expect(streams.first.videoHeight, 2160);
    expect(streams.first.isVideoOnly, isTrue);
    final hd = streams.firstWhere((stream) => stream.videoHeight == 1080);
    expect(hd.url, 'https://cdn.example/video1080.mp4?a=1&b=2');
    expect(
      streams.where((stream) => stream.isAudioOnly).single.bitrate,
      128000,
    );
    expect(
      streams
          .firstWhere((stream) => !stream.isVideoOnly && !stream.isAudioOnly)
          .videoHeight,
      isNull,
    );
  });
  test('Instagram returns every real video version with portrait dimensions', () {
    final source =
        '<script>window.data = ${jsonEncode({
          'shortcode': 'ABC',
          'video_versions': [
            {'url': 'https://cdn.example/720.mp4', 'width': 720, 'height': 1280},
            {'url': 'https://cdn.example/1080.mp4', 'width': 1080, 'height': 1920},
          ],
        })};</script>';
    final parser = SocialStreamParser()..parsePage(source, mediaId: 'ABC');
    final streams = parser.finish();
    expect(streams.first.qualityLabel, '1080p');
    expect(streams.first.videoHeight, 1920);
    expect(streams.where((stream) => !stream.isAudioOnly), hasLength(2));
  });
  test('target video does not collect recommended videos or their qualities', () {
    final source =
        '<script>${jsonEncode({
          'videos': [
            {'id': 'other', 'dash_manifest': dash},
            {
              'id': 'target',
              'video_versions': [
                {'url': 'https://cdn.example/target.mp4', 'width': 640, 'height': 360},
              ],
            },
          ],
        })}</script>';
    final parser = SocialStreamParser()..parsePage(source, mediaId: 'target');
    expect(
      parser.finish().where((stream) => !stream.isAudioOnly).single.videoHeight,
      360,
    );
  });
  test(
    'segmented and protected manifests are excluded from direct-file downloads',
    () {
      final parser =
          SocialStreamParser()..parseDash(
            '''<MPD><Period><AdaptationSet mimeType="video/mp4"><SegmentTemplate media="chunk-\$Number\$.m4s" /><Representation width="1920" height="1080"><BaseURL>https://cdn.example/video.mp4</BaseURL></Representation></AdaptationSet></Period></MPD>''',
          );
      expect(parser.finish(), isEmpty);
      parser.parseDash(
        '''<MPD><Period><AdaptationSet mimeType="video/mp4"><ContentProtection /><Representation width="1920" height="1080"><BaseURL>https://cdn.example/video.mp4</BaseURL></Representation></AdaptationSet></Period></MPD>''',
      );
      expect(parser.finish(), isEmpty);
    },
  );
  test('a video-only stream is not offered without any audio source', () {
    final parser =
        SocialStreamParser()..parseDash(
          '''<MPD><Period><AdaptationSet mimeType="video/mp4"><Representation width="1920" height="1080"><BaseURL>https://cdn.example/video.mp4</BaseURL></Representation></AdaptationSet></Period></MPD>''',
        );
    expect(parser.finish(), isEmpty);
  });
  test('relative BaseURL resolves against manifest location', () {
    final parser =
        SocialStreamParser()..parseDash(
          '''<MPD><Period><AdaptationSet mimeType="audio/mp4"><Representation bandwidth="128000"><BaseURL>audio.m4a?a=1&amp;b=2</BaseURL></Representation></AdaptationSet></Period></MPD>''',
          manifestUrl: 'https://cdn.example/media/manifest.mpd',
        );
    expect(
      parser.finish().single.url,
      'https://cdn.example/media/audio.m4a?a=1&b=2',
    );
  });
}

class _FixtureAdapter implements HttpClientAdapter {
  _FixtureAdapter(this.response);
  final String Function(RequestOptions) response;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    response(options),
    200,
    headers: {
      Headers.contentTypeHeader: ['text/plain'],
    },
  );
  @override
  void close({bool force = false}) {}
}
