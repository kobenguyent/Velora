import Foundation

/// Pure command-line builder that translates `DownloadConfiguration` into exact `yt-dlp` arguments.
public enum YTDLPCommandBuilder {

    public static func sanitizeURL(_ rawURL: String) -> String {
        var cleaned = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if (cleaned.hasPrefix("<") && cleaned.hasSuffix(">")) ||
           (cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"")) ||
           (cleaned.hasPrefix("'") && cleaned.hasSuffix("'")) {
            cleaned = String(cleaned.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
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
        jsRuntimeArg: String? = nil
    ) -> [String] {
        var args: [String] = []

        // Network reliability: avoid IPv6 blackholes on macOS networks & set bounded socket timeout.
        if let ipFlag = configuration.networkIPVersion.ytdlpFlag {
            args.append(ipFlag)
        }
        let timeout = max(5, min(120, configuration.socketTimeoutSeconds))
        args.append(contentsOf: ["--socket-timeout", "\(timeout)"])

        // Enable detected JS runtime (deno/bun/node/quickjs) for yt-dlp 2026+ YouTube EJS format resolution.
        if let jsRuntimeArg, !jsRuntimeArg.isEmpty {
            args.append(contentsOf: ["--js-runtimes", jsRuntimeArg])
        }

        // Always emit structured progress & final path while actually downloading.
        args.append(contentsOf: [
            "--newline",
            "--no-colors",
            "--no-simulate",
            "--progress",
            "--progress-template",
            "download:VELORA_PROGRESS|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(progress._total_bytes_estimate_str)s|%(progress._downloaded_bytes_str)s",
            "--print", "before_dl:VELORA_META|%(title)s|%(uploader)s|%(extractor)s",
            "--print", "after_move:VELORA_FILEPATH|%(filepath)s"
        ])

        // Point yt-dlp directly to ffmpeg/ffprobe so Finder-launched GUI apps always find them.
        if let ffmpegPath, !ffmpegPath.isEmpty {
            let dir = URL(fileURLWithPath: ffmpegPath).deletingLastPathComponent().path
            args.append(contentsOf: ["--ffmpeg-location", dir])
        }

        // Format selection
        appendFormatArguments(to: &args, configuration: configuration)

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
            args.append("--all-subs")
            if configuration.includeAutoSubtitles {
                args.append("--write-auto-subs")
            }
            if configuration.embedSubtitles && configuration.mode != .audioOnly {
                args.append("--embed-subs")
            }
        }

        // Post-processing & metadata
        if configuration.embedThumbnail {
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

        let template: String
        if configuration.playlistBehavior == .downloadEntirePlaylist && configuration.createPlaylistSubfolder {
            template = "%(playlist_title,playlist)s/%(playlist_index)02d - \(configuration.effectiveFilenameTemplate)"
        } else {
            template = configuration.effectiveFilenameTemplate
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

        // Power-user extra arguments
        let extraTokens = tokenizeShellArguments(configuration.extraArguments)
        if !extraTokens.isEmpty {
            args.append(contentsOf: extraTokens)
        }

        args.append("--")
        args.append(sanitizeURL(url))
        return args
    }

    private static func appendFormatArguments(
        to args: inout [String],
        configuration: DownloadConfiguration
    ) {
        if let customID = configuration.customFormatID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !customID.isEmpty {
            args.append(contentsOf: ["-f", customID])
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
        if let codecToken = configuration.preferredCodec.ytdlpSortToken {
            sortTokens.append(codecToken)
        }
        switch configuration.videoContainer {
        case .mp4, .mov:
            sortTokens.append("ext:mp4:m4a")
        case .webm:
            sortTokens.append("ext:webm:opus")
        case .mkv:
            break
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
        jsRuntimeArg: String? = nil
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
            jsRuntimeArg: jsRuntimeArg
        )
            .filter { token in
                // Keep preview readable while preserving every meaningful option.
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
