import Foundation

public enum DownloadStatus: String, Codable, Sendable, Equatable {
    case queued
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

    public var displayName: String {
        switch self {
        case .queued: "Queued"
        case .preparing: "Preparing"
        case .downloading: "Downloading"
        case .postProcessing: "Processing"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

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
        batchID: UUID? = nil,
        batchName: String? = nil,
        playlistIndex: Int? = nil,
        playlistTotal: Int? = nil,
        createdAt: Date = Date()
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
        self.logs = []
        self.batchID = batchID
        self.batchName = batchName
        self.playlistIndex = playlistIndex
        self.playlistTotal = playlistTotal
        self.completedFileCount = 0
        self.createdAt = createdAt
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

    public var formattedSize: String? {
        guard let fileSizeBytes, fileSizeBytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    public var fileExistsOnDisk: Bool {
        guard let outputFilePath else { return false }
        return FileManager.default.fileExists(atPath: outputFilePath)
    }
}
