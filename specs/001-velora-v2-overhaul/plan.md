# Technical Implementation Plan: Velora v2 Architecture, Security & Precision Studio Overhaul

- **Plan Path:** `specs/001-velora-v2-overhaul/plan.md`
- **Spec Reference:** `specs/001-velora-v2-overhaul/spec.md`
- **Threat Model:** `specs/001-velora-v2-overhaul/threats.md`
- **Design System:** `PRODUCT.md`
- **Data & Wire Contracts:** `specs/001-velora-v2-overhaul/data-model.md`
- **ADRs:** `docs/adr/ADR-001-per-item-observable-and-actor-store.md`, `docs/adr/ADR-002-fail-closed-supply-chain-and-subprocess-isolation.md`
- **Date:** `2026-11-27`

---

## 1. Codebase Context & Blast Radius

### 1.1 Files to Create (8 Source/Test Files)
- `Sources/VeloraCore/Engine/ProcessSupervisor.swift` — POSIX process-group runner (`setpgid`, `SIGTERM` -> `2s` -> `SIGKILL`), bounded timeouts, and complete EOF pipe draining before termination callbacks.
- `Sources/Velora/Theme/CachedThumbnailView.swift` — `NSCache<NSURL, NSImage>` + `CGImageSourceCreateThumbnailAtIndex` downsampled async thumbnail component (`392px` preview / `128px` list rows).
- `Sources/Velora/System/MacSystemBridge.swift` — `NSApp.dockTile` badge controller, `UNUserNotificationCenter` manager, opt-in `NSPasteboard` URL change detector, and `velora://` deep-link parser/router.
- `Sources/Velora/Views/MenuBarQueueView.swift` — Native `MenuBarExtra` scene view with aggregate progress/speed, `Paste & Download`, pause/resume toggle, and recent tasks.
- `Tests/VeloraCoreTests/VeloraStoreTests.swift` — Unit tests for `VeloraStoreEnvelope` v2, v1 fallback migration, `.corrupt-*.bak` preservation, and `PersistedQueueState` recovery.
- `Tests/VeloraCoreTests/EngineManagerTests.swift` — Unit tests for `ProcessLineAccumulator` (`UTF8.self` lossy decoding, `256 KB` cap), `PATH` ordering, and `URLProtocol`-mocked fail-closed `SHA-256` standalone installers (`yt-dlp`, `ffmpeg`, `deno`).
- `Tests/VeloraCoreTests/MediaInspectorTests.swift` — Unit tests for `--ignore-config --no-exec`, timeout/cancellation, leading warning resilience, and live stream metadata decoding.
- `Tests/VeloraCoreTests/DownloadManagerTests.swift` — Unit tests for natural FIFO playlist ordering, concurrency caps, `readabilityHandler` vs `terminationHandler` EOF ordering, `!status.isTerminal` race guard, pause/resume, and `queue.json` persistence.

### 1.2 Files to Modify (27 Existing Files)
- **DevOps & Bundle Config (`devops`):**
  - `.github/workflows/release.yml` — Move all `${{ ... }}` into `env:`, enforce SemVer regex gate, quote `'EOF'`, pin actions to 40-char commit SHAs (`actions/checkout@11d5960a326750d5838078e36cf38b85af677262`, `softprops/action-gh-release@3bb12739c298aeb8a4eeaf626c5b8d85266b0e65`), add `if: always()` `.p12`/keychain cleanup.
  - `.github/workflows/ci.yml` — Add `permissions: contents: read`, move `${{ ... }}` into `env:`, pin `actions/checkout@11d5960a326750d5838078e36cf38b85af677262` and `actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02`.
  - `scripts/build-app.sh` — XML-escape plist substitutions before writing `Info.plist`.
  - `Resources/Info.plist.template` — Register `CFBundleURLTypes` for `velora://` (`com.kobenguyent.velora.urlscheme`).
