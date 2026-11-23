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
        .frame(width: 540, height: 340)
    }

    private var generalTab: some View {
        Form {
            Section("Downloads") {
                Stepper(
                    "Max Concurrent Downloads: \(downloadManager.maxConcurrentDownloads)",
                    value: $downloadManager.maxConcurrentDownloads,
                    in: 1...8
                )
                Toggle("Play completion sound when downloads finish", isOn: $downloadManager.playSoundOnComplete)

                HStack {
                    Text("Default Output Folder")
                    Spacer()
                    Text(studio.configuration.outputDirectoryPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
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
        }
        .formStyle(.grouped)
    }

    private var engineTab: some View {
        Form {
            Section("Detected Binaries") {
                LabeledContent("yt-dlp") {
                    Text(engineManager.ytdlpStatus.path ?? "Not installed")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(engineManager.ytdlpStatus.isInstalled ? Color.primary : Color.orange)
                }
                LabeledContent("ffmpeg") {
                    Text(engineManager.ffmpegStatus.path ?? "Not installed")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(engineManager.ffmpegStatus.isInstalled ? Color.primary : Color.orange)
                }
                LabeledContent("JS Runtime") {
                    Text(engineManager.ytdlpJSRuntimeArgument ?? "Not detected (optional: deno / bun / node)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(engineManager.jsRuntimeStatus.isInstalled ? Color.primary : Color.secondary)
                }
            }

            Section("Custom Overrides (Optional)") {
                TextField("Custom yt-dlp path", text: $engineManager.customYTDLPPath, prompt: Text("/opt/homebrew/bin/yt-dlp"))
                    .font(.system(.callout, design: .monospaced))
                TextField("Custom ffmpeg path", text: $engineManager.customFFmpegPath, prompt: Text("/opt/homebrew/bin/ffmpeg"))
                    .font(.system(.callout, design: .monospaced))

                HStack {
                    Button("Open Engine Setup…") {
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

                Toggle("Automatically check for updates on launch", isOn: $updateChecker.autoCheckOnLaunch)
                Toggle("Include pre-release builds (beta / rc)", isOn: $updateChecker.includePrereleases)
            }

            Section("Actions") {
                HStack {
                    if let lastChecked = updateChecker.lastCheckedAt {
                        Text("Last checked: \(lastChecked.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not checked yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if updateChecker.skippedVersion != nil {
                        Button("Reset Skipped") {
                            updateChecker.skippedVersion = nil
                        }
                    }
                    Button("Check Now") {
                        Task { await updateChecker.checkForUpdates(userInitiated: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VeloraTheme.violet)
                }
            }
        }
        .formStyle(.grouped)
    }
}
