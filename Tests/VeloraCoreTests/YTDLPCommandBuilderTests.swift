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

    @Test("Validates http/https media URLs and rejects unsafe schemes or whitespace")
    func validatesMediaURLs() {
        #expect(YTDLPCommandBuilder.isValidMediaURL("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        #expect(YTDLPCommandBuilder.isValidMediaURL("http://example.com/video.mp4"))
        #expect(YTDLPCommandBuilder.isValidMediaURL("  <https://youtu.be/abc?si=1>  "))

        #expect(!YTDLPCommandBuilder.isValidMediaURL(""))
        #expect(!YTDLPCommandBuilder.isValidMediaURL("file:///etc/passwd"))
        #expect(!YTDLPCommandBuilder.isValidMediaURL("ftp://example.com/video.mp4"))
        #expect(!YTDLPCommandBuilder.isValidMediaURL("javascript:alert(1)"))
        #expect(!YTDLPCommandBuilder.isValidMediaURL("https://"))
        #expect(!YTDLPCommandBuilder.isValidMediaURL("http:///missing-host"))
        #expect(!YTDLPCommandBuilder.isValidMediaURL("https://example.com/has space"))
        #expect(!YTDLPCommandBuilder.isValidMediaURL("https://example.com/\u{0000}ctrl"))
    }

    @Test("Detects and strips dangerous extraArguments while enforcing --ignore-config and --no-exec")
    func detectsAndStripsDangerousExtraArguments() {
        let detected = YTDLPCommandBuilder.dangerousExtraArgumentFlags(
            in: #"--geo-bypass --exec "rm -rf /" --exec-before-download=id --config-location /tmp/a --config-locations=/tmp/b --plugin-dirs /tmp/p --load-info-json=/tmp/info.json -x --extract-audio"#
        )
        #expect(detected == [
            "--exec",
            "--exec-before-download",
            "--config-location",
            "--config-locations",
            "--plugin-dirs",
            "--load-info-json"
        ])
        #expect(YTDLPCommandBuilder.dangerousExtraArgumentFlags(in: "-x --no-exec --geo-bypass").isEmpty)

        var config = DownloadConfiguration()
        config.extraArguments = #"--geo-bypass --exec "touch /tmp/pwned" --plugin-dirs=/tmp/plugins --sleep-interval 2"#
        let args = YTDLPCommandBuilder.buildArguments(
            url: "https://example.com/video",
            configuration: config
        )

        #expect(args.prefix(2) == ["--ignore-config", "--no-exec"])
        #expect(args.contains("--geo-bypass"))
        #expect(args.contains("--sleep-interval"))
        #expect(args.contains("2"))
        #expect(!args.contains("--exec"))
        #expect(!args.contains("touch /tmp/pwned"))
        #expect(!args.contains("--plugin-dirs=/tmp/plugins"))
        #expect(args.suffix(3) == ["--no-exec", "--", "https://example.com/video"])
    }

    @Test("Emits JSON wire templates and keeps security flags in shellPreview")
    func jsonWireTemplatesAndShellPreview() {
        let config = DownloadConfiguration()
        let args = YTDLPCommandBuilder.buildArguments(
            url: "https://example.com/watch?v=1",
            configuration: config
        )

        #expect(args.contains("download:VELORA_PROGRESS_JSON:%(progress.{status,downloaded_bytes,total_bytes,total_bytes_estimate,speed,eta,_percent_str,_speed_str,_eta_str})j"))
        #expect(args.contains("before_dl:VELORA_META_JSON:%(.{title,uploader,channel,extractor_key,extractor,is_live})j"))
        #expect(args.contains("after_move:VELORA_FILEPATH_JSON:%(.{filepath})j"))

        let preview = YTDLPCommandBuilder.shellPreview(
            ytdlpPath: "/usr/local/bin/yt-dlp",
            url: "https://example.com/watch?v=1",
            configuration: config
        )
        #expect(preview.contains("--ignore-config"))
        #expect(preview.contains("--no-exec"))
        #expect(!preview.contains("VELORA_PROGRESS_JSON"))
        #expect(!preview.contains("VELORA_META_JSON"))
        #expect(!preview.contains("VELORA_FILEPATH_JSON"))
        #expect(!preview.contains("--progress-template"))
        #expect(!preview.contains("--print"))
    }

    @Test("Emits resume and bounded auto-retry flags")
    func resumeAndRetryFlags() {
        var config = DownloadConfiguration()
        config.resumePartialDownloads = true
        config.autoRetryCount = 5
        let retryArgs = YTDLPCommandBuilder.buildArguments(url: "https://example.com/v", configuration: config)
        #expect(retryArgs.contains("--continue"))
        #expect(!retryArgs.contains("--no-continue"))
        #expect(retryArgs.contains("--retries"))
        #expect(retryArgs.contains("5"))
        #expect(retryArgs.contains("--fragment-retries"))
        #expect(retryArgs.contains("--retry-sleep"))
        #expect(retryArgs.contains("exp=1:16"))

        config.resumePartialDownloads = false
        config.autoRetryCount = 0
        let noRetryArgs = YTDLPCommandBuilder.buildArguments(url: "https://example.com/v", configuration: config)
        #expect(noRetryArgs.contains("--no-continue"))
        #expect(!noRetryArgs.contains("--continue"))
        #expect(!noRetryArgs.contains("--retries"))
        #expect(!noRetryArgs.contains("--fragment-retries"))
        #expect(!noRetryArgs.contains("--retry-sleep"))

        config.autoRetryCount = 99
        let clampedArgs = YTDLPCommandBuilder.buildArguments(url: "https://example.com/v", configuration: config)
        #expect(clampedArgs.contains("10"))
        #expect(!clampedArgs.contains("99"))
    }

    @Test("Omits --embed-thumbnail for unsupported webm, wav, and aac formats")
    func embedThumbnailContainerGuards() {
        var config = DownloadConfiguration()
        config.embedThumbnail = true

        config.mode = .videoAndAudio
        config.videoContainer = .webm
        #expect(!YTDLPCommandBuilder.buildArguments(url: "https://example.com/v", configuration: config).contains("--embed-thumbnail"))

        config.mode = .videoOnly
        config.videoContainer = .webm
        #expect(!YTDLPCommandBuilder.buildArguments(url: "https://example.com/v", configuration: config).contains("--embed-thumbnail"))

        config.mode = .audioOnly
        config.audioFormat = .wav
        #expect(!YTDLPCommandBuilder.buildArguments(url: "https://example.com/v", configuration: config).contains("--embed-thumbnail"))

        config.audioFormat = .aac
        #expect(!YTDLPCommandBuilder.buildArguments(url: "https://example.com/v", configuration: config).contains("--embed-thumbnail"))

        config.audioFormat = .m4a
        #expect(YTDLPCommandBuilder.buildArguments(url: "https://example.com/v", configuration: config).contains("--embed-thumbnail"))
    }

    @Test("Appends +bestaudio/best when custom format ID is video-only in videoAndAudio mode")
    func customFormatVideoOnlyAudioMerge() {
        var config = DownloadConfiguration()
        config.mode = .videoAndAudio
        config.customFormatID = "313"

        let videoOnlyCustomArgs = YTDLPCommandBuilder.buildArguments(
            url: "https://example.com/v",
            configuration: config,
            customFormatIsVideoOnly: true
        )
        #expect(videoOnlyCustomArgs.contains("313+bestaudio/best"))

        let muxedCustomArgs = YTDLPCommandBuilder.buildArguments(
            url: "https://example.com/v",
            configuration: config,
            customFormatIsVideoOnly: false
        )
        #expect(muxedCustomArgs.contains("313"))
        #expect(!muxedCustomArgs.contains("313+bestaudio/best"))

        let preview = YTDLPCommandBuilder.shellPreview(
            ytdlpPath: "yt-dlp",
            url: "https://example.com/v",
            configuration: config,
            customFormatIsVideoOnly: true
        )
        #expect(preview.contains("313+bestaudio/best"))
    }

    @Test("Builds resolution-first sort flags for Best MP4 and Apple-compatible sort flags for MOV")
    func sortFlagsForBestMP4AndAppleProMOV() throws {
        let presets = DownloadPreset.builtInPresets
        #expect(presets.count == 6)
        #expect(presets.allSatisfy { !$0.subtitle.isEmpty })

        let bestMP4 = try #require(presets.first { $0.name == "Best MP4" })
        let bestMP4Args = YTDLPCommandBuilder.buildArguments(
            url: "https://example.com/v",
            configuration: bestMP4.configuration
        )
        #expect(bestMP4Args.contains("res,vcodec:h264,ext:mp4:m4a"))

        let applePro = try #require(presets.first { $0.name == "Apple Pro" })
        let appleProArgs = YTDLPCommandBuilder.buildArguments(
            url: "https://example.com/v",
            configuration: applePro.configuration
        )
        #expect(appleProArgs.contains("res:2160,vcodec:h265,vcodec:h264,acodec:aac,ext:mp4:m4a"))
        #expect(appleProArgs.contains("--remux-video"))
        #expect(appleProArgs.contains("mov"))
    }

    @Test("Uses --write-subs --sub-langs all,-live_chat for allAvailable subtitles and supports cookieFilePath")
    func allAvailableSubtitlesAndCookieFile() {
        var config = DownloadConfiguration()
        config.subtitleMode = .allAvailable
        config.includeAutoSubtitles = true
        config.embedSubtitles = false
        config.cookieFilePath = "  ~/Downloads/cookies.txt  "

        let args = YTDLPCommandBuilder.buildArguments(url: "https://example.com/v", configuration: config)
        #expect(args.contains("--write-subs"))
        #expect(args.contains("--sub-langs"))
        #expect(args.contains("all,-live_chat"))
        #expect(!args.contains("--all-subs"))
        #expect(!args.contains("--write-auto-subs"))
        #expect(args.contains("--convert-subs"))
        #expect(args.contains("srt"))
        #expect(args.contains("--cookies"))
        let expectedCookiesPath = ("~/Downloads/cookies.txt" as NSString).expandingTildeInPath
        #expect(args.contains(expectedCookiesPath))
    }

    @Test("Sanitizes playlist subfolder path traversal and custom filename template .. segments")
    func playlistSubfolderAndTemplateTraversalGuard() {
        var config = DownloadConfiguration()
        config.playlistBehavior = .downloadEntirePlaylist
        config.createPlaylistSubfolder = true
        config.filenamePreset = .custom
        config.customFilenameTemplate = "../../escape/../%(title)s.%(ext)s"

        let args = YTDLPCommandBuilder.buildArguments(
            url: "https://www.youtube.com/playlist?list=PL123",
            configuration: config
        )
        #expect(args.contains("--windows-filenames"))
        if let oIdx = args.firstIndex(of: "-o"), oIdx + 1 < args.count {
            let template = args[oIdx + 1]
            #expect(!template.contains(".."))
            #expect(template == "%(playlist_title,playlist)s/%(playlist_index)02d - escape/%(title)s.%(ext)s")
        } else {
            Issue.record("Expected -o template argument")
        }
    }
}
