import 'package:equatable/equatable.dart';
import '../../../../core/utils/url_parser.dart';

/// Immutable entity representing extracted media metadata.
class MediaInfo extends Equatable {
  final String id;
  final String title;
  final String thumbnailUrl;
  final Duration duration;
  final String uploader;
  final PlatformType platform;
  final DateTime? uploadDate;
  final int? viewCount;
  final String? description;

  const MediaInfo({
    required this.id,
    required this.title,
    required this.thumbnailUrl,
    required this.duration,
    required this.uploader,
    required this.platform,
    this.uploadDate,
    this.viewCount,
    this.description,
  });

  /// Formatted duration string (e.g. "3:45" or "1:12:30").
  String get formattedDuration {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
  }

  /// Formatted view count string (e.g. "1.2M", "450K", "1,234").
  String get formattedViews {
    if (viewCount == null) return '';
    final count = viewCount!;
    if (count >= 1000000000) {
      return '${(count / 1000000000).toStringAsFixed(1).replaceAll('.0', '')}B views';
    } else if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1).replaceAll('.0', '')}M views';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1).replaceAll('.0', '')}K views';
    } else {
      return '$count views';
    }
  }

  @override
  List<Object?> get props => [
    id,
    title,
    thumbnailUrl,
    duration,
    uploader,
    platform,
    uploadDate,
    viewCount,
    description,
  ];
}
