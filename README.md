# Velora

**Velora** is a refined, native macOS SwiftUI video & audio downloader built with Swift 6, supporting YouTube, Vimeo, X, TikTok, Instagram, Twitch, SoundCloud, and 1,000+ sources powered by `yt-dlp` and `ffmpeg`.

Built specifically so iOS/macOS developers can build, install onto a MacBook Pro **without a paid Apple Developer account**, publish universal macOS releases through GitHub Actions, and update automatically straight from GitHub Releases.

---

## Features

- **Multi-Source Extraction & Stream Inspector**
  - Paste single URLs, drag-and-drop links onto the window, or switch to **Batch Mode** for multi-URL queues.
  - Inspect media before downloading (thumbnail, channel, duration, views, detected resolutions) and pick exact video/audio stream IDs via the interactive **Format Picker**.
- **Comprehensive Download Configuration**
  - **Modes & Quality**: Video + Audio, Audio Only, or Video Only · Best, 8K, 4K (2160p), 1440p, 1080p, 720p, 480p, 360p, Smallest.
  - **Containers & Codecs**: `MP4`, `MKV`, `WebM`, `MOV` · `M4A`, `MP3`, `FLAC`, `WAV`, `OPUS`, `AAC` · Preferred video codec (`Auto`, `H.264`, `HEVC`, `VP9`, `AV1`) & frame-rate cap (`Unlimited`, `60 fps`, `30 fps`).
  - **Subtitles & Metadata**: Selected or all languages, auto-captions, embed subtitles, embed cover thumbnail, embed metadata & chapters, split chapters, and **SponsorBlock** (mark or remove sponsor/intro/outro segments).
  - **Time-Range Clipping & Playlists**: Download exact `[start - end]` segments with keyframe-accurate cuts, or download full playlists with range filters (`1-10`) and automatic subfolders.
  - **Output & Network**: Custom filename templates, ASCII-safe mode, concurrent fragment downloads (`-N`), speed limit, HTTP/SOCKS5 proxy, **Browser Cookies** import (Safari, Chrome, Brave, Firefox, Edge, Arc), and raw extra `yt-dlp` arguments with a live copyable CLI preview.
  - **Presets**: 6 built-in presets (*1080p Universal*, *4K Cinema*, *Best MP4*, *Apple Pro*, *Master Audio*, *MP3 320k*) + custom user presets.
- **Built-In Engine Setup (`yt-dlp` & `ffmpeg`)**
  - Auto-discovers Homebrew, system, and app-managed binaries.
  - One-click download of the official standalone universal `yt-dlp_macos` binary directly inside the app — plus one-click Homebrew installation for `ffmpeg`.
- **GitHub Releases Auto-Updater (Close-and-Update)**
  - Automatically checks GitHub Releases on launch (and on demand via `⌘⇧U` or the toolbar).
  - Streams release `.zip` download with live progress, verifies **SHA-256** integrity via Apple `CryptoKit` against `SHA256SUMS.txt`, validates the `.app` bundle identifier & executable, strips `com.apple.quarantine`, closes the running Velora process, atomically replaces the `.app` bundle (with rollback protection), and relaunches the new version automatically.

---

## Install on Your MacBook Pro (No Apple Developer Account Needed)

You do **not** need a paid Apple Developer membership to build, sign, and run Velora locally on your MacBook Pro. Velora uses **ad-hoc code signing** (`codesign --force --deep --sign -`), which runs natively on Apple Silicon and Intel Macs.

### 1. Build & Install Locally in One Command

```bash
cd Velora
make install
```

What `make install` (via [`scripts/install-local.sh`](scripts/install-local.sh)) does:
1. Compiles Velora in optimized release mode for your Mac's architecture.
2. Generates a native macOS squircle `AppIcon.icns` via CoreGraphics + `iconutil`.
3. Assembles `dist/Velora.app` with a valid `Info.plist`.
4. Signs the bundle with ad-hoc signing (`codesign --force --deep --sign -`) — or automatically uses a local self-signed Keychain certificate named **`Velora Local Dev`** if you create one.
5. Strips extended attributes, installs cleanly into `/Applications/Velora.app` (or `~/Applications/Velora.app` via `make install-user`), registers it with LaunchServices/Spotlight, and opens Velora.

