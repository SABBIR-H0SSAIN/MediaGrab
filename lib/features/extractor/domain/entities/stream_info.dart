import 'package:equatable/equatable.dart';

/// Immutable entity representing an individual downloadable media stream.
class StreamInfo extends Equatable {
  final String url;
  final String qualityLabel;
  final String codec;
  final String container;
  final int? sizeInBytes;
  final bool isAudioOnly;
  final int? bitrate;
  final int? videoWidth;
  final int? videoHeight;
  final bool isVideoOnly;

  const StreamInfo({
    required this.url,
    required this.qualityLabel,
    required this.codec,
    required this.container,
    this.sizeInBytes,
    this.isAudioOnly = false,
    this.bitrate,
    this.videoWidth,
    this.videoHeight,
    this.isVideoOnly = false,
  });

  /// Formatted size string (e.g. "45.2 MB", "1.2 GB", "850 KB").
  String get formattedSize {
    if (sizeInBytes == null || sizeInBytes! <= 0) {
      return 'Unknown size';
    }
    final bytes = sizeInBytes!;
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    if (mb < 1024) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }

  /// Formatted bitrate string (e.g. "128 kbps", "320 kbps").
  String get formattedBitrate {
    if (bitrate == null || bitrate! <= 0) return '';
    final kbps = (bitrate! / 1000).round();
    return '$kbps kbps';
  }

  @override
  List<Object?> get props => [
    url,
    qualityLabel,
    codec,
    container,
    sizeInBytes,
    isAudioOnly,
    bitrate,
    videoWidth,
    videoHeight,
    isVideoOnly,
  ];
}
