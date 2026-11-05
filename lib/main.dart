import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/services/download_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DownloadNotificationService.instance.init(requestPermission: false);
  runApp(
    ProviderScope(
      child: MediaGrabApp(
        // Android owns the only splash; Flutter renders the destination directly.
        onReady: DownloadNotificationService.instance.requestPermission,
      ),
    ),
  );
}
