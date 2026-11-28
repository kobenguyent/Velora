import Foundation

public enum MediaInspectorError: LocalizedError, Sendable {
    case missingEngine
    case invalidURL
    case timedOut
    case cancelled
    case processFailed(String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingEngine:
            "yt-dlp is not installed yet. Open Engine Setup to install it in one click."
        case .invalidURL:
            "Please enter a valid video or playlist URL."
        case .timedOut:
            "Inspecting this URL timed out. Check your network connection or try switching Network IP in Output & Network."
        case .cancelled:
            "Inspection cancelled."
        case .processFailed(let details):
            details.isEmpty ? "Unable to inspect this URL." : details
        case .decodingFailed(let details):
            "Could not parse metadata from yt-dlp: \(details)"
        }
    }
}

public enum PlaylistInspectMode: Sendable, Equatable {
    /// Auto-detects pure playlist/channel URLs as playlists, while inspecting hybrid `watch?v=...&list=...` as single video + offering playlist expansion.
    case automatic
    /// Forces flat-playlist inspection (expands playlists, channels, and `watch?v=...&list=...` links into entries).
    case forcePlaylist
    /// Forces single-video inspection (`--no-playlist`).
    case forceSingleVideo
}

/// Pure utilities for detecting playlist/channel URLs, parsing selection ranges, and sanitizing subfolder names.
public enum PlaylistURLDetector {

    /// Returns `true` when the URL clearly targets a playlist, set, album, showcase, or channel video feed.
    public static func isPurePlaylistURL(_ rawURL: String) -> Bool {
        let cleaned = YTDLPCommandBuilder.sanitizeURL(rawURL)
        guard let components = URLComponents(string: cleaned),
              let host = components.host?.lowercased() else {
            return false
        }
        let path = components.path.lowercased()
        let queryItems = components.queryItems ?? []
        let hasListParam = queryItems.contains { $0.name.lowercased() == "list" && !($0.value ?? "").isEmpty }
        let hasVideoParam = queryItems.contains { $0.name.lowercased() == "v" && !($0.value ?? "").isEmpty }

        // YouTube dedicated playlist page (/playlist?list=...)
        if path.contains("/playlist") && hasListParam {
            return true
        }
        // YouTube channel feeds (/@handle/videos, /channel/UC.../videos, /c/.../videos, /user/.../videos, /playlists)
        if host.contains("youtube.com") || host.contains("youtu.be") {
            let channelFeedSuffixes = ["/videos", "/shorts", "/streams", "/playlists", "/releases", "/podcasts"]
            if channelFeedSuffixes.contains(where: { path.hasSuffix($0) || path.hasSuffix($0 + "/") }) {
                return true
            }
            if hasListParam && !hasVideoParam && !host.contains("youtu.be") {
                return true
            }
        }
        // SoundCloud sets, Vimeo albums/showcases, Bilibili collections, generic /playlist/
        let multiPathTokens = ["/sets/", "/albums/", "/showcase/", "/playlists/", "/collection/"]
        if multiPathTokens.contains(where: { path.contains($0) }) {
            return true
        }
        return false
    }

    /// If a single-video URL also carries a YouTube playlist `list=` parameter (e.g. `watch?v=abc&list=PLxyz`),
    /// returns the canonical playlist URL so the user can expand the full playlist in one click.
    public static func extractLinkedPlaylistURL(from rawURL: String) -> String? {
        let cleaned = YTDLPCommandBuilder.sanitizeURL(rawURL)
        guard let components = URLComponents(string: cleaned),
              let host = components.host?.lowercased(),
              host.contains("youtube.com") || host.contains("youtu.be") else {
            return nil
        }
        guard let listID = components.queryItems?
            .first(where: { $0.name.lowercased() == "list" })?
            .value,
              !listID.isEmpty else {
            return nil
        }
        return "https://www.youtube.com/playlist?list=\(listID)"
    }

    /// Parses range expressions like `"1-10"`, `"1, 3, 5-8"`, `"-5"`, `"10-"` into 1-based item indices.
    public static func parseSelectionRange(_ expression: String, maxIndex: Int) -> Set<Int> {
        guard maxIndex >= 1 else { return [] }
        var result: Set<Int> = []
        let segments = expression
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for segment in segments {
            if segment.contains("-") {
                let parts = segment.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                let start = parts[0].isEmpty ? 1 : (Int(parts[0]) ?? 0)
                let end = parts[1].isEmpty ? maxIndex : (Int(parts[1]) ?? 0)
                guard start >= 1, end >= 1 else { continue }
                let low = max(1, min(start, end))
                let high = min(maxIndex, max(start, end))
                if low <= high {
                    for i in low...high {
                        result.insert(i)
                    }
                }
            } else if let exact = Int(segment), (1...maxIndex).contains(exact) {
                result.insert(exact)
            }
        }
        return result
    }

