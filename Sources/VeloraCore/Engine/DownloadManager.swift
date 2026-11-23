import AppKit
import Foundation

/// Coordinates concurrent `yt-dlp` download processes, bulk/playlist batches, queue state, live logs, history, and presets.
@MainActor
@Observable
public final class DownloadManager {
    public private(set) var queue: [DownloadTaskItem] = []
    public private(set) var history: [DownloadHistoryEntry] = []
    public private(set) var customPresets: [DownloadPreset] = []
    public private(set) var isQueuePaused: Bool = false

    public var maxConcurrentDownloads: Int {
        didSet {
            let clamped = max(1, min(8, maxConcurrentDownloads))
            if clamped != maxConcurrentDownloads {
                maxConcurrentDownloads = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Keys.maxConcurrentDownloads)
            pumpQueue()
        }
    }

    public var playSoundOnComplete: Bool {
        didSet {
            UserDefaults.standard.set(playSoundOnComplete, forKey: Keys.playSoundOnComplete)
        }
    }

    private let engineManager: EngineManager
    private let store: VeloraStore
    private var runningProcesses: [UUID: Process] = [:]

    private enum Keys {
        static let maxConcurrentDownloads = "velora.downloads.maxConcurrent"
        static let playSoundOnComplete = "velora.downloads.playSoundOnComplete"
    }

    public var allPresets: [DownloadPreset] {
        DownloadPreset.builtInPresets + customPresets
    }

    public var activeCount: Int {
        queue.filter { $0.status.isActive }.count
    }

    public var queuedCount: Int {
        queue.filter { $0.status == .queued }.count
    }

    public var completedCount: Int {
        queue.filter { $0.status == .completed }.count
    }

    public var failedCount: Int {
        queue.filter { $0.status == .failed }.count
    }

    public var hasActiveDownloads: Bool {
        activeCount > 0
    }

    public var hasPendingOrActiveDownloads: Bool {
        activeCount > 0 || queuedCount > 0
    }

    /// Aggregate progress across all non-cancelled queue items (ideal for bulk / playlist batches).
    public var overallQueueProgress: Double {
        let relevant = queue.filter { $0.status != .cancelled }
        guard !relevant.isEmpty else { return 0 }
        let sum = relevant.reduce(0.0) { acc, item in
            switch item.status {
            case .completed: acc + 1.0
            case .downloading, .postProcessing: acc + item.progress
            default: acc
            }
        }
        return min(1.0, max(0.0, sum / Double(relevant.count)))
    }

    public init(engineManager: EngineManager, store: VeloraStore = VeloraStore()) {
        self.engineManager = engineManager
        self.store = store

        let savedConcurrent = UserDefaults.standard.integer(forKey: Keys.maxConcurrentDownloads)
        self.maxConcurrentDownloads = savedConcurrent > 0 ? max(1, min(8, savedConcurrent)) : 3

        if UserDefaults.standard.object(forKey: Keys.playSoundOnComplete) != nil {
            self.playSoundOnComplete = UserDefaults.standard.bool(forKey: Keys.playSoundOnComplete)
        } else {
            self.playSoundOnComplete = true
        }

        self.history = store.loadHistory()
        self.customPresets = store.loadCustomPresets()
    }

    // MARK: - Enqueue & Bulk Operations

    @discardableResult
    public func enqueue(
        url rawURL: String,
        configuration: DownloadConfiguration,
        mediaInfo: MediaInfo? = nil,
        batchID: UUID? = nil,
        batchName: String? = nil,
        playlistIndex: Int? = nil,
        playlistTotal: Int? = nil
    ) -> DownloadTaskItem? {
        let trimmed = YTDLPCommandBuilder.sanitizeURL(rawURL)
        guard !trimmed.isEmpty else { return nil }

        let item = DownloadTaskItem(
            url: trimmed,
            title: mediaInfo?.title,
            uploader: mediaInfo?.uploader,
            extractor: mediaInfo?.extractor,
            thumbnailURL: mediaInfo?.thumbnailURL,
            configuration: configuration,
            batchID: batchID,
            batchName: batchName,
            playlistIndex: playlistIndex,
            playlistTotal: playlistTotal
        )
        queue.insert(item, at: 0)
        pumpQueue()
        return item
    }

