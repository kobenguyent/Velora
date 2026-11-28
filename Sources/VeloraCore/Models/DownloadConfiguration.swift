import Foundation

public enum MediaMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case videoAndAudio = "video_audio"
    case audioOnly = "audio_only"
    case videoOnly = "video_only"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .videoAndAudio: "Video + Audio"
        case .audioOnly: "Audio Only"
        case .videoOnly: "Video Only"
        }
    }

    public var systemImage: String {
        switch self {
        case .videoAndAudio: "film.stack"
        case .audioOnly: "waveform"
        case .videoOnly: "video.slash"
        }
    }
}

public enum VideoQuality: String, CaseIterable, Codable, Sendable, Identifiable {
    case best = "best"
    case p4320 = "4320"
    case p2160 = "2160"
    case p1440 = "1440"
    case p1080 = "1080"
    case p720 = "720"
    case p480 = "480"
    case p360 = "360"
    case worst = "worst"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .best: "Best Available"
        case .p4320: "8K (4320p)"
        case .p2160: "4K Ultra HD (2160p)"
        case .p1440: "2K QHD (1440p)"
        case .p1080: "Full HD (1080p)"
        case .p720: "HD (720p)"
        case .p480: "SD (480p)"
        case .p360: "Compact (360p)"
        case .worst: "Smallest Size"
        }
    }

    public var shortLabel: String {
        switch self {
        case .best: "Best"
        case .p4320: "8K"
        case .p2160: "4K"
        case .p1440: "1440p"
        case .p1080: "1080p"
        case .p720: "720p"
        case .p480: "480p"
        case .p360: "360p"
        case .worst: "Min"
        }
    }

    public var maxHeight: Int? {
        Int(rawValue)
    }
}

public enum VideoContainer: String, CaseIterable, Codable, Sendable, Identifiable {
    case mp4
    case mkv
    case webm
    case mov

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mp4: "MP4 (Universal)"
        case .mkv: "MKV (Matroska)"
        case .webm: "WebM (Open)"
        case .mov: "MOV (Apple QuickTime)"
        }
    }
}

public enum AudioFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    case m4a
    case mp3
    case flac
    case wav
    case opus
    case aac

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .m4a: "M4A (Apple AAC)"
        case .mp3: "MP3 (Universal)"
        case .flac: "FLAC (Lossless)"
        case .wav: "WAV (Uncompressed)"
        case .opus: "Opus (High Efficiency)"
        case .aac: "AAC"
        }
    }
}

public enum AudioBitrate: String, CaseIterable, Codable, Sendable, Identifiable {
    case best = "0"
    case k320 = "320K"
    case k256 = "256K"
    case k192 = "192K"
    case k128 = "128K"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .best: "Best Available"
        case .k320: "320 kbps"
        case .k256: "256 kbps"
        case .k192: "192 kbps"
        case .k128: "128 kbps"
        }
    }
}

public enum PreferredVideoCodec: String, CaseIterable, Codable, Sendable, Identifiable {
    case auto
    case h264
    case hevc
    case vp9
    case av1

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: "Auto (Best Quality)"
        case .h264: "H.264 / AVC (Max Compatibility)"
        case .hevc: "H.265 / HEVC (Apple Native)"
        case .vp9: "VP9 (YouTube High-Res)"
        case .av1: "AV1 (Smallest High-Res)"
        }
    }

    public var ytdlpSortToken: String? {
        switch self {
        case .auto: nil
        case .h264: "vcodec:h264"
        case .hevc: "vcodec:h265"
        case .vp9: "vcodec:vp9"
        case .av1: "vcodec:av01"
        }
    }
}

public enum FrameRateCap: String, CaseIterable, Codable, Sendable, Identifiable {
    case unlimited
    case fps60
    case fps30

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .unlimited: "Unlimited"
        case .fps60: "Up to 60 fps"
        case .fps30: "Up to 30 fps"
        }
    }

    public var numericCap: Int? {
        switch self {
        case .unlimited: nil
        case .fps60: 60
        case .fps30: 30
        }
    }
}

