import Foundation

/// Persists Velora history, custom presets, and default configuration in Application Support.
public final class VeloraStore: Sendable {
    private let baseDirectory: URL

    public init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.baseDirectory = appSupport.appendingPathComponent("Velora", isDirectory: true)
        }
    }

    private var historyURL: URL { baseDirectory.appendingPathComponent("history.json") }
    private var customPresetsURL: URL { baseDirectory.appendingPathComponent("custom-presets.json") }
    private var configurationURL: URL { baseDirectory.appendingPathComponent("last-configuration.json") }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    public func loadHistory() -> [DownloadHistoryEntry] {
        load([DownloadHistoryEntry].self, from: historyURL) ?? []
    }

    public func saveHistory(_ entries: [DownloadHistoryEntry]) {
        save(entries, to: historyURL)
    }

    public func loadCustomPresets() -> [DownloadPreset] {
        load([DownloadPreset].self, from: customPresetsURL) ?? []
    }

    public func saveCustomPresets(_ presets: [DownloadPreset]) {
        save(presets, to: customPresetsURL)
    }

    public func loadLastConfiguration() -> DownloadConfiguration {
        load(DownloadConfiguration.self, from: configurationURL) ?? DownloadConfiguration()
    }

    public func saveLastConfiguration(_ configuration: DownloadConfiguration) {
        save(configuration, to: configurationURL)
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        ensureDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
