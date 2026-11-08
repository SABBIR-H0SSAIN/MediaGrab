# AGENTS.md — MediaGrab maintenance guide

Read this entire guide and any scoped AGENTS.md before editing. Preserve all existing working features, UI flows, identifiers, preferences, registry/session data and partial downloads. This workspace can contain substantial intentional modified/untracked work: inspect `git status --short` first; never reset or remove it because it is uncommitted. Use the [documentation index](docs/README.md) to select task-relevant references; inspect current source before relying on historical evidence.

Current design: [architecture](ARCHITECTURE.md). Safeguard rationale and unresolved risks: [known limitations](docs/known-limitations.md). Confirm current source and report only verification actually run for the change.

## Verified toolchain and configuration

Observed on 5 November 2026: Flutter **3.47.9**, Dart **3.13.7**, JDK **17.0.21**, AGP **9.1.0**, Kotlin plugin **2.4.0**. `pubspec.yaml` declares Dart `^3.7.0`; resolved packages can impose higher requirements (background_downloader 9.6.5 declares Dart 3.13). Consult installed tools and lockfile, not that constraint alone.

Android app `com.mediagrab.mediagrab`: compileSdk **37**; minSdk/targetSdk inherit Flutter defaults. The current merged release manifest verifies **minSdk 24 / targetSdk 36**, not the old documented 21/34. Plugin subprojects are configured to compileSdk 36 in `android/build.gradle.kts`. Release currently uses debug signing: a successful APK build is not store-release readiness. Do not silently lower SDKs or change signing.

Manual Riverpod **2.6.1** providers; feature-first domain/data/presentation structure. No provider code generation. Material 3, optional wallpaper colors, system/light/dark plus AMOLED. Key locked versions (constraints may differ):

| Capability | Locked implementation |
| --- | --- |
| extraction / HTTP | youtube_explode_dart 3.1.0; Dio 5.11.1; html 0.15.7; xml 6.6.1 |
| native downloads / connectivity | background_downloader 9.6.5; connectivity_plus 6.1.5 |
| media processing | **ffmpeg_kit_flutter_new_min 3.6.7**, retain constraint **`^3.6.7`** |
| notifications | flutter_local_notifications 18.0.1 |
| storage / settings | shared_preferences 2.5.6; path_provider 2.1.6; permission_handler 11.4.0 |
| playback / safe external open | Android Media3 ExoPlayer/session 1.9.2; video_player 2.14.1 portable/probe adapter; open_filex 4.7.0 |
| routing | go_router 14.8.1 |

Drift/sqlite and receive_sharing_intent remain declared/registered, but production persistence is JSON/SharedPreferences and no incoming-share Dart listener is wired. Do not invent a database or incoming-share workflow. Read the dependency boundaries in the known limitations before removing native integrations. Do not replace FFmpegKit with discontinued `ffmpeg_kit_flutter`/`ffmpeg_kit_flutter_min` Maven artifacts.

## Ownership and directory map

Paths below are relative to the repository; tests generally mirror `lib/`.

