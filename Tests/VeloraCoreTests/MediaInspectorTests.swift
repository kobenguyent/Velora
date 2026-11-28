import Foundation
import Testing
@testable import VeloraCore

@Suite("Media Inspector")
struct MediaInspectorTests {

    @Test("Rejects non-http(s) and malformed URLs before launching yt-dlp")
    func rejectsUnsafeURLs() async {
        for badURL in ["", "file:///etc/passwd", "ftp://example.com/a.mp4", "javascript:alert(1)", "https://example.com/with space"] {
            await #expect(throws: MediaInspectorError.self) {
                try await MediaInspector.inspect(url: badURL, ytdlpPath: "/usr/bin/true")
            }
        }
    }

    @Test("Skips leading non-JSON warning lines and decodes isLive")
    func decodesLeadingWarningsAndIsLive() throws {
        let outputWithWarnings = """
        WARNING: [youtube] Falling back to generic client
        [debug] Some non-JSON chatter
        {"id":"live123","title":"24/7 Lo-Fi Stream","is_live":true,"uploader":"Beats"}
        """.data(using: .utf8)!

        let info = try MediaInspector.decodeMetadata(
            from: outputWithWarnings,
            fallbackURL: "https://www.youtube.com/watch?v=live123"
        )
        #expect(info.title == "24/7 Lo-Fi Stream")
        #expect(info.isLive)

        let liveStatusJSON = #"{"id":"live456","title":"Event","live_status":"is_live"}"#.data(using: .utf8)!
        let liveStatusInfo = try MediaInspector.decodeMetadata(
            from: liveStatusJSON,
            fallbackURL: "https://www.youtube.com/watch?v=live456"
        )
        #expect(liveStatusInfo.isLive)

        let vodJSON = #"{"id":"vod789","title":"Recorded Talk"}"#.data(using: .utf8)!
        let vodInfo = try MediaInspector.decodeMetadata(
            from: vodJSON,
            fallbackURL: "https://www.youtube.com/watch?v=vod789"
        )
        #expect(!vodInfo.isLive)
    }

    @Test("Passes --ignore-config, --no-exec, and -- before URL when inspecting")
    func inspectPassesHardenedFlags() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("velora-inspector-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let mockScript = workspace.appendingPathComponent("mock-yt-dlp")
        let script = """
        #!/bin/sh
        has_ignore=0
        has_no_exec=0
        has_sep=0
        for arg in "$@"; do
          if [ "$arg" = "--ignore-config" ]; then has_ignore=1; fi
          if [ "$arg" = "--no-exec" ]; then has_no_exec=1; fi
          if [ "$arg" = "--" ]; then has_sep=1; fi
        done
        if [ "$has_ignore" -ne 1 ] || [ "$has_no_exec" -ne 1 ] || [ "$has_sep" -ne 1 ]; then
          echo "missing hardened flags" >&2
          exit 2
        fi
        printf '{"id":"vid1","title":"Hardened Inspect","is_live":false}\n'
        """
        try script.write(to: mockScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockScript.path)

        let info = try await MediaInspector.inspect(
            url: "https://www.youtube.com/watch?v=vid1",
            ytdlpPath: mockScript.path
        )
        #expect(info.id == "vid1")
        #expect(info.title == "Hardened Inspect")
        #expect(!info.isLive)
    }
}