public enum SubtitleMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case off
    case preferredLanguages
    case allAvailable

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: "None"
        case .preferredLanguages: "Selected Languages"
        case .allAvailable: "All Languages"
        }
    }
}

public enum SponsorBlockMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case off
    case markAll
    case removeSponsors
    case removeAllSegments

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: "Disabled"
        case .markAll: "Mark as Chapters"
        case .removeSponsors: "Remove Sponsors"
        case .removeAllSegments: "Remove Sponsors, Intros & Outros"
        }
    }
}

public enum BrowserCookiesSource: String, CaseIterable, Codable, Sendable, Identifiable {
    case none
    case safari
    case chrome
    case brave
    case firefox
    case edge
    case arc

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: "None"
        case .safari: "Safari"
        case .chrome: "Google Chrome"
        case .brave: "Brave"
        case .firefox: "Firefox"
        case .edge: "Microsoft Edge"
        case .arc: "Arc"
        }
    }

    public var ytdlpIdentifier: String? {
        switch self {
        case .none: nil
        case .arc: "chrome:~/Library/Application Support/Arc/User Data"
        default: rawValue
        }
    }
}

public enum FilenameTemplatePreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case cleanTitle
    case titleWithQuality
    case uploaderAndTitle
    case dateAndTitle
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cleanTitle: "Title"
        case .titleWithQuality: "Title [Quality]"
        case .uploaderAndTitle: "Channel - Title"
        case .dateAndTitle: "Date - Title"
        case .custom: "Custom Template"
        }
    }

    public var templateString: String {
        switch self {
        case .cleanTitle: "%(title)s.%(ext)s"
        case .titleWithQuality: "%(title)s [%(height)sp].%(ext)s"
        case .uploaderAndTitle: "%(uploader)s - %(title)s.%(ext)s"
        case .dateAndTitle: "%(upload_date>%Y-%m-%d)s - %(title)s.%(ext)s"
        case .custom: "%(title)s [%(id)s].%(ext)s"
        }
    }
}

public enum PlaylistBehavior: String, CaseIterable, Codable, Sendable, Identifiable {
    case singleVideoOnly
    case downloadEntirePlaylist

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .singleVideoOnly: "Single Video Only"
        case .downloadEntirePlaylist: "Download Full Playlist"
        }
    }
}

public enum NetworkIPVersion: String, CaseIterable, Codable, Sendable, Identifiable {
    case ipv4
    case auto
    case ipv6

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ipv4: "IPv4 Only (Recommended)"
        case .auto: "System Auto (IPv4 + IPv6)"
        case .ipv6: "IPv6 Only"
        }
    }

    public var ytdlpFlag: String? {
        switch self {
        case .ipv4: "-4"
        case .auto: nil
        case .ipv6: "-6"
        }
    }
}

/// Complete configuration for a Velora download job.
public struct DownloadConfiguration: Codable, Sendable, Equatable {
    // Media & Quality
    public var mode: MediaMode = .videoAndAudio
    public var videoQuality: VideoQuality = .p1080
    public var videoContainer: VideoContainer = .mp4
    public var audioFormat: AudioFormat = .m4a
    public var audioBitrate: AudioBitrate = .best
    public var preferredCodec: PreferredVideoCodec = .h264
    public var frameRateCap: FrameRateCap = .unlimited
    public var customFormatID: String? = nil

    // Subtitles
    public var subtitleMode: SubtitleMode = .off
    public var subtitleLanguages: String = "en"
    public var includeAutoSubtitles: Bool = false
    public var embedSubtitles: Bool = true

    // Post-processing & Metadata
    public var embedThumbnail: Bool = true
    public var embedMetadata: Bool = true
    public var embedChapters: Bool = true
    public var splitChapters: Bool = false
    public var sponsorBlock: SponsorBlockMode = .off

    // Clipping / Time Range
    public var clipEnabled: Bool = false
    public var clipStart: String = ""
    public var clipEnd: String = ""
    public var forceKeyframesAtCuts: Bool = true

    // Playlist
    public var playlistBehavior: PlaylistBehavior = .singleVideoOnly
    public var playlistItems: String = ""
    public var createPlaylistSubfolder: Bool = true

