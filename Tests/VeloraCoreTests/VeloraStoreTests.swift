import Foundation
import Testing
@testable import VeloraCore

@Suite("VeloraStore & Persistence Contracts")
struct VeloraStoreTests {

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VeloraStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Round-trips v2 envelopes for history, presets, configuration, and queue")
    func v2EnvelopeRoundTrip() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = VeloraStore(baseDirectory: dir)

        var config = DownloadConfiguration()
        config.cookieFilePath = "/tmp/cookies.txt"
        config.autoRetryCount = 5
        config.resumePartialDownloads = false
        config.browserCookies = .arc

        let fixedDate = Date(timeIntervalSince1970: 1_764_250_000)

        let historyEntry = DownloadHistoryEntry(
            url: "https://example.com/video",
            title: "Sample Video",
            uploader: "Creator",
            extractor: "youtube",
            thumbnailURL: "https://example.com/thumb.jpg",
            formatSummary: "1080p · MP4",
            outputFilePath: "/tmp/Sample Video.mp4",
            outputDirectoryPath: "/tmp",
            fileSizeBytes: 12_345_678,
            completedAt: fixedDate
        )

        let preset = DownloadPreset(
            name: "Custom Test",
            subtitle: "Test preset",
            symbolName: "star",
            configuration: config
        )

        var snapshot = DownloadTaskSnapshot(
            url: "https://example.com/queued",
            title: "Queued Video",
            configuration: config,
            status: .queued,
            progress: 0.25,
            statusDetail: "Queued",
            createdAt: fixedDate
        )
        snapshot.retryAttempt = 2

        let queueState = PersistedQueueState(isQueuePaused: true, items: [snapshot])

        await store.saveHistory([historyEntry])
        await store.saveCustomPresets([preset])
        await store.saveLastConfiguration(config)
        await store.saveQueue(queueState)

        // Verify raw JSON on disk uses VeloraStoreEnvelope with schemaVersion == 2
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let historyData = try Data(contentsOf: dir.appendingPathComponent("history.json"))
        let historyEnvelope = try decoder.decode(VeloraStoreEnvelope<[DownloadHistoryEntry]>.self, from: historyData)
        #expect(historyEnvelope.schemaVersion == VeloraStoreEnvelope<[DownloadHistoryEntry]>.currentSchemaVersion)
        #expect(historyEnvelope.schemaVersion == 2)
        #expect(historyEnvelope.payload == [historyEntry])

        let loadedHistory = store.loadHistory()
        let loadedPresets = store.loadCustomPresets()
        let loadedConfig = store.loadLastConfiguration()
        let loadedQueue = store.loadQueue()

