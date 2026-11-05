# Testing and verification

These commands are instructions, not recorded results. Installed tools, test outcomes, live extraction, and device behavior must be checked for the current change. Use [the source map](source-map.md) to locate focused tests.

## Project checks

From the repository root, run serially:

```bash
flutter --version
java -version
flutter pub get
dart analyze
flutter test --reporter expanded
flutter build apk --release
```

Use JDK 17 and the toolchain requirements in [AGENTS.md](../AGENTS.md). Review lockfile changes after dependency resolution; avoid incidental upgrades. Do not run simultaneous Flutter tests/builds in the same build directory. The release command uses the normal `lib/main.dart` entrypoint, and the current release signing configuration uses the debug key.

Run relevant focused tests during implementation, then the complete required checks before committing. Do not weaken assertions, bypass production behavior with mocks, or suppress analysis issues to obtain a pass. A blocked SDK/cache/tool command is unexecuted, not an application failure or successful check.

## Select verification by behavior

| Change | Evidence to collect |
| --- | --- |
| Extractor or quality selection | URL/response fixtures, exact stream/codec/dimensions/fps selection, companion audio, and meaningful errors. Label any live requests separately. |
| Queue, retry, pause/cancel | FIFO/capacity, stopped-state guards, writer completion, same-ID retry, preserved partials, and released slots. |
| Persistence or deletion | Existing-format restoration, ordered writes, missing-file filtering, duplicate observation, and deletion success before record removal. |
| Storage | Unwritable directory fallback, physical writability probe, unique-name collision handling, and preservation of earlier files. |
| Merge or validation | Compatible/incompatible codecs, missing/invalid timing, copy failure, cancellation, source preservation, and final validation. |
| UI or player | Navigation, small layouts, theme variants, typed-input preservation, and async initialization/disposal/lifecycle behavior. |
| Android service or plugin | Actual merged manifest, selected-device service state, cleanup when idle, and native behavior affected by the change. |

## Device work

Inspect connected devices and active work before replacing an installed app. With Android platform-tools on PATH, replace `DEVICE_SERIAL` with the intended serial:

```bash
adb devices -l
adb -s DEVICE_SERIAL shell dumpsys activity services com.mediagrab.mediagrab
```

Installing over the app can interrupt downloads. Never uninstall or clear app data to make a check pass. The release manifest is normally generated at `build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml`; inspect actual generated SDK/service declarations after building.

Read probe sources under [tool/](../tool/) for supported parameters before use. The isolated YouTube runner uses `ANDROID_SERIAL` for device selection and builds a separate probe package. Keep normal UI/playback checks distinct from programmatic probes. The host-only [batch benchmark](../test/benchmarks/batch_sync_benchmark.dart) measures host CPU work, not Android or network performance.

## Reporting results

State the command, result, and any environment limitation. For device checks include model/API, app or probe entrypoint, scenario, and observed outcome. For transfer results distinguish fresh versus resumed files and injected versus natural failures.

Fixture tests do not establish live service availability. Metadata extraction does not prove a complete download; a playable header does not prove full packet integrity. An ongoing notification does not prove an actual foreground service. A local merge measurement does not measure network speed. Report untested cases explicitly and redact signed URLs, credentials, and user data from output.
