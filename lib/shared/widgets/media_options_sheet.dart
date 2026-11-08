import 'package:flutter/material.dart';

/// A content-sized options sheet that remains scrollable on short displays.
/// The modal route owns the single Material drag handle.
class MediaOptionsSheet extends StatelessWidget {
  const MediaOptionsSheet({
    super.key,
    required this.title,
    required this.children,
    this.showCloseButton = true,
  });

  final String title;
  final List<Widget> children;
  final bool showCloseButton;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .8,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (showCloseButton)
                  IconButton(
                    tooltip: 'Close $title',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    ),
  );
}