- **Core Models, Persistence, Engine & Updates (`backend`):**
  - `Sources/VeloraCore/Models/DownloadConfiguration.swift` — Add `cookieFilePath`, `autoRetryCount`, `resumePartialDownloads`; fix `BrowserCookiesSource.arc` (`chrome:~/Library/Application Support/Arc/User Data`).
  - `Sources/VeloraCore/Models/DownloadItem.swift` — Add `.paused` to `DownloadStatus`; introduce `@MainActor @Observable final class DownloadTask`, `@MainActor @Observable final class DownloadLogBuffer`, and `DownloadTaskSnapshot`; remove synchronous `fileExistsOnDisk` loop hazard.
  - `Sources/VeloraCore/Models/DownloadPreset.swift` — Align `Best MP4` and `Apple Pro` codec/container defaults for reliable 4K & QuickTime playback.
  - `Sources/VeloraCore/Persistence/VeloraStore.swift` — Convert to `actor VeloraStore` (with synchronous bootstrap loader on launch + async atomic v2 envelope writer & `.corrupt-*.bak` preservation) and add `loadQueue()` / `saveQueue(_:)`.
  - `Sources/VeloraCore/Updates/UpdateChecker.swift` — Enforce fail-closed `SHA256SUMS.txt` (`HTTP 200` + mandatory digest match), `githubRepository` regex + HTTPS GitHub host check, `.lastPathComponent` sanitization, and `100ms` download progress throttling.
  - `Sources/VeloraCore/Updates/AppUpdateInstaller.swift` — Add `SecStaticCodeCheckValidity` + `TeamIdentifier` continuity check, symlink & `CFBundleExecutable` traversal rejection, `0o700` staging, backup-preserving `swap_direct`, `EXIT` cleanup trap, and direct constant root swap command.
  - `Sources/VeloraCore/Engine/YTDLPCommandBuilder.swift` — Prepend `["--ignore-config", "--no-exec"]`, enforce `extraArguments` denylist + trailing `"--no-exec"`, validate `http(s)` URLs, switch to `VELORA_META_JSON:` / `VELORA_PROGRESS_JSON:` / `VELORA_FILEPATH_JSON:`, guard `--embed-thumbnail` against `webm`/`wav`/`aac`, append `+bestaudio/best` for video-only custom format IDs in `.videoAndAudio`, fix `-S` sort tokens & `.allAvailable` subtitle `all,-live_chat`, add `--continue`, `--retries`, `--fragment-retries`, `--retry-sleep`, and `--cookies`.
  - `Sources/VeloraCore/Engine/YTDLPOutputParser.swift` — Parse JSON wire events (`VELORA_META_JSON:`, `VELORA_PROGRESS_JSON:`, `VELORA_FILEPATH_JSON:`) including live stream progress and pipe `|` characters in titles.
  - `Sources/VeloraCore/Engine/EngineManager.swift` — Verify `SHA2-256SUMS` before installing `yt-dlp_macos`; add 1-click verified standalone `ffmpeg` + `ffprobe` (`martin-riedl.de` `.sha256`) and `deno` (`.zip.sha256sum`) installers via atomic `replaceItemAt`; fix `PATH` ordering; allowlist `brew install --formula --`; add `nvm`/`fnm`/`mise` JS discovery; use `ProcessSupervisor`.
  - `Sources/VeloraCore/Engine/MediaInspector.swift` — Pass `--ignore-config --no-exec`, enforce `http(s)`, tolerate leading non-JSON lines, and decode `isLive` metadata.
  - `Sources/VeloraCore/Engine/DownloadManager.swift` — Manage `[DownloadTask]` with `O(1)` cached status counters, `100ms` progress coalescing, `ProcessSupervisor` group kill + EOF drain, natural `#01..#N` playlist insertion, per-item `pause(id:)` / `resume(id:)`, duplicate URL guard, pre-flight disk capacity check, and debounced `queue.json` persistence.
  - `Tests/VeloraCoreTests/UpdateServiceTests.swift`, `YTDLPCommandBuilderTests.swift`, `YTDLPOutputParserTests.swift`, `BulkPlaylistTests.swift` — Expand with Red-phase security & accuracy regression tests.
