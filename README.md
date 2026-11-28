# Velora

**Velora** is a native macOS 14+ (Sonoma / Sequoia) video and audio studio downloader built with **Swift 6** (`swift-tools-version: 6.0`, strict concurrency) and **SwiftUI**, powered by external `yt-dlp`, `FFmpeg`, and `Deno` JS runtime subprocesses with **zero external SwiftPM dependencies**.

Designed so macOS developers and creators can build, ad-hoc sign, and install locally **without a paid Apple Developer account**, ship universal macOS builds via hardened GitHub Actions workflows, and receive cryptographically verified close-and-relaunch updates straight from GitHub Releases.

---

## Highlights (v2)

- **Minimalist Apple Gallery UI (`M2 · Cobalt`) & Fluid Scaling**
  - Unified hidden-titlebar top navigation pill (`Studio | Queue | History | Presets`) with live Engine/Update status indicators and zero sidebar clutter.
  - Adaptive Light (`#F9FAFC`) and Dark (`#0E1014`) Cobalt design tokens calibrated for **WCAG 2.2 AA** contrast, tabular numerals (`.monospacedDigit()`), VoiceOver labels, `:focus-visible` keyboard rings, and `@Environment(\.accessibilityReduceMotion)` compliance.
  - Continuous proportional scaling (`1.0x–1.28x`) from compact macOS Split View (`680×500` min) through standard MacBooks (`1040×680` default) to 4K/5K/ultrawide fullscreen displays.
  - Single-ring Spotlight Hero command bar, full-width symmetric **6-Preset Gallery Grid** (`3×2` / `2×3`), `CLS = 0` inspection skeleton, and collapsed-by-default Apple-Settings **All Download Options** panel (switching automatically to 2 columns at `>= 940pt`).

- **Multi-Source Extraction, Stream Inspector & Playlists**
  - Single URL Spotlight inspection, **Batch Mode** multi-URL queue, `.txt`/`.csv` import, and full-window drag-and-drop (capped at `1 MB`, read off the main actor).
  - Pre-download metadata inspector (`thumbnail`, channel, duration, view count, `LIVE` stream indicator, detected resolutions) with interactive **Format Picker** (automatically pairs video-only picks with `+bestaudio/best` in Video + Audio mode).
  - Interactive **Playlist Picker** with range filtering (`1-10, 15`), per-entry selection, natural `#01 → #N` FIFO execution, and automatic playlist subfolders.

- **Comprehensive Download Configuration (Full `yt-dlp` Control)**
  - **Modes & Quality:** Video + Audio, Audio Only, Video Only · Best, 8K, 4K (2160p), 1440p, 1080p, 720p, 480p, 360p, Smallest.
  - **Containers & Codecs:** `MP4`, `MKV`, `WebM`, `MOV` · `M4A`, `MP3`, `FLAC`, `WAV`, `OPUS`, `AAC` · Preferred video codec (`Auto`, `H.264`, `HEVC`, `VP9`, `AV1`) and frame-rate cap (`Unlimited`, `60 fps`, `30 fps`).
  - **Subtitles & Metadata:** Preferred languages, auto-captions, or all tracks (`all,-live_chat`), embed subtitles, embed cover art (automatically skipped on incompatible `webm`/`wav`/`aac`), embed metadata/chapters, split chapters, and **SponsorBlock** mark/remove integration.
  - **Time-Range Clipping & Playlists:** Trim exact timestamps with optional keyframe-accurate cuts, playlist item ranges, and subfolder organization.
  - **Output & Network:** Custom filename templates, ASCII-safe filenames, overwrite toggle, concurrent fragments (`-N`), speed limit, HTTP/SOCKS proxy, IPv4/IPv6 selector, socket timeout, **Browser Cookies** (`Safari`, `Chrome`, `Brave`, `Firefox`, `Edge`, `Arc`) or `cookies.txt` file, `--continue` partial resume, bounded exponential auto-retry (`exp=1:16`), and a live copyable hardened CLI preview.
  - **Presets:** 6 built-in presets (*1080p Universal*, *4K Cinema*, *Best MP4*, *Apple Pro*, *Master Audio*, *MP3 320k*) plus unlimited custom user presets.

