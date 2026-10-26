/// Supported video/media platforms
enum PlatformType { youtube, facebook, instagram, unknown }

/// Extension providing display name and validation helper for [PlatformType].
extension PlatformTypeExtension on PlatformType {
  String get displayName {
    switch (this) {
      case PlatformType.youtube:
        return 'YouTube';
      case PlatformType.facebook:
        return 'Facebook';
      case PlatformType.instagram:
        return 'Instagram';
      case PlatformType.unknown:
        return 'Unknown';
    }
  }

  bool get isValid => this != PlatformType.unknown;
}

/// Detects the target platform from a given URL string.
///
/// Supported patterns:
/// - YouTube: youtube.com/watch, youtu.be/, youtube.com/shorts/,
///   youtube.com/playlist, youtube.com/channel/, youtube.com/@, m.youtube.com
/// - Facebook: facebook.com, fb.watch, fb.com, m.facebook.com, web.facebook.com
/// - Instagram: instagram.com/p/, instagram.com/reel/, instagram.com/stories/, instagram.com/tv/
///
/// Returns [PlatformType.unknown] for unrecognized or invalid URLs.
PlatformType detectPlatform(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return PlatformType.unknown;
  }

  // Prepend https:// if no scheme is provided to allow Uri.tryParse to correctly parse host and path
  final uriString = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  final uri = Uri.tryParse(uriString);
  if (uri == null || uri.host.isEmpty || uri.host.contains(' ')) {
    return PlatformType.unknown;
  }

  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();

  // YouTube
  final isYouTubeHost =
      host == 'youtube.com' ||
      host.endsWith('.youtube.com') ||
      host == 'youtu.be' ||
      host.endsWith('.youtu.be');

  if (isYouTubeHost) {
    if (host == 'youtu.be' || host.endsWith('.youtu.be')) {
      return PlatformType.youtube;
    }
    if (host == 'm.youtube.com') {
      return PlatformType.youtube;
    }
    if (path.startsWith('/watch') ||
        path.startsWith('/shorts') ||
        path.startsWith('/live') ||
        path.startsWith('/playlist') ||
        path.startsWith('/channel') ||
        path.startsWith('/@') ||
        path.startsWith('/embed') ||
        path.startsWith('/v/')) {
      return PlatformType.youtube;
    }
    if (uri.queryParameters.containsKey('v')) {
      return PlatformType.youtube;
    }
  }

  // Facebook
  final isFacebookHost =
      host == 'facebook.com' ||
      host.endsWith('.facebook.com') ||
      host == 'fb.watch' ||
      host.endsWith('.fb.watch') ||
      host == 'fb.com' ||
      host.endsWith('.fb.com') ||
      host == 'fb.gg' ||
      host.endsWith('.fb.gg');

  if (isFacebookHost) {
    return PlatformType.facebook;
  }

  // Instagram
  final isInstagramHost =
      host == 'instagram.com' ||
      host.endsWith('.instagram.com') ||
      host == 'instagr.am' ||
      host.endsWith('.instagr.am');

  if (isInstagramHost) {
    if (path.startsWith('/p/') ||
        path == '/p' ||
        path.startsWith('/reel/') ||
        path == '/reel' ||
        path.startsWith('/reels/') ||
        path == '/reels' ||
        path.startsWith('/stories/') ||
        path == '/stories' ||
        path.startsWith('/tv/') ||
        path == '/tv' ||
        path.contains('/reel/') ||
        path.contains('/reels/') ||
        path.contains('/p/') ||
        path.startsWith('/share/reel') ||
        path.startsWith('/share/p')) {
      return PlatformType.instagram;
    }
  }

  return PlatformType.unknown;
}
