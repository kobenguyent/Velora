import Foundation

/// Pure command-line builder that translates `DownloadConfiguration` into exact `yt-dlp` arguments.
public enum YTDLPCommandBuilder {

    private static let dangerousExtraFlags: [String] = [
        "--exec",
        "--exec-before-download",
        "--config-location",
        "--config-locations",
        "--plugin-dirs",
        "--load-info-json"
    ]

    public static func sanitizeURL(_ rawURL: String) -> String {
        var cleaned = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if (cleaned.hasPrefix("<") && cleaned.hasSuffix(">")) ||
           (cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"")) ||
           (cleaned.hasPrefix("'") && cleaned.hasSuffix("'")) {
            cleaned = String(cleaned.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }

    /// Validates that `rawURL` is a well-formed `http://` or `https://` media URL with a non-empty host and no whitespace/control characters.
    public static func isValidMediaURL(_ rawURL: String) -> Bool {
        let cleaned = sanitizeURL(rawURL)
        guard !cleaned.isEmpty else { return false }
        let forbiddenScalars = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        guard !cleaned.unicodeScalars.contains(where: { forbiddenScalars.contains($0) }) else {
            return false
        }
        guard let components = URLComponents(string: cleaned),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty else {
            return false
        }
        return true
    }

    /// Detects dangerous `yt-dlp` flags in a user-provided extra arguments string (including `--flag=value` forms).
    public static func dangerousExtraArgumentFlags(in rawExtra: String) -> [String] {
        var seen: Set<String> = []
        var detected: [String] = []
        for token in tokenizeShellArguments(rawExtra) {
            let lower = token.lowercased()
            if let match = dangerousExtraFlags.first(where: { lower == $0 || lower.hasPrefix("\($0)=") }),
               seen.insert(match).inserted {
                detected.append(match)
            }
        }
        return detected
    }

    private static func sanitizeExtraArgumentTokens(_ tokens: [String]) -> [String] {
        var sanitized: [String] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            let lower = token.lowercased()
            if token == "--" {
                index += 1
                continue
            }
            if let _ = dangerousExtraFlags.first(where: { lower == $0 || lower.hasPrefix("\($0)=") }) {
                // Skip standalone value token so payloads like `--exec "cmd"` cannot leak as positional URLs.
                if !lower.contains("=") && index + 1 < tokens.count {
                    index += 2
                } else {
                    index += 1
                }
                continue
            }
            sanitized.append(token)
            index += 1
        }
        return sanitized
    }

