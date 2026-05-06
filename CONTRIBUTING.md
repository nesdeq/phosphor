# Contributing to PHOSPHOR

Thanks for thinking about contributing. PHOSPHOR is an open-source project and pull requests are welcome.

This document explains how to set up, what we expect, and how to land a change.

## Code of Conduct

By participating you agree to abide by the [Code of Conduct](CODE_OF_CONDUCT.md). Be kind, assume good faith, focus on the work.

## Reporting bugs

Open a [bug report issue](https://github.com/nesdeq/phosphor/issues/new?template=bug_report.yml). Include:

- PHOSPHOR version (toolbar shows it; or `Phosphor.app/Contents/Info.plist` on macOS)
- OS + version (`sw_vers` on macOS, `lsb_release -a` on Linux)
- Reproduction steps — the more concrete the better
- Expected vs actual behaviour

If the bug involves a crash, attach the relevant stack trace from the OS crash reporter.

## Suggesting features

Open a [feature request issue](https://github.com/nesdeq/phosphor/issues/new?template=feature_request.yml) and describe the use case before the proposed solution. We'd rather have a clear problem and discuss the fix than receive a PR for a thing we wouldn't merge.

## Reporting security issues

**Do not open a public issue for security vulnerabilities.** See [SECURITY.md](SECURITY.md) for the disclosure process — especially relevant for anything touching the multiplayer crypto, certificate pinning, or the relay protocol.

## Development setup

### Requirements

- Flutter ≥ 3.27.0 (stable channel)
- Dart ≥ 3.6.0
- Platform toolchain:
  - **macOS**: Xcode + command-line tools
  - **Linux**: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `liblzma-dev`, `libstdc++-12-dev`, `libgstreamer1.0-dev`, `libgstreamer-plugins-base1.0-dev`

### First run

```bash
git clone https://github.com/nesdeq/phosphor.git
cd phosphor
flutter pub get
flutter run -d macos     # or: flutter run -d linux
```

### Run the relay server locally

```bash
./server_setup.sh 127.0.0.1
cd server && ./server.sh
```

Then in PHOSPHOR Settings: `Relay Server: wss://127.0.0.1:8766`, `Server Cert: /absolute/path/to/public.pem`.

## Code style

- `flutter analyze` must pass with zero warnings — CI enforces this.
- `dart format .` must produce no diff — CI enforces this.
- Prefer relative imports inside `lib/` (already enforced by `analysis_options.yaml`).
- Match existing style: short comments only when the *why* is non-obvious; no decorative comments; no docstrings restating the function name.

## Architecture cheatsheet

```
lib/
├── app/              # Theme, router, shared widgets (CrtButton, CrtDialog, CrtTextField)
├── core/services/    # AI, crypto, event store, multiplayer session, sound, env
├── features/
│   ├── ai_assistant/    # ALAN side panel + Cmd+K command palette
│   ├── boot_sequence/   # BIOS-style POST screen
│   ├── multiplayer/     # Session lobby, participant overlay
│   ├── settings/        # DOS-style settings panel
│   ├── terminal/        # Main terminal screen + CRT shader overlay
│   └── time_travel/     # Timeline scrubber + replay engine
└── main.dart
```

State management is **Riverpod 2** (no codegen). The CRT shader lives at `shaders/crt.frag`. The relay server is a separate, dependency-light Dart program at `server/relay_server.dart`.

## Pull request process

1. **Open an issue first** for non-trivial changes so we can agree on the approach before you spend time.
2. Fork, branch off `main`, make your change.
3. Run `flutter analyze` and `dart format .` locally.
4. Add tests for non-UI logic where possible (`test/` directory). Pure-Dart code (crypto, parsing, regex) is easy to test.
5. Open the PR using the [template](.github/pull_request_template.md). Reference the issue with `Fixes #NNN` if appropriate.
6. CI must pass. A maintainer will review.

We don't squash by default — keep your commits clean and descriptive (`subject line under 70 chars, blank line, body explains *why*`). Rebase on `main` if your branch goes stale.

## Releases

Releases are tag-driven. Pushing a tag matching `v*` triggers `.github/workflows/release.yml` which builds and publishes artifacts for macOS (Intel + Apple Silicon) and Linux (x86_64 + ARM64).

Maintainers: bump `version` in `pubspec.yaml`, update `CHANGELOG.md`, commit, then `git tag vX.Y.Z && git push --tags`.

## License

By contributing you agree your work is licensed under the project's [GPL-2.0 license](LICENSE).