    // Output
    public var outputDirectoryPath: String = DownloadConfiguration.defaultOutputDirectoryPath()
    public var filenamePreset: FilenameTemplatePreset = .cleanTitle
    public var customFilenameTemplate: String = "%(title)s [%(id)s].%(ext)s"
    public var restrictFilenames: Bool = false
    public var overwriteExisting: Bool = false

    // Network & Authentication
    public var networkIPVersion: NetworkIPVersion = .ipv4
    public var socketTimeoutSeconds: Int = 20
    public var concurrentFragments: Int = 4
    public var rateLimit: String = ""
    public var proxyURL: String = ""
    public var browserCookies: BrowserCookiesSource = .none
    public var cookieFilePath: String = ""
    public var autoRetryCount: Int = 3
    public var resumePartialDownloads: Bool = true
    public var extraArguments: String = ""

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DownloadConfiguration()
        mode = try c.decodeIfPresent(MediaMode.self, forKey: .mode) ?? defaults.mode
        videoQuality = try c.decodeIfPresent(VideoQuality.self, forKey: .videoQuality) ?? defaults.videoQuality
        videoContainer = try c.decodeIfPresent(VideoContainer.self, forKey: .videoContainer) ?? defaults.videoContainer
        audioFormat = try c.decodeIfPresent(AudioFormat.self, forKey: .audioFormat) ?? defaults.audioFormat
        audioBitrate = try c.decodeIfPresent(AudioBitrate.self, forKey: .audioBitrate) ?? defaults.audioBitrate
        preferredCodec = try c.decodeIfPresent(PreferredVideoCodec.self, forKey: .preferredCodec) ?? defaults.preferredCodec
        frameRateCap = try c.decodeIfPresent(FrameRateCap.self, forKey: .frameRateCap) ?? defaults.frameRateCap
        customFormatID = try c.decodeIfPresent(String.self, forKey: .customFormatID)
        subtitleMode = try c.decodeIfPresent(SubtitleMode.self, forKey: .subtitleMode) ?? defaults.subtitleMode
        subtitleLanguages = try c.decodeIfPresent(String.self, forKey: .subtitleLanguages) ?? defaults.subtitleLanguages
        includeAutoSubtitles = try c.decodeIfPresent(Bool.self, forKey: .includeAutoSubtitles) ?? defaults.includeAutoSubtitles
        embedSubtitles = try c.decodeIfPresent(Bool.self, forKey: .embedSubtitles) ?? defaults.embedSubtitles
        embedThumbnail = try c.decodeIfPresent(Bool.self, forKey: .embedThumbnail) ?? defaults.embedThumbnail
        embedMetadata = try c.decodeIfPresent(Bool.self, forKey: .embedMetadata) ?? defaults.embedMetadata
        embedChapters = try c.decodeIfPresent(Bool.self, forKey: .embedChapters) ?? defaults.embedChapters
        splitChapters = try c.decodeIfPresent(Bool.self, forKey: .splitChapters) ?? defaults.splitChapters
        sponsorBlock = try c.decodeIfPresent(SponsorBlockMode.self, forKey: .sponsorBlock) ?? defaults.sponsorBlock
        clipEnabled = try c.decodeIfPresent(Bool.self, forKey: .clipEnabled) ?? defaults.clipEnabled
        clipStart = try c.decodeIfPresent(String.self, forKey: .clipStart) ?? defaults.clipStart
        clipEnd = try c.decodeIfPresent(String.self, forKey: .clipEnd) ?? defaults.clipEnd
        forceKeyframesAtCuts = try c.decodeIfPresent(Bool.self, forKey: .forceKeyframesAtCuts) ?? defaults.forceKeyframesAtCuts
        playlistBehavior = try c.decodeIfPresent(PlaylistBehavior.self, forKey: .playlistBehavior) ?? defaults.playlistBehavior
        playlistItems = try c.decodeIfPresent(String.self, forKey: .playlistItems) ?? defaults.playlistItems
        createPlaylistSubfolder = try c.decodeIfPresent(Bool.self, forKey: .createPlaylistSubfolder) ?? defaults.createPlaylistSubfolder
        outputDirectoryPath = try c.decodeIfPresent(String.self, forKey: .outputDirectoryPath) ?? defaults.outputDirectoryPath
        filenamePreset = try c.decodeIfPresent(FilenameTemplatePreset.self, forKey: .filenamePreset) ?? defaults.filenamePreset
        customFilenameTemplate = try c.decodeIfPresent(String.self, forKey: .customFilenameTemplate) ?? defaults.customFilenameTemplate
        restrictFilenames = try c.decodeIfPresent(Bool.self, forKey: .restrictFilenames) ?? defaults.restrictFilenames
        overwriteExisting = try c.decodeIfPresent(Bool.self, forKey: .overwriteExisting) ?? defaults.overwriteExisting
        networkIPVersion = try c.decodeIfPresent(NetworkIPVersion.self, forKey: .networkIPVersion) ?? defaults.networkIPVersion
        socketTimeoutSeconds = try c.decodeIfPresent(Int.self, forKey: .socketTimeoutSeconds) ?? defaults.socketTimeoutSeconds
        concurrentFragments = try c.decodeIfPresent(Int.self, forKey: .concurrentFragments) ?? defaults.concurrentFragments
        rateLimit = try c.decodeIfPresent(String.self, forKey: .rateLimit) ?? defaults.rateLimit
        proxyURL = try c.decodeIfPresent(String.self, forKey: .proxyURL) ?? defaults.proxyURL
        browserCookies = try c.decodeIfPresent(BrowserCookiesSource.self, forKey: .browserCookies) ?? defaults.browserCookies
        cookieFilePath = try c.decodeIfPresent(String.self, forKey: .cookieFilePath) ?? defaults.cookieFilePath
        let rawRetryCount = try c.decodeIfPresent(Int.self, forKey: .autoRetryCount) ?? defaults.autoRetryCount
        autoRetryCount = min(10, max(0, rawRetryCount))
        resumePartialDownloads = try c.decodeIfPresent(Bool.self, forKey: .resumePartialDownloads) ?? defaults.resumePartialDownloads
        extraArguments = try c.decodeIfPresent(String.self, forKey: .extraArguments) ?? defaults.extraArguments
    }

    public var activeModifierSummaries: [String] {
        var summaries: [String] = []
        if subtitleMode != .off {
            summaries.append("Subs")
        }
        if sponsorBlock != .off {
            summaries.append("SponsorBlock")
        }
        if clipEnabled {
            summaries.append("Clip")
        }
        if playlistBehavior == .downloadEntirePlaylist {
            summaries.append("Playlist")
        }
        if browserCookies != .none {
            summaries.append("\(browserCookies.displayName) Cookies")
        }
        if !cookieFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            summaries.append("cookies.txt")
        }
        if !proxyURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            summaries.append("Proxy")
        }
        if !rateLimit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            summaries.append("Speed Cap")
        }
        if !extraArguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            summaries.append("Extra Args")
        }
        if let customFormatID = customFormatID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !customFormatID.isEmpty {
            summaries.append("Stream #\(customFormatID)")
        }
        return summaries
    }

    public static func defaultOutputDirectoryPath() -> String {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        return downloads.appendingPathComponent("Velora", isDirectory: true).path
    }

    public var effectiveFilenameTemplate: String {
        switch filenamePreset {
        case .custom:
            let trimmed = customFilenameTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? FilenameTemplatePreset.cleanTitle.templateString : trimmed
        default:
            return filenamePreset.templateString
        }
    }

    public var summaryBadge: String {
        if let customFormatID, !customFormatID.isEmpty {
            return "Format #\(customFormatID)"
        }
        switch mode {
        case .audioOnly:
            let rate = audioBitrate == .best ? "Best" : audioBitrate.rawValue
            return "\(audioFormat.rawValue.uppercased()) · \(rate)"
        case .videoOnly:
            return "\(videoQuality.shortLabel) Video · \(videoContainer.rawValue.uppercased())"
        case .videoAndAudio:
            return "\(videoQuality.shortLabel) · \(videoContainer.rawValue.uppercased())"
        }
    }
}
