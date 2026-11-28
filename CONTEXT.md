# CONTEXT.md — Velora Codebase Map & Architecture

> Generated during `kb-spec` codebase orientation (`explorer` + `architect` + `security` + `ui-ux-designer`).

## 1. System Overview
**Velora** is a native macOS 14+ (`Sonoma` / `Sequoia`) video & audio studio downloader built with **Swift 6** (`swift-tools-version: 6.0`, strict concurrency enabled) and **SwiftUI**, powered by external `yt-dlp`, `ffmpeg`, and JS runtime (`deno`/`bun`/`node`/`quickjs`) subprocesses, with zero third-party Swift package dependencies and a built-in GitHub Releases close-and-relaunch auto-updater.

## 2. Target Graph (`Package.swift`)
- **`VeloraCore`** (`Sources/VeloraCore/`) — Domain models, `yt-dlp` CLI builder & output parser, subprocess engine & media inspector, JSON persistence, and GitHub Releases updater.
  - `Models/`:
    - `DownloadConfiguration.swift` — Quality, container, codec, subtitle, SponsorBlock, clipping, playlist, cookie, proxy, and network options.
    - `DownloadItem.swift` — `DownloadTaskItem` (queue state + logs) and `DownloadHistoryEntry`.
    - `DownloadPreset.swift` — 6 built-in presets + user custom preset model.
    - `MediaInfo.swift` — Inspected video/playlist metadata, `PlaylistEntry`, and `MediaFormat` stream descriptors.
    - `SemVer.swift` — SemVer 2.0.0 parser and comparator.
  - `Engine/`:
    - `EngineManager.swift` — Binary discovery (`yt-dlp`, `ffmpeg`, JS runtimes, Homebrew), `PATH` enrichment, managed `yt-dlp_macos` installer, and `ProcessLineAccumulator`.
    - `YTDLPCommandBuilder.swift` — Translates `DownloadConfiguration` into `yt-dlp` CLI arguments, shell previews, and bulk URL extraction.
    - `YTDLPOutputParser.swift` — Parses `VELORA_PROGRESS|`, `VELORA_META|`, `VELORA_FILEPATH|`, and fallback `yt-dlp` output lines.
    - `MediaInspector.swift` — Runs `yt-dlp --dump-single-json` with timeout/cancellation and `PlaylistURLDetector` helpers.
    - `DownloadManager.swift` — `@MainActor @Observable` queue scheduler, subprocess lifecycle, live progress/log routing, history, and custom presets.
  - `Persistence/`:
    - `VeloraStore.swift` — JSON persistence in `~/Library/Application Support/Velora/` (`history.json`, `custom-presets.json`, `last-configuration.json`).
  - `Updates/`:
    - `GitHubRelease.swift` — GitHub Releases API models, universal `.zip` + `SHA256SUMS.txt` asset matcher.
    - `UpdateChecker.swift` — `@MainActor @Observable` release checker and `URLSessionDownloadDelegate` downloader.
    - `AppUpdateInstaller.swift` — CryptoKit SHA-256 hashing, `ditto` extraction, bundle validation, and detached POSIX shell close-and-relaunch script.
- **`Velora`** (`Sources/Velora/`) — Native macOS SwiftUI executable target depending on `VeloraCore`.
  - `VeloraApp.swift` — `@main` `App`, menu commands, `VeloraAppDelegate`, and `@MainActor @Observable StudioViewModel`.
  - `Theme/VeloraTheme.swift` — Color tokens, card modifiers, `VeloraBadge`, and `VeloraPrimaryButtonStyle`.
  - `Views/` — `MainWindowView`, `StudioView`, `ConfigurationPanelView`, `MediaPreviewCard`, `FormatPickerSheet`, `PlaylistPickerSheet`, `QueueView`, `HistoryView`, `PresetsView`, `SettingsView`, `EngineSetupSheet`, `UpdateSheetView`.
- **`VeloraCoreTests`** (`Tests/VeloraCoreTests/`) — Swift Testing (`@Suite` / `@Test`) suite (`21` baseline tests across 5 files).
- **Build & CI/CD** (`Makefile`, `scripts/*.sh`, `scripts/generate-icon.swift`, `.github/workflows/ci.yml`, `.github/workflows/release.yml`).

## 3. Baseline Audit Hotspots (Summary for `kb-spec` / `kb-plan`)
- **Trust Boundaries (`CRITICAL`/`HIGH`):** Fail-open `SHA256SUMS.txt` checks in `UpdateChecker`, missing `SHA2-256SUMS` verification in `EngineManager`, missing `--ignore-config` & `--no-exec` + raw `extraArguments` in `YTDLPCommandBuilder`, `AppUpdateInstaller` `$TMPDIR` root TOCTOU & symlink/`CFBundleExecutable` traversal, and `${{ inputs.version }}` shell injection in `release.yml`.
- **Engine & Persistence (`HIGH`):** `terminationHandler` kernel pipe truncation in `DownloadManager`, orphan `yt-dlp`/`ffmpeg` child processes on quit/cancel, missing `queue.json` persistence across restarts/updates, synchronous `@MainActor` disk `fsync` per keystroke, `--embed-thumbnail` breaking `webm`/`wav`/`aac`, `|` title delimiter corruption, and video-only `FormatPicker` dropping audio.
- **UI/UX, SwiftUI Perf & A11y (`HIGH`):** Hard-banned violet-to-cyan gradient (`1.72:1` contrast) and broken Light Mode tokens in `VeloraTheme`, stretched 650pt `Picker`s, clipped `Quick Presets` strip, whole-tree `@Observable` array invalidation on every `yt-dlp` stdout line, and zero VoiceOver/accessibility labels across all 14 view files.