    private static func sanitizeFilenameTemplate(_ rawTemplate: String) -> String {
        let normalized = rawTemplate.replacingOccurrences(of: "\\", with: "/")
        let safeParts = normalized
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0 != "." && $0 != ".." }
        if safeParts.isEmpty {
            return FilenameTemplatePreset.cleanTitle.templateString
        }
        return safeParts.joined(separator: "/")
    }

    /// Extracts, sanitizes, and deduplicates `http://` and `https://` URLs from pasted text, newline lists, or CSVs.
    public static func extractURLs(from rawText: String) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []

        for rawLine in rawText.components(separatedBy: .newlines) {
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") { continue }

            // Support plain lines, comma/tab-separated lines, or lines containing inline links
            let candidates = trimmedLine.components(separatedBy: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;\t")))
            for candidate in candidates {
                let cleaned = sanitizeURL(candidate).trimmingCharacters(in: CharacterSet(charactersIn: "(),[]"))
                guard cleaned.hasPrefix("http://") || cleaned.hasPrefix("https://"),
                      URL(string: cleaned) != nil else {
                    continue
                }
                if seen.insert(cleaned).inserted {
                    ordered.append(cleaned)
                }
            }
        }
        return ordered
    }

    public static func buildArguments(
        url: String,
        configuration: DownloadConfiguration,
        ffmpegPath: String? = nil,
        jsRuntimeArg: String? = nil,
        customFormatIsVideoOnly: Bool = false
    ) -> [String] {
        var args: [String] = ["--ignore-config", "--no-exec"]

        // Network reliability: avoid IPv6 blackholes on macOS networks & set bounded socket timeout.
        if let ipFlag = configuration.networkIPVersion.ytdlpFlag {
            args.append(ipFlag)
        }
        let timeout = max(5, min(120, configuration.socketTimeoutSeconds))
        args.append(contentsOf: ["--socket-timeout", "\(timeout)"])

        // Resume & bounded retry behavior
        args.append(configuration.resumePartialDownloads ? "--continue" : "--no-continue")
        if configuration.autoRetryCount > 0 {
            let retries = max(1, min(10, configuration.autoRetryCount))
            args.append(contentsOf: ["--retries", "\(retries)", "--fragment-retries", "\(retries)", "--retry-sleep", "exp=1:16"])
        }

        // Enable detected JS runtime (deno/bun/node/quickjs) for yt-dlp 2026+ YouTube EJS format resolution.
        if let jsRuntimeArg, !jsRuntimeArg.isEmpty {
            args.append(contentsOf: ["--js-runtimes", jsRuntimeArg])
        }

        // Always emit structured JSON progress, metadata & final path while actually downloading.
        args.append(contentsOf: [
            "--newline",
            "--no-colors",
            "--no-simulate",
            "--progress",
            "--progress-template",
            "download:VELORA_PROGRESS_JSON:%(progress.{status,downloaded_bytes,total_bytes,total_bytes_estimate,speed,eta,_percent_str,_speed_str,_eta_str})j",
            "--print", "before_dl:VELORA_META_JSON:%(.{title,uploader,channel,extractor_key,extractor,is_live})j",
            "--print", "after_move:VELORA_FILEPATH_JSON:%(.{filepath})j"
        ])

        // Point yt-dlp directly to ffmpeg/ffprobe so Finder-launched GUI apps always find them.
        if let ffmpegPath, !ffmpegPath.isEmpty {
            let dir = URL(fileURLWithPath: ffmpegPath).deletingLastPathComponent().path
            args.append(contentsOf: ["--ffmpeg-location", dir])
        }

        // Format selection
        appendFormatArguments(
            to: &args,
            configuration: configuration,
            customFormatIsVideoOnly: customFormatIsVideoOnly
        )

        // Subtitles
        switch configuration.subtitleMode {
        case .off:
            break
        case .preferredLanguages:
            args.append("--write-subs")
            if configuration.includeAutoSubtitles {
                args.append("--write-auto-subs")
            }
            let langs = configuration.subtitleLanguages.trimmingCharacters(in: .whitespacesAndNewlines)
            if !langs.isEmpty {
                args.append(contentsOf: ["--sub-langs", langs])
            }
            if configuration.embedSubtitles && configuration.mode != .audioOnly {
                args.append("--embed-subs")
            } else {
                args.append(contentsOf: ["--convert-subs", "srt"])
            }
        case .allAvailable:
            args.append(contentsOf: ["--write-subs", "--sub-langs", "all,-live_chat"])
            if configuration.embedSubtitles && configuration.mode != .audioOnly {
                args.append("--embed-subs")
            } else {
                args.append(contentsOf: ["--convert-subs", "srt"])
            }
        }

        // Post-processing & metadata
        let supportsEmbeddedThumbnail: Bool = switch configuration.mode {
        case .audioOnly:
            configuration.audioFormat != .wav && configuration.audioFormat != .aac
        case .videoOnly, .videoAndAudio:
            configuration.videoContainer != .webm
        }
        if configuration.embedThumbnail && supportsEmbeddedThumbnail {
            args.append("--embed-thumbnail")
        }
        if configuration.embedMetadata {
            args.append("--embed-metadata")
        }
        if configuration.embedChapters {
            args.append("--embed-chapters")
        }
        if configuration.splitChapters {
            args.append("--split-chapters")
        }

        // SponsorBlock
        switch configuration.sponsorBlock {
        case .off:
            break
        case .markAll:
            args.append(contentsOf: ["--sponsorblock-mark", "all"])
        case .removeSponsors:
            args.append(contentsOf: ["--sponsorblock-remove", "sponsor"])
        case .removeAllSegments:
            args.append(contentsOf: ["--sponsorblock-remove", "sponsor,intro,outro,selfpromo,interaction"])
        }

        // Clip / Time Range
        if configuration.clipEnabled {
            let start = configuration.clipStart.trimmingCharacters(in: .whitespacesAndNewlines)
            let end = configuration.clipEnd.trimmingCharacters(in: .whitespacesAndNewlines)
            if !start.isEmpty || !end.isEmpty {
                let startToken = start.isEmpty ? "0" : start
                let endToken = end.isEmpty ? "inf" : end
                args.append(contentsOf: ["--download-sections", "*\(startToken)-\(endToken)"])
                if configuration.forceKeyframesAtCuts {
                    args.append("--force-keyframes-at-cuts")
                }
            }
        }

        // Playlist behavior
        switch configuration.playlistBehavior {
        case .singleVideoOnly:
            args.append("--no-playlist")
        case .downloadEntirePlaylist:
            args.append("--yes-playlist")
            args.append("--ignore-errors")
            let items = configuration.playlistItems.trimmingCharacters(in: .whitespacesAndNewlines)
            if !items.isEmpty {
                args.append(contentsOf: ["--playlist-items", items])
            }
        }

        // Output destination & naming template
        let outputDir = (configuration.outputDirectoryPath as NSString).expandingTildeInPath
        args.append(contentsOf: ["-P", outputDir])

        let safeBaseTemplate = sanitizeFilenameTemplate(configuration.effectiveFilenameTemplate)
        let template: String
        if configuration.playlistBehavior == .downloadEntirePlaylist && configuration.createPlaylistSubfolder {
            args.append("--windows-filenames")
            template = "%(playlist_title,playlist)s/%(playlist_index)02d - \(safeBaseTemplate)"
        } else {
            template = safeBaseTemplate
        }
        args.append(contentsOf: ["-o", template])

        if configuration.restrictFilenames {
            args.append("--restrict-filenames")
        }
        if configuration.overwriteExisting {
            args.append("--force-overwrites")
        } else {
            args.append("--no-overwrites")
        }

        // Network & Authentication
        let fragments = max(1, min(16, configuration.concurrentFragments))
        if fragments > 1 {
            args.append(contentsOf: ["-N", "\(fragments)"])
        }

        let rateLimit = configuration.rateLimit.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rateLimit.isEmpty {
            args.append(contentsOf: ["-r", rateLimit])
        }

        let proxy = configuration.proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !proxy.isEmpty {
            args.append(contentsOf: ["--proxy", proxy])
        }

        if let cookieBrowser = configuration.browserCookies.ytdlpIdentifier {
            args.append(contentsOf: ["--cookies-from-browser", cookieBrowser])
        }

        let rawCookieFile = configuration.cookieFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawCookieFile.isEmpty {
            let expandedCookieFile = (rawCookieFile as NSString).expandingTildeInPath
            args.append(contentsOf: ["--cookies", expandedCookieFile])
        }

        // Power-user extra arguments (filtered against dangerous RCE/config flags)
        let extraTokens = sanitizeExtraArgumentTokens(tokenizeShellArguments(configuration.extraArguments))
        if !extraTokens.isEmpty {
            args.append(contentsOf: extraTokens)
        }

        args.append("--no-exec")
        args.append("--")
        args.append(sanitizeURL(url))
        return args
    }

    private static func appendFormatArguments(
        to args: inout [String],
        configuration: DownloadConfiguration,
        customFormatIsVideoOnly: Bool
    ) {
        if let customID = configuration.customFormatID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !customID.isEmpty {
            let selector: String
            if configuration.mode == .videoAndAudio && customFormatIsVideoOnly && !customID.contains("+") {
                selector = "\(customID)+bestaudio/best"
            } else {
                selector = customID
            }
            args.append(contentsOf: ["-f", selector])
            if configuration.mode == .videoAndAudio {
                args.append(contentsOf: ["--merge-output-format", configuration.videoContainer.rawValue])
            }
            return
        }

        switch configuration.mode {
        case .audioOnly:
            args.append(contentsOf: [
                "-f", "bestaudio/best",
                "-x",
                "--audio-format", configuration.audioFormat.rawValue,
                "--audio-quality", configuration.audioBitrate.rawValue
            ])

        case .videoOnly:
            let selector = buildVideoOnlySelector(configuration: configuration)
            args.append(contentsOf: ["-f", selector])
            appendSortFlags(to: &args, configuration: configuration)
            args.append(contentsOf: ["--remux-video", configuration.videoContainer.rawValue])

        case .videoAndAudio:
            let selector = buildVideoAndAudioSelector(configuration: configuration)
            args.append(contentsOf: ["-f", selector])
            appendSortFlags(to: &args, configuration: configuration)
            if configuration.videoContainer == .mov {
                args.append(contentsOf: ["--remux-video", "mov"])
            } else {
                args.append(contentsOf: ["--merge-output-format", configuration.videoContainer.rawValue])
            }
        }
    }

    private static func buildVideoFilterClause(configuration: DownloadConfiguration) -> String {
        var filters = ""
        if let maxHeight = configuration.videoQuality.maxHeight {
            filters += "[height<=\(maxHeight)]"
        }
        if let fpsCap = configuration.frameRateCap.numericCap {
            filters += "[fps<=\(fpsCap)]"
        }
        return filters
    }

    private static func buildVideoAndAudioSelector(configuration: DownloadConfiguration) -> String {
        if configuration.videoQuality == .worst {
            return "worstvideo+worstaudio/worst"
        }
        let filters = buildVideoFilterClause(configuration: configuration)
        return "bestvideo\(filters)+bestaudio/best\(filters)/best"
    }

    private static func buildVideoOnlySelector(configuration: DownloadConfiguration) -> String {
        if configuration.videoQuality == .worst {
            return "worstvideo/worst"
        }
        let filters = buildVideoFilterClause(configuration: configuration)
        return "bestvideo\(filters)/bestvideo"
    }

    private static func appendSortFlags(to args: inout [String], configuration: DownloadConfiguration) {
        var sortTokens: [String] = []
        if let maxHeight = configuration.videoQuality.maxHeight {
            sortTokens.append("res:\(maxHeight)")
        }

        switch configuration.videoContainer {
        case .mov:
            switch configuration.preferredCodec {
            case .auto, .hevc:
                sortTokens.append(contentsOf: ["vcodec:h265", "vcodec:h264", "acodec:aac", "ext:mp4:m4a"])
            case .h264:
                sortTokens.append(contentsOf: ["vcodec:h264", "vcodec:h265", "acodec:aac", "ext:mp4:m4a"])
            case .vp9, .av1:
                if let codecToken = configuration.preferredCodec.ytdlpSortToken {
                    sortTokens.append(codecToken)
                }
                sortTokens.append("ext:mp4:m4a")
            }
        case .mp4:
            if let codecToken = configuration.preferredCodec.ytdlpSortToken {
                sortTokens.append(codecToken)
            }
            sortTokens.append("ext:mp4:m4a")
        case .webm:
            if let codecToken = configuration.preferredCodec.ytdlpSortToken {
                sortTokens.append(codecToken)
            }
            sortTokens.append("ext:webm:opus")
        case .mkv:
            if let codecToken = configuration.preferredCodec.ytdlpSortToken {
                sortTokens.append(codecToken)
            }
        }

        if configuration.videoQuality == .best && !sortTokens.isEmpty {
            sortTokens.insert("res", at: 0)
        }

        if !sortTokens.isEmpty {
            args.append(contentsOf: ["-S", sortTokens.joined(separator: ",")])
        }
    }

    /// Generates a human-readable, copy-pasteable shell command preview.
    public static func shellPreview(
        ytdlpPath: String,
        url: String,
        configuration: DownloadConfiguration,
        ffmpegPath: String? = nil,
        jsRuntimeArg: String? = nil,
        customFormatIsVideoOnly: Bool = false
    ) -> String {
        let executable = ytdlpPath.isEmpty ? "yt-dlp" : ytdlpPath
        let sanitized = sanitizeURL(url)
        let displayURL = sanitized.isEmpty
            ? "https://www.youtube.com/watch?v=..."
            : sanitized
        let allArgs = buildArguments(
            url: displayURL,
            configuration: configuration,
            ffmpegPath: ffmpegPath,
            jsRuntimeArg: jsRuntimeArg,
            customFormatIsVideoOnly: customFormatIsVideoOnly
        )
            .filter { token in
                // Keep preview readable while preserving every meaningful option.
                !token.hasPrefix("download:VELORA_PROGRESS_JSON:") &&
                !token.hasPrefix("before_dl:VELORA_META_JSON:") &&
                !token.hasPrefix("after_move:VELORA_FILEPATH_JSON:") &&
                !token.hasPrefix("download:VELORA_PROGRESS|") &&
                !token.hasPrefix("before_dl:VELORA_META|") &&
                !token.hasPrefix("after_move:VELORA_FILEPATH|")
            }

        // Remove orphaned --progress-template and --print flags whose payloads were filtered above.
        var cleaned: [String] = [executable]
        var index = 0
        while index < allArgs.count {
            let arg = allArgs[index]
            if arg == "--progress-template" || arg == "--print" {
                index += 1
                continue
            }
            if arg == "--newline" || arg == "--no-colors" || arg == "--no-simulate" {
                index += 1
                continue
            }
            cleaned.append(shellQuote(arg))
            index += 1
        }
        return cleaned.joined(separator: " ")
    }

    public static func shellQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        let safeCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._/:@=+,%"))
        if value.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return value
        }
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    /// Splits a string of shell-like CLI arguments respecting single/double quotes and backslash escapes.
    public static func tokenizeShellArguments(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var escaping = false

        for ch in input {
            if escaping {
                current.append(ch)
                escaping = false
                continue
            }
            if ch == "\\" && !inSingleQuote {
                escaping = true
                continue
            }
            if ch == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                continue
            }
            if ch == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                continue
            }
            if ch.isWhitespace && !inSingleQuote && !inDoubleQuote {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}
