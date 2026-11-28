# Project Constitution — Velora

> Established by `kb-spec` / `kb-plan`. Precedes generic stack defaults in `~/.kobean/`.

## 1. Purpose & Non-Goals
- **Core Problem Solved:** Deliver a fast, secure, native macOS media studio around `yt-dlp` and `ffmpeg` that feels first-party on macOS Sonoma/Sequoia, works without a paid Apple Developer account (while seamlessly supporting Developer ID signing when present), and never loses user queue/history state or executes unverified binaries.
- **Explicit Non-Goals (Never Build):**
  - Cross-platform Electron/Web wrappers, cloud accounts, telemetry, or external SwiftPM dependencies when Apple `Foundation`, `CryptoKit`, `Security`, `AppKit`, `SwiftUI`, and `UserNotifications` suffice.
  - DRM circumvention (`Widevine` / encrypted CDM decryption) — strictly support standard `yt-dlp` extractors and user-authorized browser cookies.

## 2. Tech Stack & Runtime Constraints
- **Language & Concurrency:** Swift 6.0 (`.swiftLanguageMode(.v6)` strict `Sendable` / actor isolation)
- **Platform:** macOS 14.0+ (`Sonoma` / `Sequoia`), universal (`arm64` + `x86_64`)
- **Frontend:** Native SwiftUI + targeted AppKit bridges (`NSApp.dockTile`, `NSPasteboard`, `NSWorkspace`, `QuickLookUI`)
- **Core / Backend Engine:** `VeloraCore` (`Process` subprocess supervisor, `CryptoKit`, `Security` `SecStaticCode`, `URLSession`, actor-backed `VeloraStore`)
- **Testing:** Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`) via `make test` (`swift test`)

## 3. Architectural Invariants
1. **Compiled-Package Staged Ownership (`doctrine.md` §6.3):** `backend` role owns `Sources/VeloraCore/**` and `Tests/VeloraCoreTests/**`; `frontend` / `ui-ux-designer` owns `Sources/Velora/**`, `scripts/generate-icon.swift`, and `PRODUCT.md`; `devops` owns `.github/**`, `scripts/*.sh`, and `Makefile`. Never overlap write paths in parallel subagents.
2. **Fail-Closed Binary & Update Trust:** Every downloaded executable or update archive (`yt-dlp_macos`, standalone `ffmpeg`, `Velora-*.zip`) MUST pass cryptographic `SHA-256` verification before `chmod +x`, quarantine removal, or bundle swap.
3. **Hardened Subprocess Execution:** Every `yt-dlp` invocation MUST pass `--ignore-config`, `--no-exec`, and `--` before URLs, reject dangerous `extraArguments` (`--exec`, `--config-locations`, `--plugin-dirs`), drain pipes completely before exit handling, and clean up child process groups on cancel/quit.
4. **Zero Main-Thread I/O & Smooth 120Hz UI:** Never perform synchronous disk writes or `FileManager.fileExists` loops inside SwiftUI `body` or keystroke `didSet` handlers; isolate per-item download progress observation and coalesce UI progress ticks (`~10 Hz`).
5. **Zero Secrets & Clean CI:** `betterleaks` must report `0` leaks, and GitHub Actions workflows must never interpolate `${{ ... }}` directly inside `run:` shell scripts.
6. **Test-First (Red-Green-Refactor) & Beads State:** Track all tasks exclusively in `.beads/` via `bd`, and write failing Swift Testing tests before implementation changes.
