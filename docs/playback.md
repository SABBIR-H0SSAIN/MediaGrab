# Offline playback

## Ownership and source map

- `lib/features/player/domain/` defines immutable local items/queues, state,
  preference validation and the cumulative seek policy.
- `lib/features/player/data/playback_backend.dart` defines the backend contract,
  Android channels and the retained video_player portable/test adapter.
- `lib/features/player/presentation/providers/playback_provider.dart` owns the
  app-scoped manager, command ordering, stale-event guards and seek coalescing.
- `presentation/screens/video_player_screen.dart` owns transient UI, control
  visibility, fullscreen/lock state and gesture arbitration. It does not own the
  Android decoder. Widgets alongside it provide full/mini/PiP presentation and
  the existing Settings screen's playback preference sheet.
- `android/app/src/main/kotlin/com/mediagrab/mediagrab/playback/` owns the single
  native ExoPlayer, MediaSessionService, local artwork cache, monotonic timer,
  Flutter SurfaceProducer and activity/PiP integration. The texture backend
  delegates crop/rotation to Flutter where supported and applies validated
  quarter-turn format correction otherwise, matching the installed video plugin.

The `mediagrab/playback` method channel accepts local queue loading, transport,
seeking, speed/volume/loop, audio-only, timer, preference, visibility, PiP and
surface-bounds commands. `mediagrab/playback/events` publishes authoritative
native snapshots. Queue-changing commands carry a session generation; stale
commands/events cannot replace current state. Native system controls use the
same player and may not inject their own queue or remote URLs.

## Behavior

Home, Completed Downloads and Library snapshot their current visible audio/video
list in display order. Playback advances to the next item and stops at the end;
loop repeats the current item. Missing selections fail explicitly. Unplayable
queue entries are skipped in a bounded forward search without altering media or
history. The legacy `/player?filePath=...&title=...` route remains supported.

Android Back exits fullscreen first, then minimizes. The top chevron and downward
swipe directly shrink the live surface into the docked mini-player, including
landscape fullscreen, without an intermediate portrait player. The destination
is always the portrait app/mini-player; the host releases that orientation request
when playback is closed. Platform orientation requests never block navigation. Dragging uses global pointer coordinates, follows the finger to the dock, and
commits after a screen-relative distance or a downward fling. A short or cancelled
drag animates back; a new drag can interrupt that return animation. The docked mini-player
sits above bottom navigation (or the safe bottom on details/batch routes). Tap or
swipe up restores the same session. Close/Stop releases playback. Disabling the
automatic mini-player makes route departure stop playback.

Skip buttons and double taps share a configurable 5/10/15/30-second increment
(default ten). Same-direction actions accumulate for 800 ms against the requested
seek target; seeks clamp and pending requests coalesce. Transport controls hide during seek feedback while the timeline remains visible,
then return smoothly. Pause cancels pending playback intent.
Control/icon hit regions are separate from video gestures. Horizontal swipes seek; sufficiently dominant
vertical swipes minimize. Optional side volume/brightness gestures take precedence
on their configured side and start disabled. The center lane remains available
for downward minimizing when both side adjustments are enabled. Screen lock exposes only Unlock.

Background/screen-off audio, supported PiP, audio-only availability and automatic
mini-player default on. Notification controls are required while background
playback is enabled. Foreground-only playback can disable the media session and
notification. Audio-only/background playback disables video track decoding and
restores video on the same ExoPlayer, without writing a second audio file.

Replacing an active queue preserves its sleep deadline; a default timer does not
overwrite that deadline. Sleep timers use elapsed realtime, not media time or wall time. They continue
while paused and across queue changes. Expiry pauses and optional fade-out spans
the final five seconds. Default timers start only for a new queue; minimizing,
restoring or native automatic advancement does not reset them. Timer cancellation
and expiry restore the user's volume.

Playback preferences use `settings_playback_v1` through the existing
SettingsNotifier and SharedPreferences. Defaults are validated, writes ordered,
and existing settings/download stores remain compatible. No active playback is
persisted for automatic restart after process death. Android separately saves up
to 100 per-file resume timestamps in playback-owned preferences, every five seconds
and on seek/pause/background/Close. An explicit reopen resumes the timestamp by
default; Settings can disable this. Changed file size/mtime and completed items
start at zero. This history never changes registry records or media files. Flutter reconnects if the
native service is still alive.

The full-player reference layout uses three central Previous/Play/Next controls,
an outlined settings header and a full-width red timeline. Below it, time sits
on the left and mute/speed/fullscreen sit together on the right. There is no
separate skip/lock/sleep strip. Fit, external-open, sleep and lock actions live
in the settings sheet. Double-tap bursts show a compact cumulative duration and animated directional
icon, without a shaded region. Scrubbing exposes a timestamp and timeline.
Optional brightness/volume adjustments show only their icon, level and meter.
Player sheets dismiss through selection, the outside barrier, Back or drag; they
have no redundant Close button.
Online social/recommendation controls are intentionally absent. Native PiP
requests Previous, centered Play/Pause and Next, disabling queue-boundary actions;
Android owns the close, expand and settings chrome.