    /// Enqueues selected entries from a playlist/channel as individual concurrent downloads,
    /// optionally saving them into a dedicated playlist subfolder with zero-padded track numbering.
    @discardableResult
    public func enqueuePlaylistEntries(
        _ entries: [PlaylistEntry],
        playlistTitle: String,
        extractor: String? = nil,
        baseConfiguration: DownloadConfiguration,
        createSubfolder: Bool = true,
        prefixIndex: Bool = true
    ) -> [DownloadTaskItem] {
        guard !entries.isEmpty else { return [] }

        let batchID = UUID()
        let safeFolderName = PlaylistURLDetector.sanitizeFolderName(playlistTitle)
        let expandedBase = (baseConfiguration.outputDirectoryPath as NSString).expandingTildeInPath
        let destinationDir: String = createSubfolder
            ? URL(fileURLWithPath: expandedBase, isDirectory: true).appendingPathComponent(safeFolderName, isDirectory: true).path
            : baseConfiguration.outputDirectoryPath

        let maxIndex = entries.map(\.index).max() ?? entries.count
        let padWidth = maxIndex >= 100 ? 3 : 2

        var created: [DownloadTaskItem] = []
        // Insert in reverse order at index 0? No: pumpQueue starts FIFO from the tail of `queue` (reversed indices).
        // Inserting item 1 first, then item 2 at index 0 puts item 1 at the tail so item 1 starts FIRST!
        for entry in entries {
            var itemConfig = baseConfiguration
            itemConfig.playlistBehavior = .singleVideoOnly
            itemConfig.playlistItems = ""
            itemConfig.createPlaylistSubfolder = false
            itemConfig.customFormatID = nil
            itemConfig.outputDirectoryPath = destinationDir

            if prefixIndex {
                let padded = String(format: "%0\(padWidth)d", entry.index)
                let baseTemplate = baseConfiguration.effectiveFilenameTemplate
                itemConfig.filenamePreset = .custom
                itemConfig.customFilenameTemplate = "\(padded) - \(baseTemplate)"
            }

            let item = DownloadTaskItem(
                url: entry.url,
                title: entry.title,
                uploader: entry.uploader,
                extractor: extractor,
                thumbnailURL: entry.thumbnailURL,
                configuration: itemConfig,
                batchID: batchID,
                batchName: playlistTitle,
                playlistIndex: entry.index,
                playlistTotal: entries.count
            )
            queue.insert(item, at: 0)
            created.append(item)
        }

        pumpQueue()
        return created
    }

    @discardableResult
    public func enqueueBatch(
        multilineInput: String,
        configuration: DownloadConfiguration,
        batchName: String? = nil
    ) -> [DownloadTaskItem] {
        let urls = YTDLPCommandBuilder.extractURLs(from: multilineInput)
        return enqueueURLs(urls, configuration: configuration, batchName: batchName)
    }

    @discardableResult
    public func enqueueURLs(
        _ urls: [String],
        configuration: DownloadConfiguration,
        batchName: String? = nil
    ) -> [DownloadTaskItem] {
        guard !urls.isEmpty else { return [] }
        let batchID = urls.count > 1 ? UUID() : nil
        let effectiveBatchName = batchName ?? (urls.count > 1 ? "Bulk Batch (\(urls.count))" : nil)

        var added: [DownloadTaskItem] = []
        for (idx, url) in urls.enumerated() {
            let item = DownloadTaskItem(
                url: url,
                configuration: configuration,
                batchID: batchID,
                batchName: effectiveBatchName,
                playlistIndex: urls.count > 1 ? idx + 1 : nil,
                playlistTotal: urls.count > 1 ? urls.count : nil
            )
            queue.insert(item, at: 0)
            added.append(item)
        }
        pumpQueue()
        return added
    }

