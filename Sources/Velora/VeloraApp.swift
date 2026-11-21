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
                    studioState.startDownload(downloadManager: downloadManager)
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!studioState.canDownload)

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
    var isShowingEngineSetup: Bool = false
    var isShowingSavePresetSheet: Bool = false
    var toastMessage: String?

    private let store: VeloraStore
    private var inspectTask: Task<Void, Never>?

    var canDownload: Bool {
        !urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    func startInspectingCurrentURL(engineManager: EngineManager) {
        inspectTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.inspectCurrentURL(engineManager: engineManager)
        }
        inspectTask = task
    }

    func inspectCurrentURL(engineManager: EngineManager) async {
        let trimmed = YTDLPCommandBuilder.sanitizeURL(urlInput)
        guard !trimmed.isEmpty else { return }

        isInspecting = true
        inspectionError = nil
        inspectedMedia = nil

        do {
            let info = try await MediaInspector.inspect(
                url: trimmed,
                ytdlpPath: engineManager.ytdlpStatus.path,
                browserCookies: configuration.browserCookies,
                proxyURL: configuration.proxyURL,
                networkIPVersion: configuration.networkIPVersion,
                socketTimeoutSeconds: configuration.socketTimeoutSeconds,
                jsRuntimeArg: engineManager.ytdlpJSRuntimeArgument
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
        let lines = str.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if lines.count > 1 {
            isBatchMode = true
            urlInput = str
        } else {
            isBatchMode = false
            urlInput = str
            startInspectingCurrentURL(engineManager: engineManager)
        }
    }

    func startDownload(downloadManager: DownloadManager) {
        let trimmed = YTDLPCommandBuilder.sanitizeURL(urlInput)
        guard !trimmed.isEmpty else { return }

        if isBatchMode || trimmed.contains("\n") {
            let added = downloadManager.enqueueBatch(multilineInput: trimmed, configuration: configuration)
            if added.isEmpty {
                showToast("No valid http/https URLs found.")
            } else {
                showToast("Added \(added.count) download\(added.count == 1 ? "" : "s") to queue")
                urlInput = ""
                inspectedMedia = nil
            }
        } else {
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
