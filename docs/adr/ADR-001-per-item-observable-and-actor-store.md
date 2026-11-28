# ADR-001: Per-Item `@Observable` Task Isolation & Actor-Backed Persistence

- **Status:** Accepted
- **Date:** 2026-11-27
- **Deciders:** `architect`, `backend`, `frontend` (`specs/001-velora-v2-overhaul`)

## Context
In Velora v1.0, `DownloadManager` stores value-type `DownloadTaskItem` structs (each embedding up to 400 log lines) inside a single `@Observable` array `queue: [DownloadTaskItem]`. Every `\r` progress line or stdout log line from any of up to 8 concurrent `yt-dlp` processes mutates `queue[idx]`, firing Swift `Observation` invalidations for `\DownloadManager.queue` as a whole (`20–80×/sec`). This invalidates `VeloraApp` menu commands, `MainWindowView` sidebar counters (`O(N)` filter scans), `StudioView`, and every `QueueItemCard` simultaneously. Meanwhile, `VeloraStore` runs synchronous `JSONEncoder` + `.atomic` `fsync` writes on `@MainActor` on every keystroke in `ConfigurationPanelView`, and never persists `queue.json`.

## Decision
1. **Reference-Typed Per-Item `@Observable` Model (`DownloadTask`):**
   - Keep a Codable value snapshot `DownloadTaskSnapshot` for persistence (`queue.json`), while representing live queue items in memory as `@MainActor @Observable public final class DownloadTask: Identifiable`.
   - Separate live telemetry (`progress`, `speedText`, `etaText`, `fileSizeText`, `statusDetail`) and expandable `LogBuffer` (`@Observable` ring buffer observed *only* when a card's console drawer is expanded) from `DownloadManager.queue` structural membership.
   - Maintain O(1) cached counters (`activeCount`, `queuedCount`, `completedCount`, `failedCount`) on `DownloadManager` updated only on status transitions, and coalesce subprocess progress updates to a `100ms` (`10 Hz`) cadence per task.
2. **Actor-Backed Versioned Persistence (`VeloraPersistenceActor` / `VeloraStore`):**
   - Move JSON encoding, atomic writes, corrupt-file `.corrupt-<timestamp>.bak` preservation, and debounced saves (`300ms` for configuration and queue state) onto a dedicated background serial actor.
   - Persist `queue.json` inside a schema-versioned `VeloraStoreEnvelope<T>(schemaVersion: 2, updatedAt:payload:)` so app restarts, crashes, and in-app updates restore queued, paused, and interrupted downloads cleanly (transitioning interrupted active items to `.paused` with `--continue` ready).

## Consequences
- **Positive:** Eliminates whole-window SwiftUI re-render storms during multi-stream downloads, eliminates main-thread disk hitches while typing or scrolling `HistoryView`, and guarantees zero queue loss across app restarts and updates.
- **Trade-offs / Mitigations:** Reference-typed `@MainActor` `DownloadTask` requires explicit `snapshot()` serialization when writing `queue.json`; mitigated by lightweight `DownloadTaskSnapshot` value structs with full unit test coverage.
