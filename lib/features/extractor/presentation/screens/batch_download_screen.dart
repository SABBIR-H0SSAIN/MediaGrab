import 'dart:async';
import '../../../../core/utils/url_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/utils/file_utils.dart';
import '../../../../core/utils/media_error_message.dart';
import '../../../../shared/widgets/media_link_field.dart';
import '../../../../shared/widgets/brand_artwork.dart';
import '../widgets/batch_edit_link_dialog.dart';
import '../widgets/batch_quality_picker.dart';
import '../widgets/quality_selector_sheet.dart';
import '../../../../shared/widgets/media_feedback_content.dart';
import '../../../downloads/domain/enums/download_status.dart';
import '../../../downloads/presentation/providers/download_progress_provider.dart';
import '../widgets/batch_progress_summary.dart';
import '../../../downloads/presentation/providers/download_manager_provider.dart';
import '../../domain/entities/stream_info.dart';
import '../providers/batch_preparation_provider.dart';
import '../utils/batch_download_helper.dart';
import '../utils/video_quality_options.dart';

class BatchDownloadScreen extends ConsumerStatefulWidget {
  const BatchDownloadScreen({super.key});
  @override
  ConsumerState<BatchDownloadScreen> createState() =>
      _BatchDownloadScreenState();
}

class _BatchDownloadScreenState extends ConsumerState<BatchDownloadScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  Timer? _inputDebounce;
  final _scroll = ScrollController();
  String? _inputError;
  String? _inputNotice;
  bool _submitting = false;
  BatchPreparationController get controller =>
      ref.read(batchPreparationProvider.notifier);
  @override
  void dispose() {
    _inputDebounce?.cancel();
    _scroll.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _type(String text) {
    _inputDebounce?.cancel();
    setState(() {
      _inputError = null;
      _inputNotice = null;
    });
    if (ref.read(batchPreparationProvider).autoAdd && text.trim().isNotEmpty) {
      _inputDebounce = Timer(
        const Duration(milliseconds: 600),
        () => _consumeInput(completed: false),
      );
    }
  }

  void _consumeInput({bool completed = true}) {
    _inputDebounce?.cancel();
    if (!mounted || _input.text.trim().isEmpty) return;
    final text = _input.text;
    final parts = text.trim().split(RegExp(r'[\s,]+'));
    final links = <String>[];
    final remaining = <String>[];
    for (var index = 0; index < parts.length; index++) {
      final part = parts[index];
      final explicit =
          completed ||
          index < parts.length - 1 ||
          RegExp(r'[\s,]$').hasMatch(text);
      final platform = detectPlatform(part);
      final valid = isCompleteBatchVideoUrl(part);
      // Variable-length social IDs are consumed only at an explicit boundary.
      if (!valid || (!explicit && platform != PlatformType.youtube)) {
        remaining.add(part);
      } else {
        links.add(part);
      }
    }
    final duplicates = links.isEmpty ? 0 : controller.paste(links.join('\n'));
    if (links.isNotEmpty) {
      _input.value = TextEditingValue(
        text: remaining.join(' '),
        selection: TextSelection.collapsed(offset: remaining.join(' ').length),
      );
      controller.check();
    }
    setState(() {
      _inputError =
          completed && remaining.isNotEmpty
              ? 'Enter complete YouTube, Facebook or Instagram video links.'
              : null;
      final added = links.length - duplicates;
      _inputNotice = [
        if (added > 0)
          '${added == 1 ? 'Video' : '$added videos'} added to batch.',
        if (duplicates > 0)
          '$duplicates duplicate ${duplicates == 1 ? 'link' : 'links'} skipped.',
        if (remaining.isNotEmpty && !completed)
          'Finish the link, then press Done.',
      ].where((text) => text.isNotEmpty).join(' ');
      if (_inputNotice!.isEmpty) _inputNotice = null;
    });
    final added = links.length - duplicates;
    if (added > 0) {
      _message(added == 1 ? 'Added 1 video' : 'Added $added videos');
    } else if (duplicates > 0) {
      _message('Already in this batch.');
    }
  }

  Future<void> _paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty) {
        _message('Clipboard is empty.');
        return;
      }
      _input.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      if (ref.read(batchPreparationProvider).autoAdd) {
        _consumeInput();
      } else {
        setState(() {
          _inputError = null;
          _inputNotice = 'Links pasted. Press Done to add them to the batch.';
        });
      }
    } catch (_) {
      if (mounted) {
        _message('Clipboard could not be read. Paste or type a link instead.');
      }
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: MediaFeedbackContent(message: text)));
  }

  Future<void> _download() async {
    final selected = ref.read(batchPreparationProvider).selected;
    if (_submitting || selected.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      final tasks = await enqueueBatchMediaDownloads(
        ref: ref,
        prepared: selected.map((i) => i.prepared).toList(),
        onItemQueued: (url, task) {
          final item =
              selected
                  .where((i) => normalizeBatchUrl(i.url) == url)
                  .firstOrNull;
          if (item != null) controller.attachTask(item.id, task);
        },
        onItemError: (url, error) {
          for (final item in selected.where(
            (i) => normalizeBatchUrl(i.url) == url,
          )) {
            controller.queueError(item.id, error);
          }
        },
      );
      if (!mounted) return;
      for (final task in tasks) {
        final item =
            selected
                .where(
                  (i) =>
                      i.media?.id == task.mediaInfo.id &&
                      i.selected?.url == task.selectedStream.url,
                )
                .firstOrNull;
        if (item != null &&
            ref
                .read(batchPreparationProvider)
                .items
                .any((i) => i.id == item.id && i.taskId == null)) {
          controller.attachTask(item.id, task);
        }
      }
      controller.syncTasks(
        ref.read(downloadManagerProvider),
        (id) => ref.read(downloadManagerProvider.notifier).retryDownload(id),
      );
      if (tasks.isNotEmpty) {
        ref.read(downloadsSelectedTabProvider.notifier).state = 0;
        _message(
          'Started ${tasks.length} ${tasks.length == 1 ? 'download' : 'downloads'}.',
        );
      } else {
        _message('No downloads queued. Review each failed item.');
      }
    } catch (error) {
      if (mounted) _message(mediaErrorMessage(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _control(Future<bool> Function() action) async {
    try {
      final accepted = await action();
      if (!accepted && mounted) {
        _message('This download cannot perform that action right now.');
      }
    } catch (error) {
      if (mounted) _message(mediaErrorMessage(error));
    }
  }

  Future<void> _retry(BatchItem item) async {
    try {
      if (item.taskId != null && item.task != null) {
        await ref
            .read(downloadManagerProvider.notifier)
            .retryDownload(item.taskId!);
      } else {
        if (item.taskId != null) controller.resetInterrupted(item.id);
        await controller.check(onlyId: item.id);
      }
    } catch (error) {
      if (mounted) _message(mediaErrorMessage(error));
    }
  }

  void _removeItem(BatchItem item) {
    final task =
        item.taskId == null
            ? null
            : ref.read(downloadProgressProvider(item.taskId!));
    if (task != null &&
        (task.status.isActive ||
            task.status.isQueued ||
            task.status.isPaused)) {
      _message('Cancel this download before removing it from the batch.');
      return;
    }
    controller.remove(item.id, removeInterrupted: task == null);
    _message('Video removed from batch.');
  }

  Future<bool> _confirm(
    String title,
    String description,
    String action,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(title),
              content: Text(description),
              actionsAlignment: MainAxisAlignment.end,
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep videos'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(action),
                ),
              ],
            ),
      ) ??
      false;

  Future<void> _clearAll() async {
    if (!await _confirm(
      'Clear batch?',
      'Remove prepared and finished entries from this batch? Active and paused downloads will stay here. Downloaded files are kept.',
      'Clear',
    )) {
      return;
    }
    if (!mounted) return;
    controller.clearPreparation();
    _input.clear();
    setState(() {
      _inputError = null;
      _inputNotice = null;
    });
  }

  Future<void> _batchControl({bool cancel = false}) async {
    if (cancel &&
        !await _confirm(
          'Cancel all batch downloads?',
          'Stop active, queued and paused downloads in this batch? Completed files are kept.',
          'Cancel all',
        )) {
      return;
    }
    if (!mounted) return;
    final manager = ref.read(downloadManagerProvider.notifier);
    final ids =
        ref.read(batchPreparationProvider).items.map((i) => i.taskId).toSet();
    final tasks =
        ref
            .read(downloadManagerProvider)
            .where((t) => ids.contains(t.id))
            .toList();
    final pause = tasks.any(
      (t) => t.status == DownloadStatus.downloading || t.status.isQueued,
    );
    // Pause queued work first, so releasing a slot cannot start another batch job.
    tasks.sort(
      (a, b) =>
          (a.status.isQueued ? 0 : 1).compareTo(b.status.isQueued ? 0 : 1),
    );
    for (final task in tasks) {
      if (cancel &&
          (task.status.isActive ||
              task.status.isQueued ||
              task.status.isPaused ||
              task.status.isFailed)) {
        await _control(() => manager.cancelDownload(task.id));
      } else if (!cancel &&
          pause &&
          (task.status == DownloadStatus.downloading || task.status.isQueued)) {
        await _control(() => manager.pauseDownload(task.id));
      } else if (!cancel && !pause && task.status.isPaused) {
        await _control(() => manager.resumeDownload(task.id));
      }
    }
  }

  bool _editable(BatchItem item) {
    if (item.taskId == null) return true;
    final task = ref.read(downloadProgressProvider(item.taskId!)) ?? item.task;
    return task?.status.isFailed == true || task?.status.isCancelled == true;
  }

  Future<void> _edit(BatchItem item) async {
    _inputDebounce?.cancel();
    FocusScope.of(context).unfocus();
    final updated = await showDialog<String>(
      context: context,
      builder:
          (_) => BatchEditLinkDialog(
            initialUrl: item.url,
            videoTitle: item.media?.title,
            validate: (value) {
              if (!isCompleteBatchVideoUrl(value)) {
                return 'Enter one complete YouTube, Facebook or Instagram video link.';
              }
              if (ref
                  .read(batchPreparationProvider)
                  .items
                  .any(
                    (i) =>
                        i.id != item.id &&
                        batchUrlKey(i.url) == batchUrlKey(value),
                  )) {
                return 'This video is already in the batch.';
              }
              return null;
            },
          ),
    );
    if (!mounted || updated == null) return;
    final current =
        ref
            .read(batchPreparationProvider)
            .items
            .where((i) => i.id == item.id)
            .firstOrNull;
    if (current == null || !_editable(current)) {
      _message('This video cannot be edited while downloading.');
      return;
    }
    if (normalizeBatchUrl(current.url) == normalizeBatchUrl(updated)) return;
    controller.edit(item.id, normalizeBatchUrl(updated));
    unawaited(controller.check(onlyId: item.id));
    _message('Video link updated.');
  }

  Future<void> _chooseQuality(BatchItem item) async {
    _inputDebounce?.cancel();
    FocusScope.of(context).unfocus();
    StreamInfo? companion;
    final selected = await QualitySelectorSheet.show(
      context,
      url: normalizeBatchUrl(item.url),
      prefetchedStreams: item.streams,
      initialSelection: item.selected,
      initialAudioStream: item.audio,
      initialIsAudio: item.selected?.isAudioOnly ?? false,
      selectionOnly: true,
      onDownloadWithAudio: (_, audio) => companion = audio,
    );
    if (!mounted || selected == null) return;
    final current =
        ref
            .read(batchPreparationProvider)
            .items
            .where((i) => i.id == item.id)
            .firstOrNull;
    if (current == null ||
        current.revision != item.revision ||
        !_editable(current)) {
      return;
    }
    controller.choose(item.id, selected, companion);
  }

  Widget _quality(BatchItem item) => TextButton(
    key: ValueKey('batch_item_quality_${item.id}'),
    onPressed:
        !_submitting && _editable(item) ? () => _chooseQuality(item) : null,
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            '${item.selected?.qualityLabel ?? 'Choose quality'}${item.overridden ? ' · Custom' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.expand_more, size: 18),
      ],
    ),
  );

  Widget _card(BatchItem prepared) => Consumer(
    builder: (context, ref, _) {
      final live =
          prepared.taskId == null
              ? null
              : ref.watch(downloadProgressProvider(prepared.taskId!));
      final item =
          live == null
              ? prepared
              : prepared.copy(
                task: live,
                audio: prepared.audio,
                error: prepared.error,
                notice: prepared.notice,
              );
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final task = item.task;
      final interrupted = item.taskId != null && task == null;
      final failed =
          interrupted ||
          item.status == BatchItemStatus.failed ||
          (task?.status.isFailed ?? false);
      final checking = item.status == BatchItemStatus.checking;
      final active = item.taskId != null;
      final locked =
          active &&
          (task == null ||
              !(task.status.isCompleted ||
                  task.status.isFailed ||
                  task.status.isCancelled));
      final status =
          task?.status.displayName ??
          (interrupted
              ? 'Interrupted'
              : checking
              ? 'Checking'
              : failed
              ? 'Failed'
              : item.status == BatchItemStatus.ready
              ? 'Ready'
              : 'Waiting to check');
      final error =
          task?.errorMessage ??
          item.error ??
          (interrupted
              ? 'Interrupted download. Retry to check the link again.'
              : null);
      return Card(
        key: ValueKey('batch_item_${item.id}'),
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 0,
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: .45)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: LayoutBuilder(
            builder:
                (context, constraints) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: constraints.maxWidth < 300 ? 88 : 104,
                          height: 72,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ColoredBox(
                                  color: colors.surfaceContainerHighest,
                                  child:
                                      item.media?.thumbnailUrl.isNotEmpty ==
                                              true
                                          ? CachedNetworkImage(
                                            imageUrl: item.media!.thumbnailUrl,
                                            fit: BoxFit.cover,
                                            errorWidget:
                                                (_, _, _) => const Icon(
                                                  Icons.video_library_outlined,
                                                ),
                                          )
                                          : const Icon(
                                            Icons.video_library_outlined,
                                          ),
                                ),
                                if (item.media != null &&
                                    item.media!.duration > Duration.zero)
                                  Positioned(
                                    right: 4,
                                    bottom: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colors.scrim.withValues(
                                          alpha: .8,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        formatDuration(item.media!.duration),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight:
                                      MediaQuery.textScalerOf(context).scale(
                                        theme.textTheme.titleSmall?.fontSize ??
                                            14,
                                      ) *
                                      (theme.textTheme.titleSmall?.height ??
                                          1.4) *
                                      2,
                                ),
                                child: Text(
                                  item.media?.title ?? item.url,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.media == null
                                    ? detectPlatform(item.url).displayName
                                    : [
                                      item.media!.platform.displayName,
                                      item.media!.uploader,
                                    ].where((v) => v.isNotEmpty).join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$status${active ? ' · ${task?.selectedStream.qualityLabel ?? item.selected?.qualityLabel ?? ''}' : ''}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color:
                                      failed
                                          ? colors.error
                                          : item.status ==
                                                  BatchItemStatus.ready &&
                                              !active
                                          ? colors.primary
                                          : colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (!active && !failed) ...[
                      const SizedBox(height: 12),
                      Divider(
                        height: 1,
                        color: colors.outlineVariant.withValues(alpha: .4),
                      ),
                      Row(
                        children: [
                          Semantics(
                            label: 'Include ${item.media?.title ?? 'video'}',
                            child: Checkbox(
                              value: item.included,
                              onChanged:
                                  _submitting
                                      ? null
                                      : (value) => controller.include(
                                        item.id,
                                        value ?? false,
                                      ),
                            ),
                          ),
                          Expanded(
                            child:
                                item.selected == null
                                    ? const SizedBox.shrink()
                                    : Align(
                                      alignment: Alignment.centerLeft,
                                      child: _quality(item),
                                    ),
                          ),
                          IconButton(
                            tooltip: 'Edit link',
                            onPressed: _submitting ? null : () => _edit(item),
                            color: colors.onSurfaceVariant,
                            icon: const Icon(Icons.edit_outlined, size: 20),
                          ),
                          IconButton(
                            tooltip: 'Delete video',
                            onPressed:
                                _submitting ? null : () => _removeItem(item),
                            color: colors.onSurfaceVariant,
                            icon: const Icon(Icons.delete_outline, size: 20),
                          ),
                        ],
                      ),
                    ],
                    if (task != null &&
                        !failed &&
                        !task.status.isCancelled) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(4),
                        value:
                            task.status == DownloadStatus.merging ||
                                    task.status == DownloadStatus.converting ||
                                    (task.status ==
                                            DownloadStatus.downloading &&
                                        (task.totalBytes ?? 0) <= 0)
                                ? null
                                : task.progress.clamp(0, 1),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Text(
                            '${task.formattedProgress} · ${formatFileSize(task.downloadedBytes ?? 0)} / ${(task.totalBytes ?? 0) > 0 ? formatFileSize(task.totalBytes!) : 'Unknown size'}',
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(
                            task.status == DownloadStatus.downloading
                                ? (task.formattedSpeed.isEmpty
                                    ? 'Calculating speed…'
                                    : task.formattedSpeed)
                                : status,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 4,
                        children: [
                          if (task.status == DownloadStatus.downloading ||
                              task.status.isQueued)
                            TextButton.icon(
                              onPressed:
                                  () => _control(
                                    () => ref
                                        .read(downloadManagerProvider.notifier)
                                        .pauseDownload(task.id),
                                  ),
                              icon: const Icon(Icons.pause, size: 20),
                              label: const Text('Pause'),
                            ),
                          if (task.status.isPaused)
                            TextButton.icon(
                              onPressed:
                                  () => _control(
                                    () => ref
                                        .read(downloadManagerProvider.notifier)
                                        .resumeDownload(task.id),
                                  ),
                              icon: const Icon(Icons.play_arrow, size: 20),
                              label: const Text('Resume'),
                            ),
                          if (locked && task.status != DownloadStatus.completed)
                            TextButton.icon(
                              onPressed:
                                  () => _control(
                                    () => ref
                                        .read(downloadManagerProvider.notifier)
                                        .cancelDownload(task.id),
                                  ),
                              icon: const Icon(Icons.close, size: 20),
                              label: const Text('Cancel'),
                            ),
                          if (task.status.isCompleted)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Text('Saved in Downloads'),
                            ),
                        ],
                      ),
                    ],
                    if (failed && error != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 12, bottom: 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.errorContainer.withValues(alpha: .35),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          mediaErrorMessage(error),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onErrorContainer,
                          ),
                        ),
                      ),
                    if (item.notice != null)
                      Text(item.notice!, style: theme.textTheme.bodySmall),
                    if (failed || (task?.status.isCancelled ?? false))
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () => _retry(item),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Retry'),
                          ),
                          TextButton.icon(
                            onPressed:
                                _submitting ? null : () => _removeItem(item),
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Remove'),
                          ),
                          if (!active)
                            IconButton(
                              tooltip: 'Edit link',
                              onPressed: () => _edit(item),
                              icon: const Icon(Icons.edit_outlined, size: 20),
                            ),
                          if (!locked &&
                              item.selected != null &&
                              item.streams.isNotEmpty)
                            _quality(item),
                        ],
                      ),
                  ],
                ),
          ),
        ),
      );
    },
  );

  Widget _urlInput(
    BatchPreparationState batch, {
    required bool compact,
    Widget? preferences,
  }) {
    final colors = Theme.of(context).colorScheme;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!compact) ...[
          Text(
            'Add video links',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
        ],
        MediaLinkField(
          controller: _input,
          focusNode: _focus,
          maxLines: 3,
          emphasized: false,
          alwaysShowPaste: true,
          hintText: 'Paste video links here…',
          errorText: _inputError,
          onChanged: _type,
          onPaste: _paste,
          onClear: () {
            _inputDebounce?.cancel();
            _input.clear();
            setState(() {
              _inputError = null;
              _inputNotice = null;
            });
          },
          onSubmitted: (_) => _consumeInput(),
        ),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Text(
            _inputNotice ??
                (batch.autoAdd
                    ? 'Separate links with spaces, commas or new lines.'
                    : 'Auto Add is off. Press Done to add links.'),
            key: const ValueKey('batch_input_feedback'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      ],
    );
    if (!compact) return content;
    return ExpansionTile(
      key: const ValueKey('batch_add_more'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      title: const Text('Add more videos'),
      leading: const Icon(Icons.add_link),
      shape: const Border(),
      collapsedShape: const Border(),
      children: [
        content,
        if (preferences != null) ...[const SizedBox(height: 12), preferences],
      ],
    );
  }

  Widget _settingsPanel(BatchPreparationState batch, Set<String> qualities) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final quality = Tooltip(
      message: 'Default quality',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final selected = await showBatchQualityPicker<String>(
            context,
            title: 'Default quality',
            selected: batch.quality,
            options: [
              for (final q in qualities)
                BatchQualityOption(
                  value: q,
                  label: q == 'Best' ? 'Best Available' : q,
                ),
            ],
          );
          if (mounted && selected != null) controller.setQuality(selected);
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Video quality',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      batch.quality == 'Best'
                          ? 'Best Available'
                          : batch.quality,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, size: 20),
            ],
          ),
        ),
      ),
    );
    final autoAddSwitch = Switch(
      key: const ValueKey('batch_auto_add'),
      value: batch.autoAdd,
      onChanged: (value) {
        _inputDebounce?.cancel();
        controller.setAutoAdd(value);
        if (value && _input.text.trim().isNotEmpty) _type(_input.text);
      },
    );
    final automatic = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Auto Add', style: theme.textTheme.bodyMedium),
        const SizedBox(width: 4),
        autoAddSwitch,
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (MediaQuery.textScalerOf(context).scale(14) > 19) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                quality,
                const Divider(height: 1),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Auto Add', style: theme.textTheme.bodyMedium),
                    autoAddSwitch,
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: quality),
              Container(
                width: 1,
                height: 32,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: colors.outlineVariant.withValues(alpha: .5),
              ),
              automatic,
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final batch = ref.watch(batchPreparationProvider);
    final colors = Theme.of(context).colorScheme;
    final items = batch.items.where((i) => i.url.trim().isNotEmpty).toList();
    final taskItems = items.where((i) => i.taskId != null).toList();
    final active = taskItems.isNotEmpty;
    final controllable = taskItems.any(
      (i) =>
          i.task != null &&
          (i.task!.status.isActive ||
              i.task!.status.isQueued ||
              i.task!.status.isPaused),
    );
    final canPause = taskItems.any(
      (i) =>
          i.task?.status == DownloadStatus.downloading ||
          i.task?.status.isQueued == true,
    );
    final canResume = taskItems.any((i) => i.task?.status.isPaused == true);
    final failed =
        items
            .where(
              (i) =>
                  i.status == BatchItemStatus.failed ||
                  (i.task?.status.isFailed ?? false),
            )
            .toList();
    final ready =
        items
            .where((i) => i.status == BatchItemStatus.ready && i.taskId == null)
            .length;
    final checking =
        items.where((i) => i.status == BatchItemStatus.checking).length;
    final qualities = <String>{
      'Best',
      '2160p',
      '1440p',
      '1080p',
      '720p',
      '480p',
      '360p',
      'Audio',
      batch.quality,
      for (final i in items)
        for (final s in bestVideoQualityOptions(i.streams)) s.qualityLabel,
    };
    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Batch Download',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          actions: [
            IconButton(
              tooltip: 'Batch download help',
              icon: const Icon(Icons.help_outline),
              onPressed:
                  () => showDialog<void>(
                    context: context,
                    builder:
                        (context) => Consumer(
                          builder:
                              (context, ref, _) => AlertDialog(
                                title: const Text('Batch downloads'),
                                content: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Paste links separated by spaces, commas or new lines. With Auto Add off, press Done to add them. Downloads continue here and also appear in Downloads.',
                                      ),
                                      const SizedBox(height: 16),
                                      SwitchListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text(
                                          'Auto-remove completed',
                                        ),
                                        subtitle: const Text(
                                          'Keep saved files in Downloads.',
                                        ),
                                        value: ref.watch(
                                          batchPreparationProvider.select(
                                            (s) => s.autoRemoveCompleted,
                                          ),
                                        ),
                                        onChanged:
                                            ref
                                                .read(
                                                  batchPreparationProvider
                                                      .notifier,
                                                )
                                                .setAutoRemoveCompleted,
                                      ),
                                    ],
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Got it'),
                                  ),
                                ],
                              ),
                        ),
                  ),
            ),
          ],
        ),
        body: SafeArea(
          bottom: false,
          child: CustomScrollView(
            controller: _scroll,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        child:
                            active
                                ? BatchProgressSummary(
                                  taskIds: batch.sessionTaskIds,
                                )
                                : const SizedBox.shrink(),
                      ),
                      if (active) const SizedBox(height: 12),
                      _urlInput(
                        batch,
                        compact: active,
                        preferences:
                            active ? _settingsPanel(batch, qualities) : null,
                      ),
                      if (!active) ...[
                        const SizedBox(height: 16),
                        _settingsPanel(batch, qualities),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Videos (${items.length})',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (items.isNotEmpty)
                            TextButton(
                              onPressed:
                                  items.isEmpty || _submitting
                                      ? null
                                      : _clearAll,
                              style: TextButton.styleFrom(
                                foregroundColor: colors.onSurfaceVariant,
                              ),
                              child: const Text('Clear All'),
                            ),
                        ],
                      ),
                      if (!active && items.isNotEmpty)
                        Text(
                          [
                            if (ready > 0) '$ready ready',
                            if (checking > 0) '$checking checking',
                            if (failed.isNotEmpty) '${failed.length} failed',
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      if (failed.length > 1)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () async {
                              for (final item in failed) {
                                await _retry(item);
                              }
                            },
                            child: const Text('Retry All Failed'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (items.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 32,
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.playlist_add_rounded,
                          size: 48,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Your videos will appear here',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Add links above to get started.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final platform in const [
                              'YouTube',
                              'Facebook',
                              'Instagram',
                            ])
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: colors.outlineVariant.withValues(
                                      alpha: .25,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    PlatformLogo(
                                      platform: platform.toLowerCase(),
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      platform,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (_, index) => _card(items[index]),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(
              top: BorderSide(
                color: colors.outlineVariant.withValues(alpha: .5),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                12 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (controllable) ...[
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final buttons = [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  canPause || canResume
                                      ? () => _batchControl()
                                      : null,
                              icon: Icon(
                                canPause ? Icons.pause : Icons.play_arrow,
                                size: 20,
                              ),
                              label: Text(
                                canPause ? 'Pause All' : 'Resume All',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _batchControl(cancel: true),
                              icon: const Icon(Icons.close, size: 20),
                              label: const Text('Cancel All'),
                            ),
                          ),
                        ];
                        if (MediaQuery.textScalerOf(context).scale(14) > 20) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              OutlinedButton(
                                onPressed:
                                    canPause || canResume
                                        ? () => _batchControl()
                                        : null,
                                child: Text(
                                  canPause ? 'Pause All' : 'Resume All',
                                ),
                              ),
                              OutlinedButton(
                                onPressed: () => _batchControl(cancel: true),
                                child: const Text('Cancel All'),
                              ),
                            ],
                          );
                        }
                        return Row(children: buttons);
                      },
                    ),
                    if (batch.selected.isNotEmpty || _submitting)
                      const SizedBox(height: 8),
                  ],
                  if (!active || batch.selected.isNotEmpty || _submitting)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed:
                          _submitting || batch.selected.isEmpty
                              ? null
                              : _download,
                      icon:
                          _submitting
                              ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.download),
                      label: Text(
                        _submitting
                            ? 'Queueing…'
                            : 'Download ${batch.selected.length} ${batch.selected.length == 1 ? 'video' : 'videos'}',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
