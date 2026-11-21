import Foundation
import Testing
@testable import VeloraCore

@Suite("yt-dlp Command Builder")
struct YTDLPCommandBuilderTests {
    @Test("Builds 1080p H.264 MP4 video+audio arguments")
    func video1080pMP4Arguments() {
        var config = DownloadConfiguration()
        config.mode = .videoAndAudio
        config.videoQuality = .p1080
        config.videoContainer = .mp4
        config.preferredCodec = .h264
        config.frameRateCap = .fps60
        config.outputDirectoryPath = "/tmp/VeloraTest"

        let args = YTDLPCommandBuilder.buildArguments(
            url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            configuration: config,
            ffmpegPath: "/opt/homebrew/bin/ffmpeg"
        )

        #expect(args.contains("--no-simulate"))
        #expect(args.contains("--ffmpeg-location"))
        #expect(args.contains("/opt/homebrew/bin"))
        #expect(args.contains("bestvideo[height<=1080][fps<=60]+bestaudio/best[height<=1080][fps<=60]/best"))
        #expect(args.contains("res:1080,vcodec:h264,ext:mp4:m4a"))
        #expect(args.contains("--merge-output-format"))
        #expect(args.contains("mp4"))
        #expect(args.contains("--no-playlist"))
        #expect(args.last == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    }

    @Test("Builds audio-only MP3 extraction arguments")
    func audioOnlyMP3Arguments() {
        var config = DownloadConfiguration()
        config.mode = .audioOnly
        config.audioFormat = .mp3
        config.audioBitrate = .k320
        config.embedThumbnail = true
        config.embedMetadata = true

        let args = YTDLPCommandBuilder.buildArguments(
            url: "https://youtu.be/abc123",
            configuration: config
        )

        #expect(args.contains("-x"))
        #expect(args.contains("--audio-format"))
        #expect(args.contains("mp3"))
        #expect(args.contains("--audio-quality"))
        #expect(args.contains("320K"))
        #expect(args.contains("--embed-thumbnail"))
        #expect(args.contains("--embed-metadata"))
    }

    @Test("Builds subtitles, SponsorBlock, clipping, playlist, cookies, proxy & extra args")
    func advancedOptionsArguments() {
        var config = DownloadConfiguration()
        config.subtitleMode = .preferredLanguages
        config.subtitleLanguages = "en,ja"
        config.includeAutoSubtitles = true
        config.embedSubtitles = true
        config.sponsorBlock = .removeSponsors
        config.clipEnabled = true
        config.clipStart = "00:01:00"
        config.clipEnd = "00:02:30"
        config.forceKeyframesAtCuts = true
        config.playlistBehavior = .downloadEntirePlaylist
        config.playlistItems = "1-5"
        config.createPlaylistSubfolder = true
        config.browserCookies = .safari
        config.rateLimit = "5M"
        config.proxyURL = "socks5://127.0.0.1:1080"
        config.extraArguments = "--geo-bypass --sleep-interval '2'"

        let args = YTDLPCommandBuilder.buildArguments(
            url: "https://www.youtube.com/playlist?list=PL123",
            configuration: config
        )

        #expect(args.contains("--write-subs"))
        #expect(args.contains("--write-auto-subs"))
        #expect(args.contains("en,ja"))
        #expect(args.contains("--embed-subs"))
        #expect(args.contains("--sponsorblock-remove"))
        #expect(args.contains("sponsor"))
        #expect(args.contains("--download-sections"))
        #expect(args.contains("*00:01:00-00:02:30"))
        #expect(args.contains("--force-keyframes-at-cuts"))
        #expect(args.contains("--yes-playlist"))
        #expect(args.contains("--playlist-items"))
        #expect(args.contains("1-5"))
        #expect(args.contains("--cookies-from-browser"))
        #expect(args.contains("safari"))
        #expect(args.contains("-r"))
        #expect(args.contains("5M"))
        #expect(args.contains("--proxy"))
        #expect(args.contains("socks5://127.0.0.1:1080"))
        #expect(args.contains("--geo-bypass"))
        #expect(args.contains("--sleep-interval"))
        #expect(args.contains("2"))
    }

    @Test("Handles custom format ID override and quoted extra argument tokenization")
    func customFormatOverrideAndTokenizer() {
        var config = DownloadConfiguration()
        config.customFormatID = "313+251"
        config.videoContainer = .mkv

        let args = YTDLPCommandBuilder.buildArguments(url: "https://youtu.be/test", configuration: config)
        #expect(args.contains("-f"))
        #expect(args.contains("313+251"))
        #expect(args.contains("mkv"))

        let tokens = YTDLPCommandBuilder.tokenizeShellArguments(
            #"--user-agent "Mozilla 5.0" --referer 'https://a.com/x y' --retries 5"#
        )
        #expect(tokens == ["--user-agent", "Mozilla 5.0", "--referer", "https://a.com/x y", "--retries", "5"])
    }

    @Test("Passes IPv4, socket timeout, JS runtime, and sanitizes shortened youtu.be URLs")
    func networkIPv4JSRuntimeAndShortenedURL() throws {
        let config = DownloadConfiguration()
        let args = YTDLPCommandBuilder.buildArguments(
            url: "  <https://youtu.be/PU9L0rfejSw?si=B2frSJIR34ThGFIl>  ",
            configuration: config,
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            jsRuntimeArg: "bun:/opt/homebrew/bin/bun"
        )

        #expect(args.contains("-4"))
        #expect(args.contains("--socket-timeout"))
        #expect(args.contains("20"))
        #expect(args.contains("--js-runtimes"))
        #expect(args.contains("bun:/opt/homebrew/bin/bun"))
        #expect(args.last == "https://youtu.be/PU9L0rfejSw?si=B2frSJIR34ThGFIl")

        // Backwards-compatible decoding of legacy saved configs missing networkIPVersion
        let legacyJSON = #"{"mode":"video_audio","videoQuality":"1080"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DownloadConfiguration.self, from: legacyJSON)
        #expect(decoded.networkIPVersion == .ipv4)
        #expect(decoded.socketTimeoutSeconds == 20)
    }
}
