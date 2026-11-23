import Foundation

public enum YTDLPOutputEvent: Sendable, Equatable {
    case metadata(title: String, uploader: String?, extractor: String?)
    case playlistItemProgress(current: Int, total: Int)
    case progress(fraction: Double, speed: String?, eta: String?, totalSize: String?)
    case postProcessing(stage: String)
    case destination(path: String)
    case finalFilePath(path: String)
    case error(message: String)
    case log(line: String)
}

/// Parses both structured Velora templates and standard `yt-dlp` console output lines.
public enum YTDLPOutputParser {

    public static func parse(line rawLine: String) -> YTDLPOutputEvent {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return .log(line: "") }

        // 1. Structured progress template:
        // VELORA_PROGRESS| 42.3%|  8.42MiB/s|00:08| 120.50MiB| 50.97MiB
        if line.hasPrefix("VELORA_PROGRESS|") {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
            if parts.count >= 5 {
                let pctString = parts[1].replacingOccurrences(of: "%", with: "")
                if let pct = Double(pctString) {
                    let fraction = max(0.0, min(1.0, pct / 100.0))
                    let speed = cleanMetric(parts[2])
                    let eta = cleanMetric(parts[3])
                    let size = cleanMetric(parts[4])
                    return .progress(fraction: fraction, speed: speed, eta: eta, totalSize: size)
                }
            }
        }

        // 2. Structured final filepath:
        if line.hasPrefix("VELORA_FILEPATH|") {
            let path = String(line.dropFirst("VELORA_FILEPATH|".count)).trimmingCharacters(in: .whitespaces)
            if !path.isEmpty && path != "NA" {
                return .finalFilePath(path: path)
            }
        }

        // 3. Structured metadata line:
        if line.hasPrefix("VELORA_META|") {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
            if parts.count >= 4 {
                let title = parts[1]
                let uploader = cleanMetric(parts[2])
                let extractor = cleanMetric(parts[3])
                if !title.isEmpty && title != "NA" {
                    return .metadata(title: title, uploader: uploader, extractor: extractor)
                }
            }
        }

        // 4. Error lines
        if line.hasPrefix("ERROR:") {
            let msg = String(line.dropFirst("ERROR:".count)).trimmingCharacters(in: .whitespaces)
            return .error(message: msg)
        }

        // 4.5 Playlist item progress: "[download] Downloading item 3 of 25" or "Downloading video 3 of 25"
        if line.hasPrefix("[download]"), let playlistEvent = parsePlaylistItemProgress(line) {
            return playlistEvent
        }

        // 5. Standard yt-dlp progress fallback:
        // [download]  42.3% of  120.50MiB at    8.42MiB/s ETA 00:08
        if line.hasPrefix("[download]"), let parsed = parseStandardDownloadProgress(line) {
            return parsed
        }

        // 6. Destination & Merger output paths
        if line.hasPrefix("[Merger] Merging formats into \"") && line.hasSuffix("\"") {
            let start = line.index(line.startIndex, offsetBy: "[Merger] Merging formats into \"".count)
            let end = line.index(before: line.endIndex)
            return .destination(path: String(line[start..<end]))
        }
        if line.hasPrefix("[ExtractAudio] Destination: ") {
            let path = String(line.dropFirst("[ExtractAudio] Destination: ".count))
            return .destination(path: path)
        }
        if line.hasPrefix("[download] Destination: ") {
            let path = String(line.dropFirst("[download] Destination: ".count))
            return .destination(path: path)
        }
        if line.hasPrefix("[download] ") && line.hasSuffix(" has already been downloaded") {
            let trimmed = line
                .dropFirst("[download] ".count)
                .dropLast(" has already been downloaded".count)
            return .finalFilePath(path: String(trimmed))
        }

        // 7. Post-processing phases
        if line.hasPrefix("[Merger]") {
            return .postProcessing(stage: "Merging video & audio streams…")
        }
        if line.hasPrefix("[VideoRemuxer]") || line.hasPrefix("[VideoConvertor]") {
            return .postProcessing(stage: "Remuxing container…")
        }
        if line.hasPrefix("[ExtractAudio]") {
            return .postProcessing(stage: "Extracting audio track…")
        }
        if line.hasPrefix("[EmbedThumbnail]") {
            return .postProcessing(stage: "Embedding cover artwork…")
        }
        if line.hasPrefix("[EmbedSubtitle]") {
            return .postProcessing(stage: "Embedding subtitles…")
        }
        if line.hasPrefix("[Metadata]") {
            return .postProcessing(stage: "Writing metadata & chapters…")
        }
        if line.hasPrefix("[SponsorBlock]") || line.hasPrefix("[ModifyChapters]") {
            return .postProcessing(stage: "Applying SponsorBlock chapters…")
        }

        return .log(line: line)
    }

    private static func cleanMetric(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == "NA" || trimmed == "N/A" || trimmed == "Unknown" || trimmed == "~" {
            return nil
        }
        return trimmed
    }

    private static func parsePlaylistItemProgress(_ line: String) -> YTDLPOutputEvent? {
        let pattern = #"\[download\]\s+Downloading\s+(?:item|video)\s+(\d+)\s+of\s+(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let currentRange = Range(match.range(at: 1), in: line),
              let totalRange = Range(match.range(at: 2), in: line),
              let current = Int(line[currentRange]),
              let total = Int(line[totalRange]),
              total > 0 else {
            return nil
        }
        return .playlistItemProgress(current: current, total: total)
    }

    private static func parseStandardDownloadProgress(_ line: String) -> YTDLPOutputEvent? {
        // Regex for "[download]  42.3% of ~120.50MiB at 8.42MiB/s ETA 00:08"
        let pattern = #"\[download\]\s+(\d+(?:\.\d+)?)%\s+of\s+~?(\S+)(?:\s+at\s+(\S+))?(?:\s+ETA\s+(\S+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let pctRange = Range(match.range(at: 1), in: line),
              let pct = Double(line[pctRange]) else {
            return nil
        }

        let size: String? = Range(match.range(at: 2), in: line).flatMap { cleanMetric(String(line[$0])) }
        let speed: String? = Range(match.range(at: 3), in: line).flatMap { cleanMetric(String(line[$0])) }
        let eta: String? = Range(match.range(at: 4), in: line).flatMap { cleanMetric(String(line[$0])) }

        return .progress(
            fraction: max(0.0, min(1.0, pct / 100.0)),
            speed: speed,
            eta: eta,
            totalSize: size
        )
    }
}
