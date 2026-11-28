# ADR-002: Fail-Closed Binary Supply-Chain Verification & Hardened Subprocess Supervisor

- **Status:** Accepted
- **Date:** 2026-11-27
- **Deciders:** `architect`, `security`, `threat-modeler` (`specs/001-velora-v2-overhaul`)

## Context
Velora executes external binaries (`yt-dlp`, `ffmpeg`, `ffprobe`, `deno`) and self-updates its `.app` bundle from GitHub Releases. Audit findings `SEC-01` through `SEC-05` revealed:
1. `UpdateChecker` failed open in 3 ways when `SHA256SUMS.txt` was missing, returned non-200 HTTP, or omitted the asset filename, and `AppUpdateInstaller` never ran `SecStaticCodeCheckValidity` or checked symlinks/`CFBundleExecutable` path traversal before elevated `osascript` bundle replacement.
2. `EngineManager` downloaded and executed `yt-dlp_macos` without verifying `SHA2-256SUMS`, prepended user-writable directories ahead of `/usr/bin` in `PATH`, and required Homebrew for `ffmpeg`.
3. `YTDLPCommandBuilder` omitted `--ignore-config` and `--no-exec`, allowed arbitrary `--exec`/`--config-locations` in `extraArguments`, and `DownloadManager` truncated trailing pipe output on exit while leaving orphan `yt-dlp`/`ffmpeg` child processes on cancel/quit.

## Decision
1. **Fail-Closed Cryptographic Verification Everywhere:**
   - Auto-updates (`Velora-*.zip`) MUST fetch `SHA256SUMS.txt` with HTTP `200`, match the exact asset digest via `CryptoKit.SHA256`, reject symlinks and path-traversing `CFBundleExecutable` entries, and validate `SecStaticCodeCheckValidity` (enforcing matching Apple `TeamIdentifier` whenever the running app is Developer-ID signed, and strict Mach-O code-directory seal verification on ad-hoc builds).
   - Managed engine downloads (`yt-dlp_macos` via `SHA2-256SUMS`, `deno` via `.zip.sha256sum`, and standalone static `ffmpeg` + `ffprobe` archives via companion SHA-256 endpoints) MUST verify SHA-256 on the temporary file *before* extraction, `chmod 0o755`, quarantine removal, and atomic `FileManager.replaceItemAt` installation into `~/Library/Application Support/Velora/bin`.
   - Elevated `osascript` bundle swaps MUST stage inside a `0o700` directory verified immediately prior to invocation and execute a constant-form root command rather than a user-writable script in `$TMPDIR`.
2. **Hardened Subprocess Supervisor (`ProcessSupervisor`):**
   - Always pass `["--ignore-config", "--no-exec"]` to `yt-dlp`, validate `extraArguments` against a sharp-edge denylist (`--exec`, `--exec-before-download`, `--config-location`, `--config-locations`, `--plugin-dirs`, `--load-info-json`), and enforce `http`/`https` schemes before `--`.
   - Place each download subprocess into its own POSIX process group (`posix_spawnattr_setpgroup` / `setpgid` or child-tree signal helper) so pause/cancel/quit cleanly signals both `yt-dlp` and spawned `ffmpeg` children (`SIGTERM` -> `2s` grace -> `SIGKILL`), while draining pipes to EOF (`readDataToEndOfFile()`) *before* firing exit handlers.

## Consequences
- **Positive:** Closes all 5 `CRITICAL`/`HIGH` supply-chain, privilege-escalation, and command-injection paths while enabling zero-Homebrew 1-click setup for `yt-dlp`, `ffmpeg`, and `deno` on any Mac.
- **Trade-offs / Mitigations:** Custom forks of Velora that publish GitHub Releases *without* `SHA256SUMS.txt` will be blocked from auto-updating cleanly with an explicit security error (`missingChecksumManifest`); `.github/workflows/release.yml` already generates and uploads `SHA256SUMS.txt` automatically.