- `lib/main.dart`: binding, notification initialization without permission prompt, ProviderScope, normal app entrypoint.
- `lib/app.dart`: themes/router and existing-subsystem background checkpoint callbacks. `shared/widgets/app_startup.dart`: immediate destination render, first-frame ready callback, lifecycle observer (unregistered on disposal). Native Android launch resources own the splash.
- `lib/routing/app_router.dart`: `/home`, `/downloads?tab=active|completed`, `/library`, `/settings` in indexed shell; `/media-info?url=...` (also accepts legacy String extra), `/batch-download`, `/player?filePath=...&title=...` outside shell.
- `lib/core/theme/`: `app_theme.dart`, `app_colors.dart`, `hero_wave_palette.dart`; `core/widgets/hero_background.dart` owns current artwork background. The old aurora painter was already removed by earlier user work.
- `lib/core/utils/`: platform URL parsing, FileProvider-safe open/share/delete, filename sanitization, physical folder-writability probe, user-facing extraction errors.
- `lib/core/services/download_notification_service.dart`: singleton channel, per-task notifications, serialized actual Android foreground-service starts/stops.
- `lib/features/home/presentation/`: clipboard/input, platform/help/batch actions, recent media and immediate playback. Clipboard resume must not replace nonempty typed input.
- `lib/features/extractor/domain/entities/`: MediaInfo, StreamInfo, PlaylistInfo, PreparedDownload (reviewed source URL + exact selection + companion).
- `lib/features/extractor/data/`: ExtractorFactory registry and BaseExtractor adapters. `extractors/` contains YouTube, Facebook, Instagram; shared social JSON/DASH parser; exact YouTube stream selection and maintained-client recovery.
- `lib/features/extractor/presentation/providers/`: extractor FutureProvider families and batch preparation controller. Batch owns drafts, deduplication, bounded metadata workers, overrides, linked-task status, automatic retry/removal. It does not own downloaded files.
- `lib/features/extractor/presentation/utils/`: `batch_download_helper.dart` is the sole batch enqueuer; `video_quality_options.dart` provides display-resolution/quality grouping. Screens/widgets include media details, quality/playlist sheets, full batch screen, edit/quality/progress widgets, and legacy sheet adapters.
- `lib/features/downloads/domain/`: immutable DownloadTask and DownloadStatus; provider contracts must remain compatible.
- `lib/features/downloads/data/services/download_engine.dart`: existing queue/coordinator, task controls, transport dispatch, media processing, validation/completion. Extend it narrowly; line count alone is not a reason to rewrite it.
- Adjacent services: `media_merge_plan.dart` (shared codec/timing/arguments), `media_merger.dart` (platform-neutral probing, copy/repair and cancellable FFmpeg sessions); `youtube_merge_plan.dart` retains its compatible API by delegating to the shared policy. `youtube_transfer.dart` owns ranges/continuity/deadlines; `youtube_media_validation.dart` the strict YouTube probe policy; `youtube_diagnostics.dart` bounded redacted logs; `download_registry.dart` completed records; `download_session_store.dart` restart checkpoints.
- `lib/features/downloads/presentation/`: manager cellular/settings boundary, progress providers, Active/Completed screen and task tiles.
- `lib/features/library/presentation/`: registry projections, filters/search/sort, persisted grid/list view, storage display. Compatibility `scanDirectories` delegates to registry refresh; it must never scan shared storage.
- `lib/features/player/`: app-scoped PlaybackManager and injectable backend, immutable queue/state/preferences, full player, docked mini-player and gesture controls. Android PlaybackService owns the sole native ExoPlayer, media session and monotonic sleep deadline; PlaybackBridge owns Flutter binding/texture/PiP. Route disposal minimizes, explicit Close stops. See `docs/playback.md`; preserve the safe nullable portable-controller cleanup.
- `lib/features/settings/presentation/`: preference state and settings/theme UI. `lib/shared/widgets/`: navigation shell, reusable media cards/fields/feedback and native-style brand artwork.
- `android/`: Gradle, FlutterActivity with playback lifecycle/PiP bridge, manifests, FileProvider from plugins, launcher/native splash resources. `assets/icon/app_logo.png` is declared and referenced by README/icon generation; retain it.
- `tool/`: extraction/transfer/host-matrix/device/decode/merge probes, isolated Android builder, brand-icon generator. The host batch-sync benchmark is in `test/benchmarks/`. Never package a probe as the normal production entrypoint.

## End-to-end behavior and public boundaries

URL input → `detectPlatform` → `ExtractorFactory.getExtractorOrThrow` → metadata and stream providers → original StreamInfo quality selection → `DownloadManagerNotifier.startDownload` → `DownloadEngine.startDownload` → FIFO admission → writable output → platform transfer → merge/conversion → validation → `DownloadRegistry.register` → completed providers → Library and playback.

