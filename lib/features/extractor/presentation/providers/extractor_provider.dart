import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/extractor_factory.dart';
import '../../domain/entities/media_info.dart';
import '../../domain/entities/playlist_info.dart';
import '../../domain/entities/stream_info.dart';

/// Provides the singleton [ExtractorFactory] instance.
final extractorFactoryProvider = Provider<ExtractorFactory>((ref) {
  final factory = ExtractorFactory();
  ref.onDispose(() => factory.close());
  return factory;
});

/// Fetches [MediaInfo] metadata for a given media [url].
final mediaInfoProvider = FutureProvider.family<MediaInfo, String>((
  ref,
  url,
) async {
  final factory = ref.watch(extractorFactoryProvider);
  final extractor = factory.getExtractorOrThrow(url);
  return extractor.extractInfo(url);
});

/// Fetches available [StreamInfo] streams for a given media [url].
final streamsProvider = FutureProvider.family<List<StreamInfo>, String>((
  ref,
  url,
) async {
  final factory = ref.watch(extractorFactoryProvider);
  final extractor = factory.getExtractorOrThrow(url);
  return extractor.getStreams(url);
});

/// Fetches [PlaylistInfo] if the URL points to a playlist.
final playlistProvider = FutureProvider.family<PlaylistInfo?, String>((
  ref,
  url,
) async {
  final factory = ref.watch(extractorFactoryProvider);
  final extractor = factory.getExtractor(url);
  return extractor?.extractPlaylist(url);
});
