# Feature Specification: Velora v2 Architecture, Security & Precision Studio Overhaul

- **Spec ID:** `specs/001-velora-v2-overhaul/spec.md`
- **Status:** `Clarified`
- **Date:** `2026-11-27`
- **Mode:** `Brownfield Delta`

## 0. Ponytail Ultra Gate ("Should This Exist?")
- **Problem Statement:** Baseline engineering and UI/UX audits uncovered 5 `CRITICAL`/`HIGH` trust-boundary vulnerabilities (fail-open auto-updater checksums, unverified `yt-dlp` binary execution, missing `--ignore-config`/`--no-exec`, root `$TMPDIR` TOCTOU & symlink bypass, GitHub Actions script injection), deterministic subprocess pipe truncation & orphan `ffmpeg` leaks, complete queue data loss on quit/update, `20–80×/sec` whole-window SwiftUI re-render storms + main-thread `fsync` hitches per keystroke, broken `WebM`/`WAV`/`|`-title/video-only format handling, and hard-banned neon AI-slop UI (`1.72:1` CTA contrast, Light Mode collapse, stretched 650pt `Picker`s, clipped presets, `0` VoiceOver labels).
- **Existing Alternatives Checked:** Built entirely on Apple standard frameworks (`SwiftUI`, `AppKit`, `Foundation`, `CryptoKit`, `Security`, `UserNotifications`, `QuickLookUI`, `ImageIO`) and existing `yt-dlp` JSON/retry flags — **zero external SwiftPM packages added** (no Sparkle, SQLite, or third-party UI kits required).
- **Smallest Viable Scope (Explicitly Cut):** Cut embedded WebKit browser/link-sniffer tabs, Safari/Chrome browser extension targets (replaced cleanly by lightweight `velora://` URL scheme + opt-in clipboard detector), custom transcoding timelines, and external `aria2c` daemon bundling (`yt-dlp -N` concurrent fragments already covers multi-connection acceleration).

---

## 1. User Scenarios & Acceptance Criteria

### Scenario 1 — Fail-Closed Auto-Updater & Code Signature Continuity (Priority: P1)
- **Given** Velora checks GitHub Releases for an update on a valid `owner/repo` over HTTPS
- **When** `SHA256SUMS.txt` is missing, returns non-200 HTTP, omits the `.zip` filename, mismatches `CryptoKit.SHA256`, contains symlinks or a path-traversing `CFBundleExecutable`, or fails `SecStaticCodeCheckValidity` (including matching `TeamIdentifier` when the installed app is Developer-ID signed)
- **Then** Velora aborts staging before quarantine removal or bundle replacement, cleans up temporary files via trap, preserves any existing `.velora-backup` bundle, and surfaces an explicit verification error.

### Scenario 2 — 1-Click Verified Standalone Engine Setup Without Homebrew (Priority: P1)
- **Given** a Mac without Homebrew, `yt-dlp`, `ffmpeg`, or a JS runtime installed
- **When** the user opens `EngineSetupSheet` (or clicks `Download Now` while `yt-dlp` is missing, which intercepts and opens `EngineSetupSheet` instead of enqueueing a doomed failure) and clicks 1-click install for `yt-dlp`, `ffmpeg` (`+ ffprobe`), or `deno`
- **Then** `EngineManager` downloads the architecture-matched archive/binary over HTTPS, verifies its official companion `SHA-256` manifest (`SHA2-256SUMS` / `.sha256` / `.sha256sum`) *before* setting `0o755` or stripping quarantine, atomically installs into `~/Library/Application Support/Velora/bin` via `replaceItemAt`, and refreshes version badges.

### Scenario 3 — Hardened `yt-dlp` Execution, JSON Wire Protocol & Format Accuracy (Priority: P1)
- **Given** any single-video, playlist, clip, or custom-format download
- **When** `YTDLPCommandBuilder` constructs arguments and `YTDLPOutputParser` parses output
- **Then** `--ignore-config`, `--no-exec`, and `--` are enforced; dangerous `extraArguments` (`--exec`, `--config-locations`, `--plugin-dirs`, `--load-info-json`) and non-`http(s)` URLs are rejected; `VELORA_META_JSON:`, `VELORA_PROGRESS_JSON:`, and `VELORA_FILEPATH_JSON:` parse titles containing `|` and live streams accurately; `--embed-thumbnail` is suppressed on unsupported `webm`/`wav`/`aac` targets; selecting a video-only stream in `FormatPickerSheet` under `Video + Audio` appends `+bestaudio/best`; `Best MP4` preserves 4K resolution; `Arc` cookies resolve Arc's profile directory; and optional `cookies.txt` file selection works.

