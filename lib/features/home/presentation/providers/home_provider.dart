import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/url_parser.dart';

/// Provider for the current URL input text field value.
final urlInputProvider = StateProvider<String>((ref) => '');

/// Provider that detects the media platform (YouTube, Facebook, Instagram, or unknown)
/// derived from the current [urlInputProvider] value.
final detectedPlatformProvider = Provider<PlatformType>((ref) {
  final url = ref.watch(urlInputProvider);
  return detectPlatform(url);
});

/// Provider indicating whether the URL is valid (not [PlatformType.unknown]).
final isValidUrlProvider = Provider<bool>((ref) {
  final platform = ref.watch(detectedPlatformProvider);
  return platform != PlatformType.unknown;
});

/// Future provider that retrieves text currently in the system clipboard.
final clipboardContentProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text?.trim();
  if (text != null && text.isNotEmpty) {
    return text;
  }
  return null;
});

/// Reads text from the system clipboard, updates [urlInputProvider],
/// and returns the pasted text, or null if clipboard was empty.
Future<String?> pasteFromClipboard(WidgetRef ref) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text?.trim() ?? '';
  if (text.isNotEmpty) {
    ref.read(urlInputProvider.notifier).state = text;
    return text;
  }
  return null;
}

/// StateNotifier managing the detected clipboard URL for the home clipboard banner.
class ClipboardBannerNotifier extends StateNotifier<String?> {
  ClipboardBannerNotifier() : super(null);

  String? _lastDismissedUrl;

  /// Checks the system clipboard for a supported media URL.
  Future<void> checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text != null && text.isNotEmpty) {
        final platform = detectPlatform(text);
        if (platform != PlatformType.unknown && text != _lastDismissedUrl) {
          state = text;
          return;
        }
      }
      if (text == _lastDismissedUrl) {
        return;
      }
      state = null;
    } catch (_) {
      // Ignore clipboard exceptions (e.g. platform restrictions)
      state = null;
    }
  }

  /// Dismisses the banner for the currently detected URL.
  void dismiss() {
    _lastDismissedUrl = state;
    state = null;
  }

  /// Consumes the detected URL when the user taps Extract or Paste.
  void consume() {
    _lastDismissedUrl = state;
    state = null;
  }

  /// Sets the detected URL explicitly (useful in tests or external events).
  void setDetectedUrl(String? url) {
    state = url;
  }
}

/// Provider for the clipboard banner state.
final clipboardBannerProvider =
    StateNotifierProvider<ClipboardBannerNotifier, String?>((ref) {
      return ClipboardBannerNotifier();
    });

/// Clears the URL input state.
void clearUrlInput(WidgetRef ref) {
  ref.read(urlInputProvider.notifier).state = '';
}
