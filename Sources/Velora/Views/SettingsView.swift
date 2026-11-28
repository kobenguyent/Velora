import AppKit
import SwiftUI
import VeloraCore

struct SettingsView: View {
    @Bindable var engineManager: EngineManager
    @Bindable var downloadManager: DownloadManager
    @Bindable var updateChecker: UpdateChecker
    @Bindable var studio: StudioViewModel

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            engineTab
                .tabItem {
                    Label("Engine", systemImage: "wrench.and.screwdriver")
                }

            updatesTab
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }
        }
        .frame(minWidth: 500, idealWidth: 560, maxWidth: 660, minHeight: 360, idealHeight: 410)
        .tint(VeloraTheme.accent)
    }

    private var generalTab: some View {
        Form {
            Section("Downloads") {
                Stepper(
                    value: $downloadManager.maxConcurrentDownloads,
                    in: 1...8
                ) {
                    HStack {
                        Text("Max Concurrent Downloads")
                        Spacer()
                        Text("\(downloadManager.maxConcurrentDownloads)")
                            .font(.body.monospacedDigit().weight(.medium))
                            .foregroundStyle(VeloraTheme.inkSecondary)
                    }
                }

                Toggle("Play completion sound when downloads finish", isOn: $downloadManager.playSoundOnComplete)

                HStack {
                    Text("Default Output Folder")
                    Spacer()
                    Text(studio.configuration.outputDirectoryPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(VeloraTheme.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.canCreateDirectories = true
                        if panel.runModal() == .OK, let url = panel.url {
                            studio.configuration.outputDirectoryPath = url.path
                        }
                    }
                }
            }

            Section("Automation & Alerts") {
                Toggle("Smart Clipboard URL Detection", isOn: $studio.smartClipboardEnabled)
                Toggle("Completion & Failure Notifications", isOn: $studio.systemNotificationsEnabled)
            }
        }
        .formStyle(.grouped)
    }

    private var engineTab: some View {
        Form {
            Section("Detected Binaries") {
                LabeledContent("yt-dlp") {
                    Text(engineManager.ytdlpStatus.path ?? "Not installed")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(engineManager.ytdlpStatus.isInstalled ? VeloraTheme.inkPrimary : VeloraTheme.warning)
                }
                LabeledContent("ffmpeg") {
                    Text(engineManager.ffmpegStatus.path ?? "Not installed")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(engineManager.ffmpegStatus.isInstalled ? VeloraTheme.inkPrimary : VeloraTheme.warning)
                }
                LabeledContent("JS Runtime") {
                    Text(engineManager.ytdlpJSRuntimeArgument ?? "Not detected (optional: deno / bun / node)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(engineManager.jsRuntimeStatus.isInstalled ? VeloraTheme.inkPrimary : VeloraTheme.inkSecondary)
                }
            }

            Section("Custom Overrides (Optional)") {
                TextField("Custom yt-dlp path", text: $engineManager.customYTDLPPath, prompt: Text("/opt/homebrew/bin/yt-dlp"))
                    .font(.system(.callout, design: .monospaced))
                    .accessibilityLabel("Custom yt-dlp path")
                TextField("Custom ffmpeg path", text: $engineManager.customFFmpegPath, prompt: Text("/opt/homebrew/bin/ffmpeg"))
                    .font(.system(.callout, design: .monospaced))
                    .accessibilityLabel("Custom ffmpeg path")

                HStack {
                    Button("Open Engine Setup…") {
                        studio.mainWindowOpener?()
                        NSApp.activate(ignoringOtherApps: true)
                        studio.isShowingEngineSetup = true
                    }
                    Spacer()
                    Button("Re-scan Binaries") {
                        Task { await engineManager.refresh() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var updatesTab: some View {
        Form {
            Section("GitHub Releases Auto-Update") {
                LabeledContent("Installed Version") {
                    Text("v\(UpdateChecker.currentVersionString) (build \(UpdateChecker.currentBuildNumber))")
                        .monospacedDigit()
                }

                TextField("GitHub Repository", text: $updateChecker.githubRepository, prompt: Text("owner/repo"))
                    .font(.system(.callout, design: .monospaced))
                    .accessibilityLabel("GitHub Repository")

                Toggle("Automatically check for updates on launch", isOn: $updateChecker.autoCheckOnLaunch)
                Toggle("Include pre-release builds (beta / rc)", isOn: $updateChecker.includePrereleases)
            }

            Section("Actions") {
                HStack {
                    if let lastChecked = updateChecker.lastCheckedAt {
                        Text("Last checked: \(lastChecked.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(VeloraTheme.inkSecondary)
                    } else {
                        Text("Not checked yet")
                            .font(.caption)
                            .foregroundStyle(VeloraTheme.inkSecondary)
                    }
                    Spacer()
                    if updateChecker.skippedVersion != nil {
                        Button("Reset Skipped") {
                            updateChecker.skippedVersion = nil
                        }
                    }
                    Button("Check Now") {
                        studio.mainWindowOpener?()
                        NSApp.activate(ignoringOtherApps: true)
                        updateChecker.isPresentingUpdateSheet = true
                        Task { await updateChecker.checkForUpdates(userInitiated: true) }
                    }
                    .buttonStyle(VeloraPrimaryButtonStyle())
                }
            }
        }
        .formStyle(.grouped)
    }
}
