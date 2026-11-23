import Foundation
import Testing
@testable import VeloraCore

@Suite("Bulk & Playlist Downloads")
struct BulkPlaylistTests {

    @Test("Detects pure playlist/channel URLs and linked playlists on watch URLs")
    func playlistURLDetection() {
        #expect(PlaylistURLDetector.isPurePlaylistURL("https://www.youtube.com/playlist?list=PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI"))
        #expect(PlaylistURLDetector.isPurePlaylistURL("https://www.youtube.com/@Apple/videos"))
        #expect(PlaylistURLDetector.isPurePlaylistURL("https://soundcloud.com/artist/sets/summer-mix"))
        #expect(PlaylistURLDetector.isPurePlaylistURL("https://vimeo.com/showcase/123456"))

        // Single video URLs (even with list=) are NOT pure playlists
        let hybridWatchURL = "https://www.youtube.com/watch?v=PU9L0rfejSw&list=PL123456789&index=2"
        #expect(!PlaylistURLDetector.isPurePlaylistURL(hybridWatchURL))
        #expect(!PlaylistURLDetector.isPurePlaylistURL("https://youtu.be/PU9L0rfejSw?si=B2frSJIR34ThGFIl"))

        // Linked playlist extraction works on watch?v=...&list=... and youtu.be/...?list=...
        #expect(
            PlaylistURLDetector.extractLinkedPlaylistURL(from: hybridWatchURL)
            == "https://www.youtube.com/playlist?list=PL123456789"
        )
        #expect(
            PlaylistURLDetector.extractLinkedPlaylistURL(from: "https://youtu.be/PU9L0rfejSw?list=PLXYZ")
            == "https://www.youtube.com/playlist?list=PLXYZ"
        )
        #expect(PlaylistURLDetector.extractLinkedPlaylistURL(from: "https://youtu.be/PU9L0rfejSw") == nil)
    }

    @Test("Parses bulk selection range expressions accurately")
    func selectionRangeParsing() {
        #expect(PlaylistURLDetector.parseSelectionRange("1-3, 5, 8-10", maxIndex: 12) == [1, 2, 3, 5, 8, 9, 10])
        #expect(PlaylistURLDetector.parseSelectionRange("-3", maxIndex: 10) == [1, 2, 3])
        #expect(PlaylistURLDetector.parseSelectionRange("8-", maxIndex: 10) == [8, 9, 10])
        #expect(PlaylistURLDetector.parseSelectionRange("5-3", maxIndex: 10) == [3, 4, 5])
        #expect(PlaylistURLDetector.parseSelectionRange("99-120", maxIndex: 10) == [])
    }

    @Test("Sanitizes playlist titles into safe macOS folder names")
    func folderNameSanitization() {
        #expect(PlaylistURLDetector.sanitizeFolderName("SwiftUI / macOS: 2026 Talks") == "SwiftUI - macOS - 2026 Talks")
        #expect(PlaylistURLDetector.sanitizeFolderName("...   ") == "Playlist")
    }

    @Test("Extracts, cleans, and deduplicates bulk URLs from text and CSV lists")
    func bulkURLExtraction() {
        let input = """
        # My YouTube batch
        https://youtu.be/PU9L0rfejSw?si=abc
        <https://www.youtube.com/playlist?list=PL123>, "https://vimeo.com/12345"
        https://youtu.be/PU9L0rfejSw?si=abc
        not-a-url
        """
        let extracted = YTDLPCommandBuilder.extractURLs(from: input)
        #expect(extracted == [
            "https://youtu.be/PU9L0rfejSw?si=abc",
            "https://www.youtube.com/playlist?list=PL123",
            "https://vimeo.com/12345"
        ])
    }

    @Test("Decodes flat-playlist JSON entries including availability, URLs, and total duration")
    func flatPlaylistJSONDecoding() throws {
        let json = """
        {
          "_type": "playlist",
          "id": "PLdemo123",
          "title": "Swift Concurrency Mastery",
          "uploader": "Swift Academy",
          "extractor_key": "YoutubeTab",
          "playlist_count": 3,
          "entries": [
            {
              "id": "vid1",
              "title": "Part 1: Structured Concurrency",
              "url": "https://www.youtube.com/watch?v=vid1",
              "duration": 600,
              "channel": "Swift Academy",
              "thumbnails": [{"url": "https://i.ytimg.com/vi/vid1/default.jpg"}]
            },
            {
              "id": "vid2",
              "title": "[Private video]",
              "url": "vid2",
              "ie_key": "Youtube",
              "availability": "private"
            },
            {
              "id": "vid3",
              "title": "Part 3: Actors & Sendable",
              "url": "vid3",
              "ie_key": "Youtube",
              "duration": 3600,
              "uploader": "Swift Academy"
            }
          ]
        }
        """.data(using: .utf8)!

        let info = try MediaInspector.decodeMetadata(
            from: json,
            fallbackURL: "https://www.youtube.com/playlist?list=PLdemo123"
        )

        #expect(info.isPlaylist)
        #expect(info.playlistEntries.count == 3)
        #expect(info.availablePlaylistEntries.count == 2)
        #expect(info.playlistEntries[1].isUnavailable)
        #expect(info.playlistEntries[2].url == "https://www.youtube.com/watch?v=vid3")
        #expect(info.thumbnailURL == "https://i.ytimg.com/vi/vid1/default.jpg")
        #expect(info.totalPlaylistDurationFormatted == "1h 10m")
    }

    @Test("Parses multi-item yt-dlp playlist progress lines and adds --ignore-errors for direct playlists")
    func playlistProgressAndIgnoreErrors() {
        #expect(
            YTDLPOutputParser.parse(line: "[download] Downloading item 3 of 25")
            == .playlistItemProgress(current: 3, total: 25)
        )
        #expect(
            YTDLPOutputParser.parse(line: "[download] Downloading video 4 of 10")
            == .playlistItemProgress(current: 4, total: 10)
        )

        var config = DownloadConfiguration()
        config.playlistBehavior = .downloadEntirePlaylist
        let args = YTDLPCommandBuilder.buildArguments(
            url: "https://www.youtube.com/playlist?list=PLdemo",
            configuration: config
        )
        #expect(args.contains("--yes-playlist"))
        #expect(args.contains("--ignore-errors"))
    }
}