- **macOS SwiftUI Theme, Views & Icon (`frontend`):**
  - `Sources/Velora/Theme/VeloraTheme.swift` & `scripts/generate-icon.swift` — Implement `PRODUCT.md` adaptive Light/Dark `Precision Studio Cobalt` tokens (`>= 5.0:1` contrast), `.monospacedDigit()`, and `:focus-visible` ring modifier; retire `brandGradient`.
  - **`Sources/Velora/VeloraApp.swift` & `Sources/Velora/Views/MainWindowView.swift`** — Single `Window("Velora", id: "main")` + `MenuBarExtra`, `⌘0`/`⌘1–4`/`⌘L`/`⌘I`/`⌘F` shortcuts, `VeloraAppDelegate` quit confirmation & process-group cleanup, app-level sheet coordinator (fixing `SettingsView` sheet z-order), typed `ToastKind`, missing-engine intercept on `Download Now`, **approved `M2 · Apple Gallery` zero-sidebar centered segmented pill navigation**, `velora://` handler, and debounced `300ms` config saves.
  - **`Sources/Velora/Views/StudioView.swift`, `ConfigurationPanelView.swift`, `MediaPreviewCard.swift`, `FormatPickerSheet.swift`, `PlaylistPickerSheet.swift`** — Floating Spotlight Hero Command Pill, whisper preset capsule + 6 whisper-quiet preset chips, collapsed-by-default Apple-Settings `All Download Options` disclosure (`<= 220pt` right-aligned controls, inline validation, `cookies.txt` picker), quiet hairline Recent Activity strip, `CLS = 0` `MediaPreviewSkeletonCard`, `Retry` / `Try Browser Cookies` error actions, clipboard URL pill, safe `<= 1 MB` text drop guard, `ContentUnavailableView` empty states, and accessible `Toggle` rows.
  - `Sources/Velora/Views/QueueView.swift`, `HistoryView.swift`, `PresetsView.swift`, `SettingsView.swift`, `EngineSetupSheet.swift`, `UpdateSheetView.swift` — Fine-grained `DownloadTask` subviews + thumbnails + Pause/Resume + auto-scrolling `LogDrawerView` (`Copy Log`) + `.quickLookPreview` (`Space`), async cached `fileExistsOnDisk` + filter/sort + confirmation dialogs, custom preset editing/duplication, 1-click standalone `yt-dlp`/`ffmpeg`/`deno` setup UI, block-markdown release notes, and full WCAG 2.2 AA VoiceOver labels + `Reduce Motion` gating.

---

## 2. Role Assignment & Non-Overlapping Write Ownership (`doctrine.md` §5.1 & §6.3)

