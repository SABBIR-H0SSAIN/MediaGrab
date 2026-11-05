import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/home_provider.dart';
import 'platform_chip.dart';
import '../../../../shared/widgets/media_link_field.dart';

/// Hero URL input card widget on the Home screen.
///
/// Features a pill-shaped [TextField] with link prefix icon, clear suffix icon,
/// dynamic [PlatformChip] detection, and a prominent M3 "Analyze & Download" button.
class UrlInputCard extends ConsumerStatefulWidget {
  const UrlInputCard({super.key, this.onDownload});

  /// Optional callback invoked when the Analyze & Download button is pressed with a valid URL.
  final void Function(String url)? onDownload;

  @override
  ConsumerState<UrlInputCard> createState() => _UrlInputCardState();
}

class _UrlInputCardState extends ConsumerState<UrlInputCard> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(urlInputProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clearInput() {
    _controller.clear();
    clearUrlInput(ref);
  }

  Future<void> _handlePaste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isNotEmpty) {
        ref.read(urlInputProvider.notifier).state = text;
        _controller.text = text;
        HapticFeedback.lightImpact();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Link pasted from clipboard'),
              duration: Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Clipboard is empty'),
              duration: Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (_) {}
  }

  void _handleDownload() {
    final url = ref.read(urlInputProvider);
    if (widget.onDownload != null) {
      widget.onDownload!(url);
    } else {
      if (GoRouter.maybeOf(context) != null) {
        context.push('/media-info?url=${Uri.encodeComponent(url)}');
      } else {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              'Processing download for $url',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(urlInputProvider);
    final detectedPlatform = ref.watch(detectedPlatformProvider);
    final isValid = ref.watch(isValidUrlProvider);

    final theme = Theme.of(context);
    // Keep controller in sync if provider is updated externally (e.g., Quick Actions or Banner)
    ref.listen<String>(urlInputProvider, (previous, next) {
      if (_controller.text != next) {
        _controller.text = next;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: next.length),
        );
      }
    });

    return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            MediaLinkField(
              controller: _controller,
              hintText: 'Paste video link (YouTube, ...)',
              onPaste: _handlePaste,
              onClear: _clearInput,
              onChanged:
                  (value) => ref.read(urlInputProvider.notifier).state = value,
              onSubmitted: isValid ? (_) => _handleDownload() : null,
            ),
            if (isValid) ...[
              const SizedBox(height: 10),
              PlatformChip(platform: detectedPlatform)
                  .animate()
                  .fadeIn(duration: 200.ms)
                  .scale(
                    begin: Offset(0.92, 0.92),
                    end: Offset(1, 1),
                    duration: 200.ms,
                  ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors:
                        theme.brightness == Brightness.dark
                            ? [
                              Color.lerp(
                                theme.colorScheme.primary,
                                theme.colorScheme.primaryContainer,
                                .35,
                              )!,
                              theme.colorScheme.primaryContainer,
                            ]
                            : [
                              theme.colorScheme.primary,
                              Color.lerp(
                                theme.colorScheme.primary,
                                Colors.black,
                                .15,
                              )!,
                            ],
                  ),
                ),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    foregroundColor:
                        theme.brightness == Brightness.dark
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onPrimary,
                    disabledForegroundColor: (theme.brightness ==
                                Brightness.dark
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onPrimary)
                        .withValues(alpha: .65),
                    textStyle: const TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  onPressed: isValid ? _handleDownload : null,
                  icon: const Icon(Icons.file_download_outlined, size: 19),
                  label: const Text('Analyze & Download'),
                ),
              ),
            ),
          ],
        )
        .animate()
        .fadeIn(duration: 400.ms, curve: Curves.easeOut)
        .slideY(begin: 0.08, end: 0, duration: 400.ms, curve: Curves.easeOut);
  }
}
