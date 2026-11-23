import AppKit
import SwiftUI
import VeloraCore

@main
struct VeloraApp: App {
    @NSApplicationDelegateAdaptor(VeloraAppDelegate.self) private var appDelegate

    @State private var engineManager: EngineManager
    @State private var downloadManager: DownloadManager
    @State private var updateChecker: UpdateChecker
    @State private var studioState: StudioViewModel

    init() {
        let engine = EngineManager()
        let store = VeloraStore()
        let downloads = DownloadManager(engineManager: engine, store: store)
        let updates = UpdateChecker()
        let studio = StudioViewModel(store: store)

        _engineManager = State(initialValue: engine)
        _downloadManager = State(initialValue: downloads)
        _updateChecker = State(initialValue: updates)
        _studioState = State(initialValue: studio)
    }

    var body: some Scene {
        WindowGroup("Velora") {
            MainWindowView(
                engineManager: engineManager,
                downloadManager: downloadManager,
                updateChecker: updateChecker,
                studio: studioState
            )
            .frame(minWidth: 960, minHeight: 640)
            .task {
                await engineManager.refresh()
                await updateChecker.performLaunchCheckIfEnabled()
            }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1120, height: 740)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task {
                        await updateChecker.checkForUpdates(userInitiated: true)
                    }
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])

                Button("Engine Setup…") {
                    studioState.isShowingEngineSetup = true
                }
            }

            CommandMenu("Downloads") {
                Button("Paste URL & Inspect") {
                    studioState.pasteFromClipboardAndInspect(engineManager: engineManager)
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])

                Button("Start Download") {
                    studioState.startDownload(downloadManager: downloadManager, engineManager: engineManager)
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!studioState.canDownload || studioState.isExpandingBulk)

                Divider()

                Button("Clear Completed Queue Items") {
                    downloadManager.clearFinished()
                }
                .disabled(downloadManager.queue.isEmpty)

                Button("Open Output Folder") {
                    let expanded = (studioState.configuration.outputDirectoryPath as NSString).expandingTildeInPath
                    try? FileManager.default.createDirectory(atPath: expanded, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView(
                engineManager: engineManager,
                downloadManager: downloadManager,
                updateChecker: updateChecker,
                studio: studioState
            )
        }
    }
}

final class VeloraAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure bare `swift run` launches also activate properly as a foreground macOS GUI app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@MainActor
@Observable
final class StudioViewModel {
    var urlInput: String = ""
    var isBatchMode: Bool = false
    var configuration: DownloadConfiguration {
        didSet {
            store.saveLastConfiguration(configuration)
        }
    }

    var inspectedMedia: MediaInfo?
    var isInspecting: Bool = false
    var inspectionError: String?
    var isShowingFormatPicker: Bool = false
    var isShowingPlaylistPicker: Bool = false
    var isShowingEngineSetup: Bool = false
    var isShowingSavePresetSheet: Bool = false
    var expandPlaylistsInBatch: Bool = true
    var isExpandingBulk: Bool = false
    var bulkExpansionStatus: String = ""
    var toastMessage: String?

    private let store: VeloraStore
    private var inspectTask: Task<Void, Never>?

    var canDownload: Bool {
        !urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var detectedBatchURLs: [String] {
        YTDLPCommandBuilder.extractURLs(from: urlInput)
    }

    var detectedBatchPlaylistCount: Int {
        detectedBatchURLs.filter { PlaylistURLDetector.isPurePlaylistURL($0) }.count
    }

    init(store: VeloraStore = VeloraStore()) {
        self.store = store
        self.configuration = store.loadLastConfiguration()
    }

    func applyPreset(_ preset: DownloadPreset) {
        let currentOutDir = configuration.outputDirectoryPath
        var updated = preset.configuration
        updated.outputDirectoryPath = currentOutDir
        configuration = updated
        showToast("Applied preset: \(preset.name)")
    }

    func cancelInspection() {
        inspectTask?.cancel()
        inspectTask = nil
        isInspecting = false
    }

    func startInspectingCurrentURL(
        engineManager: EngineManager,
        playlistMode: PlaylistInspectMode = .automatic
    ) {
        inspectTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.inspectCurrentURL(engineManager: engineManager, playlistMode: playlistMode)
        }
        inspectTask = task
    }

    func loadLinkedPlaylist(engineManager: EngineManager) {
        if let linked = inspectedMedia?.linkedPlaylistURL {
            urlInput = linked
        }
        startInspectingCurrentURL(engineManager: engineManager, playlistMode: .forcePlaylist)
    }