| Stage | Role (`model_tier`) | Orchestration | Exclusive Write Paths | Beads IDs |
| :---: | :--- | :--- | :--- | :--- |
| **Stage 1A** | `devops` (`pro`/`inherit`) | Parallel Subagent 1 | `.github/workflows/**`, `scripts/build-app.sh`, `Resources/Info.plist.template` | `velora-e07` |
| **Stage 1B** | `backend` (`pro`/`inherit`) | Parallel Subagent 2 | `Sources/VeloraCore/Persistence/**`, `Sources/VeloraCore/Models/DownloadItem.swift`, `Sources/VeloraCore/Models/DownloadConfiguration.swift`, `Tests/VeloraCoreTests/VeloraStoreTests.swift` | `velora-6k4` |
| **Stage 1C** | `backend` (`pro`/`inherit`) | Parallel Subagent 3 | `Sources/VeloraCore/Updates/**`, `Tests/VeloraCoreTests/UpdateServiceTests.swift` | `velora-ylk` |
| **Stage 2** | `backend` (`pro`/`inherit`) | Sequential Core Subagent (reused via `send_message`) | `Sources/VeloraCore/Engine/**`, `Sources/VeloraCore/Models/DownloadPreset.swift`, `Tests/VeloraCoreTests/{YTDLP*,EngineManager*,MediaInspector*,DownloadManager*,BulkPlaylist*}.swift` | `velora-tc3` -> `velora-0h3` -> `velora-ejr` |
| **Stage 3A** | `frontend` (`pro`/`inherit`) | Theme + App Shell Subagent | `Sources/Velora/Theme/**`, `Sources/Velora/System/**`, `Sources/Velora/VeloraApp.swift`, `Sources/Velora/Views/{MainWindowView,MenuBarQueueView}.swift`, `scripts/generate-icon.swift` | `velora-7ez` -> `velora-a1h` |
| **Stage 3B** | `frontend` (`pro`/`inherit`) | 2 Parallel View Slice Subagents | **Slice 1:** `StudioView`, `ConfigurationPanelView`, `MediaPreviewCard`, `FormatPickerSheet`, `PlaylistPickerSheet` (`velora-mon`)<br>**Slice 2:** `QueueView`, `HistoryView`, `PresetsView`, `SettingsView`, `EngineSetupSheet`, `UpdateSheetView` (`velora-cun`) -> A11y Pass (`velora-kv9`) | `velora-mon`, `velora-cun` -> `velora-kv9` |
| **Stage 4** | `reviewer`, `security`, `a11y-auditor`, `qa` | Parallel `research` Gate + `qa` Execution | Read-only audit + terminal `make test`, `make app`, `codesign`, `betterleaks` | `velora-lqd` |

---

## 3. Verification Strategy (Red-Green-Refactor TDD)

1. **Red Phase (Write Failing Swift Testing Assertions First):**
   - `UpdateServiceTests`: Assert `downloadUpdate` fails closed when `checksumAsset == nil`, HTTP `404`/`500`, or filename missing; assert `validateAppBundle` rejects symlinks and `CFBundleExecutable = "../../bin/sh"`; assert `buildUpdaterScript` preserves `$BACKUP_APP` when `$TARGET_APP` is missing and registers `trap ... EXIT`.
   - `VeloraStoreTests`: Assert v1 bare-array files migrate to v2 `VeloraStoreEnvelope`, corrupt JSON creates `.corrupt-*.bak` without wiping disk, and interrupted `.downloading` queue snapshots restore as `.paused`.
   - `YTDLPCommandBuilderTests` & `YTDLPOutputParserTests`: Assert `--ignore-config` & `--no-exec` always present, `--exec`/`--config-locations` in `extraArguments` rejected, non-`http(s)` URLs rejected, `VELORA_META_JSON:` preserves `|` in `"Part 1 | Official 4K"`, `webm`/`wav`/`aac` omit `--embed-thumbnail`, video-only `customFormatID` in `.videoAndAudio` emits `313+bestaudio/best`, and `Arc` cookie path resolves `Arc/User Data`.
   - `EngineManagerTests` & `MediaInspectorTests`: Assert `yt-dlp_macos` / `ffmpeg` / `deno` installer aborts before `chmod` on SHA-256 mismatch, `/usr/bin` precedes `~/.local/bin` in `enrichedEnvironment()`, and `ProcessLineAccumulator` decodes invalid UTF-8 bytes without dropping lines.
   - `DownloadManagerTests`: Assert 5-item playlist enqueues top-to-bottom `#01..#05` and executes `#01` first, trailing pipe bytes before process exit populate `outputFilePath`, late progress lines after `.cancelled`/`.completed` are ignored, and `pause(id:)` transitions active task to `.paused`.
2. **Build, Bundle & Security Gate (`velora-lqd`):**
   - `make test` (`swift test` — 100% pass across all 9 test suites, zero Swift 6 concurrency warnings).
   - `make app` (`./scripts/build-app.sh --arch native` + `plutil -lint` + `codesign --verify --deep --strict --verbose=2 dist/Velora.app`).
   - `betterleaks dir . -v` (`0` leaks).