- Every playlist/multi-URL submission goes through **`enqueueBatchMediaDownloads`**. It accepts videos or exact PreparedDownload entries, resolves directories, sanitizes names, forwards companion audio, and reports actual per-item queued/error results. Never create fabricated stream URLs or duplicate task/directory logic in widgets.
- Factory owns and closes extractors; injected clients retain their existing ownership semantics. Metadata/stream extraction FutureProviders are manual and cached by Riverpod. Batch checks have three workers, per-row revision guards and transient retry policy; timeout is a waiting deadline, not proof that the underlying extraction was canceled.
- Download manager owns cellular checks, configured path and runtime concurrency preferences; engine owns execution and registry completion. UI owns navigation. Starting a download selects tab **0** and routes **`/downloads?tab=active`**. Recent "See all" selects **1** and routes **`/downloads?tab=completed`**. Completed audio/video cards immediately push the in-app `/player` with URI-encoded filePath/title and an optional visible-list PlaybackQueue. Explicit external opening uses `openMediaFile`.

## Lifecycle, persistence and cancellation

Statuses: queued → downloading → merging/converting as needed → completed or failed; active/queued work can pause; explicit Resume admits paused work; Retry admits failed/cancelled work under the same ID. Cancel stops work and does not create a completed record. FIFO waiting IDs and active-ID capacity are engine-owned. Runtime limit reductions allow already-active work to finish. Progress is at most five emissions/second/task while downloading; terminal and processing-state updates are immediate. Notifications are independently throttled to about once/second/task.

- `DownloadRegistry` is authoritative for completed media. Preserve **`mediagrab_download_registry_v1`**, documents backup **`mediagrab_registry.json`**, record fields and IDs. `getCompletedRecords(verifyFileExists: true)` filters missing/empty/non-file outputs without scanning or silently purging registry history. Deletion must succeed before the caller removes history.
- Session key **`mediagrab_download_session_v1`** stores selected stream, metadata, status/bytes/path, companion audio and native-task JSON. Writes serialize; downloading checkpoints coalesce around one second, state changes checkpoint immediately. `restoreSession()` is shared/idempotent. Completed registry records hydrate first; native jobs reconnect; interrupted in-process/queued jobs restore **paused for explicit Resume**, preserving partial files. Never auto-restart all downloads after process death.
- Batch key **`batch_draft_v2`** retains quality, flags, task links, inclusion and override labels. Edits debounce 250 ms; **`flushDraft()`** serializes captured snapshots and joins pending writes. App background/detach flush initialized batch/engine only; controller disposal flushes pending draft edits. Sudden process death can still precede asynchronous persistence; SharedPreferences is not a transactional durable job database.
- YouTube uses per-run cancellation tokens and acknowledged writer completion before Resume/Retry; native fallback has an independent temporary file and owned client. FFmpeg sessions are task-specific/cancellable. Failed processing preserves source partials; cancellation cleans task-owned temporary files. Do not delete unrelated output/partial files or change established suffixes.
- Native status callbacks must not move stopped/terminal tasks back into another state. Duplicate completion is guarded by `_finalizing` and current active state. An enqueue returning false must enter the existing fallback, not leave an active task without execution.

## Non-negotiable media, storage, UI and Android safeguards

