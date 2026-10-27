import 'package:flutter/material.dart';

/// Reusable section container for the Settings screen with a purple section header
/// and children wrapped in a styled modern card with dividers, fully respecting
/// light, dark, and AMOLED themes.
class SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final cardColor = theme.colorScheme.surfaceContainerLow;
    final borderColor = theme.colorScheme.outlineVariant;
    final dividerColor = theme.colorScheme.outlineVariant;
    final titleColor = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Text(
            title,
            style: TextStyle(
              color: titleColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          elevation: 0,
          color: cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderColor, width: .6),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: dividerColor.withValues(alpha: .35),
                    indent: 54,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
