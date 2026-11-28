import AppKit
import Foundation

private final class DownloadOutputCoalescer: @unchecked Sendable {
    private let ioQueue: DispatchQueue
    private let onFlushBatch: @Sendable ([(YTDLPOutputEvent, String)]) -> Void
    private let minInterval: Duration = .milliseconds(100)

    private var lastProgressEmittedAt: ContinuousClock.Instant?
    private var pendingProgress: (YTDLPOutputEvent, String)?
    private var trailingTimerScheduled = false
    private var isClosed = false

    init(
        ioQueue: DispatchQueue,
        onFlushBatch: @escaping @Sendable ([(YTDLPOutputEvent, String)]) -> Void
    ) {
        self.ioQueue = ioQueue
        self.onFlushBatch = onFlushBatch
    }

    func process(lines: [String]) {
        guard !isClosed else { return }
        var batch: [(YTDLPOutputEvent, String)] = []
        let now = ContinuousClock.now

        for rawLine in lines {
            let event = YTDLPOutputParser.parse(line: rawLine)
            if case .progress = event {
                if let last = lastProgressEmittedAt, (now - last) < minInterval {
                    pendingProgress = (event, rawLine)
                    scheduleTrailingTimerIfNeeded()
                } else {
                    pendingProgress = nil
                    lastProgressEmittedAt = now
                    batch.append((event, rawLine))
                }
            } else {
                if let pending = pendingProgress {
                    pendingProgress = nil
                    lastProgressEmittedAt = now
                    batch.append(pending)
                }
                batch.append((event, rawLine))
            }
        }

        if !batch.isEmpty {
            onFlushBatch(batch)
        }
    }

    func takeRemainingAndClose(trailingLines: [String]) -> [(YTDLPOutputEvent, String)] {
        isClosed = true
        var batch: [(YTDLPOutputEvent, String)] = []
        if let pending = pendingProgress {
            pendingProgress = nil
            batch.append(pending)
        }
        for rawLine in trailingLines {
            batch.append((YTDLPOutputParser.parse(line: rawLine), rawLine))
        }
        return batch
    }

    private func scheduleTrailingTimerIfNeeded() {
        guard !trailingTimerScheduled, !isClosed else { return }
        trailingTimerScheduled = true
        ioQueue.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
            guard let self else { return }
            self.trailingTimerScheduled = false
            guard !self.isClosed, let pending = self.pendingProgress else { return }
            self.pendingProgress = nil
            self.lastProgressEmittedAt = ContinuousClock.now
            self.onFlushBatch([pending])
        }
    }
}

/// Coordinates concurrent `yt-dlp` download processes, bulk/playlist batches, queue state, live logs, history, and presets.
@MainActor
@Observable
public final class DownloadManager {
    private struct RunningProcessEntry {
        let process: Process
        let pid: pid_t
    }

    public private(set) var queue: [DownloadTask] = []
    public private(set) var history: [DownloadHistoryEntry] = []
    public private(set) var customPresets: [DownloadPreset] = []
    public private(set) var isQueuePaused: Bool = false

    public private(set) var activeCount: Int = 0
    public private(set) var queuedCount: Int = 0
    public private(set) var pausedCount: Int = 0
    public private(set) var completedCount: Int = 0
    public private(set) var failedCount: Int = 0

    public var onTaskFinished: (@MainActor (DownloadTask, Bool) -> Void)?
    public var onQueueChanged: (@MainActor () -> Void)?

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
    private var runningProcesses: [UUID: RunningProcessEntry] = [:]
    private var videoOnlyFormatTaskIDs: Set<UUID> = []

    private enum Keys {
        static let maxConcurrentDownloads = "velora.downloads.maxConcurrent"
        static let playSoundOnComplete = "velora.downloads.playSoundOnComplete"
    }

    public var allPresets: [DownloadPreset] {
        DownloadPreset.builtInPresets + customPresets
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

        let persisted = store.loadQueue()
        self.isQueuePaused = persisted.isQueuePaused
        self.queue = persisted.items.map(DownloadTask.init(snapshot:))
        recalculateCounters()
    }

    /// Starts any restored `.queued` tasks once `engineManager.refresh()` completes (leaving `.paused` tasks paused).
    public func restorePendingQueueAfterEngineReady() {
        pumpQueue()
    }

