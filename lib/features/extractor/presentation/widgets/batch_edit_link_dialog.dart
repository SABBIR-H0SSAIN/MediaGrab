import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// An explicit local edit; the draft does not change until Save is pressed.
class BatchEditLinkDialog extends StatefulWidget {
  const BatchEditLinkDialog({
    super.key,
    required this.initialUrl,
    required this.validate,
    this.videoTitle,
  });
  final String initialUrl;
  final String? videoTitle;
  final String? Function(String) validate;

  @override
  State<BatchEditLinkDialog> createState() => _BatchEditLinkDialogState();
}

class _BatchEditLinkDialogState extends State<BatchEditLinkDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _url;
  String? _clipboardError;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.initialUrl)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initialUrl.length,
      );
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _save() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, _url.text.trim());
    }
  }

  Future<void> _paste() async {
    try {
      final text =
          (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
      if (!mounted) return;
      if (text == null || text.isEmpty) {
        setState(() => _clipboardError = 'Clipboard is empty.');
        return;
      }
      setState(() => _clipboardError = null);
      _url.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      _form.currentState!.validate();
    } catch (_) {
      if (mounted) {
        setState(() => _clipboardError = 'Could not read the clipboard.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit video link'),
    scrollable: true,
    content: SizedBox(
      width: double.maxFinite,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.videoTitle?.isNotEmpty == true) ...[
              Text(
                widget.videoTitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              key: const ValueKey('batch_edit_url'),
              controller: _url,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              validator: (value) => widget.validate(value ?? ''),
              onFieldSubmitted: (_) => _save(),
              onChanged: (_) {
                if (_clipboardError != null) {
                  setState(() => _clipboardError = null);
                }
              },
              decoration: InputDecoration(
                labelText: 'Video URL',
                errorMaxLines: 3,
                suffixIcon: IconButton(
                  tooltip: 'Paste replacement link',
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste_rounded, size: 20),
                ),
              ),
            ),
            if (_clipboardError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _clipboardError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actionsAlignment: MainAxisAlignment.end,
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}
