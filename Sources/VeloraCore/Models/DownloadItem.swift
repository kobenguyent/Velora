import Foundation
import Observation

public enum DownloadStatus: String, Codable, Sendable, Equatable {
    case queued
    case paused
    case preparing
    case downloading
    case postProcessing
    case completed
    case failed
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: true
        default: false
        }
    }

    public var isActive: Bool {
        switch self {
        case .preparing, .downloading, .postProcessing: true
        default: false
        }
    }

    public var isResumable: Bool {
        switch self {
        case .paused, .failed, .cancelled: true
        default: false
        }
    }

    public var displayName: String {
        switch self {
        case .queued: "Queued"
        case .paused: "Paused"
        case .preparing: "Preparing"
        case .downloading: "Downloading"
        case .postProcessing: "Processing"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

public typealias DownloadTaskSnapshot = DownloadTaskItem

public struct DownloadTaskItem: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let url: String
    public var title: String
    public var uploader: String?
    public var extractor: String?
    public var thumbnailURL: String?
    public var configuration: DownloadConfiguration
    public var status: DownloadStatus
    public var progress: Double // 0.0 ... 1.0
    public var statusDetail: String
    public var speedText: String?
    public var etaText: String?
    public var fileSizeText: String?
    public var outputFilePath: String?
    public var errorMessage: String?
    public var logs: [String]
    public var batchID: UUID?
    public var batchName: String?
    public var playlistIndex: Int?
    public var playlistTotal: Int?
    public var completedFileCount: Int
    public var retryAttempt: Int
    public let createdAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        url: String,
        title: String? = nil,
        uploader: String? = nil,
        extractor: String? = nil,
        thumbnailURL: String? = nil,
        configuration: DownloadConfiguration,
        status: DownloadStatus = .queued,
        progress: Double = 0,
        statusDetail: String = "Waiting in queue",
        speedText: String? = nil,
        etaText: String? = nil,
        fileSizeText: String? = nil,
        outputFilePath: String? = nil,
        errorMessage: String? = nil,
        logs: [String] = [],
        batchID: UUID? = nil,
        batchName: String? = nil,
        playlistIndex: Int? = nil,
        playlistTotal: Int? = nil,
        completedFileCount: Int = 0,
        retryAttempt: Int = 0,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title ?? Self.fallbackTitle(from: url)
        self.uploader = uploader
        self.extractor = extractor
        self.thumbnailURL = thumbnailURL
        self.configuration = configuration
        self.status = status
        self.progress = progress
        self.statusDetail = statusDetail
        self.speedText = speedText
        self.etaText = etaText
        self.fileSizeText = fileSizeText
        self.outputFilePath = outputFilePath
        self.errorMessage = errorMessage
        self.logs = logs
        self.batchID = batchID
        self.batchName = batchName
        self.playlistIndex = playlistIndex
        self.playlistTotal = playlistTotal
        self.completedFileCount = completedFileCount
        self.retryAttempt = retryAttempt
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        url = try c.decode(String.self, forKey: .url)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? Self.fallbackTitle(from: url)
        uploader = try c.decodeIfPresent(String.self, forKey: .uploader)
        extractor = try c.decodeIfPresent(String.self, forKey: .extractor)
        thumbnailURL = try c.decodeIfPresent(String.self, forKey: .thumbnailURL)
        configuration = try c.decode(DownloadConfiguration.self, forKey: .configuration)
        status = try c.decodeIfPresent(DownloadStatus.self, forKey: .status) ?? .queued
        progress = try c.decodeIfPresent(Double.self, forKey: .progress) ?? 0
        statusDetail = try c.decodeIfPresent(String.self, forKey: .statusDetail) ?? "Waiting in queue"
        speedText = try c.decodeIfPresent(String.self, forKey: .speedText)
        etaText = try c.decodeIfPresent(String.self, forKey: .etaText)
        fileSizeText = try c.decodeIfPresent(String.self, forKey: .fileSizeText)
        outputFilePath = try c.decodeIfPresent(String.self, forKey: .outputFilePath)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        logs = try c.decodeIfPresent([String].self, forKey: .logs) ?? []
        batchID = try c.decodeIfPresent(UUID.self, forKey: .batchID)
        batchName = try c.decodeIfPresent(String.self, forKey: .batchName)
        playlistIndex = try c.decodeIfPresent(Int.self, forKey: .playlistIndex)
        playlistTotal = try c.decodeIfPresent(Int.self, forKey: .playlistTotal)
        completedFileCount = try c.decodeIfPresent(Int.self, forKey: .completedFileCount) ?? 0
        retryAttempt = try c.decodeIfPresent(Int.self, forKey: .retryAttempt) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }

    public static func fallbackTitle(from urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else {
            return urlString
        }
        let cleanedHost = host.replacingOccurrences(of: "www.", with: "")
        let pathPart = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if pathPart.isEmpty {
            return cleanedHost
        }
        return "\(cleanedHost) · \(pathPart.prefix(40))"
    }
}