### Scenario 4 — Persistent Queue, True Pause/Resume, Auto-Retry & Process-Group Cleanup (Priority: P1)
- **Given** active, queued, and paused items in `DownloadManager`
- **When** the user pauses an active item, quits Velora (`⌘Q`), applies an in-app update, or experiences a transient network drop
- **Then** `VeloraStore` persists `queue.json` atomically off `@MainActor` inside a v2 schema envelope (preserving `.corrupt-*.bak` on malformed files); pausing or quitting terminates the entire POSIX process group (`yt-dlp` + child `ffmpeg`, `SIGTERM` -> `2s` -> `SIGKILL`) with zero orphan processes; trailing kernel pipe bytes (`VELORA_FILEPATH_JSON`) are drained before exit handling; interrupted active items restore as `.paused` and resume from `.part` via `--continue`; and playlists display in natural `#01 -> #N` order.

### Scenario 5 — Zero-Jank 120Hz SwiftUI Observation & Async Disk/Image Pipeline (Priority: P1)
- **Given** 4–8 concurrent active downloads streaming progress and logs while the user types in `ConfigurationPanelView` or scrolls a 200-item playlist/history list
- **When** `yt-dlp` emits progress/log lines
- **Then** per-item `@Observable DownloadTask` isolation + `100ms` (`10 Hz`) progress coalescing updates *only* the affected `QueueItemCard` progress subview without re-rendering `VeloraApp` menus, `MainWindowView`, or `StudioView`; configuration writes debounce (`300ms`) on `actor VeloraStore`; `HistoryView` uses async cached file-existence state (`0` `stat()` calls in `body`); and thumbnails load via downsampled `NSCache` `CachedThumbnailView` across Preview, Playlist, Queue, and History.

### Scenario 6 — Precision Studio Cobalt UI, Light/Dark Adaptation & 4-State Completeness (Priority: P1)
- **Given** Velora running in either macOS Light Mode or Dark Mode
- **When** navigating `Studio`, `Queue`, `History`, `Presets`, `Settings`, and modal sheets
- **Then** all surfaces follow `PRODUCT.md` (`Precision Studio Cobalt` single accent `#3B49DF` / `#4F5BFF`, zero neon violet-to-cyan gradients, all text/badges `>= 4.5:1` contrast, `.monospacedDigit()` on all numeric readouts); `Quick Presets` renders all 6 presets in an unclipped 3×2 grid with active-preset indicator; `ConfigurationPanelView` constrains `Picker` widths (`<= 280pt`) with inline validation; `StudioView` shows a `CLS = 0` skeleton while inspecting and `Retry` / `Try Browser Cookies` on error; toasts render semantic icons/colors by `ToastKind`; destructive actions (`Cancel All`, `Clear History`, `Delete Preset`) prompt confirmation; and opening sheets from `SettingsView` presents cleanly in front.

### Scenario 7 — WCAG 2.2 AA, VoiceOver & Keyboard Operability (Priority: P1)
- **Given** macOS VoiceOver, Full Keyboard Access (`Tab`), or `Reduce Motion` enabled
- **When** operating all controls, icon buttons, preset cards, and playlist selection rows
- **Then** every control exposes an accurate contextual `.accessibilityLabel` and `.accessibilityValue`, has a `>= 24×24pt` hit target and visible `:focus-visible` ring, uses native accessible toggle semantics in `PlaylistPickerSheet` (with unavailable items disabled), suppresses motion curves when `accessibilityReduceMotion` is true, and announces async errors/toasts.

### Scenario 8 — Native macOS Superpowers: MenuBarExtra, Dock, Notifications & Quick Look (Priority: P2)
- **Given** Velora running in the background or menu bar
- **When** downloads progress, complete, or fail, or the user presses `Space` on a finished item
- **Then** `MenuBarExtra` provides live aggregate speed/progress, quick `Paste & Download`, and pause/resume controls; `NSApp.dockTile` displays active download count; `UNUserNotificationCenter` posts completion/failure notifications when Velora is inactive; and pressing `Space` (or clicking Quick Look) previews finished media via native macOS Quick Look.

### Scenario 9 — `velora://` Deep-Link Scheme & Smart Clipboard URL Pill (Priority: P2)
- **Given** a `velora://download?url=...` or `velora://inspect?url=...` URL opened from a browser/bookmarklet/Shortcut, or a supported media URL copied to `NSPasteboard` when bringing Velora to foreground (when opt-in setting is enabled)
- **When** Velora receives the URL or foreground event
- **Then** `velora://` strictly validates `http`/`https` scheme (ignoring any unapproved flag parameters) and triggers download/inspection, while clipboard detection surfaces a non-intrusive 1-click `"Paste & Inspect <domain>"` pill in `StudioView` without auto-mutating the user's current input.

