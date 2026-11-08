import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/playback_state.dart';
import '../providers/playback_provider.dart';

const playbackRed = Color(0xFFFF0033);

String playbackTime(Duration value) {
  final seconds = value.inSeconds.clamp(0, 8640000);
  final minutes = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return seconds >= 3600
      ? '${seconds ~/ 3600}:$minutes:$rest'
      : '$minutes:$rest';
}

class PlaybackSurface extends ConsumerWidget {
  const PlaybackSurface({
    super.key,
    required this.state,
    this.fit = BoxFit.contain,
    this.forPip = false,
    this.showVideo = true,
  });
  final PlaybackState state;
  final BoxFit fit;
  final bool forPip, showVideo;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artwork = state.item?.artworkPath;
    if (!showVideo ||
        state.audioOnly ||
        state.item?.isAudio == true ||
        (state.pip && !forPip)) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child:
              artwork != null
                  ? Image.file(
                    File(artwork),
                    fit: BoxFit.contain,
                    cacheWidth: 640,
                    errorBuilder:
                        (_, __, ___) => const Icon(
                          Icons.music_note_rounded,
                          size: 64,
                          color: Colors.white54,
                        ),
                  )
                  : const Icon(
                    Icons.music_note_rounded,
                    size: 64,
                    color: Colors.white54,
                  ),
        ),
      );
    }
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: fit,
          child: SizedBox(
            width: state.width > 0 ? state.width : 1920,
            height: state.height > 0 ? state.height : 1080,
            child: ref
                .read(playbackProvider.notifier)
                .backend
                .buildVideo(state),
          ),
        ),
      ),
    );
  }
}