---

## 4. Cross-Artifact Consistency Matrix (`speckit.analyze`)

| Spec Scenario / Threat | Planned Modules | Automated Test / Gate | Bead ID(s) |
| :--- | :--- | :--- | :--- |
| **S1 / T-01, T-04** (Fail-closed updater, `SecStaticCode`, safe swap) | `UpdateChecker.swift`, `AppUpdateInstaller.swift` | `UpdateServiceTests.swift` | `velora-ylk` |
| **S2 / T-02** (1-click SHA-256 `yt-dlp`, `ffmpeg`, `deno` + safe `PATH`) | `EngineManager.swift`, `EngineSetupSheet.swift` | `EngineManagerTests.swift` | `velora-0h3`, `velora-cun` |
| **S3 / T-03, T-06** (`--ignore-config`, `--no-exec`, JSON wire, formats) | `YTDLPCommandBuilder.swift`, `YTDLPOutputParser.swift` | `YTDLPCommandBuilderTests.swift`, `YTDLPOutputParserTests.swift` | `velora-tc3` |
| **S4 / T-08** (`queue.json`, pause/resume, process-group kill, EOF drain) | `VeloraStore.swift`, `ProcessSupervisor.swift`, `DownloadManager.swift` | `VeloraStoreTests.swift`, `DownloadManagerTests.swift` | `velora-6k4`, `velora-ejr` |
| **S5** (Per-item `@Observable`, `100ms` throttle, `NSCache` thumbs, async stat) | `DownloadItem.swift`, `DownloadManager.swift`, `CachedThumbnailView.swift`, `HistoryView.swift` | `DownloadManagerTests.swift` + build check | `velora-6k4`, `velora-ejr`, `velora-7ez`, `velora-cun` |
| **S6** (`PRODUCT.md` Cobalt UI, Light/Dark, 3×2 presets, 4-states, sheets) | `VeloraTheme.swift`, `MainWindowView.swift`, `StudioView.swift`, `ConfigurationPanelView.swift`, `Views/*.swift` | Contrast ratio math (`>= 5.0:1`) + `make app` | `velora-7ez`, `velora-a1h`, `velora-mon`, `velora-cun` |
| **S7** (WCAG 2.2 AA, VoiceOver, `>=24pt` targets, focus rings, Reduce Motion) | `VeloraTheme.swift`, `Sources/Velora/Views/*.swift` | `a11y-auditor` static + contrast gate | `velora-kv9`, `velora-lqd` |
| **S8** (`MenuBarExtra`, Dock badge, Notifications, Quick Look `Space`) | `VeloraApp.swift`, `MenuBarQueueView.swift`, `MacSystemBridge.swift`, `QueueView.swift`, `HistoryView.swift` | `make app` + URL/state unit tests | `velora-a1h`, `velora-cun` |
| **S9 / T-07** (`velora://` scheme & opt-in clipboard URL pill) | `Info.plist.template`, `MacSystemBridge.swift`, `StudioView.swift` | Deep-link parser security unit tests | `velora-e07`, `velora-a1h`, `velora-mon` |
| **S10 / T-05** (CI/Release `env:` hygiene, SHA-pinning, keychain cleanup) | `.github/workflows/{ci,release}.yml`, `scripts/build-app.sh` | `security` workflow audit + `betterleaks` | `velora-e07`, `velora-lqd` |

---

## 5. Beads Task Graph (`.beads/`)
> Single source of truth for execution state (`bd ready --json`).
- **Stage 1 Ready Wave:** `velora-e07`, `velora-6k4`, `velora-ylk`
- **Stage 2 Core Engine:** `velora-tc3`, `velora-0h3`, `velora-ejr`
- **Stage 3 UI & macOS Integration:** `velora-7ez`, `velora-a1h`, `velora-mon`, `velora-cun`, `velora-kv9`
- **Stage 4 Review & QA Gate:** `velora-lqd`
