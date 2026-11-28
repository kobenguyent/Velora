import Foundation

/// Built-in and user-created presets for rapid download setup.
public struct DownloadPreset: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var subtitle: String
    public var symbolName: String
    public var configuration: DownloadConfiguration
    public var isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        subtitle: String,
        symbolName: String,
        configuration: DownloadConfiguration,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.configuration = configuration
        self.isBuiltIn = isBuiltIn
    }

    public static var builtInPresets: [DownloadPreset] {
        var bestMP4 = DownloadConfiguration()
        bestMP4.mode = .videoAndAudio
        bestMP4.videoQuality = .best
        bestMP4.videoContainer = .mp4
        bestMP4.preferredCodec = .h264
        bestMP4.embedThumbnail = true
        bestMP4.embedMetadata = true

        var cinema4K = DownloadConfiguration()
        cinema4K.mode = .videoAndAudio
        cinema4K.videoQuality = .p2160
        cinema4K.videoContainer = .mkv
        cinema4K.preferredCodec = .auto
        cinema4K.subtitleMode = .preferredLanguages
        cinema4K.subtitleLanguages = "en"
        cinema4K.embedSubtitles = true
        cinema4K.embedChapters = true
        cinema4K.embedMetadata = true
        cinema4K.embedThumbnail = true

        var balanced1080 = DownloadConfiguration()
        balanced1080.mode = .videoAndAudio
        balanced1080.videoQuality = .p1080
        balanced1080.videoContainer = .mp4
        balanced1080.preferredCodec = .h264
        balanced1080.frameRateCap = .fps60
        balanced1080.embedMetadata = true
        balanced1080.embedThumbnail = true

        var appleNative = DownloadConfiguration()
        appleNative.mode = .videoAndAudio
        appleNative.videoQuality = .p2160
        appleNative.videoContainer = .mov
        appleNative.preferredCodec = .hevc
        appleNative.embedMetadata = true
        appleNative.embedThumbnail = true

        var audioM4A = DownloadConfiguration()
        audioM4A.mode = .audioOnly
        audioM4A.audioFormat = .m4a
        audioM4A.audioBitrate = .best
        audioM4A.embedThumbnail = true
        audioM4A.embedMetadata = true

        var audioMP3 = DownloadConfiguration()
        audioMP3.mode = .audioOnly
        audioMP3.audioFormat = .mp3
        audioMP3.audioBitrate = .k320
        audioMP3.embedThumbnail = true
        audioMP3.embedMetadata = true

        return [
            DownloadPreset(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                name: "1080p Universal",
                subtitle: "MP4 · H.264 · QuickTime & iOS ready",
                symbolName: "sparkles.tv",
                configuration: balanced1080,
                isBuiltIn: true
            ),
            DownloadPreset(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
                name: "4K Cinema",
                subtitle: "2160p MKV · Embedded subs & chapters",
                symbolName: "4k.tv",
                configuration: cinema4K,
                isBuiltIn: true
            ),
            DownloadPreset(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
                name: "Best MP4",
                subtitle: "Max resolution · MP4 (H.264 preferred)",
                symbolName: "crown",
                configuration: bestMP4,
                isBuiltIn: true
            ),
            DownloadPreset(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
                name: "Apple Pro",
                subtitle: "HEVC/H.264 MOV · AirDrop & Final Cut friendly",
                symbolName: "applelogo",
                configuration: appleNative,
                isBuiltIn: true
            ),
            DownloadPreset(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
                name: "Master Audio",
                subtitle: "M4A · Best bitrate + Cover art",
                symbolName: "hifispeaker.fill",
                configuration: audioM4A,
                isBuiltIn: true
            ),
            DownloadPreset(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000006")!,
                name: "MP3 320k",
                subtitle: "Universal audio · Artwork & tags",
                symbolName: "music.note",
                configuration: audioMP3,
                isBuiltIn: true
            )
        ]
    }
}
