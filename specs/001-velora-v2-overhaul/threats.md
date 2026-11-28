# Threat Model: Velora v2 Architecture, Auto-Updater & Subprocess Engine

- **Path:** `specs/001-velora-v2-overhaul/threats.md`
- **Methodology:** STRIDE + DREAD + Trail of Bits Sharp-Edges / Insecure-Defaults (`fp-check` verified)

## 1. Assets & Trust Boundaries
- **Critical Assets:**
  1. User macOS host execution context & `/Applications/Velora.app` bundle integrity (including root authorization during elevated `/Applications` swap).
  2. Browser session cookies accessed via `--cookies-from-browser` or user-selected `cookies.txt`.
  3. Local filesystem (`~/Downloads`, `~/Library/Application Support/Velora/`).
  4. GitHub Actions release credentials (`GITHUB_TOKEN` with `contents: write`, optional `APPLE_CERTIFICATE_P12` & `APPLE_CERTIFICATE_PASSWORD`).
- **Entry Points:**
  - Remote GitHub Releases API & CDN assets (`UpdateChecker`, `EngineManager` `yt-dlp` / `deno` / `ffmpeg` downloads).
  - Untrusted remote media URLs, playlist metadata (`title`, `playlist_title`, `formats`), drag-and-drop files, clipboard strings, and `velora://` deep links.
  - Imported/saved `custom-presets.json` and `extraArguments` CLI string.
  - `.github/workflows/release.yml` `workflow_dispatch` inputs & git tags.
- **Trust Boundaries:**
  - Remote Internet / GitHub / `martin-riedl.de` CDN <-> `URLSession` <-> `CryptoKit.SHA256` / `SecStaticCode` verifier <-> Executable filesystem (`bin/`, `/Applications/`).
  - External browser/clipboard/`velora://` link <-> `Velora` UI <-> `YTDLPCommandBuilder` <-> `ProcessSupervisor` (`yt-dlp`, `ffmpeg`, `deno`).
  - Unprivileged user `$TMPDIR` <-> `osascript ... with administrator privileges` (`root`).

---

## 2. STRIDE Matrix & Mandatory Testable Mitigations

