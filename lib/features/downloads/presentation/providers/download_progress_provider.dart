import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/download_task.dart';
import 'download_manager_provider.dart';

/// Per-task progress provider returning the current [DownloadTask] for [taskId],
/// or null if the task does not exist.
final downloadProgressProvider = Provider.family<DownloadTask?, String>((
  ref,
  taskId,
) {
  final tasks = ref.watch(downloadManagerProvider);
  for (final task in tasks) {
    if (task.id == taskId) {
      return task;
    }
  }
  return null;
});

/// Per-task progress fraction (0.0 to 1.0) provider for [taskId].
final downloadTaskProgressValueProvider = Provider.family<double, String>((
  ref,
  taskId,
) {
  final task = ref.watch(downloadProgressProvider(taskId));
  return task?.progress ?? 0.0;
});

/// Per-task speed formatted string provider for [taskId].
final downloadTaskSpeedProvider = Provider.family<String, String>((
  ref,
  taskId,
) {
  final task = ref.watch(downloadProgressProvider(taskId));
  return task?.formattedSpeed ?? '';
});

/// Per-task ETA formatted string provider for [taskId].
final downloadTaskEtaProvider = Provider.family<String, String>((
  ref,
  taskId,
) {
  final task = ref.watch(downloadProgressProvider(taskId));
  return task?.formattedEta ?? '';
});
