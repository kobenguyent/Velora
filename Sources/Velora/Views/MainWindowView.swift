import SwiftUI
import VeloraCore

enum SidebarSection: String, CaseIterable, Identifiable {
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

struct MainWindowView: View {
    let engineManager: EngineManager
    let downloadManager: DownloadManager
    @Bindable var updateChecker: UpdateChecker
    @Bindable var studio: StudioViewModel

    @State private var selection: SidebarSection = .studio

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 205, ideal: 225, max: 260)
        } detail: {
            ZStack(alignment: .bottom) {
                Group {
                    switch selection {
                    case .studio:
                        StudioView(
                            engineManager: engineManager,
                            downloadManager: downloadManager,
                            studio: studio,
                            onNavigateToQueue: { selection = .queue }
                        )
                    case .queue:
                        QueueView(downloadManager: downloadManager)
                    case .history:
                        HistoryView(
                            downloadManager: downloadManager,
                            onRedownload: { url in
                                studio.urlInput = url
                                studio.isBatchMode = false
                                selection = .studio
                            }
                        )
                    case .presets:
                        PresetsView(
                            downloadManager: downloadManager,
                            studio: studio,
                            onApplied: { selection = .studio }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let toast = studio.toastMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(VeloraTheme.emerald)
                        Text(toast)
                            .font(.callout.weight(.medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(VeloraTheme.subtleCardBorder, lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.28), value: studio.toastMessage)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if updateChecker.state.hasActionableUpdate, let available = updateChecker.state.availableUpdate {
                    Button {
                        updateChecker.isPresentingUpdateSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.down.app.fill")
                            Text("Update v\(available.version.description)")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(VeloraTheme.brandGradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("A new release of Velora is available on GitHub")
                }

                Button {
                    studio.isShowingEngineSetup = true
                } label: {
                    Label(
                        engineManager.isFullyReady ? "Engine Ready" : "Setup Engine",
                        systemImage: engineManager.isFullyReady
                            ? "checkmark.seal.fill"
                            : "wrench.and.screwdriver.fill"
                    )
                    .foregroundStyle(engineManager.isFullyReady ? VeloraTheme.emerald : VeloraTheme.amber)
                }
                .help("Configure yt-dlp and ffmpeg binaries")

                Button {
                    Task {
                        await updateChecker.checkForUpdates(userInitiated: true)
                    }
                } label: {
                    Label("Check Updates", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Check GitHub Releases for a newer version of Velora")
            }
        }
        .sheet(isPresented: $studio.isShowingEngineSetup) {
            EngineSetupSheet(engineManager: engineManager)
        }
        .sheet(isPresented: $updateChecker.isPresentingUpdateSheet) {
            UpdateSheetView(
                updateChecker: updateChecker,
                downloadManager: downloadManager
            )
        }
        .sheet(isPresented: $studio.isShowingFormatPicker) {
            if let media = studio.inspectedMedia {
                FormatPickerSheet(
                    mediaInfo: media,
                    selectedFormatID: studio.configuration.customFormatID
                ) { chosenFormatID in
                    studio.configuration.customFormatID = chosenFormatID
                    if let chosenFormatID {
                        studio.showToast("Selected stream format: \(chosenFormatID)")
                    } else {
                        studio.showToast("Cleared exact format override")
                    }
                }
            }
        }
    }

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Brand header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(VeloraTheme.brandGradient)
                        .frame(width: 34, height: 34)
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Velora")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text("Media Studio")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)

            List(SidebarSection.allCases, selection: $selection) { section in
                HStack {
                    Label(section.title, systemImage: section.systemImage)
                    Spacer()
                    if section == .queue {
                        let count = downloadManager.activeCount + downloadManager.queuedCount
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .foregroundStyle(.white)
                                .background(VeloraTheme.violet, in: Capsule())
                        }
                    } else if section == .history && !downloadManager.history.isEmpty {
                        Text("\(downloadManager.history.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(section)
            }
            .listStyle(.sidebar)

            Divider()

            // Footer status card: Engine + Version / Update check
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    studio.isShowingEngineSetup = true
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(engineDotColor)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(engineStatusTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(engineStatusSubtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()

                Button {
                    if updateChecker.state.hasActionableUpdate {
                        updateChecker.isPresentingUpdateSheet = true
                    } else {
                        Task { await updateChecker.checkForUpdates(userInitiated: true) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: updateChecker.state.hasActionableUpdate ? "sparkles" : "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(updateChecker.state.hasActionableUpdate ? VeloraTheme.cyan : .secondary)
                        Text("v\(UpdateChecker.currentVersionString)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        if updateChecker.state.hasActionableUpdate {
                            Text("Update Ready")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(VeloraTheme.cyan)
                        } else if case .checking = updateChecker.state {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Text("Check")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(VeloraTheme.surfaceFill.opacity(0.6))
        }
    }

    private var engineDotColor: Color {
        if engineManager.isFullyReady { return VeloraTheme.emerald }
        if engineManager.isReadyForBasicDownloads { return VeloraTheme.amber }
        return .red
    }

    private var engineStatusTitle: String {
        if engineManager.isFullyReady { return "Engines Ready" }
        if engineManager.isReadyForBasicDownloads { return "FFmpeg Missing" }
        return "Install yt-dlp"
    }

    private var engineStatusSubtitle: String {
        if let ver = engineManager.ytdlpStatus.version {
            return "yt-dlp \(ver)"
        }
        return "Click to set up engine"
    }
}
