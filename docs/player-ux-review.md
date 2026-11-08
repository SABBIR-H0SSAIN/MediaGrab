# Player UX audit and verification

## Reference research

Google Search and Google Images were opened before implementation. Expanded
image results included Android Authority's May 2025 Android mini-player capture,
Android Police's hold-speed illustration, and PhoneArena's Android speed-menu
capture. The latter is a November 2024 comparison, not a 2025 redesign. Search
results mixed Android screenshots, desktop controls, old tutorials and modified
clients; these are not interchangeable benchmarks.

- [YouTube's October 2025 announcement](https://support.google.com/youtube/blog/380540176/new-visual-updates-for-youtube-a-more-expressive-and-intuitive-experience-%E2%9C%A8?hl=en)
  describes reduced obstruction and updated double-tap seeking.
- [Android mini-player capture, May 2025](https://www.androidauthority.com/youtube-floating-mini-player-design-tweak-3549849/)
  shows a live floating video with compact corner controls. MediaGrab retains its
  existing docked layout rather than copying that different navigation model.
- [Android speed-menu comparison](https://www.phonearena.com/news/youtube-redesigns-playback-speed-controls-on-its-android-and-iphone-apps_id164612)
  shows selection checkmarks, compact rows and no redundant menu Close button.
- [Hold-speed visual reference](https://www.androidpolice.com/playback-speed-feature-makes-watching-youtube-videos-significantly-better/)
  informed the compact fast-forward/rate feedback. Its promotional illustration
  is not a pixel-accurate screenshot specification.

The supplied screenshots establish MediaGrab's reported overlapping skip and
transport controls. Text inside the playing video is content, not instructions.
Brightness/volume swipes appeared in modified-client references; they are kept as
MediaGrab's optional controls, not represented as verified official YouTube UI.
Static captures cannot establish exact gesture timing or animation physics. The
implementation uses independently testable thresholds, velocity and cancellation
rules; exact equivalence to every YouTube rollout is not claimed.

## Production changes and causes

| Finding | Change |
| --- | --- |
| Skip overlay shaded nearly half the frame while transport controls remained visible | Compact directional feedback with immediate control suppression, a retained timeline and smooth control restoration. |
| Direction reversal could use stale seek positions | Both directions use the last requested target within a burst; pending seeks still coalesce and clamp. |
| Pan cancellation could compete with double taps | Cancellation only clears an owned drag; tap and hold feedback do not cancel one another accidentally. |
| Swipe used local coordinates inside a changing frame and a fixed 48 dp commit | Global pointer tracking, proportional geometry, relative distance/velocity thresholds and interruptible return animation. |
| Temporary 2× had no lifecycle owner | Serialized transient-rate commands, selected-rate preservation, preference isolation and native background/PiP restoration. |
| Fullscreen exit only unlocked rotation, leaving a locked device in landscape | Explicit view requests retained until the sensor catches up, actual-layout reconciliation and Android system-rotation observation. |
| Native texture had no explicit source-size policy and low filtering | Source-resolution SurfaceProducer dimensions persist across views; medium texture sampling improves downscaling. |
| Position ticks rebuilt controls/surface and the hidden mini-player | Full-player timeline and mini-player progress consume position independently. |
| Version UI appended the build number | Display versionName alone; internal version/build/signing stay intact. |

The existing native ExoPlayer/service, app-scoped manager, queue, routes, branding,
optional gestures, safe external-open path and download persistence remain the
production boundaries. The GitHub action uses the requested repository. Completed
counts remain available internally; only their tab badge was removed.

## Test scope

Host tests cover cumulative seeks and delayed acknowledgements, all selectable
hold rates, cancellation/rotation/background interruptions, focused visibility,
menu dismissal, disabled gestures, layout sizing, orientation requests and video
surface rebuild isolation. The Android integration test uses a generated local
1280×720 H.264/AAC fixture and the actual Media3 backend through the normal app.
See [playback testing instructions](playback.md#android-integration-fixture).

A passing host or emulator test does not establish physical-device video
sharpness, exhaustive Android quick-settings/sensor combinations, OEM behavior,
long-duration memory/battery stability, calls/headsets, or all hardware decoders.
Those remain device QA obligations. Dependency resolution/build warnings should
be reported separately from application check results. Release still uses the
repository's existing debug signing configuration.

## Executed verification — 7 November 2026

- `flutter pub get`: passed; existing locked versions preserved. The lockfile adds
  only the Flutter SDK integration-test dependency and its test dependencies.
- `flutter build apk --release`: passed using the normal `lib/main.dart` entrypoint; APK 134.5 MB. Merged manifest retains minSdk 24/targetSdk 36, both download dataSync services and the separate mediaPlayback service. Internal version remains 1.0.0/build 1; release still uses the existing debug signing.
- `dart analyze`: no issues.
- `flutter test --reporter expanded`: 493 passed.
- `JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew :app:testDebugUnitTest
  --console=plain` from `android`: 19 tests passed across five suites.
- `flutter test integration_test/player_ux_test.dart -d emulator-5554
  --no-uninstall --dart-define=PLAYER_UX_SENSOR_ROTATION=true --reporter expanded`:
  passed on a dedicated Android 14/API 34 arm64 emulator, using the normal app's
  widgets/routes and real Media3 backend. The generated local H.264/AAC fixture
  was 1280×720, 30 fps, 120 seconds. The final four-tap input burst took 358 ms
  and requested the expected 60-second target from a paused 30-second position.
- Device assertions covered advancing playback, 1×/1.5×/1.75×/2× hold restoration,
  native brightness/volume changes with focused feedback, orientation-button
  changes, enabling system auto-rotate plus injected portrait/landscape sensors,
  hold interruption by rotation, finger-tracked downward minimizing, expansion,
  and unchanged texture ID, generation, source dimensions and paused position.
  Mini/full frame captures were visually inspected; these do not establish
  physical-display sharpness or long-duration performance.

The normal release APK was installed over the emulator test build after confirming no active MediaGrab services, and its main Activity launched successfully.

The emulator was newly created for these checks. No existing user device, app
registry or download data was used. Tests restore playback preferences and close
the test session. The integration runner must use `--no-uninstall` to preserve
its installed app. Initial device attempts exposed permission/setup, rapid-input
and orientation failures; the final run passed after those were investigated.
The host suite covers gesture cancellation, rapid seeking, disabled optional
controls, menu Back dismissal, queue transitions and resource ownership.

Physical-device/OEM validation, exhaustive Quick Settings interactions,
30-transition memory profiling, 60-minute playback, calls/headsets and battery
measurements were not run. No latency, memory or battery improvement percentage
is claimed. Plugin Kotlin/Gradle compatibility warnings remain outside this
player change.
