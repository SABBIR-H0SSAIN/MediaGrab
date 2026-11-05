import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/url_parser.dart';
import '../../../downloads/presentation/providers/download_manager_provider.dart';
import '../../../downloads/domain/entities/download_task.dart';
import '../../../home/presentation/providers/home_provider.dart';
import '../../domain/entities/media_info.dart';
import '../utils/batch_download_helper.dart';

/// Modal dialog/sheet allowing users to dynamically add, remove, and populate
/// multiple video/audio URLs for batch downloading.
class DynamicBatchDownloadSheet extends ConsumerStatefulWidget {
  const DynamicBatchDownloadSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const DynamicBatchDownloadSheet(),
    );
  }

  @override
  ConsumerState<DynamicBatchDownloadSheet> createState() =>
      _DynamicBatchDownloadSheetState();
}

class _DynamicBatchDownloadSheetState
    extends ConsumerState<DynamicBatchDownloadSheet> {
  final List<TextEditingController> _controllers = [];
  final ScrollController _scrollController = ScrollController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _controllers.add(TextEditingController());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _addLinkField([String text = '']) {
    setState(() {
      _controllers.add(TextEditingController(text: text));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _removeLinkField(int index) {
    if (_controllers.length <= 1) return;
    setState(() {
      final removed = _controllers.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;

    final urls =
        text
            .split(RegExp(r'[\r\n\s]+'))
            .map((u) => u.trim())
            .where((u) => u.startsWith('http://') || u.startsWith('https://'))
            .toSet()
            .toList();

    if (urls.isEmpty) {
      // If no http prefix, fallback to simple newline split
      final lines =
          text
              .split(RegExp(r'[\r\n]+'))
              .map((u) => u.trim())
              .where((u) => u.isNotEmpty)
              .toList();
      urls.addAll(lines);
    }

    if (urls.isEmpty) return;

    setState(() {
      // First populate any existing empty controllers
      int urlIndex = 0;
      for (final controller in _controllers) {
        if (controller.text.trim().isEmpty && urlIndex < urls.length) {
          controller.text = urls[urlIndex];
          urlIndex++;
        }
      }

      // Append remaining URLs
      while (urlIndex < urls.length) {
        _controllers.add(TextEditingController(text: urls[urlIndex]));
        urlIndex++;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleStartDownload() async {
    final urls =
        _controllers
            .map((c) => c.text.trim())
            .where((u) => u.isNotEmpty)
            .toSet()
            .toList();

    if (urls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter at least one link to download'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (urls.any((url) => detectPlatform(url) == PlatformType.unknown)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter supported YouTube, Facebook or Instagram links.',
          ),
        ),
      );
      return;
    }
    final router = GoRouter.maybeOf(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSubmitting = true);

    if (urls.length == 1) {
      final singleUrl = urls.first;
      ref.read(urlInputProvider.notifier).state = singleUrl;
      Navigator.of(context).pop();
      router?.push('/media-info?url=${Uri.encodeComponent(singleUrl)}');
    } else {
      final mediaItems =
          urls.map((u) {
            final platform = detectPlatform(u);
            return MediaInfo(
              id: u,
              title:
                  'Batch Item (${u.length > 25 ? "${u.substring(0, 25)}..." : u})',
              platform: platform,
              uploader: 'Batch',
              thumbnailUrl: '',
              duration: Duration.zero,
            );
          }).toList();

      List<DownloadTask> tasks;
      try {
        tasks = await enqueueBatchMediaDownloads(ref: ref, videos: mediaItems);
      } catch (error) {
        if (!mounted) return;
        setState(() => _isSubmitting = false);
        messenger.showSnackBar(
          SnackBar(content: Text('Could not queue downloads: $error')),
        );
        return;
      }

      if (!mounted) return;
      if (tasks.isEmpty) {
        setState(() => _isSubmitting = false);
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'No downloads could be queued. Check your connection and try each link individually.',
            ),
          ),
        );
        return;
      }
      ref.read(downloadsSelectedTabProvider.notifier).state = 0;
      Navigator.of(context).pop();
      router?.go('/downloads?tab=active');
      messenger.showSnackBar(
        SnackBar(
          content: Text('Queued ${tasks.length} of ${urls.length} downloads'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dialogBg = colors.surfaceContainerHigh;
    final borderColor = colors.outlineVariant;
    final cardBg = colors.surfaceContainerLow;
    final textColor = colors.onSurface;
    final subtitleColor = colors.onSurfaceVariant;

    final filledCount =
        _controllers.where((c) => c.text.trim().isNotEmpty).length;

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: borderColor),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
          maxWidth: 480,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.layers_rounded,
                      color: colors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Batch Download',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Add multiple links to queue',
                          style: TextStyle(fontSize: 12, color: subtitleColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: subtitleColor,
                      size: 22,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Scrollable Links List
              Flexible(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    children: [
                      for (int i = 0; i < _controllers.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: colors.primary.withValues(
                                        alpha: 0.15,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        color: colors.primary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _controllers[i],
                                    onChanged: (_) => setState(() {}),
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 13,
                                    ),
                                    decoration: InputDecoration(
                                      hintText:
                                          'https://youtube.com/watch?v=...',
                                      hintStyle: TextStyle(
                                        color: subtitleColor.withValues(
                                          alpha: 0.6,
                                        ),
                                        fontSize: 13,
                                      ),
                                      filled: false,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                    ),
                                  ),
                                ),
                                if (_controllers.length > 1)
                                  IconButton(
                                    icon: Icon(
                                      Icons.close_rounded,
                                      color: subtitleColor.withValues(
                                        alpha: 0.8,
                                      ),
                                      size: 18,
                                    ),
                                    tooltip: 'Remove',
                                    onPressed: () => _removeLinkField(i),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // Action Buttons Row: "Add another link" and "Paste from Clipboard"
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.primary,
                        side: BorderSide(
                          color: colors.primary.withValues(alpha: 0.5),
                          width: 1.2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      onPressed: () => _addLinkField(),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text(
                        'Add another link',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      backgroundColor: cardBg,
                      foregroundColor: colors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: borderColor),
                      ),
                    ),
                    icon: const Icon(Icons.assignment_outlined, size: 19),
                    tooltip: 'Paste links from clipboard',
                    onPressed: _pasteFromClipboard,
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Bottom Actions: Pinned prominent Start Download button
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: _isSubmitting ? null : _handleStartDownload,
                child:
                    _isSubmitting
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : Text(
                          filledCount > 1
                              ? 'Start Download ($filledCount)'
                              : 'Start Download',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.2,
                          ),
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
