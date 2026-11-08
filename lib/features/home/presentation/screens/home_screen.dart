import '../../../../shared/widgets/brand_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/widgets/hero_background.dart';
import '../../../../core/utils/permission_utils.dart';
import '../../../../core/utils/url_parser.dart';
import '../providers/home_provider.dart';
import '../widgets/quick_actions_row.dart';
import '../widgets/recent_downloads_section.dart';
import '../widgets/url_input_card.dart';

/// Full Home screen implementation matching the modern design in the reference screenshot:
/// - Top Bar with MediaGrab gradient logo and (i) info icon
/// - Aurora luminous background wave
/// - Hero title: "Download videos, fast and simple"
/// - Hero URL Input Card with "Analyze & Download" gradient button
/// - Platforms Row (YouTube, Facebook, Instagram, More)
/// - Feature Cards (Batch Download, Playlists)
/// - Recent Downloads Section
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _checkAndAutoPaste();
      PermissionUtils.checkAndRequestStoragePermission(context);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndAutoPaste();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String? _lastClipboardUrl;

  Future<void> _checkAndAutoPaste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isNotEmpty) {
        final platform = detectPlatform(text);
        if (mounted &&
            platform != PlatformType.unknown &&
            text != _lastClipboardUrl) {
          final currentInput = ref.read(urlInputProvider).trim();
          // A newly copied link may refresh an earlier automatic paste, but
          // returning to the app must never replace the user's typed draft.
          if (currentInput.isNotEmpty && currentInput != _lastClipboardUrl) {
            return;
          }
          _lastClipboardUrl = text;
          ref.read(urlInputProvider.notifier).state = text;
        }
      }
    } catch (_) {
      // Ignore platform clipboard access errors
    }
  }

  void _showInfoDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          title: Row(
            children: [
              const MediaGrabMark(size: 36),
              const SizedBox(width: 12),
              Text(
                AppConstants.appName,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'High-performance media downloader for Android.\n\n'
                '• Download videos up to 4K resolution\n'
                '• High-quality audio extraction (MP3 / M4A)\n'
                '• YouTube, Facebook & Instagram supported\n'
                '• Automatic FFmpeg stream merging',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Close',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headingColor = theme.colorScheme.onSurface;
    final infoIconColor = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HeroBackground(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: MediaQuery.paddingOf(context).top + 20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Bar: Logo + MediaGrab + (i) Info icon
                      Row(
                            children: [
                              const MediaGrabMark(size: 36),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  AppConstants.appName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: headingColor,
                                    letterSpacing: -.4,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'About MediaGrab',
                                icon: Icon(
                                  Icons.info_outline_rounded,
                                  color: infoIconColor,
                                  size: 22,
                                ),
                                onPressed: () => _showInfoDialog(context),
                              ),
                            ],
                          )
                          .animate()
                          .fadeIn(duration: 300.ms, curve: Curves.easeOut)
                          .slideY(
                            begin: -0.05,
                            end: 0,
                            duration: 300.ms,
                            curve: Curves.easeOut,
                          ),

                      const SizedBox(height: 16),

                      SizedBox(
                        height: 128,
                        width: double.infinity,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 12, top: 18),
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    const TextSpan(text: 'Download videos,\n'),
                                    TextSpan(
                                      text: 'fast',
                                      style: TextStyle(
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                    const TextSpan(text: ' and simple'),
                                  ],
                                ),
                                style: TextStyle(
                                  fontSize: 26,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                  color: headingColor,
                                  letterSpacing: -.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const UrlInputCard(),
                    const SizedBox(height: 20),
                    QuickActionsRow(),
                    const SizedBox(height: 16),
                    RecentDownloadsSection(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