Press-and-hold on the video temporarily selects 2× while playing. Release,
pointer cancellation, rotation, backgrounding, minimizing and transport changes
restore the previous rate. Temporary changes serialize with restoration and do
not write remembered speed preferences or the native queue default. Native
background/PiP transitions also restore the rate if a Flutter pointer is lost.

The orientation button requests a real landscape/portrait change, with bounded
request debouncing. Layout changes cancel transient gestures and use actual
available dimensions. Android releases a manual request once the physical device matches that view,
then follows system rotation. A system auto-rotate setting change explicitly
returns control to Android. Rotation
does not create another decoder or queue. Android may restrict orientation on
large-screen devices; the button reconciles with the actual layout after the
request timeout.

The same source-resolution native texture is used in full and mini presentation;
mini-player layout bounds never reduce its buffer size. Texture sampling uses
medium filtering for downscaling. Position ticks rebuild the timeline/progress
rather than the full video surface and mini-player controls.

## Verification

Run required Flutter checks serially as described in [testing](testing.md).
Focused controls, queue/lifecycle races and preferences are under
`test/features/player/`. Optional host layout capture (on macOS, loads a local
Arial font for readable text):

```bash
flutter test --no-pub test/features/player/presentation/screens/premium_player_test.dart \
  --dart-define=PLAYBACK_SCREENSHOT=/tmp/mediagrab-player-portrait.png --reporter expanded
```

Native ownership/policy and sleep-deadline tests use Robolectric/JUnit:

```bash
cd android
JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew :app:testDebugUnitTest --console=plain
```

Host tests verify policy and layout, not decoded audio/video or physical PiP.
On a selected Android device, use registered local MP4/WebM/video/audio samples
with networking disabled. Check seeking, speed, loop, fit, mute/volume, all queue
controls, swipe/lock, full/mini restoration, supported PiP, notification actions,
Home/screen lock, calls/audio focus, headset disconnection, timer expiry/fade,
settings restart and coexistence with active downloads. Inspect `dumpsys
activity services com.mediagrab.mediagrab` and `dumpsys media_session` to verify
actual mediaPlayback service/session activity and cleanup. Profile 30 full/mini
transitions and 60 minutes of playback on hardware before making stability,
latency, memory or battery claims.

## Platform limits

Android PiP requires API 26+, a supporting device and system permission. Android
chooses notification/PiP action placement. OEM termination and force-stop are
not guaranteed survivable. Unsupported or damaged media retains safe external
opening. There is no iOS runner in this repository; iOS background audio,
Now Playing and PiP are deferred. The portable adapter does not advertise native
Android service/PiP capabilities.

### Android integration fixture

`integration_test/player_ux_test.dart` launches the normal app and uses its real
Media3 backend, routing and player widgets. The Flutter SDK's `integration_test`
is a development-only dependency. Use a dedicated emulator, inspect active work,
and install a debug build before copying the test fixture to its app cache:

```bash
ffmpeg -f lavfi -i 'testsrc2=size=1280x720:rate=30' \
  -f lavfi -i 'sine=frequency=440:sample_rate=48000' -t 120 \
  -c:v libx264 -preset ultrafast -crf 28 -c:a aac /tmp/player-ux-fixture.mp4
adb -s SERIAL push /tmp/player-ux-fixture.mp4 /data/local/tmp/player-ux-fixture.mp4
adb -s SERIAL shell run-as com.mediagrab.mediagrab cp \
  /data/local/tmp/player-ux-fixture.mp4 cache/player-ux-fixture.mp4
flutter test integration_test/player_ux_test.dart -d SERIAL --no-uninstall --reporter expanded
```

This test requires a dedicated device with the normal app's existing storage and
notification permissions already granted. Always pass `--no-uninstall`; Flutter's
integration runner otherwise uninstalls its test APK during cleanup. It restores playback preferences and closes its session in cleanup.
It does not clear app data or alter download history. Use the optional
`PLAYER_UX_FIXTURE` Dart define for another app-readable fixture path.

For a dedicated Android emulator, `PLAYER_UX_SENSOR_ROTATION=true` adds a hold
interruption and actual sensor rotation check. At the `UX_SENSOR_ENABLE_LANDSCAPE`
log marker, enable system auto-rotate and set emulator acceleration to
`9.8:0:0.8` using `adb -s SERIAL emu sensor set acceleration`. At
`UX_SENSOR_PORTRAIT`, set it to `0:9.8:0.8`. The test waits for actual layout
changes and exact speed restoration. This is emulator sensor injection, not
physical-device sensor evidence.