    // MARK: - Queue Controls

    public func pauseQueue() {
        isQueuePaused = true
    }

    public func resumeQueue() {
        isQueuePaused = false
        pumpQueue()
    }

    public func cancel(id: UUID) {
        if let process = runningProcesses[id] {
            process.terminate()
            runningProcesses.removeValue(forKey: id)
        }
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[idx].status = .cancelled
        queue[idx].statusDetail = "Cancelled by user"
        queue[idx].speedText = nil
        queue[idx].etaText = nil
        pumpQueue()
    }

    /// Cancels all currently running downloads AND any waiting queued items.
    public func cancelAllActive() {
        // First mark all queued items cancelled so termination handlers do not launch them.
        for idx in queue.indices where queue[idx].status == .queued || queue[idx].status.isActive {
            queue[idx].status = .cancelled
            queue[idx].statusDetail = "Cancelled"
            queue[idx].speedText = nil
            queue[idx].etaText = nil
        }
        for (_, process) in runningProcesses {
            process.terminate()
        }
        runningProcesses.removeAll()
    }

    public func retry(id: UUID) {
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }
        guard queue[idx].status.isTerminal else { return }
        queue[idx].status = .queued
        queue[idx].progress = 0
        queue[idx].statusDetail = "Queued for retry"
        queue[idx].errorMessage = nil
        queue[idx].speedText = nil
        queue[idx].etaText = nil
        queue[idx].logs.append("— Retrying download —")
        pumpQueue()
    }

    public func retryAllFailed() {
        var didRequeue = false
        for idx in queue.indices where queue[idx].status == .failed || queue[idx].status == .cancelled {
            queue[idx].status = .queued
            queue[idx].progress = 0
            queue[idx].statusDetail = "Queued for retry"
            queue[idx].errorMessage = nil
            queue[idx].speedText = nil
            queue[idx].etaText = nil
            queue[idx].logs.append("— Retrying download —")
            didRequeue = true
        }
        if didRequeue {
            isQueuePaused = false
            pumpQueue()
        }
    }

    public func remove(id: UUID) {
        if let process = runningProcesses[id] {
            process.terminate()
            runningProcesses.removeValue(forKey: id)
        }
        queue.removeAll { $0.id == id }
        pumpQueue()
    }

    public func clearFinished() {
        queue.removeAll { $0.status.isTerminal }
    }

    // MARK: - History & Presets

    public func removeHistoryEntry(id: UUID) {
        history.removeAll { $0.id == id }
        store.saveHistory(history)
    }

    public func clearHistory() {
        history.removeAll()
        store.saveHistory(history)
    }

    public func saveCustomPreset(name: String, subtitle: String, symbolName: String, configuration: DownloadConfiguration) {
        let preset = DownloadPreset(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            symbolName: symbolName,
            configuration: configuration,
            isBuiltIn: false
        )
        customPresets.append(preset)
        store.saveCustomPresets(customPresets)
    }

    public func deleteCustomPreset(id: UUID) {
        customPresets.removeAll { $0.id == id }
        store.saveCustomPresets(customPresets)
    }

    // MARK: - Execution Pipeline

    private func pumpQueue() {
        guard !isQueuePaused else { return }
        guard activeCount < maxConcurrentDownloads else { return }

        // Start oldest queued item first (FIFO)
        let queuedIndices = queue.indices.filter { queue[$0].status == .queued }.reversed()
        for idx in queuedIndices {
            guard activeCount < maxConcurrentDownloads else { break }
            startItem(at: idx)
        }
    }

    private func startItem(at index: Int) {
        let item = queue[index]
        guard let ytdlpPath = engineManager.ytdlpStatus.path else {
            queue[index].status = .failed
            queue[index].statusDetail = "yt-dlp not installed"
            queue[index].errorMessage = "Install yt-dlp via Engine Setup before downloading."
            return
        }

        // Ensure destination folder exists
        let expandedOutDir = (item.configuration.outputDirectoryPath as NSString).expandingTildeInPath
        do {
            try FileManager.default.createDirectory(
                atPath: expandedOutDir,
                withIntermediateDirectories: true
            )
        } catch {
            queue[index].status = .failed
            queue[index].statusDetail = "Output folder unavailable"
            queue[index].errorMessage = error.localizedDescription
            return
        }

        let args = YTDLPCommandBuilder.buildArguments(
            url: item.url,
            configuration: item.configuration,
            ffmpegPath: engineManager.ffmpegStatus.path,
            jsRuntimeArg: engineManager.ytdlpJSRuntimeArgument
        )

        queue[index].status = .preparing
        queue[index].statusDetail = "Connecting & resolving streams…"
        queue[index].logs.append("$ \(YTDLPCommandBuilder.shellPreview(ytdlpPath: ytdlpPath, url: item.url, configuration: item.configuration, ffmpegPath: engineManager.ffmpegStatus.path, jsRuntimeArg: engineManager.ytdlpJSRuntimeArgument))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = args
        process.environment = EngineManager.enrichedEnvironment()

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let taskID = item.id
        let accumulator = ProcessLineAccumulator()

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let lines = accumulator.append(data)
            guard !lines.isEmpty else { return }
            Task { @MainActor [weak self] in
                for line in lines {
                    self?.handleOutputLine(line, for: taskID)
                }
            }
        }

        process.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            let trailing = accumulator.flush()
            let exitCode = proc.terminationStatus
            let reason = proc.terminationReason
            Task { @MainActor [weak self] in
                for line in trailing {
                    self?.handleOutputLine(line, for: taskID)
                }
                self?.handleProcessExit(taskID: taskID, status: exitCode, reason: reason)
            }
        }

        do {
            try process.run()
            runningProcesses[taskID] = process
        } catch {
            queue[index].status = .failed
            queue[index].statusDetail = "Failed to launch yt-dlp"
            queue[index].errorMessage = error.localizedDescription
            pumpQueue()
        }
    }

    private func handleOutputLine(_ rawLine: String, for taskID: UUID) {
        guard let idx = queue.firstIndex(where: { $0.id == taskID }) else { return }

        let event = YTDLPOutputParser.parse(line: rawLine)
        switch event {
        case let .metadata(title, uploader, extractor):
            queue[idx].title = title
            if let uploader { queue[idx].uploader = uploader }
            if let extractor { queue[idx].extractor = extractor }

        case let .playlistItemProgress(current, total):
            queue[idx].playlistIndex = current
            queue[idx].playlistTotal = total
            queue[idx].status = .downloading
            queue[idx].statusDetail = "Item \(current) of \(total) · Preparing…"
            appendLog(rawLine, at: idx)

        case let .progress(fraction, speed, eta, totalSize):
            queue[idx].status = .downloading
            queue[idx].speedText = speed
            queue[idx].etaText = eta
            if let totalSize { queue[idx].fileSizeText = totalSize }

            let pctInt = Int((fraction * 100).rounded())
            if queue[idx].configuration.playlistBehavior == .downloadEntirePlaylist,
               let current = queue[idx].playlistIndex,
               let total = queue[idx].playlistTotal,
               total > 1 {
                let overall = (Double(current - 1) + fraction) / Double(total)
                queue[idx].progress = min(1.0, max(0.0, overall))
                queue[idx].statusDetail = "Item \(current)/\(total) · \(pctInt)%"
            } else {
                queue[idx].progress = fraction
                queue[idx].statusDetail = "Downloading \(pctInt)%"
            }

        case let .postProcessing(stage):
            queue[idx].status = .postProcessing
            if queue[idx].configuration.playlistBehavior != .downloadEntirePlaylist {
                queue[idx].progress = max(queue[idx].progress, 0.99)
            }
            queue[idx].speedText = nil
            queue[idx].etaText = nil
            if queue[idx].configuration.playlistBehavior == .downloadEntirePlaylist,
               let current = queue[idx].playlistIndex,
               let total = queue[idx].playlistTotal,
               total > 1 {
                queue[idx].statusDetail = "Item \(current)/\(total) · \(stage)"
            } else {
                queue[idx].statusDetail = stage
            }
            appendLog(rawLine, at: idx)

        case let .destination(path):
            queue[idx].outputFilePath = path
            appendLog(rawLine, at: idx)

        case let .finalFilePath(path):
            queue[idx].outputFilePath = path
            queue[idx].completedFileCount += 1
            appendLog("Saved: \(path)", at: idx)

            // For multi-item direct playlist downloads, record each finished video into history immediately.
            if queue[idx].configuration.playlistBehavior == .downloadEntirePlaylist {
                recordHistory(for: queue[idx], filePath: path)
            }

        case let .error(message):
            queue[idx].errorMessage = message
            appendLog(rawLine, at: idx)

        case let .log(line):
            if !line.isEmpty {
                appendLog(line, at: idx)
            }
        }
    }

    private func appendLog(_ line: String, at index: Int) {
        queue[index].logs.append(line)
        if queue[index].logs.count > 400 {
            queue[index].logs.removeFirst(queue[index].logs.count - 400)
        }
    }

    private func recordHistory(for item: DownloadTaskItem, filePath: String?) {
        let fileSizeBytes: Int64? = filePath.flatMap { path in
            (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
        }
        let entry = DownloadHistoryEntry(
            url: item.url,
            title: item.title,
            uploader: item.uploader,
            extractor: item.extractor,
            thumbnailURL: item.thumbnailURL,
            formatSummary: item.configuration.summaryBadge,
            outputFilePath: filePath,
            outputDirectoryPath: item.configuration.outputDirectoryPath,
            fileSizeBytes: fileSizeBytes,
            completedAt: Date()
        )
        history.insert(entry, at: 0)
        if history.count > 500 {
            history.removeLast(history.count - 500)
        }
        store.saveHistory(history)
    }

    private func handleProcessExit(taskID: UUID, status: Int32, reason: Process.TerminationReason) {
        runningProcesses.removeValue(forKey: taskID)
        guard let idx = queue.firstIndex(where: { $0.id == taskID }) else {
            pumpQueue()
            return
        }

        if queue[idx].status == .cancelled {
            pumpQueue()
            return
        }

        let isDirectPlaylist = queue[idx].configuration.playlistBehavior == .downloadEntirePlaylist
        // With --ignore-errors on playlists, yt-dlp exits 1 if 1 private video failed while 19 succeeded.
        let succeeded = (status == 0 && reason == .exit) || (isDirectPlaylist && queue[idx].completedFileCount > 0 && reason == .exit)

        if succeeded {
            queue[idx].status = .completed
            queue[idx].progress = 1.0
            queue[idx].speedText = nil
            queue[idx].etaText = nil
            if isDirectPlaylist && queue[idx].completedFileCount > 1 {
                queue[idx].statusDetail = status == 0
                    ? "Completed (\(queue[idx].completedFileCount) files)"
                    : "Completed \(queue[idx].completedFileCount) files (some skipped)"
            } else {
                queue[idx].statusDetail = "Completed"
            }
            queue[idx].completedAt = Date()

            if !isDirectPlaylist {
                recordHistory(for: queue[idx], filePath: queue[idx].outputFilePath)
            }

            // Play completion chime only when this finishes the active burst or single job (avoid spamming 50 chimes).
            if playSoundOnComplete && activeCount == 0 && queuedCount == 0 {
                NSSound(named: NSSound.Name("Glass"))?.play()
            }
        } else {
            queue[idx].status = .failed
            queue[idx].speedText = nil
            queue[idx].etaText = nil
            queue[idx].statusDetail = "Download failed (code \(status))"
            if queue[idx].errorMessage == nil {
                queue[idx].errorMessage = queue[idx].logs.last(where: { !$0.isEmpty })
                    ?? "yt-dlp exited with code \(status)."
            }
        }

        pumpQueue()
    }
}