        #expect(loadedHistory == [historyEntry])
        #expect(loadedPresets == [preset])
        #expect(loadedConfig == config)
        #expect(loadedQueue == queueState)
    }

    @Test("Migrates legacy v1 bare arrays and objects without envelopes")
    func legacyV1Migration() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let legacyHistoryJSON = """
        [
          {
            "id": "11111111-1111-1111-1111-111111111111",
            "url": "https://youtu.be/legacy",
            "title": "Legacy Item",
            "formatSummary": "1080p · MP4",
            "outputDirectoryPath": "/tmp",
            "completedAt": "2025-01-01T00:00:00Z"
          }
        ]
        """
        try legacyHistoryJSON.data(using: .utf8)!.write(to: dir.appendingPathComponent("history.json"))

        let legacyPresetsJSON = """
        [
          {
            "id": "22222222-2222-2222-2222-222222222222",
            "name": "Legacy Preset",
            "subtitle": "v1",
            "symbolName": "film",
            "configuration": {
              "mode": "audio_only",
              "audioFormat": "mp3"
            },
            "isBuiltIn": false
          }
        ]
        """
        try legacyPresetsJSON.data(using: .utf8)!.write(to: dir.appendingPathComponent("custom-presets.json"))

        let legacyConfigJSON = """
        {
          "mode": "video_only",
          "videoQuality": "720"
        }
        """
        try legacyConfigJSON.data(using: .utf8)!.write(to: dir.appendingPathComponent("last-configuration.json"))

        let store = VeloraStore(baseDirectory: dir)

        let history = store.loadHistory()
        #expect(history.count == 1)
        #expect(history.first?.title == "Legacy Item")

        let presets = store.loadCustomPresets()
        #expect(presets.count == 1)
        #expect(presets.first?.configuration.mode == .audioOnly)
        #expect(presets.first?.configuration.autoRetryCount == 3)
        #expect(presets.first?.configuration.resumePartialDownloads == true)

        let config = store.loadLastConfiguration()
        #expect(config.mode == .videoOnly)
        #expect(config.videoQuality == .p720)
        #expect(config.cookieFilePath == "")
        #expect(config.autoRetryCount == 3)
        #expect(config.resumePartialDownloads == true)
    }

    @Test("Preserves corrupt non-empty JSON files as .corrupt-*.bak without losing original bytes")
    func corruptJSONBackupPreservation() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let corruptBytes = Data("{ not valid json at all :::".utf8)
        let historyURL = dir.appendingPathComponent("history.json")
        try corruptBytes.write(to: historyURL)

        // Also test a corrupt v2 envelope on last-configuration.json
        let corruptConfigEnvelope = Data(#"{"schemaVersion":2,"updatedAt":"2026-01-01T00:00:00Z","payload":"invalid"}"#.utf8)
        let configURL = dir.appendingPathComponent("last-configuration.json")
        try corruptConfigEnvelope.write(to: configURL)

        let store = VeloraStore(baseDirectory: dir)

        let history = store.loadHistory()
        #expect(history.isEmpty)

        let config = store.loadLastConfiguration()
        #expect(config == DownloadConfiguration())

        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let historyBackups = contents.filter { $0.hasPrefix("history.json.corrupt-") && $0.hasSuffix(".bak") }
        let configBackups = contents.filter { $0.hasPrefix("last-configuration.json.corrupt-") && $0.hasSuffix(".bak") }

        #expect(historyBackups.count == 1)
        #expect(configBackups.count == 1)

        if let backupName = historyBackups.first {
            let backedUpBytes = try Data(contentsOf: dir.appendingPathComponent(backupName))
            #expect(backedUpBytes == corruptBytes)
        }
        if let configBackupName = configBackups.first {
            let backedUpConfig = try Data(contentsOf: dir.appendingPathComponent(configBackupName))
            #expect(backedUpConfig == corruptConfigEnvelope)
        }
    }

    @Test("Recovers interrupted active queue items to .paused on loadQueue()")
    func queueInterruptedTaskRecovery() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = VeloraStore(baseDirectory: dir)
        let config = DownloadConfiguration()

        let preparing = DownloadTaskSnapshot(url: "https://example.com/1", configuration: config, status: .preparing, progress: 0.05, statusDetail: "Starting")
        let downloading = DownloadTaskSnapshot(url: "https://example.com/2", configuration: config, status: .downloading, progress: 0.42, statusDetail: "Downloading 42%")
        let postProcessing = DownloadTaskSnapshot(url: "https://example.com/3", configuration: config, status: .postProcessing, progress: 0.99, statusDetail: "Muxing")
        let queued = DownloadTaskSnapshot(url: "https://example.com/4", configuration: config, status: .queued, progress: 0.0, statusDetail: "Waiting in queue")
        let completed = DownloadTaskSnapshot(url: "https://example.com/5", configuration: config, status: .completed, progress: 1.0, statusDetail: "Completed")

        await store.saveQueue(PersistedQueueState(
            isQueuePaused: false,
            items: [preparing, downloading, postProcessing, queued, completed]
        ))

        let recovered = store.loadQueue()
        #expect(recovered.items.count == 5)

        for idx in 0...2 {
            #expect(recovered.items[idx].status == .paused)
            #expect(recovered.items[idx].statusDetail == "Interrupted — Resume to continue")
        }
        #expect(recovered.items[3].status == .queued)
        #expect(recovered.items[4].status == .completed)
    }

    @Test("Supports non-blocking enqueueSave methods and async flush()")
    func enqueueAndFlush() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = VeloraStore(baseDirectory: dir)
        var config1 = DownloadConfiguration()
        config1.rateLimit = "2M"
        var config2 = DownloadConfiguration()
        config2.rateLimit = "8M"

        store.enqueueSaveLastConfiguration(config1)
        store.enqueueSaveLastConfiguration(config2)
        await store.flush()

        let loaded = store.loadLastConfiguration()
        #expect(loaded.rateLimit == "8M")
    }

    @Test("Validates DownloadConfiguration power options, Arc cookie path, and DownloadTask snapshot/log buffer")
    @MainActor
    func modelsAndLogBuffer() {
        #expect(BrowserCookiesSource.arc.ytdlpIdentifier == "chrome:~/Library/Application Support/Arc/User Data")

        var config = DownloadConfiguration()
        #expect(config.activeModifierSummaries.isEmpty)

        config.subtitleMode = .preferredLanguages
        config.sponsorBlock = .removeSponsors
        config.clipEnabled = true
        config.playlistBehavior = .downloadEntirePlaylist
        config.browserCookies = .arc
        config.cookieFilePath = "/tmp/cookies.txt"
        config.proxyURL = "socks5://127.0.0.1:1080"
        config.rateLimit = "5M"
        config.extraArguments = "--geo-bypass"
        config.customFormatID = "313+251"

        let summaries = config.activeModifierSummaries
        #expect(summaries.contains("Subs"))
        #expect(summaries.contains("SponsorBlock"))
        #expect(summaries.contains("Clip"))
        #expect(summaries.contains("Playlist"))
        #expect(summaries.contains("Arc Cookies"))
        #expect(summaries.contains("cookies.txt"))
        #expect(summaries.contains("Proxy"))
        #expect(summaries.contains("Speed Cap"))
        #expect(summaries.contains("Extra Args"))
        #expect(summaries.contains("Stream #313+251"))

        #expect(DownloadStatus.paused.displayName == "Paused")
        #expect(DownloadStatus.paused.isResumable == true)
        #expect(DownloadStatus.failed.isResumable == true)
        #expect(DownloadStatus.cancelled.isResumable == true)
        #expect(DownloadStatus.downloading.isResumable == false)
        #expect(DownloadStatus.paused.isTerminal == false)
        #expect(DownloadStatus.paused.isActive == false)

        let task = DownloadTask(url: "https://example.com/watch?v=1", configuration: config)
        for i in 1...450 {
            task.logBuffer.append("Line \(i)")
        }
        #expect(task.logBuffer.lines.count == 400)
        #expect(task.logBuffer.lines.first == "Line 51")
        #expect(task.logBuffer.lines.last == "Line 450")

        task.status = .paused
        task.retryAttempt = 2
        let snapshot = task.makeSnapshot()
        let restored = DownloadTask(snapshot: snapshot)
        #expect(restored.id == task.id)
        #expect(restored.status == .paused)
        #expect(restored.retryAttempt == 2)

        task.logBuffer.clear()
        #expect(task.logBuffer.lines.isEmpty)
        #expect(task.logBuffer.joinedText == "")
    }
}