### Optional Tip: Preserve macOS Permissions Across Rebuilds

With ad-hoc signing, macOS treats each fresh rebuild as a new signature. If you want macOS to remember folder/automation permissions across rebuilds without a paid Developer account:
1. Open **Keychain Access** → menu **Keychain Access → Certificate Assistant → Create a Certificate…**
2. Name it exactly **`Velora Local Dev`**
3. Set **Identity Type**: `Self Signed Root` and **Certificate Type**: `Code Signing`
4. Click **Create**.

`scripts/install-local.sh` automatically detects `"Velora Local Dev"` and signs your local builds with it.

---

## GitHub Actions & Publishing Releases

Two workflows are included under `.github/workflows/`:

1. **[`.github/workflows/ci.yml`](.github/workflows/ci.yml)** — Runs on every push and pull request to `main`: executes `swift test` and verifies native `Velora.app` bundling and code signing on `macos-15`.
2. **[`.github/workflows/release.yml`](.github/workflows/release.yml)** — Triggered automatically when you push a version tag (`v*.*.*`) or manually via **Actions → Release macOS App → Run workflow**:
   - Runs the unit test suite (`swift test`).
   - Builds a **Universal Binary** (`arm64` + `x86_64`) with your repository automatically baked into `Info.plist` (`VeloraGitHubRepository`).
   - Packages and publishes a GitHub Release with:
     - `Velora-<version>-macos-universal.dmg` (drag-to-Applications installer)
     - `Velora-<version>-macos-universal.zip` (consumed by the in-app auto-updater)
     - `SHA256SUMS.txt` (SHA-256 digests verified by the in-app auto-updater)

### Creating Your First Release

```bash
git init
git add .
git commit -m "Initial Velora release"
git remote add origin https://github.com/<your-username>/Velora.git
git push -u origin main

# Publish v1.0.0 via GitHub Actions:
git tag v1.0.0
git push origin v1.0.0
```

> **Note for users downloading unsigned builds from GitHub Releases:**
> After dragging `Velora.app` from the `.dmg` into `/Applications`, run once in Terminal:
> ```bash
> xattr -dr com.apple.quarantine /Applications/Velora.app
> ```
> Or open **System Settings → Privacy & Security → Open Anyway**.
> Future in-app updates automatically strip quarantine and restart Velora seamlessly.

> **Optional Apple Developer Signing Later:**
> If you ever join the Apple Developer Program, add repository secrets `APPLE_CERTIFICATE_P12` (base64 `.p12`), `APPLE_CERTIFICATE_PASSWORD`, and `APPLE_SIGNING_IDENTITY` — `.github/workflows/release.yml` detects them automatically and switches from ad-hoc signing to Developer ID hardened-runtime signing.

---

## Testing the Auto-Updater Locally

1. Install an older version string locally onto your MacBook Pro:
   ```bash
   make install VERSION=0.9.0
   ```
2. Publish a newer GitHub Release (e.g. `v1.0.0`) on your repo (`kobenguyent/Velora` or any repo configured in **Settings → Updates → GitHub Repository**).
3. Open Velora (`v0.9.0`) — it will automatically detect `v1.0.0` on launch (or press `⌘⇧U`).
4. Click **Download & Restart to Update**:
   - Velora downloads `Velora-1.0.0-macos-universal.zip` and `SHA256SUMS.txt`
   - Verifies SHA-256 checksum & bundle identifier
   - Spawns a detached atomic updater helper, closes `v0.9.0`, swaps `/Applications/Velora.app` (with automatic rollback on failure), strips quarantine, and relaunches `v1.0.0`!
   - Updater logs are recorded at `~/Library/Logs/Velora/updater.log`.

---

## Development Commands

| Command | Description |
| --- | --- |
| `make test` | Run `VeloraCoreTests` unit tests |
| `make run` | Run directly via `swift run Velora` |
| `make app` | Assemble & ad-hoc sign `dist/Velora.app` |
| `make install` | Build & install `/Applications/Velora.app` and launch it |
| `make install-user` | Build & install `~/Applications/Velora.app` |
| `make dmg` | Build universal `.dmg`, `.zip`, and `SHA256SUMS.txt` in `dist/` |
| `make clean` | Clean `.build` and `dist` |