- **Persistent Queue, Pause/Resume & Isolated Subprocesses**
  - Atomic `VeloraStore` actor persistence (v2 schema envelopes under `~/Library/Application Support/Velora/` for `queue.json`, `history.json`, `custom-presets.json`, `last-configuration.json`) with corrupt-file `.corrupt-*.bak` preservation.
  - True per-item **Pause & Resume** (`--continue`), crash/quit recovery restoring interrupted active items to `.paused`, isolated POSIX process groups (`ProcessSupervisor` via `setpgid` + `SIGTERM` → `SIGKILL` escalation), EOF pipe draining before exit, and `100ms` UI progress/log coalescing.

- **Zero-Homebrew 1-Click Standalone Engine Setup**
  - Auto-discovers managed, Homebrew (`/opt/homebrew/bin/brew`, `/usr/local/bin/brew`), system, and JS runtime (`nvm`/`fnm`/`mise`/`asdf`) binaries.
  - One-click **CryptoKit SHA-256 verified** standalone installers for `yt-dlp`, `FFmpeg & FFprobe`, and `Deno` (plus optional allowlisted Homebrew install/upgrade).

- **Native macOS Integrations**
  - **`MenuBarExtra` Quick Queue:** Track active progress, pause/resume, drop URLs, and jump into Velora from the menu bar.
  - **Live Dock Badge & System Alerts:** Dock tile active count badge and `UNUserNotificationCenter` completion/failure notifications when running in the background.
  - **Quick Look (`Space`):** Preview finished audio/video files directly inside Queue and History.
  - **Opt-In Smart Clipboard Pill:** Detects copied `http`/`https` media URLs cleanly when switching back to Velora.
  - **`velora://` Deep Links:** Automate inspection or instant downloads from browsers, Raycast, Alfred, or Apple Shortcuts.

---

## Security & Supply-Chain Hardening

- **Fail-Closed Checksums Everywhere:** App updates require a matching `SHA256SUMS.txt` digest over GitHub HTTPS (including redirect host validation); standalone `yt-dlp`, `FFmpeg`/`FFprobe`, and `Deno` installers verify SHA-256 checksums via Apple `CryptoKit` and reject zip entries containing symlinks.
- **Hardened App Auto-Updater (`AppUpdateInstaller`):** Uses `0o700` staging directories, verifies `SecStaticCodeCheckValidity` and `TeamIdentifier` continuity, blocks symlink and `CFBundleExecutable` path traversal, cleans staging via an `EXIT` trap, and preserves backup bundles for atomic rollback.
- **Hardened `yt-dlp` Execution (`YTDLPCommandBuilder` & `YTDLPOutputParser`):** Always prepends `--ignore-config --no-exec` and `--` before target URLs, validates `http`/`https` schemes, strips dangerous flags (`--exec`, `--config-locations`, `--plugin-dirs`, `--load-info-json`) from extra user arguments, and consumes structured JSON wire templates (`VELORA_PROGRESS_JSON:`, `VELORA_META_JSON:`, `VELORA_FILEPATH_JSON:`).
- **Hardened CI/CD Workflows:** Actions are 40-char SHA-pinned with least-privilege permissions (`contents: read` by default), `env:`-only input interpolation (preventing script injection), strict SemVer 2.0.0 tag/dispatch gating, and `if: always()` keychain/certificate shredding.

---

## Keyboard Shortcuts & Deep Links

| Shortcut | Action |
| --- | --- |
| `⌘0` | Bring main Velora window forward |
| `⌘1` / `⌘2` / `⌘3` / `⌘4` | Switch between **Studio**, **Queue**, **History**, and **Presets** |
| `⌘L` | Focus Studio URL input |
| `⌘I` | Inspect current URL streams & metadata |
| `⇧⌘V` | Paste clipboard URL and inspect |
| `⌘↩` | Start download / queue batch |
| `⇧⌘O` | Open output folder in Finder |
| `⇧⌘U` | Check GitHub Releases for app updates |
| `Space` | Quick Look selected completed download (Queue & History) |