1. **File exposure:** always use `openMediaFile` from core file_utils for external files. Never `launchUrl(Uri.file(...))`. Keep leading dot/space stripping in `sanitizeFilename` and nullable player-controller cleanup even during async initialization.
2. **Storage:** request existing permissions at startup/folder selection, physically probe via `PermissionUtils.isFolderWritable`, and fall back to app documents/MediaGrab when a selected directory is restricted. Permission.videos/audio does not establish arbitrary folder writability. Resolve `_ensureWritableTargetPath` **before** deriving final/temp paths. Re-reserve a unique name in a fallback directory against files and engine tasks; existing files/records must survive repeat downloads.
3. **Privacy:** Library displays only registered MediaGrab downloads. No scanning `/Download`, camera folders or arbitrary device files. Do not log signed URLs/tokens; YouTube diagnostics whitelist fields. Registry/session formats currently retain stream URLs for compatibility; treat those files as potentially sensitive.
4. **YouTube extraction:** preserve primary `_yt.videos.get`, official oEmbed metadata fallback, default manifest attempt, and required legacy androidSdkless/ios/tv fallbacks (Android is also present). Recovery additionally uses the maintained VisionOS profile with watch-page context. Do not remove the native `streamsClient.get` adapter, claim it automatically repairs every token restriction, or silently substitute selected formats. Preserve progressive preference when it covers a resolution, exact video itag/codec/dimensions/fps, 60fps labels, original-language companion policy and meaningful underlying errors.
5. **HTTP 416 conflict resolution:** the older guide said any received bytes imply EOF. That is unsafe and is superseded here by the user's preservation requirement and the stricter YouTube transfer contract. **Never weaken YoutubeTransfer:** completion requires known total equality and continuity checks; a 416 alone is insufficient. Generic `_streamToFile` still has the older permissive behavior for non-YouTube fallback; it is a documented remaining risk, not a policy to copy into new transport code. Change that path only with focused compatibility tests.
6. **Quality and validation:** no silent HD → 360p fallback. YouTube output passes exact selected dimensions, requested fps tolerance, required audio/video and known codecs, finite positive duration and source/track-duration tolerances, then an FFmpeg packet-read integrity scan. Do not replace strict checks with the generic legacy >360p/85% height check (which remains on non-YouTube completion). Unknown dimensions cannot prove selected video quality. Cropped sources use actual selected dimensions, not nominal label height.
7. **Codec/sync:** WebM cannot contain AAC; use copy/Opus. MP4 uses compatible copy/AAC. Preserve `-avoid_negative_ts make_zero -shortest`; encoding/repair retains `-af aresample=async=1`. The measured YouTube AAC-copy path requires probed start difference ≤50 ms and duration difference ≤250 ms; missing/invalid timing uses the resampling path. Keep copy-failure fallback and final validation. Stream copy cannot be combined with audio filtering.
8. **Foreground service:** never remove/modify WorkManager's `androidx.work.impl.foreground.SystemForegroundService` **dataSync** declaration. Keep notification plugin's separate dataSync ForegroundService, FOREGROUND_SERVICE/DATA_SYNC permissions and `mediagrab_downloads` ongoing notifications. Actual service start is required; an ongoing notification alone does not promote a process. Starts/stops serialize while active tasks change. Current service is not sticky and stops with task; background-start restrictions, Android 15+ six-hour dataSync budget for apps targeting ≥35, force-stop and OEM kills still apply. Plugin 18.0.1 lacks an onTimeout override: long-background timeout behavior remains a reliability risk. Do not claim guaranteed survival or process-death continuation of Dart/FFmpeg work.
9. **Theming/dialogs:** use semantic `Theme.of(context).colorScheme` surfaces/text/accents so Material You and AMOLED remain correct. AMOLED background/surface is true black. Brand artwork/theme definitions are deliberate exceptions, not permission to hardcode ordinary widget colors. Global filled buttons keep `minimumSize: Size(0, 48)`, not infinite width. Dialog actions remain end-aligned horizontal Cancel/Delete with actionsPadding left/right/bottom 16.

## Exact development and diagnostic commands