    public func flushPersistence() async {
        await store.flush()
    }

    // MARK: - Enqueue & Bulk Operations

    public func hasPendingOrActiveDownload(for rawURL: String) -> Bool {
        let normalized = YTDLPCommandBuilder.sanitizeURL(rawURL)
        guard !normalized.isEmpty else { return false }
        return queue.contains { task in
            task.url == normalized && !task.status.isTerminal
        }
    }

    @discardableResult
    public func enqueue(
        url rawURL: String,
        configuration: DownloadConfiguration,
        mediaInfo: MediaInfo? = nil,
        customFormatIsVideoOnly: Bool = false,
        batchID: UUID? = nil,
        batchName: String? = nil,
        playlistIndex: Int? = nil,
        playlistTotal: Int? = nil
    ) -> DownloadTask? {
        let trimmed = YTDLPCommandBuilder.sanitizeURL(rawURL)
        guard YTDLPCommandBuilder.isValidMediaURL(trimmed) else { return nil }

        let task = DownloadTask(
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
        if customFormatIsVideoOnly {
            videoOnlyFormatTaskIDs.insert(task.id)
        }
        queue.insert(task, at: 0)
        recalculateCounters()
        persistQueue()
        pumpQueue()
        return task
    }

    /// Enqueues selected entries from a playlist/channel in natural `#01 -> #N` top-to-bottom order
    /// while executing them in FIFO order (`#01` first).
    @discardableResult
    public func enqueuePlaylistEntries(
        _ entries: [PlaylistEntry],
        playlistTitle: String,
        extractor: String? = nil,
        baseConfiguration: DownloadConfiguration,
        createSubfolder: Bool = true,
        prefixIndex: Bool = true
    ) -> [DownloadTask] {
        let validEntries = entries.filter { YTDLPCommandBuilder.isValidMediaURL($0.url) }
        guard !validEntries.isEmpty else { return [] }

        let batchID = UUID()
        let batchCreatedAt = Date()
        let safeFolderName = PlaylistURLDetector.sanitizeFolderName(playlistTitle)
        let expandedBase = (baseConfiguration.outputDirectoryPath as NSString).expandingTildeInPath
        let destinationDir: String = createSubfolder
            ? URL(fileURLWithPath: expandedBase, isDirectory: true).appendingPathComponent(safeFolderName, isDirectory: true).path
            : baseConfiguration.outputDirectoryPath

        let maxIndex = validEntries.map(\.index).max() ?? validEntries.count
        let padWidth = maxIndex >= 100 ? 3 : 2

        var created: [DownloadTask] = []
        created.reserveCapacity(validEntries.count)

        for entry in validEntries {
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

            let task = DownloadTask(
                url: YTDLPCommandBuilder.sanitizeURL(entry.url),
                title: entry.title,
                uploader: entry.uploader,
                extractor: extractor,
                thumbnailURL: entry.thumbnailURL,
                configuration: itemConfig,
                batchID: batchID,
                batchName: playlistTitle,
                playlistIndex: entry.index,
                playlistTotal: validEntries.count,
                createdAt: batchCreatedAt
            )
            created.append(task)
        }

        queue.insert(contentsOf: created, at: 0)
        recalculateCounters()
        persistQueue()
        pumpQueue()
        return created
    }

    @discardableResult
    public func enqueueBatch(
        multilineInput: String,
        configuration: DownloadConfiguration,
        batchName: String? = nil
    ) -> [DownloadTask] {
        let urls = YTDLPCommandBuilder.extractURLs(from: multilineInput)
        return enqueueURLs(urls, configuration: configuration, batchName: batchName)
    }

    @discardableResult
    public func enqueueURLs(
        _ urls: [String],
        configuration: DownloadConfiguration,
        batchName: String? = nil
    ) -> [DownloadTask] {
        let validURLs = urls
            .map(YTDLPCommandBuilder.sanitizeURL)
            .filter(YTDLPCommandBuilder.isValidMediaURL)
        guard !validURLs.isEmpty else { return [] }

        let batchID = validURLs.count > 1 ? UUID() : nil
        let batchCreatedAt = Date()
        let effectiveBatchName = batchName ?? (validURLs.count > 1 ? "Bulk Batch (\(validURLs.count))" : nil)

        var added: [DownloadTask] = []
        added.reserveCapacity(validURLs.count)

        for (idx, url) in validURLs.enumerated() {
            let task = DownloadTask(
                url: url,
                configuration: configuration,
                batchID: batchID,
                batchName: effectiveBatchName,
                playlistIndex: validURLs.count > 1 ? idx + 1 : nil,
                playlistTotal: validURLs.count > 1 ? validURLs.count : nil,
                createdAt: batchCreatedAt
            )
            added.append(task)
        }

        queue.insert(contentsOf: added, at: 0)
        recalculateCounters()
        persistQueue()
        pumpQueue()
        return added
    }

    // MARK: - Queue Controls

    public func pauseQueue() {
        isQueuePaused = true
        persistQueue()
    }

    public func resumeQueue() {
        isQueuePaused = false
        persistQueue()
        pumpQueue()
    }

    public func pause(id: UUID) {
        guard let task = queue.first(where: { $0.id == id }) else { return }
        guard task.status.isActive || task.status == .queued else { return }

        task.status = .paused
        task.statusDetail = "Paused — Resume to continue"
        task.speedText = nil
        task.etaText = nil
        task.logBuffer.append("— Paused by user —")

        if let running = runningProcesses.removeValue(forKey: id) {
            ProcessSupervisor.terminateProcessGroup(pid: running.pid, process: running.process)
        }

        recalculateCounters()
        persistQueue()
        pumpQueue()
    }

    public func resume(id: UUID) {
        guard let task = queue.first(where: { $0.id == id }) else { return }
        guard task.status.isResumable else { return }

        task.configuration.resumePartialDownloads = true
        task.status = .queued
        task.statusDetail = "Queued to resume"
        task.errorMessage = nil
        task.speedText = nil
        task.etaText = nil
        task.logBuffer.append("— Resuming download —")

        recalculateCounters()
        persistQueue()
        pumpQueue()
    }

    public func cancel(id: UUID) {
        if let task = queue.first(where: { $0.id == id }) {
            task.status = .cancelled
            task.statusDetail = "Cancelled by user"
            task.speedText = nil
            task.etaText = nil
        }
        if let running = runningProcesses.removeValue(forKey: id) {
            ProcessSupervisor.terminateProcessGroup(pid: running.pid, process: running.process)
        }
        recalculateCounters()
        persistQueue()
        pumpQueue()
    }

    /// Cancels all currently running downloads AND any waiting queued items.
    public func cancelAllActive() {
        for task in queue where task.status == .queued || task.status.isActive {
            task.status = .cancelled
            task.statusDetail = "Cancelled"
            task.speedText = nil
            task.etaText = nil
        }
        for (_, running) in runningProcesses {
            ProcessSupervisor.terminateProcessGroup(pid: running.pid, process: running.process)
        }
        runningProcesses.removeAll()
        recalculateCounters()
        persistQueue()
    }

    /// Gracefully transitions active downloads to `.paused`, persists `queue.json`, and terminates all process groups on app quit.
    public func terminateAllOnQuit() {
        for task in queue where task.status.isActive {
            task.status = .paused
            task.statusDetail = "Interrupted — Resume to continue"
            task.speedText = nil
            task.etaText = nil
        }
        recalculateCounters()
        persistQueue()

        for (_, running) in runningProcesses {
            ProcessSupervisor.terminateProcessGroup(pid: running.pid, process: running.process, graceSeconds: 0.5)
        }
        runningProcesses.removeAll()
    }

    public func retry(id: UUID) {
        guard let task = queue.first(where: { $0.id == id }) else { return }
        guard task.status.isTerminal else { return }

        task.status = .queued
        task.progress = 0
        task.statusDetail = "Queued for retry"
        task.errorMessage = nil
        task.speedText = nil
        task.etaText = nil
        task.logBuffer.append("— Retrying download —")

        recalculateCounters()
        persistQueue()
        pumpQueue()
    }

    public func retryAllFailed() {
        var didRequeue = false
        for task in queue where task.status == .failed || task.status == .cancelled {
            task.status = .queued
            task.progress = 0
            task.statusDetail = "Queued for retry"
            task.errorMessage = nil
            task.speedText = nil
            task.etaText = nil
            task.logBuffer.append("— Retrying download —")
            didRequeue = true
        }
        if didRequeue {
            isQueuePaused = false
            recalculateCounters()
            persistQueue()
            pumpQueue()
        }
    }

    public func remove(id: UUID) {
        if let running = runningProcesses.removeValue(forKey: id) {
            ProcessSupervisor.terminateProcessGroup(pid: running.pid, process: running.process)
        }
        videoOnlyFormatTaskIDs.remove(id)
        queue.removeAll { $0.id == id }
        recalculateCounters()
        persistQueue()
        pumpQueue()
    }

    public func clearFinished() {
        let removedIDs = Set(queue.filter { $0.status.isTerminal }.map(\.id))
        videoOnlyFormatTaskIDs.subtract(removedIDs)
        queue.removeAll { $0.status.isTerminal }
        recalculateCounters()
        persistQueue()
    }

    // MARK: - History & Presets

    public func removeHistoryEntry(id: UUID) {
        history.removeAll { $0.id == id }
        store.enqueueSaveHistory(history)
    }

    public func clearHistory() {
        history.removeAll()
        store.enqueueSaveHistory(history)
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
        store.enqueueSaveCustomPresets(customPresets)
    }

    public func deleteCustomPreset(id: UUID) {
        customPresets.removeAll { $0.id == id }
        store.enqueueSaveCustomPresets(customPresets)
    }

    // MARK: - Counters & Persistence

    private func recalculateCounters() {
        var active = 0
        var queued = 0
        var paused = 0
        var completed = 0
        var failed = 0

        for task in queue {
            switch task.status {
            case .preparing, .downloading, .postProcessing:
                active += 1
            case .queued:
                queued += 1
            case .paused:
                paused += 1
            case .completed:
                completed += 1
            case .failed:
                failed += 1
            case .cancelled:
                break
            }
        }

        activeCount = active
        queuedCount = queued
        pausedCount = paused
        completedCount = completed
        failedCount = failed
    }

    private func persistQueue() {
        let state = PersistedQueueState(
            isQueuePaused: isQueuePaused,
            items: queue.map { $0.makeSnapshot() }
        )
        store.enqueueSaveQueue(state)
        onQueueChanged?()
    }

    // MARK: - Execution Pipeline

    private func pumpQueue() {
        guard !isQueuePaused else { return }
        guard !engineManager.isWorking else { return }
        guard activeCount < maxConcurrentDownloads else { return }

        // FIFO: earliest createdAt first, then playlistIndex ascending so #01 runs first while displaying at index 0.
        let queuedTasks = queue
            .filter { $0.status == .queued }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return (lhs.playlistIndex ?? 0) < (rhs.playlistIndex ?? 0)
            }

        for task in queuedTasks {
            guard activeCount < maxConcurrentDownloads else { break }
            startItem(task)
        }
    }

