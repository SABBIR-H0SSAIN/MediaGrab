import 'package:flutter/widgets.dart';

/// Renders the app immediately and defers permission work until its first frame.
/// Android's native launch window is the only splash screen.
class AppStartup extends StatefulWidget {
  const AppStartup({
    super.key,
    required this.child,
    this.onReady,
    this.onBackground,
  });

  final Widget child;
  final VoidCallback? onReady;
  final VoidCallback? onBackground;

  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady?.call();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      widget.onBackground?.call();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