    /// Converts a playlist title into a safe macOS folder name.
    public static func sanitizeFolderName(_ rawName: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\\0\n\r\t")
        let replaced = rawName
            .components(separatedBy: forbidden)
            .joined(separator: " - ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        if replaced.isEmpty {
            return "Playlist"
        }
        return String(replaced.prefix(120))
    }
}

private final class InspectorProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var pid: pid_t = 0
    private var cancelled = false

    func store(_ proc: Process, pid: pid_t = 0) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if cancelled {
            return false
        }
        process = proc
        self.pid = pid
        return true
    }

    func updatePID(_ pid: pid_t) {
        lock.lock()
        self.pid = pid
        let shouldKill = cancelled
        let proc = process
        lock.unlock()
        if shouldKill, let proc {
            ProcessSupervisor.terminateProcessGroup(pid: pid, process: proc, graceSeconds: 0.5)
        }
    }

    func terminate() {
        lock.lock()
        cancelled = true
        let proc = process
        let activePID = pid
        lock.unlock()
        if let proc {
            ProcessSupervisor.terminateProcessGroup(pid: activePID, process: proc, graceSeconds: 0.5)
        }
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Data()

    func set(_ data: Data) {
        lock.lock()
        value = data
        lock.unlock()
    }

    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Fetches rich video/playlist metadata, playlist entry lists, and stream format tables via `yt-dlp --dump-single-json`.
public enum MediaInspector {

    public static func inspect(
        url rawURL: String,
        ytdlpPath: String?,
        browserCookies: BrowserCookiesSource = .none,
        proxyURL: String = "",
        networkIPVersion: NetworkIPVersion = .ipv4,
        socketTimeoutSeconds: Int = 20,
        jsRuntimeArg: String? = nil,
        playlistMode: PlaylistInspectMode = .automatic,
        overallTimeoutSeconds: Double = 60
    ) async throws -> MediaInfo {
        guard let ytdlpPath, !ytdlpPath.isEmpty else {
            throw MediaInspectorError.missingEngine
        }

        let trimmedURL = YTDLPCommandBuilder.sanitizeURL(rawURL)
        guard YTDLPCommandBuilder.isValidMediaURL(trimmedURL) else {
            throw MediaInspectorError.invalidURL
        }

        let useFlatPlaylist: Bool
        let targetURL: String
        switch playlistMode {
        case .forcePlaylist:
            useFlatPlaylist = true
            // If user passed watch?v=...&list=PL... and asked to expand playlist, query the canonical playlist URL directly.
            targetURL = PlaylistURLDetector.extractLinkedPlaylistURL(from: trimmedURL) ?? trimmedURL
        case .forceSingleVideo:
            useFlatPlaylist = false
            targetURL = trimmedURL
        case .automatic:
            useFlatPlaylist = PlaylistURLDetector.isPurePlaylistURL(trimmedURL)
            targetURL = trimmedURL
        }

        var args: [String] = ["--ignore-config", "--no-exec"]
        if let ipFlag = networkIPVersion.ytdlpFlag {
            args.append(ipFlag)
        }
        let boundedSocketTimeout = max(5, min(60, socketTimeoutSeconds))
        args.append(contentsOf: ["--socket-timeout", "\(boundedSocketTimeout)"])

        if let jsRuntimeArg, !jsRuntimeArg.isEmpty {
            args.append(contentsOf: ["--js-runtimes", jsRuntimeArg])
        }

        args.append(contentsOf: [
            "--dump-single-json",
            "--no-warnings",
            "--skip-download"
        ])
        if useFlatPlaylist {
            args.append(contentsOf: ["--flat-playlist", "--yes-playlist"])
        } else {
            args.append("--no-playlist")
        }

        if let browser = browserCookies.ytdlpIdentifier {
            args.append(contentsOf: ["--cookies-from-browser", browser])
        }

        let trimmedProxy = proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedProxy.isEmpty {
            args.append(contentsOf: ["--proxy", trimmedProxy])
        }

        args.append("--")
        args.append(targetURL)

        let immutableArgs = args
        let processBox = InspectorProcessBox()

        let outputData: Data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    ProcessSupervisor.configure(
                        process,
                        executableURL: URL(fileURLWithPath: ytdlpPath),
                        arguments: immutableArgs,
                        environment: EngineManager.enrichedEnvironment()
                    )

                    let stdout = Pipe()
                    let stderr = Pipe()
                    process.standardOutput = stdout
                    process.standardError = stderr

                    guard processBox.store(process) else {
                        continuation.resume(throwing: MediaInspectorError.cancelled)
                        return
                    }

                    let timedOutFlag = InspectorProcessBox()
                    let timeoutWork = DispatchWorkItem {
                        if process.isRunning {
                            timedOutFlag.terminate()
                            processBox.terminate()
                        }
                    }
                    DispatchQueue.global(qos: .utility).asyncAfter(
                        deadline: .now() + overallTimeoutSeconds,
                        execute: timeoutWork
                    )

                    do {
                        let pid = try ProcessSupervisor.launchInNewProcessGroup(process)
                        processBox.updatePID(pid)

                        // Drain stdout & stderr concurrently to eliminate any 64KB pipe buffer deadlock.
                        let outBox = DataBox()
                        let errBox = DataBox()
                        let ioGroup = DispatchGroup()

                        ioGroup.enter()
                        DispatchQueue.global(qos: .userInitiated).async {
                            outBox.set(stdout.fileHandleForReading.readDataToEndOfFile())
                            ioGroup.leave()
                        }

                        ioGroup.enter()
                        DispatchQueue.global(qos: .userInitiated).async {
                            errBox.set(stderr.fileHandleForReading.readDataToEndOfFile())
                            ioGroup.leave()
                        }

                        process.waitUntilExit()
                        timeoutWork.cancel()
                        ioGroup.wait()

                        if timedOutFlag.isCancelled {
                            continuation.resume(throwing: MediaInspectorError.timedOut)
                            return
                        }
                        if processBox.isCancelled {
                            continuation.resume(throwing: MediaInspectorError.cancelled)
                            return
                        }

                        let outData = outBox.get()
                        let errData = errBox.get()

                        if process.terminationStatus != 0 {
                            let errText = String(data: errData, encoding: .utf8)?
                                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            continuation.resume(throwing: MediaInspectorError.processFailed(errText))
                            return
                        }
                        continuation.resume(returning: outData)
                    } catch {
                        timeoutWork.cancel()
                        continuation.resume(throwing: MediaInspectorError.processFailed(error.localizedDescription))
                    }
                }
            }
        } onCancel: {
            processBox.terminate()
        }

        return try decodeMetadata(from: outputData, fallbackURL: trimmedURL)
    }

    public static func decodeMetadata(from data: Data, fallbackURL: String) throws -> MediaInfo {
        let jsonData: Data
        if let firstBrace = data.firstIndex(of: UInt8(ascii: "{")) {
            jsonData = data.subdata(in: firstBrace..<data.endIndex)
        } else {
            jsonData = data
        }

        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw MediaInspectorError.decodingFailed("Expected a JSON object.")
        }

        let id = (root["id"] as? String) ?? UUID().uuidString
        let webpageURL = (root["webpage_url"] as? String) ?? fallbackURL
        let title = (root["title"] as? String) ?? DownloadTaskItem.fallbackTitle(from: fallbackURL)
        let uploader = (root["uploader"] as? String) ?? (root["channel"] as? String)
        let extractor = (root["extractor_key"] as? String) ?? (root["extractor"] as? String)
        let duration = (root["duration"] as? Double) ?? (root["duration"] as? Int).map(Double.init)
        let viewCount = root["view_count"] as? Int
        let uploadDate = root["upload_date"] as? String
        let isLive = (root["is_live"] as? Bool) ?? ((root["live_status"] as? String) == "is_live")

        let rawEntries = root["entries"] as? [[String: Any]]
        let isPlaylist = (root["_type"] as? String) == "playlist" || rawEntries != nil

        let parsedEntries: [PlaylistEntry] = (rawEntries ?? []).enumerated().compactMap { offset, item in
            let entryID = (item["id"] as? String) ?? "item-\(offset + 1)"
            let entryTitle = (item["title"] as? String) ?? "Video #\(offset + 1)"
            let entryURL = resolveEntryURL(item: item, fallbackExtractor: extractor)
            guard let entryURL else { return nil }

            let entryUploader = (item["uploader"] as? String) ?? (item["channel"] as? String)
            let entryDuration = (item["duration"] as? Double) ?? (item["duration"] as? Int).map(Double.init)
            let availability = item["availability"] as? String

            var entryThumb = item["thumbnail"] as? String
            if entryThumb == nil, let thumbs = item["thumbnails"] as? [[String: Any]] {
                entryThumb = thumbs.first?["url"] as? String ?? thumbs.last?["url"] as? String
            }

            return PlaylistEntry(
                index: offset + 1,
                id: entryID,
                title: entryTitle,
                url: entryURL,
                uploader: entryUploader,
                durationSeconds: entryDuration,
                thumbnailURL: entryThumb,
                availability: availability
            )
        }

        let playlistCount = parsedEntries.isEmpty
            ? ((root["playlist_count"] as? Int) ?? rawEntries?.count)
            : parsedEntries.count

        var thumbnailURL = root["thumbnail"] as? String
        if thumbnailURL == nil, let thumbnails = root["thumbnails"] as? [[String: Any]] {
            thumbnailURL = thumbnails.last?["url"] as? String
        }
        if thumbnailURL == nil {
            thumbnailURL = parsedEntries.first(where: { $0.thumbnailURL != nil })?.thumbnailURL
        }

        let linkedPlaylistURL: String? = isPlaylist
            ? nil
            : PlaylistURLDetector.extractLinkedPlaylistURL(from: fallbackURL)

        let rawFormats = root["formats"] as? [[String: Any]] ?? []
        let parsedFormats: [MediaFormat] = rawFormats.compactMap { item in
            guard let formatID = item["format_id"] as? String,
                  let ext = item["ext"] as? String else {
                return nil
            }
            if ext == "mhtml" || (item["format_note"] as? String)?.lowercased() == "storyboard" {
                return nil
            }
            let width = item["width"] as? Int
            let height = item["height"] as? Int
            let fps = (item["fps"] as? Double) ?? (item["fps"] as? Int).map(Double.init)
            let vcodec = item["vcodec"] as? String
            let acodec = item["acodec"] as? String
            let tbr = (item["tbr"] as? Double) ?? (item["tbr"] as? Int).map(Double.init)
            let filesize = (item["filesize"] as? Int64)
                ?? (item["filesize"] as? Int).map(Int64.init)
                ?? (item["filesize_approx"] as? Int64)
                ?? (item["filesize_approx"] as? Int).map(Int64.init)
            let resolution = item["resolution"] as? String
            let formatNote = item["format_note"] as? String

            return MediaFormat(
                formatID: formatID,
                ext: ext,
                resolution: resolution,
                width: width,
                height: height,
                fps: fps,
                vcodec: vcodec,
                acodec: acodec,
                tbr: tbr,
                filesize: filesize,
                formatNote: formatNote
            )
        }
        .sorted { lhs, rhs in
            let lh = lhs.height ?? 0
            let rh = rhs.height ?? 0
            if lh != rh { return lh > rh }
            let lf = lhs.fps ?? 0
            let rf = rhs.fps ?? 0
            if lf != rf { return lf > rf }
            return (lhs.tbr ?? 0) > (rhs.tbr ?? 0)
        }

        return MediaInfo(
            id: id,
            webpageURL: webpageURL,
            title: title,
            uploader: uploader,
            extractor: extractor,
            durationSeconds: duration,
            viewCount: viewCount,
            uploadDate: uploadDate,
            thumbnailURL: thumbnailURL,
            isPlaylist: isPlaylist,
            playlistCount: playlistCount,
            playlistEntries: parsedEntries,
            linkedPlaylistURL: linkedPlaylistURL,
            formats: parsedFormats,
            isLive: isLive
        )
    }

    private static func resolveEntryURL(item: [String: Any], fallbackExtractor: String?) -> String? {
        if let webpageURL = item["webpage_url"] as? String,
           webpageURL.hasPrefix("http://") || webpageURL.hasPrefix("https://") {
            return webpageURL
        }
        if let rawURL = item["url"] as? String, !rawURL.isEmpty {
            if rawURL.hasPrefix("http://") || rawURL.hasPrefix("https://") {
                return rawURL
            }
            let ieKey = ((item["ie_key"] as? String) ?? fallbackExtractor ?? "").lowercased()
            if ieKey.contains("youtube") {
                return "https://www.youtube.com/watch?v=\(rawURL)"
            }
        }
        if let id = item["id"] as? String, !id.isEmpty {
            let ieKey = ((item["ie_key"] as? String) ?? fallbackExtractor ?? "").lowercased()
            if ieKey.contains("youtube") {
                return "https://www.youtube.com/watch?v=\(id)"
            }
        }
        return nil
    }
}
