import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/playback_provider.dart';
import 'playback_surface.dart';

void restorePlayback(BuildContext context, WidgetRef ref) {
  final state = ref.read(playbackProvider);
  final item = state.item;
  if (item == null) return;
  ref.read(playbackProvider.notifier).showFullPlayer();
  context.push(
    Uri(
      path: '/player',
      queryParameters: {'filePath': item.filePath, 'title': item.title},
    ).toString(),
  );
}

class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});
  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  double _drag = 0;
  final _preview = GlobalKey();
  Rect? _bounds;
  void _reportBounds() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _preview.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect == _bounds) return;
      _bounds = rect;
      unawaited(
        ref
            .read(playbackProvider.notifier)
            .videoBounds(rect, MediaQuery.devicePixelRatioOf(context)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = ref.watch(
      playbackProvider.select((s) => s.hasSession && !s.fullPlayer && !s.pip),
    );
    if (shown) {
      ref.watch(
        playbackProvider.select(
          (s) => (
            s.item,
            s.playing,
            s.error,
            s.audioOnly,
            s.width,
            s.height,
            s.textureId,
            s.rotation,
          ),
        ),
      );
    }
    final state = ref.read(playbackProvider);
    if (shown) _reportBounds();
    return AnimatedSize(
      duration:
          MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child:
          !shown
              ? const SizedBox(width: double.infinity)
              : Material(
                key: const Key('playback_mini_player'),
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => restorePlayback(context, ref),
                  onVerticalDragStart: (_) => _drag = 0,
                  onVerticalDragUpdate: (d) => _drag += d.delta.dy,
                  onVerticalDragEnd: (_) {
                    if (_drag < -48) restorePlayback(context, ref);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 64,
                        child: Row(
                          children: [
                            SizedBox(
                              key: _preview,
                              width: 96,
                              child: PlaybackSurface(state: state),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    state.item!.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: scheme.onSurface,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (state.error != null)
                                    Text(
                                      'Playback unavailable',
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              key: const Key('mini_player_play_pause'),
                              tooltip: state.playing ? 'Pause' : 'Play',
                              icon: Icon(
                                state.playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 24,
                                color: scheme.onSurface,
                              ),
                              onPressed:
                                  () => unawaited(
                                    ref
                                        .read(playbackProvider.notifier)
                                        .togglePlay(),
                                  ),
                            ),
                            IconButton(
                              key: const Key('mini_player_close'),
                              tooltip: 'Close player',
                              icon: Icon(
                                Icons.close_rounded,
                                size: 22,
                                color: scheme.onSurface,
                              ),
                              onPressed:
                                  () => unawaited(
                                    ref.read(playbackProvider.notifier).close(),
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Consumer(
                        builder:
                            (context, ref, _) => LinearProgressIndicator(
                              value: ref.watch(
                                playbackProvider.select((s) => s.progress),
                              ),
                              minHeight: 2,
                              color: playbackRed,
                              backgroundColor:
                                  Theme.of(context).colorScheme.outlineVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
    );
  }
}

/// PiP presentation and mini-player on root routes outside the navigation shell.
class PlaybackHost extends ConsumerWidget {
  const PlaybackHost({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      playbackProvider.select((s) => (s.pip, s.hasSession, s.restoreRequested)),
    );
    ref.listen(
      playbackProvider.select((s) => (s.hasSession, s.fullPlayer, s.pip)),
      (_, next) {
        if (next.$1 && !next.$2 && !next.$3) {
          unawaited(
            SystemChrome.setPreferredOrientations([
              DeviceOrientation.portraitUp,
            ]),
          );
        } else if (!next.$1) {
          unawaited(SystemChrome.setPreferredOrientations(const []));
        }
      },
    );
    ref.listen(playbackProvider.select((s) => s.restoreRequested), (
      _,
      restore,
    ) {
      if (restore) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          ref.read(playbackProvider.notifier).consumeRestore();
          final router = ref.read(_hostRouterProvider);
          if (router != null &&
              router.routeInformationProvider.value.uri.path != '/player') {
            final item = ref.read(playbackProvider).item;
            if (item != null) {
              router.push(
                Uri(
                  path: '/player',
                  queryParameters: {
                    'filePath': item.filePath,
                    'title': item.title,
                  },
                ).toString(),
              );
            }
          }
        });
      }
    });
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(offstage: state.$1, child: child),
        if (state.$1 && state.$2) const _PipSurface(),
      ],
    );
  }
}

// The host sits above Navigator, so its context does not resolve GoRouter.of.
// Inject the already-existing router without creating a navigation dependency in playback state.
final _hostRouterProvider = Provider<GoRouter?>((ref) => null);
Override playbackHostRouterOverride(GoRouter router) =>
    _hostRouterProvider.overrideWithValue(router);

class _PipSurface extends ConsumerWidget {
  const _PipSurface();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Native video frames and PiP controls render independently of Dart position
    // updates. Only changes to the actual surface/presentation need a rebuild.
    ref.watch(
      playbackProvider.select(
        (s) => (
          s.item,
          s.textureId,
          s.rotation,
          s.width,
          s.height,
          s.audioOnly,
        ),
      ),
    );
    return ColoredBox(
      color: Colors.black,
      child: PlaybackSurface(state: ref.read(playbackProvider), forPip: true),
    );
  }
}

class PlaybackPageFrame extends StatelessWidget {
  const PlaybackPageFrame({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(child: child),
      const SafeArea(top: false, child: MiniPlayer()),
    ],
  );
}