### Scenario 10 — Hardened GitHub Actions CI & Release Pipeline (Priority: P1)
- **Given** a push, PR, git tag, or `workflow_dispatch` release run
- **When** `.github/workflows/ci.yml` or `release.yml` executes
- **Then** zero `${{ ... }}` expressions are interpolated inside `run:` shell blocks, `version` is validated against strict SemVer 2.0.0, all GitHub Actions are pinned to 40-char commit SHAs with minimal `permissions`, and temporary signing certificates/keychains are shredded in an `if: always()` step.

---

## 2. Delta Summary (OpenSpec Brownfield Delta)
- **ADDED:**
  - `PRODUCT.md`, `CONTEXT.md`, `.kobean/constitution.md`, `docs/adr/ADR-001-*.md`, `docs/adr/ADR-002-*.md`.
  - `Sources/VeloraCore/Engine/ProcessSupervisor.swift` — POSIX process-group lifecycle (`setpgid` + `SIGTERM` -> `SIGKILL`), timeout, and complete EOF pipe draining.
  - `Sources/Velora/Views/MenuBarQueueView.swift` & `Sources/Velora/System/MacSystemBridge.swift` — `MenuBarExtra`, `NSDockTile`, `UNUserNotificationCenter`, clipboard URL detector, and `velora://` deep-link router.
  - `Sources/Velora/Theme/CachedThumbnailView.swift` — `NSCache` + `CGImageSource` downsampled async image loader.
  - `queue.json` persistence (`VeloraStoreEnvelope` v2), 1-click SHA-256 verified standalone `ffmpeg`/`ffprobe` & `deno` installers, per-item Pause/Resume (`--continue`), `cookies.txt` file support, and Quick Look preview.
  - Comprehensive Swift Testing suites: `VeloraStoreTests.swift`, `EngineManagerTests.swift`, `MediaInspectorTests.swift`, `DownloadManagerTests.swift`.
- **MODIFIED:**
  - `UpdateChecker.swift` & `AppUpdateInstaller.swift` — Fail-closed `SHA256SUMS.txt`, `SecStaticCode` check, symlink/`CFBundleExecutable` validation, safe root swap & backup preservation.
  - `EngineManager.swift`, `YTDLPCommandBuilder.swift`, `YTDLPOutputParser.swift`, `MediaInspector.swift`, `DownloadManager.swift`, `DownloadItem.swift`, `DownloadConfiguration.swift`, `DownloadPreset.swift`, `VeloraStore.swift`.
  - `VeloraTheme.swift`, `VeloraApp.swift`, all 12 files in `Sources/Velora/Views/`, `scripts/generate-icon.swift`, `scripts/build-app.sh`, `Resources/Info.plist.template`, `.github/workflows/ci.yml`, `.github/workflows/release.yml`.
- **REMOVED:**
  - Hard-banned `VeloraTheme.brandGradient` (`violet -> cyan`) and unused `VeloraTheme.magenta` token.
  - Legacy pipe-delimited `VELORA_META|` / `VELORA_PROGRESS|` / `VELORA_FILEPATH|` wire strings (replaced by JSON wire contracts).
  - Duplicate top-right toolbar Engine Setup & Check Updates icons on `MainWindowView`.

---

## 3. Edge Cases & Failure Modes
- **Invalid / Empty / Malicious Input:** Reject non-`http(s)` URLs (`file://`, `javascript:`, leading `-`), cap dropped `.txt`/`.csv` files to `<= 1 MB` UTF-8 plain text off `@MainActor`, reject dangerous `extraArguments` flags with an inline explanation, and block `CFBundleExecutable` or playlist folder names containing `..` or `/`.
- **Network / Upstream Failure:** Enforce bounded `--socket-timeout`, `--retries`, `--fragment-retries`, and `--retry-sleep exp=1:16`; surface actionable `Retry` + `Try Browser Cookies` buttons on extractor auth/rate-limit failures; handle live streams (`total_bytes == nil`) with indeterminate live badge instead of `0%` stall.
- **Concurrency / Race Conditions:** Drain stdout/stderr pipes to EOF before `terminationHandler` finalizes task state; guard `!task.status.isTerminal` against late progress callbacks; prevent engine binary replacement while `DownloadManager.hasActiveDownloads` is true; guard corrupt JSON files with `.corrupt-<timestamp>.bak` backups.
- **Security / Trust Boundary:** `Yes -> require specs/001-velora-v2-overhaul/threats.md` (auto-updater, binary installer, subprocess execution, browser cookies, custom URL scheme, CI signing secrets).

## 4. Out of Scope
- Embedded web browser / media stream packet sniffer, browser extension store packages, DRM decryption, cloud sync, or Windows/Linux targets.
