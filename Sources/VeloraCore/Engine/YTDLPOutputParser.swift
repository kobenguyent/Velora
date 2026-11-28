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

        // 1. JSON structured progress template:
        // VELORA_PROGRESS_JSON:{"status":"downloading","downloaded_bytes":...}
        if line.hasPrefix("VELORA_PROGRESS_JSON:") {
            let jsonPart = String(line.dropFirst("VELORA_PROGRESS_JSON:".count)).trimmingCharacters(in: .whitespaces)
            if let event = parseProgressJSON(jsonPart) {
                return event
            }
        }

        // 1b. Legacy pipe-delimited progress template:
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

        // 2. JSON structured final filepath:
        if line.hasPrefix("VELORA_FILEPATH_JSON:") {
            let jsonPart = String(line.dropFirst("VELORA_FILEPATH_JSON:".count)).trimmingCharacters(in: .whitespaces)
            if let data = jsonPart.data(using: .utf8),
               let payload = try? JSONDecoder().decode(FilepathJSONPayload.self, from: data),
               let path = payload.filepath.flatMap(cleanMetric) {
                return .finalFilePath(path: path)
            }
        }

        // 2b. Legacy structured final filepath:
        if line.hasPrefix("VELORA_FILEPATH|") {
            let path = String(line.dropFirst("VELORA_FILEPATH|".count)).trimmingCharacters(in: .whitespaces)
            if !path.isEmpty && path != "NA" {
                return .finalFilePath(path: path)
            }
        }

        // 3. JSON structured metadata line:
        if line.hasPrefix("VELORA_META_JSON:") {
            let jsonPart = String(line.dropFirst("VELORA_META_JSON:".count)).trimmingCharacters(in: .whitespaces)
            if let data = jsonPart.data(using: .utf8),
               let payload = try? JSONDecoder().decode(MetaJSONPayload.self, from: data),
               let rawTitle = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines),
               !rawTitle.isEmpty && rawTitle != "NA" {
                let uploader = payload.uploader.flatMap(cleanMetric) ?? payload.channel.flatMap(cleanMetric)
                let extractor = payload.extractor_key.flatMap(cleanMetric) ?? payload.extractor.flatMap(cleanMetric)
                return .metadata(title: rawTitle, uploader: uploader, extractor: extractor)
            }
        }

        // 3b. Legacy structured metadata line:
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

    private struct MetaJSONPayload: Decodable {
        let title: String?
        let uploader: String?
        let channel: String?
        let extractor_key: String?
        let extractor: String?
        let is_live: Bool?
    }

    private struct FilepathJSONPayload: Decodable {
        let filepath: String?
    }

    private struct ProgressJSONPayload: Decodable {
        let status: String?
        let downloaded_bytes: Double?
        let total_bytes: Double?
        let total_bytes_estimate: Double?
        let speed: Double?
        let eta: Double?
        let _percent_str: String?
        let _speed_str: String?
        let _eta_str: String?
    }

    private static func parseProgressJSON(_ jsonString: String) -> YTDLPOutputEvent? {
        guard let data = jsonString.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ProgressJSONPayload.self, from: data) else {
            return nil
        }

        let speedText = formatSpeed(payload.speed) ?? payload._speed_str.flatMap(cleanMetric)
        let totalBytes = payload.total_bytes ?? payload.total_bytes_estimate

        if payload.status == "finished" {
            let finalSize = formatBytes(totalBytes ?? payload.downloaded_bytes)
            return .progress(fraction: 1.0, speed: speedText, eta: "00:00", totalSize: finalSize)
        }

        if let total = totalBytes, total > 0 {
            let fraction: Double
            if let downloaded = payload.downloaded_bytes {
                fraction = max(0.0, min(1.0, downloaded / total))
            } else if let pct = parsePercent(payload._percent_str) {
                fraction = max(0.0, min(1.0, pct / 100.0))
            } else {
                fraction = 0.0
            }
            let etaText = formatETA(payload.eta) ?? payload._eta_str.flatMap(cleanMetric)
            return .progress(fraction: fraction, speed: speedText, eta: etaText, totalSize: formatBytes(total))
        }

        if let pct = parsePercent(payload._percent_str) {
            let etaText = formatETA(payload.eta) ?? payload._eta_str.flatMap(cleanMetric)
            return .progress(
                fraction: max(0.0, min(1.0, pct / 100.0)),
                speed: speedText,
                eta: etaText,
                totalSize: formatBytes(payload.downloaded_bytes)
            )
        }

        // Indeterminate / live stream progress when neither total_bytes nor total_bytes_estimate is known
        let etaText = formatETA(payload.eta) ?? payload._eta_str.flatMap(cleanMetric) ?? "Live"
        return .progress(
            fraction: 0.0,
            speed: speedText,
            eta: etaText,
            totalSize: formatBytes(payload.downloaded_bytes)
        )
    }

    private static func parsePercent(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let cleaned = raw.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }

    private static func formatBytes(_ bytes: Double?) -> String? {
        guard let bytes, bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes.rounded()), countStyle: .file)
    }

    private static func formatSpeed(_ bytesPerSecond: Double?) -> String? {
        guard let bytesPerSecond, bytesPerSecond > 0 else { return nil }
        let formatted = ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond.rounded()), countStyle: .file)
        return "\(formatted)/s"
    }

    private static func formatETA(_ seconds: Double?) -> String? {
        guard let seconds, seconds >= 0 else { return nil }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private static func cleanMetric(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty ||
           trimmed == "NA" ||
           trimmed == "N/A" ||
           trimmed == "Unknown" ||
           trimmed == "Unknown B/s" ||
           trimmed == "~" {
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
