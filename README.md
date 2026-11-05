# MediaGrab 🎬

<p align="center">
  <img src="assets/icon/app_logo.png" width="140" height="140" alt="MediaGrab Logo" style="border-radius: 28px;" />
</p>

<p align="center">
  <strong>A modern, powerful Android video and audio downloader built with Flutter 3, Material You, and Clean Architecture.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.47+-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.13+-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white" alt="Android" />
  <img src="https://img.shields.io/badge/Design-Material_3-7B1FA2" alt="Material 3" />
  <img src="https://img.shields.io/badge/Riverpod-2.6.1-00A6A6" alt="Riverpod 2.6.1" />
  <img src="https://img.shields.io/badge/License-MIT-blue" alt="License" />
</p>

<p align="center">
  <a href="#features">Features</a> &nbsp;·&nbsp;
  <a href="#supported-sources">Supported sources</a> &nbsp;·&nbsp;
  <a href="#getting-started">Getting started</a> &nbsp;·&nbsp;
  <a href="#project-structure">Architecture</a> &nbsp;·&nbsp;
  <a href="CONTRIBUTING.md">Contributing</a> &nbsp;·&nbsp;
  <a href="https://github.com/SABBIR-H0SSAIN/MediaGrab/discussions">Discussions</a>
</p>

---

## Features

| Feature | What you can do |
| --- | --- |
| Quality selection | Choose from available video resolutions and audio formats. Separate YouTube video and audio tracks are merged when needed. |
| Download queue | Track progress, transfer speed, and estimated time remaining. Pause, resume, cancel, or retry individual tasks. |
| Batch downloads | Prepare playlist items or multiple links, review selections, and queue the included items. |
| Media library | Search completed MediaGrab downloads, filter by source or media type, and switch between grid and list views. |
| Playback | Watch completed videos in the app or open audio with a compatible app on the device. |
| Appearance | Use system, light, dark, or AMOLED themes, with optional wallpaper-based colors on supported devices. |
| Preferences | Configure download concurrency, storage location, preferred quality, audio format, and cellular network behavior. |

### Supported sources

| Source | Supported content |
| --- | --- |
| YouTube | Videos, Shorts, playlists, and available audio streams. |
| Facebook | Public videos and Reels. |
| Instagram | Public posts and Reels. |

Available formats depend on the source. Private, region-restricted, age-restricted, or otherwise protected content may be unavailable, and platform changes can affect extraction.

Support for additional platforms will be prioritized based on community demand and contributor availability. Request a platform through [GitHub Discussions](https://github.com/SABBIR-H0SSAIN/MediaGrab/discussions), or help add support by submitting a pull request. See the [platform contribution guide](CONTRIBUTING.md#adding-support-for-another-platform) to get started.

## Using MediaGrab

1. Paste a supported link on the Home screen.
2. Review the media details and choose an available video or audio option.
3. Start the download and follow its progress in Downloads.
4. Open completed media from Downloads or the Library.

For playlists or multiple links, use the batch flow to review items and their quality selections before queueing. The Library displays registered MediaGrab downloads; it does not scan unrelated device files.

## Getting started

### Prerequisites

The current maintenance toolchain uses Flutter **3.47.9**, Dart **3.13.7**, and **OpenJDK 17**. Install the Android SDK with **API 37** available for compilation, and connect an Android device or start an emulator.

### Run locally

```bash
git clone https://github.com/SABBIR-H0SSAIN/MediaGrab.git
cd MediaGrab
flutter pub get
flutter run
```

If you already have a checkout, run the last two commands from the repository root. Use the committed lockfile as the dependency baseline.

### Build an APK

```bash
flutter build apk --release
```

The APK is generated at `build/app/outputs/flutter-apk/app-release.apk`. The current release configuration uses debug signing; configure release signing before store distribution.

To install on a connected device, list the devices and replace `DEVICE_SERIAL` with the intended serial:

```bash
adb devices -l
adb -s DEVICE_SERIAL install -r build/app/outputs/flutter-apk/app-release.apk
```

Check for active downloads before replacing an existing installation, as installation can interrupt running work.

## Project structure

```text
lib/
├── core/           Shared services, themes, and utilities
├── features/
│   ├── home/       URL input and recent media
│   ├── extractor/  Source adapters, stream selection, and batch preparation
│   ├── downloads/  Queue, transfers, media processing, and persistence
│   ├── library/    Completed-media browsing and filtering
│   ├── player/     In-app video playback
│   └── settings/   Preferences and appearance
├── routing/        App routes
└── shared/         Reusable widgets
android/            Android configuration and native resources
test/               Unit and widget tests
tool/               Diagnostic probes and development tools
```

Features use domain, data, and presentation layers where applicable, with manual Riverpod providers. Extractors supply metadata and stream choices; the download engine handles execution and registers completed media. The Library reads those completion records.

See [Architecture](ARCHITECTURE.md) for the application design, [Maintenance guide](AGENTS.md) for compatibility requirements, and the [documentation index](docs/README.md) for the maintained technical guides.

## Development checks

Run the following checks from the repository root before submitting a change:

```bash
flutter pub get
dart analyze
flutter test --reporter expanded
flutter build apk --release
```

| Command | Purpose |
| --- | --- |
| `flutter pub get` | Resolve dependencies; review any lockfile changes. |
| `dart analyze` | Check Dart code for static analysis issues. |
| `flutter test --reporter expanded` | Run the complete Flutter test suite. |
| `flutter build apk --release` | Build the Android APK using the normal app entrypoint. |

Run tests and builds serially when they share a build directory. Automated fixtures do not establish live platform availability or Android background reliability; report device and live-source checks separately.

## Contributing

Bug reports, documentation improvements, and code contributions are welcome, including support for additional video and audio platforms. See [Adding support for another platform](CONTRIBUTING.md#adding-support-for-another-platform) for integration guidance, and [CONTRIBUTING.md](CONTRIBUTING.md) for setup, verification expectations, and the pull request workflow.

## License

MediaGrab is distributed under the [MIT License](LICENSE).

## Support the project

If you find MediaGrab useful, consider [starring the repository](https://github.com/SABBIR-H0SSAIN/MediaGrab). It helps others discover the project and shows your support for its development. You can also contribute by reporting issues, sharing feedback, or submitting a pull request.
