import AppKit
import Foundation

/// Coordinates concurrent `yt-dlp` download processes, queue state, live logs, history, and presets.
@MainActor
@Observable
public final class DownloadManager {
    public private(set) var queue: [DownloadTaskItem] = []
    public private(set) var history: [DownloadHistoryEntry] = []
    public private(set) var customPresets: [DownloadPreset] = []

    public var maxConcurrentDownloads: Int {
        didSet {
            let clamped = max(1, min(6, maxConcurrentDownloads))
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

    public var hasActiveDownloads: Bool {
        activeCount > 0
    }

    public init(engineManager: EngineManager, store: VeloraStore = VeloraStore()) {
        self.engineManager = engineManager
        self.store = store

        let savedConcurrent = UserDefaults.standard.integer(forKey: Keys.maxConcurrentDownloads)
        self.maxConcurrentDownloads = savedConcurrent > 0 ? max(1, min(6, savedConcurrent)) : 2

        if UserDefaults.standard.object(forKey: Keys.playSoundOnComplete) != nil {
            self.playSoundOnComplete = UserDefaults.standard.bool(forKey: Keys.playSoundOnComplete)
        } else {
            self.playSoundOnComplete = true
        }

        self.history = store.loadHistory()
        self.customPresets = store.loadCustomPresets()
    }

    // MARK: - Enqueue & Queue Operations

    @discardableResult
    public func enqueue(
        url rawURL: String,
        configuration: DownloadConfiguration,
        mediaInfo: MediaInfo? = nil
    ) -> DownloadTaskItem? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let item = DownloadTaskItem(
            url: trimmed,
            title: mediaInfo?.title,
            uploader: mediaInfo?.uploader,
            extractor: mediaInfo?.extractor,
            thumbnailURL: mediaInfo?.thumbnailURL,
            configuration: configuration
        )
        queue.insert(item, at: 0)
        pumpQueue()
        return item
    }

    @discardableResult
    public func enqueueBatch(
        multilineInput: String,
        configuration: DownloadConfiguration
    ) -> [DownloadTaskItem] {
        let urls = multilineInput
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && ($0.hasPrefix("http://") || $0.hasPrefix("https://")) }

        var added: [DownloadTaskItem] = []
        for url in urls {
            if let item = enqueue(url: url, configuration: configuration) {
                added.append(item)
            }
        }
        return added
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

    public func cancelAllActive() {
        for (id, process) in runningProcesses {
            process.terminate()
            if let idx = queue.firstIndex(where: { $0.id == id }) {
                queue[idx].status = .cancelled
                queue[idx].statusDetail = "Cancelled"
            }
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

        case let .progress(fraction, speed, eta, totalSize):
            queue[idx].status = .downloading
            queue[idx].progress = fraction
            queue[idx].speedText = speed
            queue[idx].etaText = eta
            if let totalSize { queue[idx].fileSizeText = totalSize }
            let pctInt = Int((fraction * 100).rounded())
            queue[idx].statusDetail = "Downloading \(pctInt)%"

        case let .postProcessing(stage):
            queue[idx].status = .postProcessing
            queue[idx].progress = max(queue[idx].progress, 0.99)
            queue[idx].speedText = nil
            queue[idx].etaText = nil
            queue[idx].statusDetail = stage
            appendLog(rawLine, at: idx)

        case let .destination(path):
            queue[idx].outputFilePath = path
            appendLog(rawLine, at: idx)

        case let .finalFilePath(path):
            queue[idx].outputFilePath = path
            appendLog("Saved: \(path)", at: idx)

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

        if status == 0 && reason == .exit {
            queue[idx].status = .completed
            queue[idx].progress = 1.0
            queue[idx].speedText = nil
            queue[idx].etaText = nil
            queue[idx].statusDetail = "Completed"
            queue[idx].completedAt = Date()

            let finished = queue[idx]
            let fileSizeBytes: Int64? = finished.outputFilePath.flatMap { path in
                (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
            }

            let entry = DownloadHistoryEntry(
                url: finished.url,
                title: finished.title,
                uploader: finished.uploader,
                extractor: finished.extractor,
                thumbnailURL: finished.thumbnailURL,
                formatSummary: finished.configuration.summaryBadge,
                outputFilePath: finished.outputFilePath,
                outputDirectoryPath: finished.configuration.outputDirectoryPath,
                fileSizeBytes: fileSizeBytes,
                completedAt: finished.completedAt ?? Date()
            )
            history.insert(entry, at: 0)
            if history.count > 500 {
                history.removeLast(history.count - 500)
            }
            store.saveHistory(history)

            if playSoundOnComplete {
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
