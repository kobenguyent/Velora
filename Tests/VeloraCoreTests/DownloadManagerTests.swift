import Darwin
import Foundation
import Testing
@testable import VeloraCore

@Suite("Download Manager")
struct DownloadManagerTests {

    @Test("Inserts playlist entries in natural #01 -> #05 display order and executes FIFO")
    @MainActor
    func playlistOrderingAndFIFOExecution() async throws {
        let workspace = try makeWorkspace("playlist-fifo")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let executionLog = workspace.appendingPathComponent("exec-order.txt")
        let mockYTDLP = try makeMockExecutable(
            in: workspace,
            script: """
            #!/bin/sh
            last=""
            for arg in "$@"; do last="$arg"; done
            printf '%s\n' "$last" >> '\(executionLog.path)'
            printf 'VELORA_FILEPATH_JSON:{"filepath":"\(workspace.path)/done.mp4"}\n'
            """
        )

        let engine = try await makeEngineManager(ytdlpPath: mockYTDLP.path, workspace: workspace)
        let store = VeloraStore(baseDirectory: workspace.appendingPathComponent("store"))
        let manager = DownloadManager(engineManager: engine, store: store)
        manager.maxConcurrentDownloads = 1
        manager.playSoundOnComplete = false
        manager.pauseQueue()

        let entries = (1...5).map { idx in
            PlaylistEntry(
                index: idx,
                id: "vid-\(idx)",
                title: "Episode \(idx)",
                url: "https://example.com/watch?v=vid-\(idx)"
            )
        }

        var config = DownloadConfiguration()
        config.outputDirectoryPath = workspace.appendingPathComponent("out").path

        let created = manager.enqueuePlaylistEntries(
            entries,
            playlistTitle: "My Series",
            baseConfiguration: config
        )

        #expect(created.count == 5)
        #expect(manager.queue.prefix(5).compactMap(\.playlistIndex) == [1, 2, 3, 4, 5])
        #expect(manager.queuedCount == 5)

        manager.resumeQueue()

        try await waitUntil(timeoutSeconds: 5) {
            manager.completedCount == 5 && manager.activeCount == 0
        }

        let recorded = try String(contentsOf: executionLog, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        #expect(recorded == [
            "https://example.com/watch?v=vid-1",
            "https://example.com/watch?v=vid-2",
            "https://example.com/watch?v=vid-3",
            "https://example.com/watch?v=vid-4",
            "https://example.com/watch?v=vid-5"
        ])
    }

    @Test("Rejects non-http(s) URLs in enqueue and tracks pending/active duplicates")
    @MainActor
    func urlValidationAndPendingDetection() async throws {
        let workspace = try makeWorkspace("url-validation")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let engine = EngineManager(urlSession: .shared, binDirectory: workspace.appendingPathComponent("bin"))
        let store = VeloraStore(baseDirectory: workspace.appendingPathComponent("store"))
        let manager = DownloadManager(engineManager: engine, store: store)
        manager.pauseQueue()

        let config = DownloadConfiguration()
        #expect(manager.enqueue(url: "file:///etc/passwd", configuration: config) == nil)
        #expect(manager.enqueue(url: "javascript:alert(1)", configuration: config) == nil)
        #expect(manager.enqueue(url: "ftp://example.com/file.mp4", configuration: config) == nil)
        #expect(manager.queue.isEmpty)

        let valid = manager.enqueue(url: "  <https://example.com/video?id=42>  ", configuration: config)
        #expect(valid != nil)
        #expect(manager.hasPendingOrActiveDownload(for: "https://example.com/video?id=42"))

        if let id = valid?.id {
            manager.cancel(id: id)
        }
        #expect(!manager.hasPendingOrActiveDownload(for: "https://example.com/video?id=42"))
    }

    @Test("Drains trailing pipe bytes without newline before exit and records history")
    @MainActor
    func drainsTrailingPipeBytesAndRecordsHistory() async throws {
        let workspace = try makeWorkspace("pipe-drain")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let outputFile = workspace.appendingPathComponent("Final | Video.mp4")
        try Data("video-bytes".utf8).write(to: outputFile)

        let mockYTDLP = try makeMockExecutable(
            in: workspace,
            script: """
            #!/bin/sh
            printf 'VELORA_META_JSON:{"title":"Demo | Title","uploader":"Velora","extractor_key":"Youtube"}\n'
            printf 'VELORA_PROGRESS_JSON:{"status":"downloading","downloaded_bytes":50,"total_bytes":100,"speed":1000,"eta":1}\n'
            # Emit final JSON without trailing newline right before exit
            printf 'VELORA_FILEPATH_JSON:{"filepath":"\(outputFile.path)"}'
            """
        )

        let engine = try await makeEngineManager(ytdlpPath: mockYTDLP.path, workspace: workspace)
        let store = VeloraStore(baseDirectory: workspace.appendingPathComponent("store"))
        let manager = DownloadManager(engineManager: engine, store: store)
        manager.playSoundOnComplete = false

        var finishedResult: (UUID, Bool)?
        manager.onTaskFinished = { task, succeeded in
            finishedResult = (task.id, succeeded)
        }

        var config = DownloadConfiguration()
        config.outputDirectoryPath = workspace.path
        let task = try #require(manager.enqueue(url: "https://example.com/demo", configuration: config))

        try await waitUntil(timeoutSeconds: 5) {
            task.status == .completed
        }

        #expect(task.title == "Demo | Title")
        #expect(task.outputFilePath == outputFile.path)
        #expect(manager.completedCount == 1)
        #expect(manager.activeCount == 0)
        #expect(manager.history.first?.outputFilePath == outputFile.path)
        #expect(finishedResult?.0 == task.id)
        #expect(finishedResult?.1 == true)
    }

    @Test("Supports per-item pause/resume with --continue and terminateAllOnQuit")
    @MainActor
    func pauseResumeAndTerminateOnQuit() async throws {
        let workspace = try makeWorkspace("pause-resume")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let argsLog = workspace.appendingPathComponent("args.log")
        let pidFile = workspace.appendingPathComponent("child.pid")
        let counterFile = workspace.appendingPathComponent("run-count.txt")
        let outputFile = workspace.appendingPathComponent("resumed.mp4")
        try Data("ok".utf8).write(to: outputFile)

        // First run sleeps after emitting progress; second run completes immediately.
        let mockYTDLP = try makeMockExecutable(
            in: workspace,
            script: """
            #!/bin/sh
            printf '%s\n' "$*" >> '\(argsLog.path)'
            if [ ! -f '\(counterFile.path)' ]; then
              touch '\(counterFile.path)'
              echo $$ > '\(pidFile.path)'
              printf 'VELORA_PROGRESS_JSON:{"status":"downloading","downloaded_bytes":25,"total_bytes":100,"speed":1000,"eta":5}\n'
              sleep 30
              exit 0
            fi
            printf 'VELORA_FILEPATH_JSON:{"filepath":"\(outputFile.path)"}\n'
            """
        )

        let engine = try await makeEngineManager(ytdlpPath: mockYTDLP.path, workspace: workspace)
        let store = VeloraStore(baseDirectory: workspace.appendingPathComponent("store"))
        let manager = DownloadManager(engineManager: engine, store: store)
        manager.playSoundOnComplete = false

        var config = DownloadConfiguration()
        config.outputDirectoryPath = workspace.path
        config.resumePartialDownloads = false
        let task = try #require(manager.enqueue(url: "https://example.com/long", configuration: config))

        try await waitUntil(timeoutSeconds: 5) {
            task.status == .downloading && FileManager.default.fileExists(atPath: pidFile.path)
        }

        let firstPID = pid_t(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        manager.pause(id: task.id)
        #expect(task.status == .paused)
        #expect(manager.pausedCount == 1)
        #expect(manager.activeCount == 0)

        // Verify process terminates cleanly
        if firstPID > 0 {
            try await waitUntil(timeoutSeconds: 3) {
                Darwin.kill(firstPID, 0) != 0
            }
        }

        manager.resume(id: task.id)
        #expect(task.configuration.resumePartialDownloads == true)

        try await waitUntil(timeoutSeconds: 5) {
            task.status == .completed
        }

        let allLoggedArgs = try String(contentsOf: argsLog, encoding: .utf8)
        #expect(allLoggedArgs.contains("--continue"))

        // Verify terminateAllOnQuit stops running processes cleanly
        try? FileManager.default.removeItem(at: counterFile)
        try? FileManager.default.removeItem(at: pidFile)
        let task2 = try #require(manager.enqueue(url: "https://example.com/quit-test", configuration: config))

        try await waitUntil(timeoutSeconds: 5) {
            task2.status == .downloading && FileManager.default.fileExists(atPath: pidFile.path)
        }
        let secondPID = pid_t(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        manager.terminateAllOnQuit()
        #expect(manager.activeCount == 0)
        #expect(task2.status == .paused)
        if secondPID > 0 {
            try await waitUntil(timeoutSeconds: 3) {
                Darwin.kill(secondPID, 0) != 0
            }
        }
    }

    @Test("Cancelled or paused tasks ignore late output lines and never resurrect")
    @MainActor
    func lateLinesDoNotResurrectCancelledOrPausedTasks() async throws {
        let workspace = try makeWorkspace("race-guard")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let mockYTDLP = try makeMockExecutable(
            in: workspace,
            script: """
            #!/bin/sh
            trap 'printf "VELORA_PROGRESS_JSON:{\\"status\\":\\"downloading\\",\\"downloaded_bytes\\":90,\\"total_bytes\\":100}\\n"; exit 0' TERM
            printf 'VELORA_PROGRESS_JSON:{"status":"downloading","downloaded_bytes":10,"total_bytes":100}\n'
            sleep 30
            """
        )

        let engine = try await makeEngineManager(ytdlpPath: mockYTDLP.path, workspace: workspace)
        let store = VeloraStore(baseDirectory: workspace.appendingPathComponent("store"))
        let manager = DownloadManager(engineManager: engine, store: store)
        manager.playSoundOnComplete = false

        var config = DownloadConfiguration()
        config.outputDirectoryPath = workspace.path
        let task = try #require(manager.enqueue(url: "https://example.com/trap", configuration: config))

        try await waitUntil(timeoutSeconds: 5) {
            task.status == .downloading
        }

        manager.cancel(id: task.id)
        #expect(task.status == .cancelled)

        // Allow trapped SIGTERM output + exit handler to settle
        try await Task.sleep(for: .milliseconds(250))
        #expect(task.status == .cancelled)
        #expect(manager.activeCount == 0)
    }

    @Test("Persists queue.json, recovers interrupted tasks as paused, and restores queued tasks on launch")
    @MainActor
    func persistsAndRestoresQueueAcrossRestart() async throws {
        let workspace = try makeWorkspace("queue-persist")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let storeDir = workspace.appendingPathComponent("store")
        let store1 = VeloraStore(baseDirectory: storeDir)
        let outputFile = workspace.appendingPathComponent("restored.mp4")
        try Data("ok".utf8).write(to: outputFile)

        let mockYTDLP = try makeMockExecutable(
            in: workspace,
            script: """
            #!/bin/sh
            printf 'VELORA_FILEPATH_JSON:{"filepath":"\(outputFile.path)"}\n'
            """
        )

        let engine1 = EngineManager(urlSession: .shared, binDirectory: workspace.appendingPathComponent("empty-bin"))
        let manager1 = DownloadManager(engineManager: engine1, store: store1)
        manager1.pauseQueue()

        let config = DownloadConfiguration()
        let pausedItem = try #require(manager1.enqueue(url: "https://example.com/paused", configuration: config))
        manager1.pause(id: pausedItem.id)
        let queuedItem = try #require(manager1.enqueue(url: "https://example.com/queued", configuration: config))
        manager1.resumeQueue() // Starts queuedItem? No, engine has no yt-dlp yet -> keep paused before adding!
        // Re-seed clean state in store directly to simulate active + queued + paused snapshot across crash
        let activeSnapshot = DownloadTaskSnapshot(
            url: "https://example.com/interrupted",
            configuration: config,
            status: .downloading,
            progress: 0.4
        )
        let queuedSnapshot = DownloadTaskSnapshot(
            url: "https://example.com/pending",
            configuration: config,
            status: .queued
        )
        _ = queuedItem
        await store1.saveQueue(PersistedQueueState(isQueuePaused: false, items: [activeSnapshot, queuedSnapshot]))

        let engine2 = try await makeEngineManager(ytdlpPath: mockYTDLP.path, workspace: workspace)
        let store2 = VeloraStore(baseDirectory: storeDir)
        let manager2 = DownloadManager(engineManager: engine2, store: store2)
        manager2.playSoundOnComplete = false

        #expect(manager2.queue.count == 2)
        #expect(manager2.queue[0].status == .paused)
        #expect(manager2.queue[0].statusDetail == "Interrupted — Resume to continue")
        #expect(manager2.queue[1].status == .queued)
        #expect(manager2.pausedCount == 1)
        #expect(manager2.queuedCount == 1)

        manager2.restorePendingQueueAfterEngineReady()
        try await waitUntil(timeoutSeconds: 5) {
            manager2.completedCount == 1
        }
        #expect(manager2.queue[0].status == .paused)
        #expect(manager2.queue[1].status == .completed)
    }

    @Test("Passes customFormatIsVideoOnly to YTDLPCommandBuilder and updates counters on remove/clearFinished")
    @MainActor
    func customFormatVideoOnlyAndCounters() async throws {
        let workspace = try makeWorkspace("video-only-counters")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let argsLog = workspace.appendingPathComponent("args.log")
        let outputFile = workspace.appendingPathComponent("merged.mp4")
        try Data("ok".utf8).write(to: outputFile)

        let mockYTDLP = try makeMockExecutable(
            in: workspace,
            script: """
            #!/bin/sh
            printf '%s\n' "$*" >> '\(argsLog.path)'
            printf 'VELORA_FILEPATH_JSON:{"filepath":"\(outputFile.path)"}\n'
            """
        )

        let engine = try await makeEngineManager(ytdlpPath: mockYTDLP.path, workspace: workspace)
        let store = VeloraStore(baseDirectory: workspace.appendingPathComponent("store"))
        let manager = DownloadManager(engineManager: engine, store: store)
        manager.playSoundOnComplete = false

        var config = DownloadConfiguration()
        config.mode = .videoAndAudio
        config.customFormatID = "313"
        config.outputDirectoryPath = workspace.path

        let task = try #require(
            manager.enqueue(
                url: "https://example.com/custom-vo",
                configuration: config,
                customFormatIsVideoOnly: true
            )
        )
        try await waitUntil(timeoutSeconds: 5) {
            task.status == .completed
        }

        let logged = try String(contentsOf: argsLog, encoding: .utf8)
        #expect(logged.contains("-f 313+bestaudio/best"))
        #expect(manager.completedCount == 1)

        manager.clearFinished()
        #expect(manager.queue.isEmpty)
        #expect(manager.completedCount == 0)
    }

    // MARK: - Helpers

    private func makeWorkspace(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("velora-dm-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeMockExecutable(in workspace: URL, script: String) throws -> URL {
        let binDir = workspace.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let url = binDir.appendingPathComponent("yt-dlp")
        let body = script.replacingOccurrences(of: "#!/bin/sh\n", with: "")
        let fullScript = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "2026.01.01"
          exit 0
        fi
        \(body)
        """
        try fullScript.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @MainActor
    private func makeEngineManager(ytdlpPath: String, workspace: URL) async throws -> EngineManager {
        _ = ytdlpPath
        let manager = EngineManager(urlSession: .shared, binDirectory: workspace.appendingPathComponent("bin"))
        await manager.refresh()
        return manager
    }

    @MainActor
    private func waitUntil(
        timeoutSeconds: Double,
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .milliseconds(Int(timeoutSeconds * 1000))
        while !condition() {
            if ContinuousClock.now >= deadline {
                Issue.record("Timed out waiting for DownloadManager condition")
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}
