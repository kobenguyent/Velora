import Foundation

/// A single video/audio item inside a playlist, channel, or collection returned by `--flat-playlist`.
public struct PlaylistEntry: Sendable, Codable, Equatable, Identifiable, Hashable {
    public let index: Int
    public let id: String
    public let title: String
    public let url: String
    public let uploader: String?
    public let durationSeconds: Double?
    public let thumbnailURL: String?
    public let availability: String?

    public init(
        index: Int,
        id: String,
        title: String,
        url: String,
        uploader: String? = nil,
        durationSeconds: Double? = nil,
        thumbnailURL: String? = nil,
        availability: String? = nil
    ) {
        self.index = index
        self.id = id
        self.title = title
        self.url = url
        self.uploader = uploader
        self.durationSeconds = durationSeconds
        self.thumbnailURL = thumbnailURL
        self.availability = availability
    }

    public var formattedDuration: String? {
        MediaInfo.formatDuration(durationSeconds)
    }

    public var isUnavailable: Bool {
        let lowerTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowerTitle == "[private video]" || lowerTitle == "[deleted video]" || lowerTitle == "[unavailable video]" {
            return true
        }
        if let availability = availability?.lowercased(),
           availability == "private" || availability == "unavailable" {
            return true
        }
        return false
    }
}

/// Metadata extracted from a media URL using `yt-dlp --dump-single-json`.
public struct MediaInfo: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let webpageURL: String
    public let title: String
    public let uploader: String?
    public let extractor: String?
    public let durationSeconds: Double?
    public let viewCount: Int?
    public let uploadDate: String?
    public let thumbnailURL: String?
    public let isPlaylist: Bool
    public let playlistCount: Int?
    public let playlistEntries: [PlaylistEntry]
    public let linkedPlaylistURL: String?
    public let formats: [MediaFormat]

    public init(
        id: String,
        webpageURL: String,
        title: String,
        uploader: String? = nil,
        extractor: String? = nil,
        durationSeconds: Double? = nil,
        viewCount: Int? = nil,
        uploadDate: String? = nil,
        thumbnailURL: String? = nil,
        isPlaylist: Bool = false,
        playlistCount: Int? = nil,
        playlistEntries: [PlaylistEntry] = [],
        linkedPlaylistURL: String? = nil,
        formats: [MediaFormat] = []
    ) {
        self.id = id
        self.webpageURL = webpageURL
        self.title = title
        self.uploader = uploader
        self.extractor = extractor
        self.durationSeconds = durationSeconds
        self.viewCount = viewCount
        self.uploadDate = uploadDate
        self.thumbnailURL = thumbnailURL
        self.isPlaylist = isPlaylist
        self.playlistCount = playlistCount
        self.playlistEntries = playlistEntries
        self.linkedPlaylistURL = linkedPlaylistURL
        self.formats = formats
    }

    public static func formatDuration(_ seconds: Double?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    public var formattedDuration: String? {
        Self.formatDuration(durationSeconds)
    }

    public var availablePlaylistEntries: [PlaylistEntry] {
        playlistEntries.filter { !$0.isUnavailable }
    }

    public var totalPlaylistDurationFormatted: String? {
        let totalSeconds = playlistEntries.compactMap(\.durationSeconds).reduce(0, +)
        guard totalSeconds > 0 else { return nil }
        let total = Int(totalSeconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(max(1, m))m"
    }

    public var formattedViewCount: String? {
        guard let viewCount else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: viewCount))
    }

    public var availableHeights: [Int] {
        let heights = Set(formats.compactMap(\.height).filter { $0 >= 144 })
        return heights.sorted(by: >)
    }
}

public struct MediaFormat: Sendable, Codable, Equatable, Identifiable {
    public let formatID: String
    public let ext: String
    public let resolution: String?
    public let width: Int?
    public let height: Int?
    public let fps: Double?
    public let vcodec: String?
    public let acodec: String?
    public let tbr: Double?
    public let filesize: Int64?
    public let formatNote: String?

    public var id: String { formatID }

    public init(
        formatID: String,
        ext: String,
        resolution: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        fps: Double? = nil,
        vcodec: String? = nil,
        acodec: String? = nil,
        tbr: Double? = nil,
        filesize: Int64? = nil,
        formatNote: String? = nil
    ) {
        self.formatID = formatID
        self.ext = ext
        self.resolution = resolution
        self.width = width
        self.height = height
        self.fps = fps
        self.vcodec = vcodec
        self.acodec = acodec
        self.tbr = tbr
        self.filesize = filesize
        self.formatNote = formatNote
    }

    public var hasVideo: Bool {
        guard let vcodec else { return height != nil }
        return vcodec != "none"
    }

    public var hasAudio: Bool {
        guard let acodec else { return false }
        return acodec != "none"
    }

    public var kindLabel: String {
        switch (hasVideo, hasAudio) {
        case (true, true): "Muxed"
        case (true, false): "Video"
        case (false, true): "Audio"
        case (false, false): "Other"
        }
    }

    public var displayResolution: String {
        if let height {
            if let fps, fps >= 48 {
                return "\(height)p\(Int(fps.rounded()))"
            }
            return "\(height)p"
        }
        if hasAudio && !hasVideo {
            if let tbr {
                return "\(Int(tbr.rounded())) kbps"
            }
            return "Audio"
        }
        return resolution ?? formatNote ?? "—"
    }

    public var formattedFilesize: String {
        guard let filesize, filesize > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: filesize, countStyle: .file)
    }

    public var codecSummary: String {
        let v = (vcodec == nil || vcodec == "none") ? nil : vcodec
        let a = (acodec == nil || acodec == "none") ? nil : acodec
        return [v, a].compactMap { $0 }.joined(separator: " + ")
    }
}
