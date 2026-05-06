# Changelog

All notable changes to PHOSPHOR are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] — 2026-05-06

### Added
- `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `CHANGELOG.md`
- GitHub issue templates (bug, feature) + pull-request template
- Dependabot config for `pub` and `github-actions`
- Continuous-integration workflow (`flutter analyze`, `dart format --set-exit-if-changed`, build smoke, tests)
- CodeQL workflow for GitHub Actions language scanning
- Font selector with three Nerd Font choices: Departure Mono (default), IBM 3270, JetBrains Mono
- Replay protection in `CryptoService` — receiver maintains a 1024-entry nonce LRU and rejects duplicates
- AI shell context now passed via the `system` parameter (was previously injected as fake user/assistant turns)
- Tightened `analysis_options.yaml`; added `.editorconfig`

### Changed
- Migrated to `flutter_riverpod` 3.x — `StateNotifier`/`StateProvider` ported to `Notifier`/`NotifierProvider`
- Bumped `go_router` 14 → 17, `audioplayers` → 6.6.0, `window_manager` → 0.5.1, `flutter_lints` → 6
- Bumped GitHub Actions: `checkout` v6, `upload-artifact` v7, `download-artifact` v8, `codeql-action` v4
- Settings persistence consolidated through a single `_update` diff-writer — only changed keys hit `SharedPreferences`
- Backward seeks in time-travel concatenate output events into a single `Terminal.write` call
- Initial PTY size standardised to VT100 80×24 across host, peer, and replay
- AI service throws consistently on configuration errors
- Session-service peer input exposed as a `Stream` instead of a public mutable callback

### Fixed
- EventStore append race: concurrent writes now serialise via a `_writeChain` future
- Peer joining mid-session now sees the host's actual terminal dimensions instead of the hard-coded fallback
- `_outputBuffer` for error detection bounded at 64 KB
- CrtOverlay ticker no longer runs at 60 fps when the shader is unavailable or intensity is zero
- PTY output `StreamSubscription` is retained and cancelled on dispose
- EventStore in-memory event list capped at 100 000 entries (on-disk JSONL keeps full history)

### Removed
- Pre-built macOS x86_64 release artifact — Apple Silicon only
- Pre-built Linux ARM64 release artifact — blocked on upstream Flutter aarch64 SDK
- Dead `TerminalEvent.id` field and the `uuid` dependency it required
- Dead `SessionState.serverUrl` field
- Unused `riverpod_annotation`, `riverpod_generator`, `build_runner`, `custom_lint`, `riverpod_lint` dev dependencies

## [0.1.5] — 2026-04-02

Release artifacts: macOS (Apple Silicon), Linux (x86_64).
See [GitHub release](https://github.com/nesdeq/phosphor/releases/tag/v0.1.5) for installation instructions.

## [0.1.4]

Initial public release.

[0.2.0]: https://github.com/nesdeq/phosphor/releases/tag/v0.2.0
[0.1.5]: https://github.com/nesdeq/phosphor/releases/tag/v0.1.5
[0.1.4]: https://github.com/nesdeq/phosphor/releases/tag/v0.1.4
