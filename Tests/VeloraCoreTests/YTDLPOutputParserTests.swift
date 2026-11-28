import Testing
@testable import VeloraCore

@Suite("yt-dlp Output Parser")
struct YTDLPOutputParserTests {
    @Test("Parses Velora structured progress line")
    func structuredProgressParsing() {
        let line = "VELORA_PROGRESS| 42.5%|  9.34MiB/s|00:12| 180.40MiB| 76.67MiB"
        let event = YTDLPOutputParser.parse(line: line)
        #expect(event == .progress(fraction: 0.425, speed: "9.34MiB/s", eta: "00:12", totalSize: "180.40MiB"))
    }

    @Test("Parses standard yt-dlp progress line fallback")
    func standardProgressFallbackParsing() {
        let line = "[download]  75.0% of ~52.40MiB at    4.12MiB/s ETA 00:03"
        let event = YTDLPOutputParser.parse(line: line)
        #expect(event == .progress(fraction: 0.75, speed: "4.12MiB/s", eta: "00:03", totalSize: "52.40MiB"))
    }

    @Test("Parses final filepath, metadata, post-processing stages, and errors")
    func finalPathMetadataAndPostProcessingParsing() {
        #expect(
            YTDLPOutputParser.parse(line: "VELORA_FILEPATH|/Users/test/Downloads/Velora/Demo.mp4")
            == .finalFilePath(path: "/Users/test/Downloads/Velora/Demo.mp4")
        )

        #expect(
            YTDLPOutputParser.parse(line: "VELORA_META|Swift 6 Deep Dive|Apple Developer|Youtube")
            == .metadata(title: "Swift 6 Deep Dive", uploader: "Apple Developer", extractor: "Youtube")
        )

        #expect(
            YTDLPOutputParser.parse(line: #"[Merger] Merging formats into "/tmp/video.mkv""#)
            == .destination(path: "/tmp/video.mkv")
        )

        #expect(
            YTDLPOutputParser.parse(line: "[EmbedThumbnail] mutagen: Adding thumbnail to video.mp4")
            == .postProcessing(stage: "Embedding cover artwork…")
        )

        #expect(
            YTDLPOutputParser.parse(line: "ERROR: Private video. Sign in if you've been granted access")
            == .error(message: "Private video. Sign in if you've been granted access")
        )
    }

    @Test("Parses VELORA_META_JSON including pipes, emojis, and channel fallback")
    func jsonMetadataParsing() {
        let line = #"VELORA_META_JSON:{"title":"Part 1 | Swift 6 🚀","uploader":null,"channel":"SwiftOrg","extractor_key":"Youtube","extractor":"youtube","is_live":false}"#
        let event = YTDLPOutputParser.parse(line: line)
        #expect(event == .metadata(title: "Part 1 | Swift 6 🚀", uploader: "SwiftOrg", extractor: "Youtube"))
    }

    @Test("Parses VELORA_PROGRESS_JSON with exact numeric bytes, estimates, and live indeterminate streams")
    func jsonProgressParsing() {
        let exactLine = #"VELORA_PROGRESS_JSON:{"status":"downloading","downloaded_bytes":50000000,"total_bytes":100000000,"total_bytes_estimate":null,"speed":5000000,"eta":10,"_percent_str":" 50.0%","_speed_str":"  5.00MB/s","_eta_str":"00:10"}"#
        let exactEvent = YTDLPOutputParser.parse(line: exactLine)
        if case let .progress(fraction, speed, eta, totalSize) = exactEvent {
            #expect(abs(fraction - 0.5) < 0.001)
            #expect(speed != nil)
            #expect(eta == "00:10")
            #expect(totalSize != nil)
        } else {
            Issue.record("Expected .progress event for exact JSON, got \(exactEvent)")
        }

        let estimateLine = #"VELORA_PROGRESS_JSON:{"status":"downloading","downloaded_bytes":25000000,"total_bytes":null,"total_bytes_estimate":100000000,"speed":2500000,"eta":30}"#
        let estimateEvent = YTDLPOutputParser.parse(line: estimateLine)
        if case let .progress(fraction, speed, eta, totalSize) = estimateEvent {
            #expect(abs(fraction - 0.25) < 0.001)
            #expect(speed != nil)
            #expect(eta == "00:30")
            #expect(totalSize != nil)
        } else {
            Issue.record("Expected .progress event for estimate JSON, got \(estimateEvent)")
        }

        let liveLine = #"VELORA_PROGRESS_JSON:{"status":"downloading","downloaded_bytes":4194304,"total_bytes":null,"total_bytes_estimate":null,"speed":1048576,"eta":null,"_percent_str":"N/A","_speed_str":"Unknown B/s","_eta_str":"Unknown"}"#
        let liveEvent = YTDLPOutputParser.parse(line: liveLine)
        if case let .progress(fraction, speed, eta, totalSize) = liveEvent {
            #expect(fraction == 0)
            #expect(speed != nil)
            #expect(eta == "Live")
            #expect(totalSize != nil)
        } else {
            Issue.record("Expected .progress event for live JSON, got \(liveEvent)")
        }
    }

    @Test("Parses VELORA_FILEPATH_JSON including pipes in filenames")
    func jsonFilepathParsing() {
        let line = #"VELORA_FILEPATH_JSON:{"filepath":"/Users/test/Downloads/Velora/Part 1 | Demo.mp4"}"#
        #expect(
            YTDLPOutputParser.parse(line: line)
            == .finalFilePath(path: "/Users/test/Downloads/Velora/Part 1 | Demo.mp4")
        )
    }
}
