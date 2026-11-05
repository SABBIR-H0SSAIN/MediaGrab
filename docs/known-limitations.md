# Known limitations and investigation boundaries

These notes distinguish source behavior from reliability hypotheses. They are not fresh runtime verification. Recheck the linked implementation before proposing a fix; preserve the strict contracts in [AGENTS.md](../AGENTS.md).

## Source-visible behavior

| Area | Evidence and implication |
| --- | --- |
| Generic HTTP 416 | [DownloadEngine._streamToFile](../lib/features/downloads/data/services/download_engine.dart) accepts a 416 when positive bytes exist and assigns that length as the total. This is weaker than the dedicated YouTube continuity/known-total policy. A future fix needs focused compatibility fixtures. |
| Registry corruption | [DownloadRegistry._load](../lib/features/downloads/data/services/download_registry.dart) marks preferences loaded before decoding. Malformed primary data can suppress the documents backup, and malformed records can interrupt loading. Define salvage and deletion semantics before changing fallback. |
| Connectivity handling | [DownloadManagerNotifier._handleConnectivityChange](../lib/features/downloads/presentation/providers/download_manager_provider.dart) pauses a snapshot of active jobs. Admission during those awaits and overlapping settings/network callbacks need a targeted race test; do not claim comprehensive cellular enforcement from the setting alone. |
| Player initialization | [VideoPlayerScreen](../lib/features/player/presentation/screens/video_player_screen.dart) plays after async initialization when mounted, while lifecycle events separately pause the controller. Whether backgrounding during initialization permits later autoplay needs a delayed-initialization regression. |
| Batch timeout | [BatchPreparationController](../lib/features/extractor/presentation/providers/batch_preparation_provider.dart) uses waiting deadlines and revision guards. A timeout does not establish cancellation of the underlying extraction operation. Closing a shared extractor may affect other rows. |

## Boundaries requiring separate evidence

- Native stopped-state guards do not by themselves prove that an old callback cannot affect a rapid retry under the same ID. Exercise delayed events from an earlier job.
- Generic network cancellation does not have all dedicated YouTube run guarantees. Do not infer equivalent behavior from the shared merge writer's acknowledged shutdown.
- SharedPreferences and lifecycle flushes are asynchronous, not transactional crash durability. Preserve paused restoration and explicit Resume rather than automatically restarting every interrupted task.
- Completion can be observed through both the engine and a library compatibility bridge. Verify direct task-update callers and persisted record behavior before consolidating ownership.
- Batch/playlist/default quality policies have distinct fallback behavior. Compare portrait/cropped media, fps, overrides, and missing audio before merging selection algorithms.
- Foreground notifications require actual Android service starts. Background restrictions, dataSync budgets, force-stop, and OEM termination still apply. Root guidance records the notification plugin's timeout-handler limitation; inspect installed native source before changing integration or claiming recovery.

## Features that must not be inferred

Drift/sqlite and receive_sharing_intent are declared/registered dependencies. They do not establish production database persistence or an incoming-share Dart listener. Inspect native effects before removing them.

The Library is registry-backed and does not scan arbitrary shared storage. Stream recovery does not supply a universal attestation provider. Private, age/region-restricted, live, or otherwise protected media and live Facebook/Instagram availability require separate checks. A build or fixture pass proves none of those external capabilities.

## Merge safeguards

[MediaMergePlan.audioCodecs](../lib/features/downloads/data/services/media_merge_plan.dart) permits MP4 AAC copy first only when valid input probes show start difference at most 50 ms and positive-duration difference at most 250 ms. Missing, invalid, or misaligned timing keeps resampling first. WebM uses copy/Opus. Preserve fallback and final validation, and never apply an audio filter with stream copy.

Shared processing does not make generic validation equivalent to strict YouTube validation. Keep exact selected format, required tracks, duration policy, and packet-read checks where implemented. Diagnose failures through the current policy rather than relaxing checks to produce a completed status.