    func inspectCurrentURL(
        engineManager: EngineManager,
        playlistMode: PlaylistInspectMode = .automatic
    ) async {
        let trimmed = YTDLPCommandBuilder.sanitizeURL(urlInput)
        guard !trimmed.isEmpty else { return }

        isInspecting = true
        inspectionError = nil
        inspectedMedia = nil

        let effectiveMode: PlaylistInspectMode
        if playlistMode == .automatic && configuration.playlistBehavior == .downloadEntirePlaylist && PlaylistURLDetector.extractLinkedPlaylistURL(from: trimmed) != nil {
            effectiveMode = .forcePlaylist
        } else {
            effectiveMode = playlistMode
        }

        do {
            let info = try await MediaInspector.inspect(
                url: trimmed,
                ytdlpPath: engineManager.ytdlpStatus.path,
                browserCookies: configuration.browserCookies,
                proxyURL: configuration.proxyURL,
                networkIPVersion: configuration.networkIPVersion,
                socketTimeoutSeconds: configuration.socketTimeoutSeconds,
                jsRuntimeArg: engineManager.ytdlpJSRuntimeArgument,
                playlistMode: effectiveMode
            )
            guard !Task.isCancelled else { return }
            inspectedMedia = info
            if info.isPlaylist {
                configuration.playlistBehavior = .downloadEntirePlaylist
            }
        } catch MediaInspectorError.cancelled {
            // User explicitly cancelled or started a newer inspect; keep UI quiet.
        } catch is CancellationError {
            // Superseded by a newer inspect call.
        } catch {
            inspectionError = error.localizedDescription
        }
        if !Task.isCancelled {
            isInspecting = false
        }
    }

    func pasteFromClipboardAndInspect(engineManager: EngineManager) {
        guard let str = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !str.isEmpty else {
            return
        }
        let extracted = YTDLPCommandBuilder.extractURLs(from: str)
        if extracted.count > 1 {
            isBatchMode = true
            urlInput = extracted.joined(separator: "\n")
        } else {
            isBatchMode = false
            urlInput = extracted.first ?? str
            startInspectingCurrentURL(engineManager: engineManager)
        }
    }

    func queuePlaylistEntries(
        _ entries: [PlaylistEntry],
        mediaInfo: MediaInfo,
        downloadManager: DownloadManager,
        createSubfolder: Bool,
        prefixIndex: Bool
    ) {
        guard !entries.isEmpty else { return }
        let added = downloadManager.enqueuePlaylistEntries(
            entries,
            playlistTitle: mediaInfo.title,
            extractor: mediaInfo.extractor,
            baseConfiguration: configuration,
            createSubfolder: createSubfolder,
            prefixIndex: prefixIndex
        )
        showToast("Queued \(added.count) video\(added.count == 1 ? "" : "s") from \"\(mediaInfo.title)\"")
    }