/// Bounded per-item log storage isolated from queue list observation.
@MainActor
@Observable
public final class DownloadLogBuffer {
    public static let maxLines = 400
    public private(set) var lines: [String] = []

    public init() {}

    public func append(_ line: String) {
        lines.append(line)
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }
    }

    public func clear() {
        lines.removeAll()
    }

    public var joinedText: String {
        lines.joined(separator: "\n")
    }
}

/// Live observable download task model so per-item progress mutations don't re-render unrelated rows.
@MainActor
@Observable
public final class DownloadTask: Identifiable {
    public let id: UUID
    public let url: String
    public let createdAt: Date

    public var title: String
    public var uploader: String?
    public var extractor: String?
    public var thumbnailURL: String?
    public var configuration: DownloadConfiguration
    public var status: DownloadStatus
    public var progress: Double
    public var statusDetail: String
    public var speedText: String?
    public var etaText: String?
    public var fileSizeText: String?
    public var outputFilePath: String?
    public var errorMessage: String?
    public var batchID: UUID?
    public var batchName: String?
    public var playlistIndex: Int?
    public var playlistTotal: Int?
    public var completedFileCount: Int
    public var retryAttempt: Int
    public var completedAt: Date?

    public let logBuffer = DownloadLogBuffer()

    public init(
        id: UUID = UUID(),
        url: String,
        title: String? = nil,
        uploader: String? = nil,
        extractor: String? = nil,
        thumbnailURL: String? = nil,
        configuration: DownloadConfiguration,
        status: DownloadStatus = .queued,
        progress: Double = 0,
        statusDetail: String = "Waiting in queue",
        speedText: String? = nil,
        etaText: String? = nil,
        fileSizeText: String? = nil,
        outputFilePath: String? = nil,
        errorMessage: String? = nil,
        batchID: UUID? = nil,
        batchName: String? = nil,
        playlistIndex: Int? = nil,
        playlistTotal: Int? = nil,
        completedFileCount: Int = 0,
        retryAttempt: Int = 0,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.url = url
        self.createdAt = createdAt
        self.title = title ?? DownloadTaskItem.fallbackTitle(from: url)
        self.uploader = uploader
        self.extractor = extractor
        self.thumbnailURL = thumbnailURL
        self.configuration = configuration
        self.status = status
        self.progress = progress
        self.statusDetail = statusDetail
        self.speedText = speedText
        self.etaText = etaText
        self.fileSizeText = fileSizeText
        self.outputFilePath = outputFilePath
        self.errorMessage = errorMessage
        self.batchID = batchID
        self.batchName = batchName
        self.playlistIndex = playlistIndex
        self.playlistTotal = playlistTotal
        self.completedFileCount = completedFileCount
        self.retryAttempt = retryAttempt
        self.completedAt = completedAt
    }

