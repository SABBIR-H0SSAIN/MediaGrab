# Contributing to MediaGrab

Thank you for considering a contribution. This guide covers the contribution workflow and the checks expected for a change. The repository's [AGENTS.md](AGENTS.md) is the detailed maintenance reference; read it before changing application code.

## Ways to contribute

- Report a reproducible bug or regression.
- Propose a feature or user experience change.
- Add download support for another video or audio platform.
- Improve documentation, tests, accessibility, or maintainability.
- Fix an issue that already has enough detail to implement safely.

For a large or behavior-changing proposal, open an issue first so the expected behavior and compatibility impact can be discussed before implementation.

## Adding support for another platform

Contributions that extend MediaGrab to additional media platforms are welcome. Open an issue describing the platform, supported link types, available video/audio formats, and any access restrictions before starting a substantial integration.

Use the existing extraction and download boundaries:

1. Implement `BaseExtractor` and register the adapter with `ExtractorFactory`. Extend platform URL detection as needed.
2. Return real `MediaInfo` and `StreamInfo` entries for the source's available muxed, video-only, and audio-only streams. Preserve the user's selected format and pass companion audio through the existing download manager and engine.
3. Use the shared download and `MediaMerger` paths. Route playlist or multi-link submissions through `enqueueBatchMediaDownloads` rather than adding separate queue or file-handling logic.
4. Add fixtures and tests for URL detection, metadata, stream selection, error handling, and any new container or codec behavior at the shared merge boundary.
5. Update the README's supported-source list once the integration is implemented. Report live checks separately from fixture coverage and document known restrictions.

See `AGENTS.md` for adapter ownership, media validation, storage, cancellation, and persistence requirements that apply to new integrations.

## Before opening an issue

Search existing issues and discussions for the same problem. Include enough detail for someone else to reproduce it:

- App version or commit, device model, and Android version.
- The steps that lead to the problem and what you expected to happen.
- What happened instead, including exact error text when available.
- Whether the issue is repeatable and whether it happens with a specific source, format, or network condition.
- Relevant screenshots or a short screen recording for visual problems.

Do not include signed media URLs, cookies, access tokens, private account data, or unredacted diagnostic files in a public issue. Treat registry and session files as potentially sensitive because they can contain stream URLs.

## Development environment

Use the versions recorded in the [README](README.md) as the project's current maintenance toolchain. The app is Android-focused and uses Flutter, Dart, and JDK 17. A release APK build currently uses debug signing, so it is for local verification rather than store distribution.

From the repository root, install the dependencies:

```bash
flutter pub get
```

Keep `pubspec.lock` in sync with intentional dependency changes. Avoid broad or unrelated upgrades. Before changing a native plugin or removing a dependency, inspect its Android/build integration and read the rationale in `AGENTS.md` and the [known limitations](docs/known-limitations.md).

## Branch and change workflow

1. Start from the current project state and create a focused branch, for example `fix/player-lifecycle` or `docs/contributing-guide`.
2. Keep each change centered on one issue or closely related set of behavior.
3. Inspect the relevant feature, provider, service, tests, and persisted formats before editing. Follow the ownership map in `AGENTS.md` and any more specific instructions in the affected directory.
4. Preserve existing behavior and compatibility unless the change explicitly requires an intentional migration.
5. Add or update tests for changed production behavior. Prefer tests at the existing production boundary over mocks that bypass the behavior under change.
6. Update documentation when a user-visible behavior, setup requirement, supported format, or maintenance constraint changes.
7. Review the final diff and run the applicable checks before committing or opening a pull request.

Do not discard or overwrite unrelated local work. Avoid resets, clean operations, app-data clears, and deletion of partial downloads as a way to make development checks pass.

## Project conventions and compatibility

These are high-level reminders, not a replacement for the complete requirements in `AGENTS.md`:

- Keep the feature-first domain/data/presentation organization and use the existing manual Riverpod provider patterns. Do not introduce provider code generation without an agreed design.
- Keep public routes, provider contracts, download task identifiers, user preferences, registry/session keys, and serialized fields compatible. A required data migration needs old-format fixtures and explicit handling.
- Send playlist and multi-URL work through `enqueueBatchMediaDownloads`; do not duplicate task creation, output-directory handling, or name sanitization in a screen or widget.
- Treat `DownloadRegistry` as the source for completed library media. Do not scan shared storage or show unrelated device files in the library.
- Resolve and physically verify writable output directories before deriving final or temporary paths. Preserve existing files and partial downloads; reserve unique names when falling back to another directory.
- Keep YouTube format selection exact. Preserve selected itag, codec, dimensions, frame rate, companion-audio policy, and strict transfer/output validation. Do not silently downgrade a requested quality.
- Use the shared `MediaMerger` path and existing container/codec policy for new sources. WebM/AAC incompatibility and timing validation are documented in `AGENTS.md`.
- Use `openMediaFile` for external media file access. Do not pass file URIs to `launchUrl`.
- Keep logs and diagnostics redacted. Never log signed URLs, cookies, or tokens.
- Preserve the Android foreground-service declarations and permissions described in `AGENTS.md`. Do not describe notifications as a guarantee that background work survives process death or OS termination.
- Keep probes and benchmarks under `tool/` or their existing test location. Do not use a diagnostic entrypoint as the normal app entrypoint.

## Tests and verification

Run Flutter commands serially when they share the same build directory; concurrent test and build processes can race in generated native assets. Before committing, the expected project checks are:

```bash
flutter pub get
dart analyze
flutter test --reporter expanded
flutter build apk --release
```

Inspect `pubspec.lock` after dependency resolution and include any intended lockfile changes. A tool or SDK access failure means that check was not run; report it as such rather than as an application failure or a pass.

Add or update focused tests for the behavior changed, then run the full suite as well. Depending on the affected area, review the relevant existing coverage for:

- URL parsing, extractor fixtures, stream and quality selection, playlist/batch preparation.
- Download queue admission, progress, cancellation, retry, restoration, and registry behavior.
- Output path selection, file collisions, storage fallback, merge/validation, and partial-file preservation.
- Navigation, lifecycle handling, player disposal, theming, and dialog layouts.
- Android manifest and foreground-service declarations for native or background-work changes.

Fixture tests and host-only probes do not prove live third-party availability or Android device behavior. If you run a live source or device check, state the device/source, conditions, and observed result. Clearly distinguish injected failures from naturally occurring failures. Only claim verification from checks actually run for the change.

## Pull request checklist

Before submitting, confirm that the pull request:

- Explains the problem and the resulting behavior in plain language.
- Links the related issue, if one exists.
- Keeps unrelated changes out of the diff and includes tests for changed behavior.
- Reports the commands run and their results; identifies checks that were unavailable.
- Includes screenshots or a short recording when the UI changes.
- Calls out migration, dependency, permission, Android manifest, or storage effects.
- States limitations and unverified behavior, especially for live extraction and background execution.

Keep the pull request description focused. Do not include secrets, signed URLs, user data, or private diagnostic output.

## Review and licensing

Maintainers may request revisions to clarify behavior, add coverage, or preserve compatibility. Please update the same pull request as the discussion progresses.

By contributing, you agree that your contribution is provided under the repository's [MIT License](LICENSE).