    private func startItem(_ task: DownloadTask) {
        guard !engineManager.isWorking else { return }

        guard let ytdlpPath = engineManager.ytdlpStatus.path else {
            task.status = .failed
            task.statusDetail = "yt-dlp not installed"
            task.errorMessage = "Install yt-dlp via Engine Setup before downloading."
            recalculateCounters()
            persistQueue()
            return
        }

        // Ensure destination folder exists
        let expandedOutDir = (task.configuration.outputDirectoryPath as NSString).expandingTildeInPath
        do {
            try FileManager.default.createDirectory(
                atPath: expandedOutDir,
                withIntermediateDirectories: true
            )
        } catch {
            task.status = .failed
            task.statusDetail = "Output folder unavailable"
            task.errorMessage = error.localizedDescription
            recalculateCounters()
            persistQueue()
            return
        }

        // Pre-flight disk space check (>= 256 MB)
        let outURL = URL(fileURLWithPath: expandedOutDir, isDirectory: true)
        if let values = try? outURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let availableBytes = values.volumeAvailableCapacityForImportantUsage,
           availableBytes < 256 * 1024 * 1024 {
            task.status = .failed
            task.statusDetail = "Insufficient disk space"
            task.errorMessage = "Insufficient disk space (< 256 MB available)."
            recalculateCounters()
            persistQueue()
            return
        }

        let isVideoOnlyCustom = videoOnlyFormatTaskIDs.contains(task.id)
        let args = YTDLPCommandBuilder.buildArguments(
            url: task.url,
            configuration: task.configuration,
            ffmpegPath: engineManager.ffmpegStatus.path,
            jsRuntimeArg: engineManager.ytdlpJSRuntimeArgument,
            customFormatIsVideoOnly: isVideoOnlyCustom
        )

        task.status = .preparing
        task.statusDetail = "Connecting & resolving streams…"
        task.logBuffer.append(
            "$ \(YTDLPCommandBuilder.shellPreview(ytdlpPath: ytdlpPath, url: task.url, configuration: task.configuration, ffmpegPath: engineManager.ffmpegStatus.path, jsRuntimeArg: engineManager.ytdlpJSRuntimeArgument, customFormatIsVideoOnly: isVideoOnlyCustom))"
        )
        recalculateCounters()
        persistQueue()

        let process = Process()
        ProcessSupervisor.configure(
            process,
            executableURL: URL(fileURLWithPath: ytdlpPath),
            arguments: args,
            environment: EngineManager.enrichedEnvironment()
        )

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let taskID = task.id
        let ioQueue = DispatchQueue(label: "com.velora.download.\(taskID.uuidString)")
        let accumulator = ProcessLineAccumulator()
        let coalescer = DownloadOutputCoalescer(ioQueue: ioQueue) { [weak self] batch in
            Task { @MainActor [weak self] in
                self?.handleOutputBatch(batch, for: taskID)
            }
        }

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            ioQueue.sync {
                let lines = accumulator.append(data)
                guard !lines.isEmpty else { return }
                coalescer.process(lines: lines)
            }
        }