| ID | Category | Component / Entry Point | Threat Description (`fp-check` Verified) | DREAD (1–10) | Mandatory Mitigation (Verified by Automated Tests / Audit) |
| :--- | :--- | :--- | :--- | :---: | :--- |
| **T-01** | Tampering / Elevation | `UpdateChecker` & `AppUpdateInstaller` | Triple fail-open SHA-256 check (missing `SHA256SUMS.txt`, non-200 HTTP, missing filename entry) + zero `SecStaticCode` check allows unverified `.app` swap and quarantine strip (`SEC-01`). | **9** | Require `checksumAsset != nil`, enforce HTTP `200`, throw `missingChecksumManifest` if entry absent, enforce `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$` repo + `https://` GitHub hosts, and run `SecStaticCodeCheckValidity` (matching `TeamIdentifier` when current app is Team-signed). |
| **T-02** | Tampering / Supply Chain | `EngineManager` (`yt-dlp`, `ffmpeg`, `deno`) | `installOrUpdateManagedYTDLP()` executes downloaded binaries without verifying `SHA2-256SUMS`, and `enrichedEnvironment()` places `~/.local/bin` before `/usr/bin` (`SEC-02`). | **8** | Verify `CryptoKit.SHA256` against official `SHA2-256SUMS` / `.sha256` / `.sha256sum` on temp file *before* `chmod 0o755` & `replaceItemAt`; place `/usr/bin:/bin:/usr/sbin:/sbin` ahead of user dirs in `PATH`; restrict `brew` to `/opt/homebrew/bin/brew` & `/usr/local/bin/brew` with `--formula --` allowlist. |
| **T-03** | Elevation / RCE | `YTDLPCommandBuilder` & `MediaInspector` | Missing `--ignore-config` and `--no-exec` allows stray `yt-dlp.conf` or `extraArguments` (`--exec`, `--config-locations`, `--plugin-dirs`, `--load-info-json`) to run arbitrary shell commands (`SEC-03`). | **8** | Prepend `["--ignore-config", "--no-exec"]` on every `yt-dlp` call, reject denylisted flags in `extraArguments`, append trailing `"--no-exec"` + `"--"` before URL, and enforce `http`/`https` schemes in `enqueue`, `inspect`, and `velora://`. |
| **T-04** | Elevation / Tampering | `AppUpdateInstaller` (`osascript` + `ditto`) | User-writable `$TMPDIR` updater script executed as `root`, archive symlink preservation, `CFBundleExecutable` `../../` traversal, and premature `$BACKUP_APP` deletion (`SEC-04`). | **8** | Reject symlinks across extracted `.app`, reject `/` or `..` in `CFBundleExecutable` & asset filename, create `0o700` staging dir, preserve `$BACKUP_APP` when `$TARGET_APP` is missing, add `EXIT` cleanup trap, and run direct constant root swap commands instead of executing a `$TMPDIR` script as `root`. |
| **T-05** | Tampering / Info Disclosure | `.github/workflows/release.yml` & `ci.yml` | `${{ inputs.version }}` interpolated directly into `run:` bash script & unquoted heredoc with `contents: write` + signing secrets; unpinned third-party actions; leftover `.p12` keychain (`SEC-05`). | **8** | Pass all GitHub expressions via `env:`, validate strict SemVer regex, quote `'EOF'`, pin `actions/checkout`, `actions/upload-artifact`, and `softprops/action-gh-release` to 40-char commit SHAs, set `permissions: contents: read` on `ci.yml`, and shred `.p12` + temporary keychain in `if: always()`. |
| **T-06** | Tampering (Path Traversal) | `YTDLPCommandBuilder` & `PlaylistURLDetector` | Remote playlist titled `".."` with `%(playlist_title,playlist)s/...` template writes files outside `outputDirectoryPath`. | **6** | Sanitize subfolder names via `PlaylistURLDetector.sanitizeFolderName` (or pass `--windows-filenames` / explicit validated `-P` directory) and reject `..` path components in custom filename templates. |
| **T-07** | Spoofing / RCE via Deep Link | `velora://` URL Scheme Handler | Malicious webpage triggers `velora://download?...` attempting to inject `extraArguments`, `outputDir`, or `file://` URLs. | **7** | `velora://` parser accepts ONLY `action` (`inspect` / `download`), `url` (`http`/`https`, `<= 4096` chars), and `preset` (matched by UUID/name against existing presets); ignores all CLI/path query keys. |
| **T-08** | Denial of Service | Drag-and-Drop, `ProcessLineAccumulator` & Pipes | Dropping a multi-GB video file reads entire file synchronously on `@MainActor`; unbounded stdout line or unread `stderr` `Pipe()` deadlocks/OOMs Velora. | **6** | Restrict dropped batch files to `.txt`/`.csv` (`<= 1 MB`) read off `@MainActor`; cap `ProcessLineAccumulator` single-line buffer at `256 KB` using `UTF8.self` decoding; drain all pipes concurrently with bounded timeouts. |

---

## 3. Insecure Defaults & Sharp Edges Checklist
- [x] **Fails closed** on missing/HTTP-error/unmatched `SHA256SUMS.txt` and managed engine checksums (never fail-open).
- [x] **Payload & resource caps** enforced on drag-and-drop files (`1 MB`), `velora://` URLs (`4096 B`), log ring buffers (`400` lines), history (`500` items), and subprocess line buffers (`256 KB`).
- [x] **Zero secrets** stored in repository (`betterleaks` verified); browser cookies never copied into logs or CLI shell previews when sensitive paths are masked/quoted cleanly.
- [x] **CI expression hygiene** enforced across all `.github/workflows/*.yml` files with SHA-pinned actions and `if: always()` credential cleanup.
