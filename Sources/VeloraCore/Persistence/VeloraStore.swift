import Foundation
import OSLog

/// Versioned persistence envelope supporting schema migration and corruption preservation.
public struct VeloraStoreEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public static var currentSchemaVersion: Int { 2 }

    public let schemaVersion: Int
    public let updatedAt: Date
    public let payload: Payload

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        updatedAt: Date = Date(),
        payload: Payload
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.payload = payload
    }
}

/// Serializable queue snapshot persisted to `queue.json`.
public struct PersistedQueueState: Codable, Sendable, Equatable {
    public var isQueuePaused: Bool
    public var items: [DownloadTaskSnapshot]

    public init(isQueuePaused: Bool = false, items: [DownloadTaskSnapshot] = []) {
        self.isQueuePaused = isQueuePaused
        self.items = items
    }
}

/// Serializes off-main-thread atomic JSON persistence and corrupt-file backups.
actor VeloraPersistenceActor {
    private static let logger = Logger(subsystem: "com.velora.core", category: "VeloraStore")

    private let baseDirectory: URL

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    func saveEnvelope<T: Codable & Sendable>(_ payload: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let envelope = VeloraStoreEnvelope(payload: payload)
            let data = try encoder.encode(envelope)
            try data.write(to: url, options: .atomic)
        } catch {
            Self.logger.error("Failed to persist \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadEnvelopeOrLegacy<T: Codable & Sendable>(_ type: T.Type, from url: URL) -> T? {
        Self.loadEnvelopeOrLegacySync(type, from: url)
    }

    static func loadEnvelopeOrLegacySync<T: Codable & Sendable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let envelope = try? decoder.decode(VeloraStoreEnvelope<T>.self, from: data) {
            return envelope.payload
        }

        // Prevent corrupt v2 envelopes from falling back to a default-initialized struct (e.g., DownloadConfiguration).
        if !containsEnvelopeWrapperKeys(in: data),
           let legacy = try? decoder.decode(type, from: data) {
            return legacy
        }

        preserveCorruptFile(at: url, data: data)
        return nil
    }

    private static func containsEnvelopeWrapperKeys(in data: Data) -> Bool {
        guard let rawObject = try? JSONSerialization.jsonObject(with: data),
              let dict = rawObject as? [String: Any] else {
            return false
        }
        return dict["schemaVersion"] != nil && dict["payload"] != nil
    }

    private static func preserveCorruptFile(at url: URL, data: Data) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dir = url.deletingLastPathComponent()
        let baseName = url.lastPathComponent

        var backupURL = dir.appendingPathComponent("\(baseName).corrupt-\(timestamp).bak")
        if FileManager.default.fileExists(atPath: backupURL.path) {
            backupURL = dir.appendingPathComponent("\(baseName).corrupt-\(timestamp)-\(UUID().uuidString.prefix(8)).bak")
        }

        do {
            try data.write(to: backupURL, options: .atomic)
            logger.warning("Backed up corrupt store file \(baseName, privacy: .public) to \(backupURL.lastPathComponent, privacy: .public)")
        } catch {
            logger.error("Failed to write corrupt backup for \(baseName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Persists Velora history, custom presets, queue, and default configuration in Application Support.
public final class VeloraStore: Sendable {
    private enum WriteOperation: Sendable {
        case saveHistory([DownloadHistoryEntry], CheckedContinuation<Void, Never>?)
        case saveCustomPresets([DownloadPreset], CheckedContinuation<Void, Never>?)
        case saveLastConfiguration(DownloadConfiguration, CheckedContinuation<Void, Never>?)
        case saveQueue(PersistedQueueState, CheckedContinuation<Void, Never>?)
        case flush(CheckedContinuation<Void, Never>)
    }

    private let baseDirectory: URL
    private let persistenceActor: VeloraPersistenceActor
    private let writeContinuation: AsyncStream<WriteOperation>.Continuation

    public init(baseDirectory: URL? = nil) {
        let resolvedBaseDirectory: URL
        if let baseDirectory {
            resolvedBaseDirectory = baseDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            resolvedBaseDirectory = appSupport.appendingPathComponent("Velora", isDirectory: true)
        }
        self.baseDirectory = resolvedBaseDirectory

        let actor = VeloraPersistenceActor(baseDirectory: resolvedBaseDirectory)
        self.persistenceActor = actor

        let (stream, continuation) = AsyncStream<WriteOperation>.makeStream()
        self.writeContinuation = continuation

        let historyURL = resolvedBaseDirectory.appendingPathComponent("history.json")
        let customPresetsURL = resolvedBaseDirectory.appendingPathComponent("custom-presets.json")
        let configurationURL = resolvedBaseDirectory.appendingPathComponent("last-configuration.json")
        let queueURL = resolvedBaseDirectory.appendingPathComponent("queue.json")

        Task.detached(priority: .utility) {
            for await operation in stream {
                switch operation {
                case .saveHistory(let entries, let done):
                    await actor.saveEnvelope(entries, to: historyURL)
                    done?.resume()
                case .saveCustomPresets(let presets, let done):
                    await actor.saveEnvelope(presets, to: customPresetsURL)
                    done?.resume()
                case .saveLastConfiguration(let configuration, let done):
                    await actor.saveEnvelope(configuration, to: configurationURL)
                    done?.resume()
                case .saveQueue(let state, let done):
                    await actor.saveEnvelope(state, to: queueURL)
                    done?.resume()
                case .flush(let done):
                    done.resume()
                }
            }
        }
    }

    deinit {
        writeContinuation.finish()
    }

    private var historyURL: URL { baseDirectory.appendingPathComponent("history.json") }
    private var customPresetsURL: URL { baseDirectory.appendingPathComponent("custom-presets.json") }
    private var configurationURL: URL { baseDirectory.appendingPathComponent("last-configuration.json") }
    private var queueURL: URL { baseDirectory.appendingPathComponent("queue.json") }

    // MARK: - Synchronous Bootstrap Loads

    public func loadHistory() -> [DownloadHistoryEntry] {
        VeloraPersistenceActor.loadEnvelopeOrLegacySync([DownloadHistoryEntry].self, from: historyURL) ?? []
    }

    public func loadCustomPresets() -> [DownloadPreset] {
        VeloraPersistenceActor.loadEnvelopeOrLegacySync([DownloadPreset].self, from: customPresetsURL) ?? []
    }

    public func loadLastConfiguration() -> DownloadConfiguration {
        VeloraPersistenceActor.loadEnvelopeOrLegacySync(DownloadConfiguration.self, from: configurationURL) ?? DownloadConfiguration()
    }

    public func loadQueue() -> PersistedQueueState {
        guard var state = VeloraPersistenceActor.loadEnvelopeOrLegacySync(PersistedQueueState.self, from: queueURL) else {
            return PersistedQueueState()
        }
        for index in state.items.indices {
            if state.items[index].status.isActive {
                state.items[index].status = .paused
                state.items[index].statusDetail = "Interrupted — Resume to continue"
                state.items[index].speedText = nil
                state.items[index].etaText = nil
            }
        }
        return state
    }

    // MARK: - Async Persistence

    public func saveHistory(_ entries: [DownloadHistoryEntry]) async {
        await withCheckedContinuation { continuation in
            writeContinuation.yield(.saveHistory(entries, continuation))
        }
    }

    public func saveCustomPresets(_ presets: [DownloadPreset]) async {
        await withCheckedContinuation { continuation in
            writeContinuation.yield(.saveCustomPresets(presets, continuation))
        }
    }

    public func saveLastConfiguration(_ configuration: DownloadConfiguration) async {
        await withCheckedContinuation { continuation in
            writeContinuation.yield(.saveLastConfiguration(configuration, continuation))
        }
    }

    public func saveQueue(_ state: PersistedQueueState) async {
        await withCheckedContinuation { continuation in
            writeContinuation.yield(.saveQueue(state, continuation))
        }
    }

    // MARK: - Non-Blocking Fire-and-Forget Enqueue

    public func enqueueSaveHistory(_ entries: [DownloadHistoryEntry]) {
        writeContinuation.yield(.saveHistory(entries, nil))
    }

    public func enqueueSaveCustomPresets(_ presets: [DownloadPreset]) {
        writeContinuation.yield(.saveCustomPresets(presets, nil))
    }

    public func enqueueSaveLastConfiguration(_ configuration: DownloadConfiguration) {
        writeContinuation.yield(.saveLastConfiguration(configuration, nil))
    }

    public func enqueueSaveQueue(_ state: PersistedQueueState) {
        writeContinuation.yield(.saveQueue(state, nil))
    }

    public func flush() async {
        await withCheckedContinuation { continuation in
            writeContinuation.yield(.flush(continuation))
        }
    }

    // MARK: - Synchronous Compatibility Forwarders (Off-Main-Thread)

    public func saveHistory(_ entries: [DownloadHistoryEntry]) {
        enqueueSaveHistory(entries)
    }

    public func saveCustomPresets(_ presets: [DownloadPreset]) {
        enqueueSaveCustomPresets(presets)
    }

    public func saveLastConfiguration(_ configuration: DownloadConfiguration) {
        enqueueSaveLastConfiguration(configuration)
    }
}
