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
}
