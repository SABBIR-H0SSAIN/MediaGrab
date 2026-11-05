import 'package:flutter/material.dart';

class BatchQualityOption<T> {
  const BatchQualityOption({
    required this.value,
    required this.label,
    this.detail,
  });
  final T value;
  final String label;
  final String? detail;
}

/// Default batch preferences use a bounded, scrollable selection surface.
Future<T?> showBatchQualityPicker<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<BatchQualityOption<T>> options,
  required T? selected,
}) {
  FocusScope.of(context).unfocus();
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder:
        (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight:
                    (MediaQuery.sizeOf(context).height -
                        MediaQuery.viewInsetsOf(context).bottom) *
                    .7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close quality selector',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  if (subtitle?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      itemCount: options.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 2),
                      itemBuilder: (context, index) {
                        final option = options[index];
                        final current = option.value == selected;
                        return ListTile(
                          key: ValueKey('batch_quality_option_$index'),
                          minVerticalPadding: 12,
                          selected: current,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          selectedTileColor:
                              Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHigh,
                          title: Text(
                            option.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle:
                              option.detail == null
                                  ? null
                                  : Text(
                                    option.detail!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          trailing: Icon(
                            current
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked,
                            color:
                                current
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.outline,
                          ),
                          onTap: () => Navigator.pop(context, option.value),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
  );
}
