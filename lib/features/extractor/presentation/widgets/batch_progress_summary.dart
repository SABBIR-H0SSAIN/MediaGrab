import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/file_utils.dart';
import '../../../downloads/domain/enums/download_status.dart';
import '../../../downloads/presentation/providers/download_manager_provider.dart';

/// Only this dashboard and individual cards subscribe to high-frequency events.
class BatchProgressSummary extends ConsumerWidget {
  const BatchProgressSummary({super.key, required this.taskIds});
  final Set<String> taskIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks =
        ref
            .watch(downloadManagerProvider)
            .where((t) => taskIds.contains(t.id))
            .toList();
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    final active = tasks.where((t) => t.status.isActive).length;
    final completed = tasks.where((t) => t.status.isCompleted).length;
    final downloaded = tasks.fold<int>(
      0,
      (sum, t) => sum + (t.downloadedBytes ?? 0),
    );
    final total = tasks.fold<int>(0, (sum, t) => sum + (t.totalBytes ?? 0));
    final known =
        tasks.isNotEmpty && tasks.every((t) => (t.totalBytes ?? 0) > 0);
    final speed = tasks
        .where((t) => t.status == DownloadStatus.downloading)
        .fold<double>(0, (sum, t) => sum + (t.speedBytesPerSecond ?? 0));
    final progress =
        tasks.isEmpty
            ? 0.0
            : known
            ? tasks.fold<double>(
                  0,
                  (sum, t) => sum + t.progress.clamp(0, 1) * t.totalBytes!,
                ) /
                total
            : tasks.fold<double>(0, (sum, t) => sum + t.progress.clamp(0, 1)) /
                tasks.length;
    final remaining = tasks
        .where((t) => !t.status.isCompleted)
        .fold<int>(
          0,
          (sum, t) =>
              sum +
              ((t.totalBytes ?? 0) - (t.downloadedBytes ?? 0)).clamp(
                0,
                1 << 60,
              ),
        );
    final eta =
        known &&
                speed > 0 &&
                !tasks.any((t) => t.status.isPaused || t.status.isFailed)
            ? '~${formatDuration(Duration(seconds: (remaining / speed).ceil()))}'
            : '—';
    Widget metric(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(value, style: theme.titleSmall),
      ],
    );
    return Container(
      key: const ValueKey('batch_progress_summary'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$completed of ${tasks.length} complete',
                  style: theme.titleSmall,
                ),
              ),
              Text(
                '${(progress * 100).toStringAsFixed(1)}%',
                style: theme.titleSmall?.copyWith(color: colors.primary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$active active',
            style: theme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress.clamp(0, 1),
            minHeight: 6,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final metrics = [
                metric(
                  'Speed',
                  speed > 0 ? '${formatFileSize(speed.round())}/s' : '—',
                ),
                metric('Downloaded', formatFileSize(downloaded)),
                metric('Remaining', eta),
              ];
              // Larger accessibility text gets additional room without shrinking it.
              if (MediaQuery.textScalerOf(context).scale(14) > 20) {
                return Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: metrics[0]),
                        const SizedBox(width: 12),
                        Expanded(child: metrics[1]),
                      ],
                    ),
                    const SizedBox(height: 10),
                    metrics[2],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final m in metrics) Expanded(child: m)],
              );
            },
          ),
        ],
      ),
    );
  }
}