### `velora://` URL Scheme

```bash
# Inspect a media URL in Studio
open "velora://inspect?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DdQw4w9WgXcQ"

# Start downloading immediately with an optional preset name or UUID
open "velora://download?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DdQw4w9WgXcQ&preset=1080p%20Universal"
```

---

## Architecture & Repository Layout

- **`Sources/VeloraCore/` (`VeloraCore`):**
  - `Models/` — `DownloadConfiguration`, `DownloadItem` (`DownloadTask` + isolated `DownloadLogBuffer`), `DownloadPreset`, `MediaInfo`, `SemVer`.
  - `Engine/` — `EngineManager`, `ProcessSupervisor`, `MediaInspector`, `YTDLPCommandBuilder`, `YTDLPOutputParser`, `DownloadManager`.
  - `Persistence/` — Actor-isolated `VeloraStore` with atomic writes and schema v2 envelopes.
  - `Updates/` — `GitHubRelease`, `UpdateChecker`, `AppUpdateInstaller`.
- **`Sources/Velora/` (`Velora`):**
  - `VeloraApp.swift` (`Window`, `MenuBarExtra`, `Settings`, `VeloraAppDelegate`, `StudioViewModel`).
  - `Theme/` — `VeloraTheme` (semantic adaptive tokens), `VeloraLayout` (fluid metrics, `FlowWrapLayout`, `WindowChromeBridge`), `CachedThumbnailView` (`NSCache` + `CGImageSource` downsampling).
  - `System/` — `MacSystemBridge` (`VeloraDeepLinkParser`, Dock badge, `UNUserNotificationCenter`, clipboard monitor).
  - `Views/` — `MainWindowView`, `StudioView`, `ConfigurationPanelView`, `MediaPreviewCard`, `FormatPickerSheet`, `PlaylistPickerSheet`, `QueueView`, `HistoryView`, `PresetsView`, `MenuBarQueueView`, `EngineSetupSheet`, `UpdateSheetView`, `SettingsView`.
- **`Tests/VeloraCoreTests/`:** **62 tests across 9 Swift Testing suites** covering command construction, JSON wire parsing, process supervision, queue recovery/ordering, atomic store migration, engine SHA-256 verification, and auto-updater signature/checksum gates.
- **Docs & Specs:** [`CONTEXT.md`](CONTEXT.md), [`PRODUCT.md`](PRODUCT.md), [`docs/adr/ADR-001-per-item-observable-and-actor-store.md`](docs/adr/ADR-001-per-item-observable-and-actor-store.md), [`docs/adr/ADR-002-fail-closed-supply-chain-and-subprocess-isolation.md`](docs/adr/ADR-002-fail-closed-supply-chain-and-subprocess-isolation.md), and [`specs/001-velora-v2-overhaul/spec.md`](specs/001-velora-v2-overhaul/spec.md).

---

## Install on Your MacBook Pro (No Apple Developer Account Needed)

You do **not** need a paid Apple Developer membership to build, sign, and run Velora locally. Velora uses **ad-hoc code signing** (`codesign --force --deep --sign -`), which runs natively on Apple Silicon and Intel Macs.

### 1. Build & Install Locally in One Command

```bash
cd Velora
make install
```

What `make install` (via [`scripts/install-local.sh`](scripts/install-local.sh)) does:
1. Compiles Velora in optimized release mode for your Mac's architecture.
2. Generates a native Precision Cobalt macOS `AppIcon.icns` via CoreGraphics + `iconutil`.
3. Assembles `dist/Velora.app` with [`Resources/Info.plist.template`](Resources/Info.plist.template) (including `velora://` registration).
4. Signs the bundle with ad-hoc signing (`codesign --force --deep --sign -`) — or automatically uses a local self-signed Keychain certificate named **`Velora Local Dev`** if present.
5. Strips extended attributes, installs cleanly into `/Applications/Velora.app` (or `~/Applications/Velora.app` via `make install-user`), registers with LaunchServices/Spotlight, and launches Velora.

