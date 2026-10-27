import 'package:flutter/material.dart';

/// Bounded feedback keeps verbose media titles from becoming full-screen toasts.
/// The complete title stays in metadata, filenames, and the details view.
class MediaFeedbackContent extends StatelessWidget {
  const MediaFeedbackContent({super.key, required this.message, this.title});
  final String message;
  final String? title;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
      if (title?.trim().isNotEmpty == true) ...[
        const SizedBox(height: 4),
        Text(
          title!.replaceAll(RegExp(r'\s+'), ' ').trim(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ],
  );
}