    public convenience init(snapshot: DownloadTaskSnapshot) {
        self.init(
            id: snapshot.id,
            url: snapshot.url,
            title: snapshot.title,
            uploader: snapshot.uploader,
            extractor: snapshot.extractor,
            thumbnailURL: snapshot.thumbnailURL,
            configuration: snapshot.configuration,
            status: snapshot.status,
            progress: snapshot.progress,
            statusDetail: snapshot.statusDetail,
            speedText: snapshot.speedText,
            etaText: snapshot.etaText,
            fileSizeText: snapshot.fileSizeText,
            outputFilePath: snapshot.outputFilePath,
            errorMessage: snapshot.errorMessage,
            batchID: snapshot.batchID,
            batchName: snapshot.batchName,
            playlistIndex: snapshot.playlistIndex,
            playlistTotal: snapshot.playlistTotal,
            completedFileCount: snapshot.completedFileCount,
            retryAttempt: snapshot.retryAttempt,
            createdAt: snapshot.createdAt,
            completedAt: snapshot.completedAt
        )
        for line in snapshot.logs {
            logBuffer.append(line)
        }
    }

    /// Produces a slim Codable snapshot excluding transient speed/ETA/stdout logs to keep queue.json small.
    public func makeSnapshot() -> DownloadTaskSnapshot {
        DownloadTaskSnapshot(
            id: id,
            url: url,
            title: title,
            uploader: uploader,
            extractor: extractor,
            thumbnailURL: thumbnailURL,
            configuration: configuration,
            status: status,
            progress: progress,
            statusDetail: statusDetail,
            speedText: nil,
            etaText: nil,
            fileSizeText: fileSizeText,
            outputFilePath: outputFilePath,
            errorMessage: errorMessage,
            logs: [],
            batchID: batchID,
            batchName: batchName,
            playlistIndex: playlistIndex,
            playlistTotal: playlistTotal,
            completedFileCount: completedFileCount,
            retryAttempt: retryAttempt,
            createdAt: createdAt,
            completedAt: completedAt
        )
    }
}

public struct DownloadHistoryEntry: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let url: String
    public let title: String
    public let uploader: String?
    public let extractor: String?
    public let thumbnailURL: String?
    public let formatSummary: String
    public let outputFilePath: String?
    public let outputDirectoryPath: String
    public let fileSizeBytes: Int64?
    public let completedAt: Date

    public init(
        id: UUID = UUID(),
        url: String,
        title: String,
        uploader: String?,
        extractor: String?,
        thumbnailURL: String?,
        formatSummary: String,
        outputFilePath: String?,
        outputDirectoryPath: String,
        fileSizeBytes: Int64?,
        completedAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.uploader = uploader
        self.extractor = extractor
        self.thumbnailURL = thumbnailURL
        self.formatSummary = formatSummary
        self.outputFilePath = outputFilePath
        self.outputDirectoryPath = outputDirectoryPath
        self.fileSizeBytes = fileSizeBytes
        self.completedAt = completedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        url = try c.decode(String.self, forKey: .url)
        title = try c.decode(String.self, forKey: .title)
        uploader = try c.decodeIfPresent(String.self, forKey: .uploader)
        extractor = try c.decodeIfPresent(String.self, forKey: .extractor)
        thumbnailURL = try c.decodeIfPresent(String.self, forKey: .thumbnailURL)
        formatSummary = try c.decodeIfPresent(String.self, forKey: .formatSummary) ?? ""
        outputFilePath = try c.decodeIfPresent(String.self, forKey: .outputFilePath)
        outputDirectoryPath = try c.decodeIfPresent(String.self, forKey: .outputDirectoryPath) ?? ""
        fileSizeBytes = try c.decodeIfPresent(Int64.self, forKey: .fileSizeBytes)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt) ?? Date()
    }

    public var formattedSize: String? {
        guard let fileSizeBytes, fileSizeBytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    public var fileExistsOnDisk: Bool {
        guard let outputFilePath else { return false }
        return FileManager.default.fileExists(atPath: outputFilePath)
    }
}
