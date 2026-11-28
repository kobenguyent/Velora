import AppKit
import SwiftUI
import VeloraCore

enum AppSection: String, CaseIterable, Identifiable {
    case studio
    case queue
    case history
    case presets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .studio: "Studio"
        case .queue: "Queue"
        case .history: "History"
        case .presets: "Presets"
        }
    }

    var systemImage: String {
        switch self {
        case .studio: "sparkles.rectangle.stack"
        case .queue: "arrow.down.circle"
        case .history: "clock.arrow.circlepath"
        case .presets: "slider.horizontal.3"
        }
    }
}

enum ToastKind: Sendable, Equatable {
    case success
    case warning
    case error
    case info
}

struct ToastItem: Identifiable, Equatable, Sendable {
    let id = UUID()
    let message: String
    let kind: ToastKind
}

@main
struct VeloraApp: App {
    @NSApplicationDelegateAdaptor(VeloraAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

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
        Window("Velora", id: "main") {
            MainWindowView(
                engineManager: engineManager,
                downloadManager: downloadManager,
                updateChecker: updateChecker,
                studio: studioState
            )
            .tint(VeloraTheme.accent)
            .frame(minWidth: 680, minHeight: 500)
            .task {
                configureAppLifecycle()
                MacSystemBridge.shared.requestNotificationPermissionIfBundled()
                await engineManager.refresh()
                downloadManager.restorePendingQueueAfterEngineReady()
                await updateChecker.performLaunchCheckIfEnabled()
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1040, height: 680)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task {
                        await updateChecker.checkForUpdates(userInitiated: true)
                    }
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])

