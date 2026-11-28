import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeloraCore

struct MainWindowView: View {
    let engineManager: EngineManager
    let downloadManager: DownloadManager
    @Bindable var updateChecker: UpdateChecker
    @Bindable var studio: StudioViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTargeted = false
    @State private var isFullScreen = false

    private nonisolated static let maxDropFileBytes: Int64 = 1_048_576

    var body: some View {
        GeometryReader { proxy in
            let layout = VeloraLayoutMetrics(windowSize: proxy.size)

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    galleryTopBar(layout: layout)

                    Divider()
                        .overlay(VeloraTheme.hairline)

                    activeContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .ignoresSafeArea(.container, edges: .top)
                .background(VeloraTheme.ground)

                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(VeloraTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .background(VeloraTheme.accent.opacity(0.05))
                        .padding(12)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                if let toast = studio.activeToast {
                    toastBanner(toast, layout: layout)
                }
            }
            .environment(\.veloraLayout, layout)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: studio.activeToast?.id)
        .onDrop(of: [.url, .fileURL, .plainText], isTargeted: $isDropTargeted) { providers in
            handleWindowDrop(providers)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshClipboardSuggestion()
        }
        .onChange(of: studio.isShowingFormatPicker) { _, isPresented in
            if isPresented && studio.inspectedMedia == nil {
                studio.isShowingFormatPicker = false
            }
        }
        .onChange(of: studio.isShowingPlaylistPicker) { _, isPresented in
            if isPresented && !(studio.inspectedMedia?.isPlaylist == true) {
                studio.isShowingPlaylistPicker = false
            }
        }
        .onChange(of: studio.activeToast?.id) { _, _ in
            if let message = studio.activeToast?.message {
                AccessibilityNotification.Announcement(message).post()
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
                    selectedFormatID: studio.configuration.customFormatID,
                    onSelectFormat: { chosenFormatID, isVideoOnly in
                        studio.configuration.customFormatID = chosenFormatID
                        studio.customFormatIsVideoOnly = chosenFormatID != nil ? isVideoOnly : false
                        if let chosenFormatID {
                            studio.showToast("Selected stream format: \(chosenFormatID)", kind: .success)
                        } else {
                            studio.showToast("Cleared exact format override", kind: .info)
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $studio.isShowingPlaylistPicker) {
            if let media = studio.inspectedMedia, media.isPlaylist {
                PlaylistPickerSheet(
                    mediaInfo: media,
                    defaultCreateSubfolder: studio.configuration.createPlaylistSubfolder
                ) { selectedEntries, createSubfolder, prefixIndex in
                    studio.queuePlaylistEntries(
                        selectedEntries,
                        mediaInfo: media,
                        downloadManager: downloadManager,
                        createSubfolder: createSubfolder,
                        prefixIndex: prefixIndex
                    )
                    studio.selectedSection = .queue
                }
            }
        }
    }

    // MARK: - M2 Apple Gallery Top Bar

    private func galleryTopBar(layout: VeloraLayoutMetrics) -> some View {
        let leadingInset: CGFloat = isFullScreen ? layout.scaled(22) : 84
        let trailingInset: CGFloat = layout.widthClass == .compact ? 16 : layout.scaled(20)
        let compactHideEngineText = layout.widthClass == .compact && updateChecker.state.hasActionableUpdate

        return Group {
            if layout.usesCenteredTopBar {
                ZStack {
                    HStack(spacing: 12) {
                        brandCluster(layout: layout, showsWordmark: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        rightStatusCluster(layout: layout, compactTextHidden: false)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    segmentedNavigationPill(layout: layout)
                }
            } else {
                HStack(spacing: 8) {
                    brandCluster(layout: layout, showsWordmark: layout.showsBrandWordmark)

                    Spacer(minLength: 4)

                    segmentedNavigationPill(layout: layout)
                        .layoutPriority(1)

                    Spacer(minLength: 4)

                    rightStatusCluster(layout: layout, compactTextHidden: compactHideEngineText)
                }
            }
        }
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .frame(height: layout.topBarHeight)
        .background {
            ZStack {
                VeloraTheme.ground
                WindowChromeBridge(isFullScreen: $isFullScreen)
            }
        }
    }

    private func brandCluster(layout: VeloraLayoutMetrics, showsWordmark: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .font(layout.font(18, weight: .semibold))
                .foregroundStyle(VeloraTheme.accent)
                .accessibilityHidden(true)
            if showsWordmark {
                Text("Velora")
                    .font(layout.font(14.5, weight: .semibold))
                    .foregroundStyle(VeloraTheme.inkPrimary)
                    .lineLimit(1)
            }
        }
    }

    private func segmentedNavigationPill(layout: VeloraLayoutMetrics) -> some View {
        HStack(spacing: 4) {
            ForEach(AppSection.allCases) { section in
                let isSelected = studio.selectedSection == section
                Button {
                    if reduceMotion {
                        studio.selectedSection = section
                    } else {
                        withAnimation(.snappy(duration: 0.18)) {
                            studio.selectedSection = section
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(section.title)
                            .font(layout.font(13, weight: isSelected ? .semibold : .medium))
                        if section == .queue {
                            let pendingCount = downloadManager.activeCount + downloadManager.queuedCount
                            if pendingCount > 0 {
                                Text("\(pendingCount)")
                                    .font(layout.font(10.5, weight: .semibold))
                                    .monospacedDigit()
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .foregroundStyle(isSelected ? .white : VeloraTheme.accentText)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? VeloraTheme.accent : VeloraTheme.accent.opacity(0.12))
                                    )
                            }
                        }
                    }
                    .foregroundStyle(isSelected ? VeloraTheme.inkPrimary : VeloraTheme.inkSecondary)
                    .padding(.horizontal, layout.scaled(14))
                    .padding(.vertical, layout.scaled(6))
                    .frame(minHeight: layout.scaled(30))
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(VeloraTheme.surfaceElevated)
                                .overlay(Capsule().stroke(VeloraTheme.hairline, lineWidth: 1))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .veloraFocusableRing(cornerRadius: 999)
                .accessibilityLabel(sectionAccessibilityLabel(section))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(VeloraTheme.surfaceSubtle)
        )
        .overlay(
            Capsule()
                .stroke(VeloraTheme.hairline, lineWidth: 1)
        )
    }

    private func rightStatusCluster(layout: VeloraLayoutMetrics, compactTextHidden: Bool) -> some View {
        let pillHeight = layout.scaled(28)
        let dotSize = max(7, (7.5 * layout.badgeScale).rounded())

        return HStack(spacing: 8) {
            Button {
                studio.isShowingEngineSetup = true
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(engineDotColor)
                        .frame(width: dotSize, height: dotSize)
                        .accessibilityHidden(true)
                    if !compactTextHidden {
                        Text(engineCompactLabel)
                            .font(layout.font(12, weight: .medium))
                            .foregroundStyle(VeloraTheme.inkSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, compactTextHidden ? 8 : layout.scaled(11))
                .padding(.vertical, 5)
                .frame(minWidth: pillHeight, minHeight: pillHeight)
                .background(
                    Capsule()
                        .fill(VeloraTheme.surfaceSubtle)
                )
                .overlay(
                    Capsule()
                        .stroke(VeloraTheme.hairline, lineWidth: 1)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .veloraFocusableRing(cornerRadius: 999)
            .help("Configure yt-dlp, FFmpeg, and Deno binaries")
            .accessibilityLabel("Engine status: \(engineCompactLabel). Open Engine Setup")

            if updateChecker.state.hasActionableUpdate, let available = updateChecker.state.availableUpdate {
                Button {
                    updateChecker.isPresentingUpdateSheet = true
                } label: {
                    Text("Update v\(available.version.description)")
                        .font(layout.font(12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, layout.scaled(11))
                        .padding(.vertical, 5)
                        .frame(minWidth: pillHeight, minHeight: pillHeight)
                        .background(VeloraTheme.accent, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .veloraFocusableRing(cornerRadius: 999)
                .help("A new release of Velora is available on GitHub")
                .accessibilityLabel("Update available: version \(available.version.description)")
            }

            Button {
                Task {
                    await updateChecker.checkForUpdates(userInitiated: true)
                }
            } label: {
                Group {
                    if case .checking = updateChecker.state {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(layout.font(12, weight: .medium))
                            .foregroundStyle(VeloraTheme.inkSecondary)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: pillHeight, height: pillHeight)
                .background(
                    Circle()
                        .fill(VeloraTheme.surfaceSubtle)
                )
                .overlay(
                    Circle()
                        .stroke(VeloraTheme.hairline, lineWidth: 1)
                )
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .veloraFocusableRing(cornerRadius: 999)
            .help("Check GitHub Releases for a newer version of Velora")
            .accessibilityLabel(isCheckingUpdates ? "Checking for updates" : "Check for updates")
        }
    }

    // MARK: - Section Router

    @ViewBuilder
    private var activeContent: some View {
        switch studio.selectedSection {
        case .studio:
            StudioView(
                engineManager: engineManager,
                downloadManager: downloadManager,
                studio: studio,
                onNavigateToQueue: { studio.selectedSection = .queue }
            )
        case .queue:
            QueueView(
                downloadManager: downloadManager,
                onNavigateToStudio: { studio.selectedSection = .studio }
            )
        case .history:
            HistoryView(
                downloadManager: downloadManager,
                onRedownload: { url in
                    studio.urlInput = url
                    studio.isBatchMode = false
                    studio.selectedSection = .studio
                }
            )
        case .presets:
            PresetsView(
                downloadManager: downloadManager,
                studio: studio,
                onApplied: { studio.selectedSection = .studio }
            )
        }
    }

    // MARK: - Typed Floating Toast

    private func toastBanner(_ toast: ToastItem, layout: VeloraLayoutMetrics) -> some View {
        HStack(spacing: 8) {
            Image(systemName: toastIcon(for: toast.kind))
                .font(layout.font(13, weight: .semibold))
                .foregroundStyle(toastColor(for: toast.kind))
                .accessibilityHidden(true)
            Text(toast.message)
                .font(layout.font(13, weight: .medium))
                .foregroundStyle(VeloraTheme.inkPrimary)
        }
        .padding(.horizontal, layout.scaled(16))
        .padding(.vertical, layout.scaled(10))
        .background(VeloraTheme.surfaceElevated, in: Capsule())
        .overlay(Capsule().stroke(VeloraTheme.borderStrong, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)
        .padding(.bottom, 18)
        .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }

    private var isCheckingUpdates: Bool {
        if case .checking = updateChecker.state { return true }
        return false
    }

    private func toastIcon(for kind: ToastKind) -> String {
        switch kind {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        case .info: "info.circle.fill"
        }
    }

    private func toastColor(for kind: ToastKind) -> Color {
        switch kind {
        case .success: VeloraTheme.success
        case .warning: VeloraTheme.warning
        case .error: VeloraTheme.danger
        case .info: VeloraTheme.info
        }
    }

    private func sectionAccessibilityLabel(_ section: AppSection) -> String {
        if section == .queue {
            let count = downloadManager.activeCount + downloadManager.queuedCount
            return count > 0 ? "Queue, \(count) active or queued" : "Queue"
        }
        return section.title
    }

    private var engineDotColor: Color {
        if engineManager.isFullyReady { return VeloraTheme.success }
        if engineManager.isReadyForBasicDownloads { return VeloraTheme.warning }
        return VeloraTheme.danger
    }

    private var engineCompactLabel: String {
        if engineManager.isReadyForBasicDownloads { return "Engine OK" }
        return "Setup"
    }

    // MARK: - Foreground Clipboard Detection

    private func refreshClipboardSuggestion() {
        guard studio.smartClipboardEnabled,
              studio.selectedSection == .studio,
              !studio.isBatchMode else {
            return
        }
        if let suggested = MacSystemBridge.shared.detectClipboardMediaURL(currentInput: studio.urlInput) {
            studio.clipboardSuggestionURL = suggested
        }
    }

    // MARK: - Safe Full-Window Drop Handler

    private func handleWindowDrop(_ providers: [NSItemProvider]) -> Bool {
        let supported = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ||
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) ||
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }
        guard !supported.isEmpty else { return false }

        for provider in supported {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let fileURL = Self.extractURL(from: item), fileURL.isFileURL else { return }
                    Task.detached(priority: .utility) {
                        let result = Self.readDropFileURLs(from: fileURL)
                        await MainActor.run {
                            applyDropResult(result)
                        }
                    }
                }
                return true
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    guard let droppedURL = Self.extractURL(from: item), !droppedURL.isFileURL else { return }
                    let raw = droppedURL.absoluteString
                    Task { @MainActor in
                        applyDroppedText(raw)
                    }
                }
                return true
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    guard let text = Self.extractString(from: item) else { return }
                    Task { @MainActor in
                        applyDroppedText(text)
                    }
                }
                return true
            }
        }
        return false
    }

    private enum DropFileOutcome: Sendable {
        case urls([String])
        case tooLarge
        case unsupportedOrEmpty
    }

    private nonisolated static func readDropFileURLs(from fileURL: URL) -> DropFileOutcome {
        let ext = fileURL.pathExtension.lowercased()
        guard ext == "txt" || ext == "csv" || ext.isEmpty else {
            return .unsupportedOrEmpty
        }

        if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
           let size = values.fileSize,
           Int64(size) > maxDropFileBytes {
            return .tooLarge
        }

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return .unsupportedOrEmpty
        }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: Int(maxDropFileBytes) + 1) else {
            return .unsupportedOrEmpty
        }
        if Int64(data.count) > maxDropFileBytes {
            return .tooLarge
        }

        let text = String(decoding: data, as: UTF8.self)
        let urls = YTDLPCommandBuilder.extractURLs(from: text)
        return urls.isEmpty ? .unsupportedOrEmpty : .urls(urls)
    }

    private func applyDropResult(_ outcome: DropFileOutcome) {
        studio.selectedSection = .studio
        switch outcome {
        case .urls(let urls):
            applyExtractedDropURLs(urls)
        case .tooLarge:
            studio.showToast("Dropped file exceeds 1 MB limit.", kind: .warning)
        case .unsupportedOrEmpty:
            studio.showToast("No valid http/https URLs found in dropped file.", kind: .warning)
        }
    }

    private func applyDroppedText(_ rawText: String) {
        studio.selectedSection = .studio
        let extracted = YTDLPCommandBuilder.extractURLs(from: rawText)
        guard !extracted.isEmpty else {
            studio.showToast("No valid http/https URL found in drop.", kind: .warning)
            return
        }
        applyExtractedDropURLs(extracted)
    }

    private func applyExtractedDropURLs(_ urls: [String]) {
        studio.clipboardSuggestionURL = nil
        if urls.count > 1 {
            studio.isBatchMode = true
            studio.urlInput = urls.joined(separator: "\n")
            studio.showToast("Loaded \(urls.count) URLs into batch studio", kind: .info)
        } else if let single = urls.first {
            studio.isBatchMode = false
            studio.urlInput = single
            studio.startInspectingCurrentURL(engineManager: engineManager)
        }
    }

    private nonisolated static func extractURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let nsurl = item as? NSURL {
            return nsurl as URL
        }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let str = item as? String {
            return URL(string: str.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private nonisolated static func extractString(from item: NSSecureCoding?) -> String? {
        if let str = item as? String {
            return str
        }
        if let nsstr = item as? NSString {
            return nsstr as String
        }
        if let data = item as? Data {
            return String(decoding: data, as: UTF8.self)
        }
        return nil
    }
}
