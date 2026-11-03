import '../../../../shared/widgets/brand_artwork.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Ultra-modern empty state widget matching Screen 2 of the reference screenshot:
/// - 3D/glassmorphism purple floating download box
/// - "No active downloads" bold title
/// - "Start a download to see the progress here" descriptive subtitle
/// - Outlined purple "Paste Link to Download" button
class EmptyDownloadsView extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String buttonLabel;
  final VoidCallback? onActionPressed;
  final bool showActionButton;

  const EmptyDownloadsView({
    super.key,
    this.title = 'No active downloads',
    this.subtitle = 'Start a download to see the progress here',
    this.icon = Icons.download_outlined,
    this.buttonLabel = 'Paste Link to Download',
    this.onActionPressed,
    this.showActionButton = true,
  });

  void _handleAction(BuildContext context) {
    if (onActionPressed != null) {
      onActionPressed!();
    } else {
      try {
        context.go('/home');
      } catch (_) {
        // Fallback when outside GoRouter context
      }
    }
  }

  Widget _buildBoxIllustration(BuildContext context) =>
      MediaStackArtwork(size: 142, icon: icon);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildBoxIllustration(context),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (showActionButton) ...[
              const SizedBox(height: 40),
              OutlinedButton.icon(
                onPressed: () => _handleAction(context),
                icon: Icon(
                  Icons.link_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                label: Text(
                  buttonLabel,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