        process.terminationHandler = { [weak self] proc in
            let exitCode = proc.terminationStatus
            let reason = proc.terminationReason
            let weakManager = self
            ioQueue.async {
                pipe.fileHandleForReading.readabilityHandler = nil
                let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
                var trailing: [String] = []
                if !remaining.isEmpty {
                    trailing.append(contentsOf: accumulator.append(remaining))
                }
                trailing.append(contentsOf: accumulator.flush())
                let finalBatch = coalescer.takeRemainingAndClose(trailingLines: trailing)

                Task { @MainActor in
                    if !finalBatch.isEmpty {
                        weakManager?.handleOutputBatch(finalBatch, for: taskID)
                    }
                    weakManager?.handleProcessExit(taskID: taskID, status: exitCode, reason: reason)
                }
            }
        }

        do {
            let pid = try ProcessSupervisor.launchInNewProcessGroup(process)
            runningProcesses[taskID] = RunningProcessEntry(process: process, pid: pid)
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            task.status = .failed
            task.statusDetail = "Failed to launch yt-dlp"
            task.errorMessage = error.localizedDescription
            recalculateCounters()
            persistQueue()
            pumpQueue()
        }
    }

    private func handleOutputBatch(_ batch: [(YTDLPOutputEvent, String)], for taskID: UUID) {
        guard let task = queue.first(where: { $0.id == taskID }) else { return }
        guard !task.status.isTerminal && task.status != .paused else { return }

        let previousStatus = task.status
        var shouldPersistSnapshot = false

        for (event, rawLine) in batch {
            guard !task.status.isTerminal && task.status != .paused else { break }

            switch event {
            case let .metadata(title, uploader, extractor):
                task.title = title
                if let uploader { task.uploader = uploader }
                if let extractor { task.extractor = extractor }
                shouldPersistSnapshot = true

            case let .playlistItemProgress(current, total):
                task.playlistIndex = current
                task.playlistTotal = total
                task.status = .downloading
                task.statusDetail = "Item \(current) of \(total) · Preparing…"
                task.logBuffer.append(rawLine)

            case let .progress(fraction, speed, eta, totalSize):
                task.status = .downloading
                task.speedText = speed
                task.etaText = eta
                if let totalSize { task.fileSizeText = totalSize }

                let pctInt = Int((fraction * 100).rounded())
                if task.configuration.playlistBehavior == .downloadEntirePlaylist,
                   let current = task.playlistIndex,
                   let total = task.playlistTotal,
                   total > 1 {
                    let overall = (Double(current - 1) + fraction) / Double(total)
                    task.progress = min(1.0, max(0.0, overall))
                    task.statusDetail = "Item \(current)/\(total) · \(pctInt)%"
                } else {
                    task.progress = fraction
                    task.statusDetail = "Downloading \(pctInt)%"
                }

            case let .postProcessing(stage):
                task.status = .postProcessing
                if task.configuration.playlistBehavior != .downloadEntirePlaylist {
                    task.progress = max(task.progress, 0.99)
                }
                task.speedText = nil
                task.etaText = nil
                if task.configuration.playlistBehavior == .downloadEntirePlaylist,
                   let current = task.playlistIndex,
                   let total = task.playlistTotal,
                   total > 1 {
                    task.statusDetail = "Item \(current)/\(total) · \(stage)"
                } else {
                    task.statusDetail = stage
                }
                task.logBuffer.append(rawLine)

            case let .destination(path):
                task.outputFilePath = path
                task.logBuffer.append(rawLine)

            case let .finalFilePath(path):
                task.outputFilePath = path
                task.completedFileCount += 1
                task.logBuffer.append("Saved: \(path)")
                shouldPersistSnapshot = true

                // For multi-item direct playlist downloads, record each finished video into history immediately.
                if task.configuration.playlistBehavior == .downloadEntirePlaylist {
                    recordHistory(for: task, filePath: path)
                }

            case let .error(message):
                task.errorMessage = message
                task.logBuffer.append(rawLine)

            case let .log(line):
                if !line.isEmpty {
                    task.logBuffer.append(line)
                }
            }
        }

        if task.status != previousStatus {
            recalculateCounters()
            persistQueue()
        } else if shouldPersistSnapshot {
            persistQueue()
        }
    }

    private func recordHistory(for task: DownloadTask, filePath: String?) {
        let fileSizeBytes: Int64? = filePath.flatMap { path in
            (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
        }
        let entry = DownloadHistoryEntry(
            url: task.url,
            title: task.title,
            uploader: task.uploader,
            extractor: task.extractor,
            thumbnailURL: task.thumbnailURL,
            formatSummary: task.configuration.summaryBadge,
            outputFilePath: filePath,
            outputDirectoryPath: task.configuration.outputDirectoryPath,
            fileSizeBytes: fileSizeBytes,
            completedAt: Date()
        )
        history.insert(entry, at: 0)
        if history.count > 500 {
            history.removeLast(history.count - 500)
        }
        store.enqueueSaveHistory(history)
    }

    private func handleProcessExit(taskID: UUID, status: Int32, reason: Process.TerminationReason) {
        runningProcesses.removeValue(forKey: taskID)
        guard let task = queue.first(where: { $0.id == taskID }) else {
            pumpQueue()
            return
        }

        if task.status == .cancelled || task.status == .paused {
            recalculateCounters()
            pumpQueue()
            return
        }

        let isDirectPlaylist = task.configuration.playlistBehavior == .downloadEntirePlaylist
        // With --ignore-errors on playlists, yt-dlp exits 1 if 1 private video failed while 19 succeeded.
        let succeeded = (status == 0 && reason == .exit) || (isDirectPlaylist && task.completedFileCount > 0 && reason == .exit)

        if succeeded {
            task.status = .completed
            task.progress = 1.0
            task.speedText = nil
            task.etaText = nil
            if isDirectPlaylist && task.completedFileCount > 1 {
                task.statusDetail = status == 0
                    ? "Completed (\(task.completedFileCount) files)"
                    : "Completed \(task.completedFileCount) files (some skipped)"
            } else {
                task.statusDetail = "Completed"
            }
            task.completedAt = Date()

            if !isDirectPlaylist {
                recordHistory(for: task, filePath: task.outputFilePath)
            }
        } else {
            task.status = .failed
            task.speedText = nil
            task.etaText = nil
            task.statusDetail = "Download failed (code \(status))"
            if task.errorMessage == nil {
                task.errorMessage = task.logBuffer.lines.last(where: { !$0.isEmpty })
                    ?? "yt-dlp exited with code \(status)."
            }
        }

        recalculateCounters()
        persistQueue()
        onTaskFinished?(task, succeeded)

        // Play completion chime only when this finishes the active burst or single job (avoid spamming 50 chimes).
        if succeeded && playSoundOnComplete && activeCount == 0 && queuedCount == 0 {
            NSSound(named: NSSound.Name("Glass"))?.play()
        }

        pumpQueue()
    }
}
