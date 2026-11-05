import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/brand_artwork.dart';
import '../../../../core/utils/url_parser.dart';

/// A chip displaying the detected platform badge (YouTube red, Facebook blue,
/// Instagram gradient-pink) with its respective icon and name.
class PlatformChip extends StatelessWidget {
  const PlatformChip({super.key, required this.platform, this.compact = false});

  final PlatformType platform;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (platform == PlatformType.unknown) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    final String label = platform.displayName;
    final Color? solidColor;
    final Gradient? gradient;

    switch (platform) {
      case PlatformType.youtube:
        solidColor = AppColors.youtubeRed;
        gradient = null;
        break;
      case PlatformType.facebook:
        solidColor = AppColors.facebookBlue;
        gradient = null;
        break;
      case PlatformType.instagram:
        solidColor = null;
        gradient = const LinearGradient(
          colors: [
            AppColors.instagramPurple,
            AppColors.instagramPink,
            AppColors.instagramOrange,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
        break;
      case PlatformType.unknown:
        return const SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 3 : 6,
      ),
      decoration: BoxDecoration(
        color: solidColor,
        gradient: gradient,
        borderRadius: BorderRadius.circular(compact ? 12 : 20),
        boxShadow: [
          BoxShadow(
            color: (solidColor ?? AppColors.instagramPink).withValues(
              alpha: 0.25,
            ),
            blurRadius: compact ? 4 : 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlatformLogo(platform: platform.name, size: compact ? 14 : 18),
          SizedBox(width: compact ? 4 : 6),
          Text(
            label,
            style: (compact
                    ? theme.textTheme.labelSmall
                    : theme.textTheme.labelMedium)
                ?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 10 : null,
                ),
          ),
        ],
      ),
    );
  }
}