    func startDownload(downloadManager: DownloadManager, engineManager: EngineManager) {
        let trimmed = YTDLPCommandBuilder.sanitizeURL(urlInput)
        guard !trimmed.isEmpty, !isExpandingBulk else { return }

        // 1. Batch Mode (or multiline paste)
        if isBatchMode || trimmed.contains("\n") {
            let urls = YTDLPCommandBuilder.extractURLs(from: trimmed)
            guard !urls.isEmpty else {
                showToast("No valid http/https URLs found.")
                return
            }

            let playlistURLs = expandPlaylistsInBatch
                ? urls.filter { PlaylistURLDetector.isPurePlaylistURL($0) }
                : []

            if playlistURLs.isEmpty {
                let added = downloadManager.enqueueURLs(urls, configuration: configuration)
                showToast("Queued \(added.count) download\(added.count == 1 ? "" : "s")")
                urlInput = ""
                inspectedMedia = nil
                return
            }

            // Expand playlists in batch into individual parallel queue items
            let singleURLs = urls.filter { !PlaylistURLDetector.isPurePlaylistURL($0) }
            let configSnapshot = configuration
            Task { [weak self] in
                guard let self else { return }
                self.isExpandingBulk = true
                var totalQueued = 0

                if !singleURLs.isEmpty {
                    let added = downloadManager.enqueueURLs(singleURLs, configuration: configSnapshot)
                    totalQueued += added.count
                }

                for (idx, plURL) in playlistURLs.enumerated() {
                    self.bulkExpansionStatus = "Expanding playlist \(idx + 1) of \(playlistURLs.count)…"
                    do {
                        let info = try await MediaInspector.inspect(
                            url: plURL,
                            ytdlpPath: engineManager.ytdlpStatus.path,
                            browserCookies: configSnapshot.browserCookies,
                            proxyURL: configSnapshot.proxyURL,
                            networkIPVersion: configSnapshot.networkIPVersion,
                            socketTimeoutSeconds: configSnapshot.socketTimeoutSeconds,
                            jsRuntimeArg: engineManager.ytdlpJSRuntimeArgument,
                            playlistMode: .forcePlaylist
                        )
                        let entries = info.availablePlaylistEntries
                        if !entries.isEmpty {
                            let added = downloadManager.enqueuePlaylistEntries(
                                entries,
                                playlistTitle: info.title,
                                extractor: info.extractor,
                                baseConfiguration: configSnapshot,
                                createSubfolder: configSnapshot.createPlaylistSubfolder,
                                prefixIndex: true
                            )
                            totalQueued += added.count
                        } else {
                            // Fallback to direct playlist download if flat expansion returned no entries
                            var fallbackConfig = configSnapshot
                            fallbackConfig.playlistBehavior = .downloadEntirePlaylist
                            if downloadManager.enqueue(url: plURL, configuration: fallbackConfig) != nil {
                                totalQueued += 1
                            }
                        }
                    } catch {
                        // Fallback to direct yt-dlp playlist execution so nothing is dropped
                        var fallbackConfig = configSnapshot
                        fallbackConfig.playlistBehavior = .downloadEntirePlaylist
                        if downloadManager.enqueue(url: plURL, configuration: fallbackConfig) != nil {
                            totalQueued += 1
                        }
                    }
                }

                self.isExpandingBulk = false
                self.bulkExpansionStatus = ""
                self.urlInput = ""
                self.inspectedMedia = nil
                self.showToast("Queued \(totalQueued) download\(totalQueued == 1 ? "" : "s") across bulk batch")
            }
            return
        }

        // 2. Single URL Mode: already-inspected playlist -> queue all available entries concurrently
        if let media = inspectedMedia,
           media.isPlaylist,
           !media.playlistEntries.isEmpty,
           (media.webpageURL == trimmed || trimmed.contains(media.id)) {
            let entries: [PlaylistEntry]
            let rangeText = configuration.playlistItems.trimmingCharacters(in: .whitespacesAndNewlines)
            if !rangeText.isEmpty {
                let allowed = PlaylistURLDetector.parseSelectionRange(rangeText, maxIndex: media.playlistEntries.count)
                entries = media.availablePlaylistEntries.filter { allowed.contains($0.index) }
            } else {
                entries = media.availablePlaylistEntries
            }
            if !entries.isEmpty {
                queuePlaylistEntries(
                    entries,
                    mediaInfo: media,
                    downloadManager: downloadManager,
                    createSubfolder: configuration.createPlaylistSubfolder,
                    prefixIndex: true
                )
                return
            }
        }

        // 3. Single URL Mode: uninspected pure playlist URL -> expand automatically into parallel queue tasks
        let shouldAutoExpandPlaylist = PlaylistURLDetector.isPurePlaylistURL(trimmed) ||
            (configuration.playlistBehavior == .downloadEntirePlaylist && PlaylistURLDetector.extractLinkedPlaylistURL(from: trimmed) != nil)

        if shouldAutoExpandPlaylist {
            let configSnapshot = configuration
            Task { [weak self] in
                guard let self else { return }
                self.isExpandingBulk = true
                self.bulkExpansionStatus = "Expanding playlist videos for parallel download…"
                do {
                    let info = try await MediaInspector.inspect(
                        url: trimmed,
                        ytdlpPath: engineManager.ytdlpStatus.path,
                        browserCookies: configSnapshot.browserCookies,
                        proxyURL: configSnapshot.proxyURL,
                        networkIPVersion: configSnapshot.networkIPVersion,
                        socketTimeoutSeconds: configSnapshot.socketTimeoutSeconds,
                        jsRuntimeArg: engineManager.ytdlpJSRuntimeArgument,
                        playlistMode: .forcePlaylist
                    )
                    self.inspectedMedia = info
                    let rangeText = configSnapshot.playlistItems.trimmingCharacters(in: .whitespacesAndNewlines)
                    let entries: [PlaylistEntry]
                    if !rangeText.isEmpty {
                        let allowed = PlaylistURLDetector.parseSelectionRange(rangeText, maxIndex: info.playlistEntries.count)
                        entries = info.availablePlaylistEntries.filter { allowed.contains($0.index) }
                    } else {
                        entries = info.availablePlaylistEntries
                    }

                    if !entries.isEmpty {
                        let added = downloadManager.enqueuePlaylistEntries(
                            entries,
                            playlistTitle: info.title,
                            extractor: info.extractor,
                            baseConfiguration: configSnapshot,
                            createSubfolder: configSnapshot.createPlaylistSubfolder,
                            prefixIndex: true
                        )
                        self.showToast("Queued \(added.count) video\(added.count == 1 ? "" : "s") from \"\(info.title)\"")
                    } else {
                        var fallbackConfig = configSnapshot
                        fallbackConfig.playlistBehavior = .downloadEntirePlaylist
                        downloadManager.enqueue(url: trimmed, configuration: fallbackConfig, mediaInfo: info)
                        self.showToast("Added playlist to download queue")
                    }
                } catch {
                    // Graceful fallback to direct yt-dlp --yes-playlist
                    var fallbackConfig = configSnapshot
                    fallbackConfig.playlistBehavior = .downloadEntirePlaylist
                    downloadManager.enqueue(url: trimmed, configuration: fallbackConfig)
                    self.showToast("Added playlist to download queue")
                }
                self.isExpandingBulk = false
                self.bulkExpansionStatus = ""
            }
            return
        }

        // 4. Standard single video download
        let matchesInspected: Bool = {
            guard let media = inspectedMedia else { return false }
            return media.webpageURL == trimmed || (!media.id.isEmpty && trimmed.contains(media.id))
        }()
        downloadManager.enqueue(
            url: trimmed,
            configuration: configuration,
            mediaInfo: matchesInspected ? inspectedMedia : nil
        )
        showToast("Added to download queue")
        configuration.customFormatID = nil
    }

    func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2.8))
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }
}
