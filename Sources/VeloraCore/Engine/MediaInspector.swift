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

private final class InspectorProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func store(_ proc: Process) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if cancelled {
            return false
        }
        process = proc
        return true
    }

    func terminate() {
        lock.lock()
        cancelled = true
        let proc = process
        lock.unlock()
        if let proc, proc.isRunning {
            proc.terminate()
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

/// Fetches rich video/playlist metadata and stream format tables via `yt-dlp --dump-single-json`.
public enum MediaInspector {

    public static func inspect(
        url rawURL: String,
        ytdlpPath: String?,
        browserCookies: BrowserCookiesSource = .none,
        proxyURL: String = "",
        networkIPVersion: NetworkIPVersion = .ipv4,
        socketTimeoutSeconds: Int = 20,
        jsRuntimeArg: String? = nil,
        overallTimeoutSeconds: Double = 45
    ) async throws -> MediaInfo {
        guard let ytdlpPath, !ytdlpPath.isEmpty else {
            throw MediaInspectorError.missingEngine
        }

        let trimmedURL = YTDLPCommandBuilder.sanitizeURL(rawURL)
        guard !trimmedURL.isEmpty, URL(string: trimmedURL) != nil else {
            throw MediaInspectorError.invalidURL
        }

        let looksLikePurePlaylist = trimmedURL.contains("/playlist?") || trimmedURL.contains("/sets/")

        var args: [String] = []
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
        if looksLikePurePlaylist {
            args.append("--flat-playlist")
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
        args.append(trimmedURL)

        let immutableArgs = args
        let processBox = InspectorProcessBox()

        let outputData: Data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: ytdlpPath)
                    process.arguments = immutableArgs
                    process.environment = EngineManager.enrichedEnvironment()

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
                            process.terminate()
                        }
                    }
                    DispatchQueue.global(qos: .utility).asyncAfter(
                        deadline: .now() + overallTimeoutSeconds,
                        execute: timeoutWork
                    )

                    do {
                        try process.run()

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
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
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

        let entries = root["entries"] as? [[String: Any]]
        let isPlaylist = (root["_type"] as? String) == "playlist" || entries != nil
        let playlistCount = (root["playlist_count"] as? Int) ?? entries?.count

        var thumbnailURL = root["thumbnail"] as? String
        if thumbnailURL == nil, let thumbnails = root["thumbnails"] as? [[String: Any]] {
            thumbnailURL = thumbnails.last?["url"] as? String
        }
        if thumbnailURL == nil, let firstEntry = entries?.first {
            thumbnailURL = firstEntry["thumbnail"] as? String
        }

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
            formats: parsedFormats
        )
    }
}
