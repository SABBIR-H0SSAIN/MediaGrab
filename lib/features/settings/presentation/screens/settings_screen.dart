import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/permission_utils.dart';
import '../../../../shared/widgets/brand_artwork.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings_section.dart';
import '../widgets/theme_selector.dart';

/// Full settings screen allowing users to configure Appearance, Download preferences,
/// and inspect application information and licenses.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const String githubRepoUrl = 'https://github.com/sabbir/mediagrab';

  void _showVideoQualityDialog(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) {
    const qualities = ['Best', '1080p', '720p', '480p', '360p', 'Audio Only'];

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Default Video Quality'),
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          content: RadioGroup<String>(
            groupValue: current,
            onChanged: (val) {
              if (val != null) {
                ref.read(settingsProvider.notifier).setDefaultVideoQuality(val);
                Navigator.of(dialogContext).pop();
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children:
                  qualities.map((quality) {
                    return RadioListTile<String>(
                      title: Text(quality),
                      value: quality,
                    );
                  }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showAudioFormatDialog(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) {
    const formats = ['MP3', 'M4A', 'OPUS'];

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Default Audio Format'),
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          content: RadioGroup<String>(
            groupValue: current,
            onChanged: (val) {
              if (val != null) {
                ref.read(settingsProvider.notifier).setDefaultAudioFormat(val);
                Navigator.of(dialogContext).pop();
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children:
                  formats.map((format) {
                    return RadioListTile<String>(
                      title: Text(format),
                      value: format,
                    );
                  }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _selectDownloadFolder(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final hasPermission =
        await PermissionUtils.checkAndRequestStoragePermission(context);
    if (!hasPermission && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Storage permission is required to save to custom directories. Please grant access.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    if (!context.mounted) return;
    final selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Download Folder',
    );
    if (selectedDirectory != null && selectedDirectory.trim().isNotEmpty) {
      final trimmed = selectedDirectory.trim();
      if (Platform.isAndroid) {
        final isWritable = await PermissionUtils.isFolderWritable(trimmed);
        if (!isWritable) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Selected folder is not writable by Android. Please grant All Files access or select another folder.',
                ),
                behavior: SnackBarBehavior.floating,
                action: SnackBarAction(
                  label: 'Retry Permission',
                  onPressed: () {
                    PermissionUtils.checkAndRequestStoragePermission(context);
                  },
                ),
              ),
            );
          }
          return;
        }
      }

      await ref.read(settingsProvider.notifier).setDownloadDirectory(trimmed);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download folder updated: $trimmed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openGitHub() async {
    final uri = Uri.parse(githubRepoUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  void _openLicenses(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: AppConstants.appName,
      applicationVersion: 'v${AppConstants.appVersion}',
      applicationIcon: const MediaGrabMark(size: 64),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final isLightMode = settings.themeMode == ThemeMode.light;

    final subColor = theme.colorScheme.onSurfaceVariant;
    final iconColor = theme.colorScheme.onSurfaceVariant;
    final textColor = theme.colorScheme.onSurface;
    final sliderInactive = theme.colorScheme.outlineVariant;

    final appVersion = ref
        .watch(appVersionProvider)
        .maybeWhen(
          data: (val) => val,
          orElse: () => 'v${AppConstants.appVersion}',
        );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        title: const Text(
          'Settings',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // Appearance Section
          SettingsSection(
            title: 'Appearance',
            children: [
              ListTile(
                leading: Icon(
                  Icons.brightness_medium_outlined,
                  color: iconColor,
                ),
                title: const Text(
                  'Theme mode',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                ),
                subtitle: Text(
                  settings.themeModeLabel,
                  style: TextStyle(color: subColor, fontSize: 12),
                ),
                trailing: Icon(Icons.chevron_right_rounded, color: iconColor),
                onTap: () => showThemeSelectorDialog(context),
              ),
              SwitchListTile(
                secondary: Icon(Icons.nightlight_outlined, color: iconColor),
                title: const Text(
                  'AMOLED Dark Mode',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                ),
                subtitle: Text(
                  isLightMode
                      ? 'Only available in Dark or System theme'
                      : 'Pure black background for OLED screens',
                  style: TextStyle(color: subColor, fontSize: 12),
                ),
                value: settings.amoledDark && !isLightMode,
                onChanged:
                    isLightMode
                        ? null
                        : (val) => ref
                            .read(settingsProvider.notifier)
                            .setAmoledDark(val),
              ),
              SwitchListTile(
                secondary: Icon(Icons.palette_outlined, color: iconColor),
                title: const Text(
                  'Dynamic Colors',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                ),
                subtitle: Text(
                  'Match with your wallpaper accent color',
                  style: TextStyle(color: subColor, fontSize: 12),
                ),
                value: settings.dynamicColors,
                onChanged:
                    (val) => ref
                        .read(settingsProvider.notifier)
                        .setDynamicColors(val),
              ),
            ],
          ),

          // Download Section
          SettingsSection(
            title: 'Download',
            children: [
              ListTile(
                leading: Icon(Icons.videocam_outlined, color: iconColor),
                title: const Text(
                  'Default Video Quality',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                ),
                subtitle: Text(
                  settings.defaultVideoQuality,
                  style: TextStyle(color: subColor, fontSize: 12),
                ),
                trailing: Icon(Icons.chevron_right_rounded, color: iconColor),
                onTap:
                    () => _showVideoQualityDialog(
                      context,
                      ref,
                      settings.defaultVideoQuality,
                    ),
              ),
              ListTile(
                leading: Icon(Icons.music_note_outlined, color: iconColor),
                title: const Text(
                  'Default Audio Format',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                ),
                subtitle: Text(
                  settings.defaultAudioFormat,
                  style: TextStyle(color: subColor, fontSize: 12),
                ),
                trailing: Icon(Icons.chevron_right_rounded, color: iconColor),
                onTap:
                    () => _showAudioFormatDialog(
                      context,
                      ref,
                      settings.defaultAudioFormat,
                    ),
              ),
              ListTile(
                leading: Icon(Icons.layers_outlined, color: iconColor),
                title: const Text(
                  'Max Concurrent Downloads',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: settings.maxConcurrentDownloads.toDouble(),
                          min: 1,
                          max: 5,
                          divisions: 4,
                          activeColor: theme.colorScheme.primary,
                          inactiveColor: sliderInactive,
                          thumbColor: theme.colorScheme.primary,
                          label: '${settings.maxConcurrentDownloads}',
                          onChanged: (val) {
                            ref
                                .read(settingsProvider.notifier)
                                .setMaxConcurrentDownloads(val.round());
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${settings.maxConcurrentDownloads}',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SwitchListTile(
                secondary: Icon(
                  Icons.signal_cellular_alt_rounded,
                  color: iconColor,
                ),
                title: const Text(
                  'Download over cellular',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                ),
                subtitle: Text(
                  settings.downloadOverCellular
                      ? 'Allow downloading using mobile data'
                      : 'Download over Wi-Fi only',
                  style: TextStyle(color: subColor, fontSize: 12),
                ),
                value: settings.downloadOverCellular,
                onChanged:
                    (val) => ref
                        .read(settingsProvider.notifier)
                        .setDownloadOverCellular(val),
              ),
            ],
          ),

          SettingsSection(
            title: 'Storage',
            children: [
              ListTile(
                leading: Icon(Icons.folder_open_rounded, color: iconColor),
                title: const Text(
                  'Storage Location',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                ),
                subtitle: Text(
                  settings.downloadDirectory.isNotEmpty
                      ? settings.downloadDirectory
                      : 'Default (${AppConstants.defaultDownloadDirectory})',
                  style: TextStyle(color: subColor, fontSize: 12),
                ),
                trailing:
                    settings.downloadDirectory.isNotEmpty
                        ? IconButton(
                          icon: Icon(Icons.clear_rounded, color: iconColor),
                          tooltip: 'Reset Default',
                          onPressed: () async {
                            await ref
                                .read(settingsProvider.notifier)
                                .setDownloadDirectory('');
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Download folder reset to default',
                                  ),
                                ),
                              );
                            }
                          },
                        )
                        : Icon(Icons.chevron_right_rounded, color: iconColor),
                onTap: () => _selectDownloadFolder(context, ref),
              ),
            ],
          ),

          // About Section
          SettingsSection(
            title: 'About',
            children: [
              ListTile(
                leading: const MediaGrabMark(size: 32),
                title: const Text(
                  'App version',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                ),
                subtitle: Text(
                  appVersion,
                  style: TextStyle(color: subColor, fontSize: 12),
                ),
              ),
              ListTile(
                leading: Icon(Icons.code_rounded, color: iconColor),
                title: const Text(
                  'GitHub',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                ),
                subtitle: Text(
                  'Source code & project tracker',
                  style: TextStyle(color: subColor, fontSize: 12),
                ),
                trailing: Icon(
                  Icons.open_in_new_rounded,
                  size: 20,
                  color: iconColor,
                ),
                onTap: _openGitHub,
              ),
              ListTile(
                leading: Icon(Icons.description_outlined, color: iconColor),
                title: const Text(
                  'Licenses',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                ),
                subtitle: Text(
                  'Open source licenses & attributions',
                  style: TextStyle(color: subColor, fontSize: 12),
                ),
                trailing: Icon(Icons.chevron_right_rounded, color: iconColor),
                onTap: () => _openLicenses(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
