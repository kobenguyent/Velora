# Data & Wire Contracts — `specs/001-velora-v2-overhaul/data-model.md`

> Defines persistence envelopes (`~/Library/Application Support/Velora/`), structured `yt-dlp` IPC wire formats, and the `velora://` deep-link contract.

## 1. Versioned JSON Persistence Envelopes (`VeloraStore`)

All JSON files under `~/Library/Application Support/Velora/` are managed by `actor VeloraStore` using atomic writes (`Data.WritingOptions.atomic`), automatic legacy v1 bare-array migration on read, and `.corrupt-<ISO8601>.bak` preservation before any overwrite if decoding fails.

### 1.1 Generic Envelope (`VeloraStoreEnvelope<Payload: Codable & Sendable>`)
```swift
public struct VeloraStoreEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public static var currentSchemaVersion: Int { 2 }
    public let schemaVersion: Int
    public let updatedAt: Date
    public let payload: Payload
}
```
- **Backward Compatibility:** When reading `history.json`, `custom-presets.json`, or `last-configuration.json`, `VeloraStore` first decodes `VeloraStoreEnvelope<T>`; if that fails, it falls back to decoding legacy v1 `T` directly and upgrades to `schemaVersion = 2` on next write. If both fail on a non-empty file, it copies the file to `<filename>.corrupt-<timestamp>.bak` and logs a warning rather than silently wiping user data.

### 1.2 Persisted Queue (`queue.json` — NEW)
```swift
public struct PersistedQueueState: Codable, Sendable, Equatable {
    public var isQueuePaused: Bool
    public var items: [DownloadTaskSnapshot] // Ordered display order (top-to-bottom FIFO)
}

public struct DownloadTaskSnapshot: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let url: String
    public var title: String
    public var uploader: String?
    public var extractor: String?
    public var thumbnailURL: String?
    public var configuration: DownloadConfiguration
    public var status: DownloadStatus // .queued, .paused, .completed, .failed, .cancelled
    public var progress: Double
    public var fileSizeText: String?
    public var statusDetail: String
    public var errorMessage: String?
    public var outputFilePath: String?
    public var completedFileCount: Int
    public var retryAttempt: Int
    public let createdAt: Date
    public var completedAt: Date?
    public var batchID: UUID?
    public var batchName: String?
    public var playlistIndex: Int?
    public var playlistTotal: Int?
    // Note: transient speedText, etaText, and 400-line raw stdout logs are excluded from queue.json to keep writes < 32 KB.
}
```
- **Crash / Update Recovery Rule:** On launch, any snapshot whose persisted `status` was `.preparing`, `.downloading`, or `.postProcessing` transitions deterministically to `.paused` (with `statusDetail = "Interrupted — Resume to continue"` and `--continue` enabled) so partial `.part` files resume without re-downloading from byte 0.

### 1.3 Extended `DownloadStatus` & `DownloadConfiguration` Delta
- **`DownloadStatus`:** Add `.paused` (`isTerminal == false`, `isActive == false`, `isResumable == true`).
- **`DownloadConfiguration`:**
  - `cookieFilePath: String = ""` (optional Netscape `cookies.txt` path alongside `BrowserCookiesSource`, solving Safari TCC restrictions).
  - `autoRetryCount: Int = 3` (`0...10`, passed as `--retries` / `--fragment-retries` + `--retry-sleep exp=1:16` and supervisor transient-network retry).
  - `resumePartialDownloads: Bool = true` (`--continue` vs `--no-continue`).

---

## 2. Structured `yt-dlp` Subprocess Wire Contracts

Replaces pipe-delimited `VELORA_META|%(title)s|...` (which broke on `|` in titles) with collision-proof single-line JSON prefixes:

| Prefix | `yt-dlp` Argument | Payload Schema |
| :--- | :--- | :--- |
| **`VELORA_META_JSON:`** | `--print "before_dl:VELORA_META_JSON:%(.{id,title,uploader,channel,extractor_key,extractor,thumbnail,duration,is_live})j"` | JSON object decoded via `JSONDecoder` (handles `\|`, quotes, emojis, newlines safely). |
| **`VELORA_PROGRESS_JSON:`** | `--progress-template "download:VELORA_PROGRESS_JSON:%(progress.{status,downloaded_bytes,total_bytes,total_bytes_estimate,speed,eta,_percent_str,_speed_str,_eta_str})j"` | JSON object with exact numeric bytes/speed/ETA + fallback string tokens; supports live streams (`status == "downloading"`, `total_bytes == null` -> indeterminate/elapsed live indicator). |
| **`VELORA_FILEPATH_JSON:`** | `--print "after_move:VELORA_FILEPATH_JSON:%(.{filepath})j"` | JSON object emitting exact final post-processed path on disk. |

---

## 3. Custom URL Scheme Contract (`velora://`)

Registered in `Resources/Info.plist.template` under `CFBundleURLTypes` (`CFBundleURLSchemes = ["velora"]`) and handled via `.onOpenURL` / `NSApplicationDelegate`:

- `velora://inspect?url=<percent-encoded-http-or-https-url>` — Focuses Studio, populates `urlInput`, and starts `MediaInspector.inspect`.
- `velora://download?url=<percent-encoded-http-or-https-url>&preset=<optional-preset-name-or-id>` — Validates `http`/`https` scheme; if `preset` matches, applies preset for that task; enqueues into `DownloadManager` (or opens `EngineSetupSheet` if `yt-dlp` is missing) without overwriting user's saved configuration unless requested.
- **Security Invariant:** Strictly validate decoded `url` starts with `https://` or `http://`, cap length `<= 4096` bytes, and NEVER accept CLI flags (`extraArguments`, `outputDir`, `cookieFile`) via `velora://` query parameters (prevents drive-by web link RCE / arbitrary file write!).