Run from the repository. SDK cache/Gradle/pub tools may require sandbox escalation; report an access failure as unexecuted, not a failed application check. Do not run simultaneous Flutter test/build commands against the same build directory (native-assets races).

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
export PATH="$JAVA_HOME/bin:$PATH"
flutter --version
java -version
flutter pub get                    # inspect lockfile changes; no incidental upgrades
dart analyze                       # must report no issues
flutter test --reporter expanded   # complete suite, not only focused tests
flutter build apk --release        # normal lib/main.dart entrypoint
# Inspect actual merged SDK/service declarations after building:
cat build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml
# Select a device explicitly; inspect active work before replacing its app:
~/Library/Android/sdk/platform-tools/adb devices -l
~/Library/Android/sdk/platform-tools/adb -s SERIAL shell dumpsys activity services com.mediagrab.mediagrab
~/Library/Android/sdk/platform-tools/adb -s SERIAL install -r build/app/outputs/flutter-apk/app-release.apk
```

Always dependency/analyzer/full-test/release-build check before committing. Never clear app data to make a test pass. Installing a release can interrupt active work; inspect it first. No automatic uninstall or `pm clear`. Test extraction with both watch and Shorts URLs, progressive/adaptive/audio, exact fps/container validation, controls/FIFO/restoration, registry filtering/deletion, all platforms' fixtures, navigation/player lifecycle, themes/dialog layouts. Mark live cases actually run separately from fixture coverage.

```bash
# Host-only CPU benchmark, no network or Android performance claim:
flutter test test/benchmarks/batch_sync_benchmark.dart --reporter expanded
# Isolated actual-engine device probe; builds separate .youtubeprobe package.
# Existing runner uses adb without -s, so select through ANDROID_SERIAL:
ANDROID_SERIAL=SERIAL YOUTUBE_TEST_CASES='39h7ZJbRcsw|360p,39h7ZJbRcsw|720p|pause' python3 tool/run_isolated_youtube_probe.py
# Build an isolated local-source merge benchmark without installation:
YOUTUBE_BUILD_ONLY=1 YOUTUBE_PROBE_ENTRYPOINT=tool/youtube_merge_device_benchmark.dart python3 tool/run_isolated_youtube_probe.py
# Other probes document arguments in their sources:
dart run tool/youtube_extract_probe.dart aqz-KE-bpKQ
# Bounded redacted diagnostics: app-support/youtube-diagnostics/<task-id>.jsonl
~/Library/Android/sdk/platform-tools/adb -s SERIAL logcat -d -s flutter:I
```

Inspect probe sources for supported arguments before use. Host FFmpeg measurements do not establish Android performance. Device matrix modes include pause/resume, injected 403, expired URL and cancel/retry; label injected versus natural failures and cold versus resumed files. For actual service state use dumpsys and look for isForeground/type dataSync, then verify cleanup after completion. Validate normal UI/player separately from programmatic probes.

## Extension guidance and known limits

Extend existing adapters/pure policies before adding framework layers. New extractors implement BaseExtractor and register with ExtractorFactory; new batch callers use the shared helper; new completed-media consumers use DownloadRegistry. Keep public providers/routes and persisted formats compatible; migrations require old-format fixtures. Test behavior through changed production logic; do not mock it away or suppress analyzer warnings.

Remaining caveats are detailed in the known limitations: generic transfer cancellation/416 rules, stale native events after rapid same-ID retry, cellular/queue races, corrupt-registry fallback, overlapping Library/engine registration, extraction timeouts without upstream cancellation, shared-preferences durability, and Android dataSync timeout handling. These require separate targeted evidence/design, not speculative rewrites. Live private/age/region/attestation-restricted YouTube, live broadcasts, exhaustive Doze/OEM kills and live Facebook/Instagram availability are not guaranteed by unit tests.

## Shared merge extension boundary

Current and future extractors should return real muxed/video-only/audio-only StreamInfo entries and pass companion audio through the existing download manager/engine. The default engine uses MediaMerger for every platform, so no platform-specific FFmpeg command is needed. MP4 AAC-copy requires the same verified 50 ms start / 250 ms duration thresholds; WebM retains copy/Opus. Already muxed streams skip merging. Genuine codec/timing repair and the generic last-resort video/container repair can still take longer; YouTube never enables video re-encoding. Keep the YoutubeMergePlan compatibility entrypoint, strict YouTube validation and persisted task formats intact. Generic merge pause/cancel joins its FFmpeg writer; failed/paused processing keeps source tracks and successful completion removes them only after validation. This does not resolve all older generic network/native-event lifecycle risks listed above. New containers/codecs require tests at this shared boundary rather than a new per-platform merger.
