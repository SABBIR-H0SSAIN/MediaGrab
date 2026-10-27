import 'package:flutter/material.dart';

/// Consistent compact URL field used on Home and in the playlist dialog.
class MediaLinkField extends StatelessWidget {
  const MediaLinkField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onPaste,
    required this.onClear,
    this.onChanged,
    this.onSubmitted,
    this.errorText,
    this.focusNode,
    this.alwaysShowPaste = false,
    this.maxLines = 1,
    this.emphasized = false,
  });

  final TextEditingController controller;
  final String hintText;
  final VoidCallback onPaste, onClear;
  final ValueChanged<String>? onChanged, onSubmitted;
  final String? errorText;
  final FocusNode? focusNode;
  final bool alwaysShowPaste;
  final int maxLines;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(16);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.done,
      autocorrect: false,
      enableSuggestions: false,
      minLines: 1,
      maxLines: maxLines,
      style: TextStyle(color: scheme.onSurface, fontSize: 13),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        floatingLabelBehavior: FloatingLabelBehavior.never,
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        prefixIcon: Icon(Icons.link, size: 20, color: scheme.onSurfaceVariant),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder:
              (context, value, _) => IconButton(
                tooltip:
                    value.text.isEmpty || alwaysShowPaste
                        ? 'Paste from clipboard'
                        : 'Clear',
                icon: Icon(
                  value.text.isEmpty || alwaysShowPaste
                      ? Icons.content_paste_rounded
                      : Icons.close,
                  size: 20,
                  color:
                      value.text.isEmpty || alwaysShowPaste
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                ),
                onPressed:
                    value.text.isEmpty || alwaysShowPaste ? onPaste : onClear,
              ),
        ),
        border: OutlineInputBorder(borderRadius: radius),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(
            color:
                emphasized
                    ? scheme.primary.withValues(alpha: .65)
                    : scheme.outlineVariant,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        errorText: errorText,
        errorMaxLines: 2,
      ),
    );
  }
}
