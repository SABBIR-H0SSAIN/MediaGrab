import '../../../../core/utils/url_parser.dart';
import '../../../../shared/widgets/brand_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../shared/widgets/media_link_field.dart';
import '../../../../shared/widgets/media_options_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/home_provider.dart';

/// Modern Quick Actions section matching the screenshot:
/// 1. Row of 4 platform buttons: YouTube, Facebook, Instagram, More
/// 2. Feature Action Cards: "Batch Download" and "Playlists"
class QuickActionsRow extends ConsumerWidget {
  const QuickActionsRow({
    super.key,
    this.onPaste,
    this.onPasteLink,
    this.onBatch,
    this.onSupportedSites,
    this.onHowToUse,
    this.onSearch,
    this.onBrowse,
  });

  final VoidCallback? onPaste;
  final VoidCallback? onPasteLink;
  final VoidCallback? onBatch;
  final VoidCallback? onSupportedSites;
  final VoidCallback? onHowToUse;

  // Backwards compatibility
  final VoidCallback? onSearch;
  final VoidCallback? onBrowse;

  void _showBatchDownloadDialog(BuildContext context, WidgetRef ref) {
    context.push('/batch-download');
  }

  Future<void> _showPlaylistPromptDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final url = await showDialog<String>(
      context: context,
      builder: (_) => const _PlaylistLinkDialog(),
    );
    if (url == null || !context.mounted) return;
    ref.read(urlInputProvider.notifier).state = url;
    context.push('/media-info?url=${Uri.encodeComponent(url)}');
  }

  void _showSupportedSites(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder:
          (sheetContext) => MediaOptionsSheet(
            title: 'Supported Platforms',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                child: Text(
                  'Download videos and audio from these platforms. Availability depends on the source.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              _buildSiteItem(
                context,
                circleColor: AppColors.youtubeRed,
                title: 'YouTube',
                desc: 'Videos, Shorts, playlists and audio.',
              ),
              const SizedBox(height: 20),
              _buildSiteItem(
                context,
                circleColor: AppColors.facebookBlue,
                title: 'Facebook',
                desc: 'Public videos, Watch links and Reels.',
              ),
              const SizedBox(height: 20),
              _buildSiteItem(
                context,
                gradient: LinearGradient(
                  colors: [
                    AppColors.instagramPurple,
                    AppColors.instagramPink,
                    AppColors.instagramOrange,
                  ],
                ),
                title: 'Instagram',
                desc: 'Reels, video posts and available Stories.',
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Got It'),
              ),
            ],
          ),
    );
  }

  Widget _buildSiteItem(
    BuildContext context, {
    Color? circleColor,
    Gradient? gradient,
    required String title,
    required String desc,
  }) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: circleColor,
            gradient: gradient,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: PlatformLogo(platform: title.toLowerCase(), size: 28),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlatformCircle(
    BuildContext context, {
    required Widget icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 48,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  width: .6,
                ),
              ),
              child: Center(child: icon),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: .6,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 22,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        // Platform Circles Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildPlatformCircle(
              context,
              icon: const PlatformLogo(platform: 'youtube'),
              label: 'YouTube',
              onTap: () {
                if (onBrowse != null) {
                  onBrowse!();
                } else {
                  _showSupportedSites(context);
                }
              },
            ),
            _buildPlatformCircle(
              context,
              icon: const PlatformLogo(platform: 'facebook'),
              label: 'Facebook',
              onTap: () {
                _showSupportedSites(context);
              },
            ),
            _buildPlatformCircle(
              context,
              icon: const PlatformLogo(platform: 'instagram'),
              label: 'Instagram',
              onTap: () {
                _showSupportedSites(context);
              },
            ),
            _buildPlatformCircle(
              context,
              icon: Icon(
                Icons.more_horiz_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 22,
              ),
              label: 'More',
              onTap: () {
                if (onSupportedSites != null) {
                  onSupportedSites!();
                } else {
                  _showSupportedSites(context);
                }
              },
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Feature Action Cards
        _buildFeatureCard(
          context,
          icon: Icons.layers_outlined,
          title: 'Batch Download',
          subtitle: 'Download multiple links',
          onTap: () {
            if (onBatch != null) {
              onBatch!();
            } else {
              _showBatchDownloadDialog(context, ref);
            }
          },
        ),

        const SizedBox(height: 8),

        _buildFeatureCard(
          context,
          icon: Icons.format_list_bulleted_rounded,
          title: 'Playlists',
          subtitle: 'Download entire playlists',
          onTap: () {
            if (onBatch != null) {
              onBatch!();
            } else {
              _showPlaylistPromptDialog(context, ref);
            }
          },
        ),
      ],
    );
  }
}

class _PlaylistLinkDialog extends StatefulWidget {
  const _PlaylistLinkDialog();
  @override
  State<_PlaylistLinkDialog> createState() => _PlaylistLinkDialogState();
}

class _PlaylistLinkDialogState extends State<_PlaylistLinkDialog> {
  final _controller = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      final text = data?.text?.trim() ?? '';
      if (text.isNotEmpty) {
        _controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        setState(() => _error = null);
      }
    } catch (_) {
      /* The field remains editable if clipboard access fails. */
    }
  }

  void _submit() {
    final url = _controller.text.trim();
    final uri = Uri.tryParse(url.contains('://') ? url : 'https://$url');
    if (uri == null ||
        detectPlatform(url) != PlatformType.youtube ||
        (uri.queryParameters['list']?.isEmpty ?? true)) {
      setState(() => _error = 'Enter a YouTube link containing a playlist.');
      return;
    }
    Navigator.pop(context, url);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Download Playlist'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Choose videos from a YouTube playlist.'),
          const SizedBox(height: 20),
          MediaLinkField(
            controller: _controller,
            hintText: 'Paste playlist link',
            errorText: _error,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onClear: () {
              _controller.clear();
              setState(() => _error = null);
            },
            onPaste: _paste,
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.end,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Load Playlist')),
      ],
    );
  }
}