### Optional Tip: Preserve macOS Permissions Across Rebuilds

With ad-hoc signing, macOS treats each rebuild as a new signature. To retain folder and notification permissions across rebuilds without a paid Developer account:
1. Open **Keychain Access** → **Keychain Access → Certificate Assistant → Create a Certificate…**
2. Name it exactly **`Velora Local Dev`**
3. Set **Identity Type**: `Self Signed Root` and **Certificate Type**: `Code Signing`
4. Click **Create**.

[`scripts/install-local.sh`](scripts/install-local.sh) automatically detects `"Velora Local Dev"` and signs local builds with it.

---

## GitHub Actions & Publishing Releases

Two workflows live under `.github/workflows/`:

1. **[`.github/workflows/ci.yml`](.github/workflows/ci.yml)** — Runs on every push and pull request to `main`: executes `swift test` and verifies native `Velora.app` bundling and code signing on `macos-15`.
2. **[`.github/workflows/release.yml`](.github/workflows/release.yml)** — Triggered on SemVer tags (`v*.*.*`) or manually via **Actions → Release macOS App → Run workflow**:
   - Runs `swift test`.
   - Builds a **Universal Binary** (`arm64` + `x86_64`) with `VeloraGitHubRepository` baked into `Info.plist`.
   - Publishes a GitHub Release containing:
     - `Velora-<version>-macos-universal.dmg` (drag-to-Applications installer)
     - `Velora-<version>-macos-universal.zip` (consumed by the in-app auto-updater)
     - `SHA256SUMS.txt` (verified via `CryptoKit` by the in-app auto-updater)

### Publishing a Release

```bash
git tag v2.0.0
git push origin v2.0.0
```

> **Note for users downloading unsigned builds from GitHub Releases:**
> After dragging `Velora.app` from the `.dmg` into `/Applications`, run once in Terminal:
> ```bash
> xattr -dr com.apple.quarantine /Applications/Velora.app
> ```
> Or open **System Settings → Privacy & Security → Open Anyway**.
> Future in-app updates automatically verify SHA-256 checksums, strip quarantine, and relaunch Velora seamlessly.

> **Optional Apple Developer Signing Later:**
> If you join the Apple Developer Program, add repository secrets `APPLE_CERTIFICATE_P12` (base64 `.p12`), `APPLE_CERTIFICATE_PASSWORD`, and `APPLE_SIGNING_IDENTITY` — [`.github/workflows/release.yml`](.github/workflows/release.yml) switches automatically from ad-hoc signing to Developer ID hardened-runtime signing.

---

## Testing the Auto-Updater Locally

1. Install an older version string locally onto your Mac:
   ```bash
   make install VERSION=0.9.0
   ```
2. Ensure a newer GitHub Release exists on your configured repository (`kobenguyent/Velora` by default, editable in **Settings → Updates → GitHub Repository**).
3. Launch Velora (`v0.9.0`) — it checks GitHub Releases on launch (or press `⌘⇧U`).
4. Click **Download & Restart to Update**:
   - Downloads `Velora-<version>-macos-universal.zip` and `SHA256SUMS.txt`
   - Verifies SHA-256 digest, bundle identifier, executable path, and code signature continuity
   - Swaps `/Applications/Velora.app` atomically with backup rollback protection, strips quarantine, and relaunches the new version
   - Records updater diagnostics at `~/Library/Logs/Velora/updater.log`.

---

## Development Commands

| Command | Description |
| --- | --- |
| `make test` | Run all **62** `VeloraCoreTests` unit tests across **9** suites |
| `make run` | Run directly via `swift run Velora` |
| `make build` | Build SwiftPM targets in release mode |
| `make app` | Assemble and ad-hoc sign `dist/Velora.app` |
| `make install` | Build, sign, install `/Applications/Velora.app`, and launch it |
| `make install-user` | Build, sign, and install into `~/Applications/Velora.app` |
| `make dmg` | Build universal `.dmg`, `.zip`, and `SHA256SUMS.txt` in `dist/` |
| `make clean` | Clean `.build` and `dist` |