                Button("Engine Setup…") {
                    openMainWindow()
                    studioState.isShowingEngineSetup = true
                }
            }

            CommandMenu("Navigate") {
                Button("Open Velora") {
                    openMainWindow()
                }
                .keyboardShortcut("0", modifiers: [.command])

                Divider()

                Button("Studio") {
                    studioState.selectedSection = .studio
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Queue") {
                    studioState.selectedSection = .queue
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button("History") {
                    studioState.selectedSection = .history
                }
                .keyboardShortcut("3", modifiers: [.command])

                Button("Presets") {
                    studioState.selectedSection = .presets
                }
                .keyboardShortcut("4", modifiers: [.command])
            }

            CommandMenu("Downloads") {
                Button("Focus URL Input") {
                    openMainWindow()
                    studioState.selectedSection = .studio
                    studioState.focusURLRequestToken = UUID()
                }
                .keyboardShortcut("l", modifiers: [.command])

                Button("Inspect URL") {
                    openMainWindow()
                    studioState.selectedSection = .studio
                    studioState.startInspectingCurrentURL(engineManager: engineManager)
                }
                .keyboardShortcut("i", modifiers: [.command])
                .disabled(!studioState.canDownload || studioState.isBatchMode)

                Button("Paste URL & Inspect") {
                    openMainWindow()
                    studioState.selectedSection = .studio
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

        MenuBarExtra {
            MenuBarQueueView(
                engineManager: engineManager,
                downloadManager: downloadManager,
                studio: studioState,
                onOpenMainWindow: { openMainWindow() }
            )
            .tint(VeloraTheme.accent)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                if downloadManager.activeCount > 0 {
                    Text("\(downloadManager.activeCount)")
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                engineManager: engineManager,
                downloadManager: downloadManager,
                updateChecker: updateChecker,
                studio: studioState
            )
            .tint(VeloraTheme.accent)
        }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureAppLifecycle() {
        studioState.mainWindowOpener = { [openWindow] in
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        appDelegate.onConfirmQuit = { [weak downloadManager] in
            downloadManager?.hasActiveDownloads ?? false
        }
        appDelegate.onTerminate = { [weak downloadManager] in
            downloadManager?.terminateAllOnQuit()
        }

        downloadManager.onQueueChanged = { [weak downloadManager] in
            guard let downloadManager else { return }
            MacSystemBridge.shared.updateDockBadge(
                activeCount: downloadManager.activeCount,
                pausedCount: downloadManager.pausedCount
            )
        }

        downloadManager.onTaskFinished = { [weak studioState] task, succeeded in
            let enabled = studioState?.systemNotificationsEnabled ?? true
            MacSystemBridge.shared.postCompletionNotification(
                title: task.title,
                succeeded: succeeded,
                detail: task.statusDetail,
                enabled: enabled
            )
        }

        MacSystemBridge.shared.updateDockBadge(
            activeCount: downloadManager.activeCount,
            pausedCount: downloadManager.pausedCount
        )
    }

    private func handleDeepLink(_ url: URL) {
        guard let action = VeloraDeepLinkParser.parse(url) else {
            studioState.showToast("Ignored invalid velora:// link.", kind: .warning)
            return
        }

        openMainWindow()
        studioState.selectedSection = .studio
        studioState.isBatchMode = false

        switch action {
        case .inspect(let mediaURL):
            studioState.urlInput = mediaURL
            studioState.startInspectingCurrentURL(engineManager: engineManager)

        case .download(let mediaURL, let presetQuery):
            studioState.urlInput = mediaURL
            if let presetQuery {
                if let matched = matchPreset(query: presetQuery) {
                    studioState.applyPreset(matched)
                }
            }
            studioState.startDownload(downloadManager: downloadManager, engineManager: engineManager)
        }
    }

    private func matchPreset(query: String) -> DownloadPreset? {
        if let id = UUID(uuidString: query) {
            return downloadManager.allPresets.first { $0.id == id }
        }
        let lowered = query.lowercased()
        return downloadManager.allPresets.first { $0.name.lowercased() == lowered }
    }
}

@MainActor
final class VeloraAppDelegate: NSObject, NSApplicationDelegate {
    var onConfirmQuit: (() -> Bool)?
    var onTerminate: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure bare `swift run` launches also activate properly as a foreground macOS GUI app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard onConfirmQuit?() == true else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Active Downloads Running"
        alert.informativeText = "Active downloads are running. Quit and pause them for resume later?"
        alert.addButton(withTitle: "Quit & Pause")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        return response == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        onTerminate?()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@MainActor
@Observable
final class StudioViewModel {
    var selectedSection: AppSection = .studio
    var urlInput: String = ""
    var isBatchMode: Bool = false
    var configuration: DownloadConfiguration {
        didSet {
            scheduleDebouncedConfigurationSave()
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
    var activeToast: ToastItem?

    var customFormatIsVideoOnly: Bool = false
    var isAllOptionsExpanded: Bool = false
    var focusURLRequestToken: UUID = UUID()
    var clipboardSuggestionURL: String? = nil
    var mainWindowOpener: (() -> Void)?

    var smartClipboardEnabled: Bool {
        didSet {
            UserDefaults.standard.set(smartClipboardEnabled, forKey: Keys.smartClipboard)
            if !smartClipboardEnabled {
                clipboardSuggestionURL = nil
            }
        }
    }

    var systemNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(systemNotificationsEnabled, forKey: Keys.systemNotifications)
        }
    }

    private enum Keys {
        static let smartClipboard = "velora.ux.smartClipboard"
        static let systemNotifications = "velora.ux.systemNotifications"
    }

    private let store: VeloraStore
    private var inspectTask: Task<Void, Never>?
    private var saveConfigTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?

    var canDownload: Bool {
        if isBatchMode || urlInput.contains("\n") {
            return !detectedBatchURLs.isEmpty
        }
        let trimmed = YTDLPCommandBuilder.sanitizeURL(urlInput)
        return YTDLPCommandBuilder.isValidMediaURL(trimmed) || PlaylistURLDetector.isPurePlaylistURL(trimmed)
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

        if UserDefaults.standard.object(forKey: Keys.smartClipboard) != nil {
            self.smartClipboardEnabled = UserDefaults.standard.bool(forKey: Keys.smartClipboard)
        } else {
            self.smartClipboardEnabled = true
        }

        if UserDefaults.standard.object(forKey: Keys.systemNotifications) != nil {
            self.systemNotificationsEnabled = UserDefaults.standard.bool(forKey: Keys.systemNotifications)
        } else {
            self.systemNotificationsEnabled = true
        }
    }

    private func scheduleDebouncedConfigurationSave() {
        let snapshot = configuration
        saveConfigTask?.cancel()
        saveConfigTask = Task { [store] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            store.enqueueSaveLastConfiguration(snapshot)
        }
    }

    func applyPreset(_ preset: DownloadPreset) {
        let currentOutDir = configuration.outputDirectoryPath
        var updated = preset.configuration
        updated.outputDirectoryPath = currentOutDir
        configuration = updated
        customFormatIsVideoOnly = false
        showToast("Applied preset: \(preset.name)", kind: .success)
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
            clipboardSuggestionURL = nil
        } else {
            isBatchMode = false
            urlInput = extracted.first ?? str
            clipboardSuggestionURL = nil
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
        showToast("Queued \(added.count) video\(added.count == 1 ? "" : "s") from \"\(mediaInfo.title)\"", kind: .success)
    }

    func startDownload(downloadManager: DownloadManager, engineManager: EngineManager) {
        let trimmed = YTDLPCommandBuilder.sanitizeURL(urlInput)
        guard !trimmed.isEmpty, !isExpandingBulk else { return }

        guard engineManager.isReadyForBasicDownloads else {
            isShowingEngineSetup = true
            showToast("Install yt-dlp via Engine Setup first.", kind: .warning)
            return
        }

        // 1. Batch Mode (or multiline paste)
        if isBatchMode || trimmed.contains("\n") {
            let urls = YTDLPCommandBuilder.extractURLs(from: trimmed)
            guard !urls.isEmpty else {
                showToast("No valid http/https URLs found.", kind: .warning)
                return
            }

            let playlistURLs = expandPlaylistsInBatch
                ? urls.filter { PlaylistURLDetector.isPurePlaylistURL($0) }
                : []

            if playlistURLs.isEmpty {
                let added = downloadManager.enqueueURLs(urls, configuration: configuration)
                showToast("Queued \(added.count) download\(added.count == 1 ? "" : "s")", kind: .success)
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
                self.showToast("Queued \(totalQueued) download\(totalQueued == 1 ? "" : "s") across bulk batch", kind: .success)
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
                        self.showToast("Queued \(added.count) video\(added.count == 1 ? "" : "s") from \"\(info.title)\"", kind: .success)
                    } else {
                        var fallbackConfig = configSnapshot
                        fallbackConfig.playlistBehavior = .downloadEntirePlaylist
                        downloadManager.enqueue(url: trimmed, configuration: fallbackConfig, mediaInfo: info)
                        self.showToast("Added playlist to download queue", kind: .success)
                    }
                } catch {
                    // Graceful fallback to direct yt-dlp --yes-playlist
                    var fallbackConfig = configSnapshot
                    fallbackConfig.playlistBehavior = .downloadEntirePlaylist
                    downloadManager.enqueue(url: trimmed, configuration: fallbackConfig)
                    self.showToast("Added playlist to download queue", kind: .success)
                }
                self.isExpandingBulk = false
                self.bulkExpansionStatus = ""
            }
            return
        }

        // 4. Standard single video download
        if downloadManager.hasPendingOrActiveDownload(for: trimmed) {
            showToast("This URL is already active or queued.", kind: .info)
            return
        }

        let matchesInspected: Bool = {
            guard let media = inspectedMedia else { return false }
            return media.webpageURL == trimmed || (!media.id.isEmpty && trimmed.contains(media.id))
        }()

        let queued = downloadManager.enqueue(
            url: trimmed,
            configuration: configuration,
            mediaInfo: matchesInspected ? inspectedMedia : nil,
            customFormatIsVideoOnly: customFormatIsVideoOnly
        )
        if queued != nil {
            showToast("Added to download queue", kind: .success)
            configuration.customFormatID = nil
            customFormatIsVideoOnly = false
        } else {
            showToast("Enter a valid http or https URL.", kind: .warning)
        }
    }

    func showToast(_ message: String, kind: ToastKind = .success) {
        let item = ToastItem(message: message, kind: kind)
        activeToast = item
        toastDismissTask?.cancel()
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.8))
            guard !Task.isCancelled else { return }
            if self?.activeToast?.id == item.id {
                self?.activeToast = nil
            }
        }
    }
}
