import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/url_parser.dart';
import '../providers/home_provider.dart';
import 'platform_chip.dart';

/// A sleek Material 3 dismissible banner displayed when a supported media URL
/// is detected in the system clipboard.
///
/// Automatically checks the clipboard on mount and whenever the app resumes focus.
class ClipboardBanner extends ConsumerStatefulWidget {
  const ClipboardBanner({super.key, this.onExtract});

  /// Optional callback invoked when the user taps "Extract".
  final void Function(String url)? onExtract;

  @override
  ConsumerState<ClipboardBanner> createState() => _ClipboardBannerState();
}

class _ClipboardBannerState extends ConsumerState<ClipboardBanner>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(clipboardBannerProvider.notifier).checkClipboard();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(clipboardBannerProvider.notifier).checkClipboard();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleExtract(String url) {
    ref.read(urlInputProvider.notifier).state = url;
    ref.read(clipboardBannerProvider.notifier).consume();

    if (widget.onExtract != null) {
      widget.onExtract!(url);
    } else if (GoRouter.maybeOf(context) != null) {
      context.push('/media-info?url=${Uri.encodeComponent(url)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detectedUrl = ref.watch(clipboardBannerProvider);
    final currentInputUrl = ref.watch(urlInputProvider);

    // Don't show if no clipboard link or if it is already in the text input
    if (detectedUrl == null ||
        detectedUrl.isEmpty ||
        detectedUrl == currentInputUrl) {
      return SizedBox.shrink();
    }

    final platform = detectPlatform(detectedUrl);

    // Format snippet: strip protocol and truncate
    String snippet = detectedUrl;
    if (snippet.startsWith('https://')) {
      snippet = snippet.substring(8);
    } else if (snippet.startsWith('http://')) {
      snippet = snippet.substring(7);
    }
    if (snippet.length > 34) {
      snippet = '${snippet.substring(0, 31)}...';
    }

    final bannerBg = theme.colorScheme.surfaceContainerLow;
    final borderColor = theme.colorScheme.outlineVariant;
    final titleColor = theme.colorScheme.onSurface;
    final snippetColor = theme.colorScheme.onSurfaceVariant;

    return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Container(
            decoration: BoxDecoration(
              color: bannerBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primaryPurple.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.content_paste_go_rounded,
                    color: AppColors.primaryPurple,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Copied link detected',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: titleColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (platform != PlatformType.unknown) ...[
                            const SizedBox(width: 6),
                            PlatformChip(platform: platform, compact: true),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        snippet,
                        style: TextStyle(fontSize: 12, color: snippetColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _handleExtract(detectedUrl),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Extract',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: snippetColor,
                  ),
                  tooltip: 'Dismiss',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    ref.read(clipboardBannerProvider.notifier).dismiss();
                  },
                ),
              ],
            ),
          ),
        )
        .animate()
        .fadeIn(duration: 250.ms, curve: Curves.easeOut)
        .slideY(begin: -0.1, end: 0, duration: 250.ms, curve: Curves.easeOut);
  }
}
