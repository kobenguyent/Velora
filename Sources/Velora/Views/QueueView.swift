import AppKit
import QuickLook
import SwiftUI
import VeloraCore

private enum QueueFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case queued = "Queued"
    case paused = "Paused"
    case completed = "Completed"
    case failed = "Failed"

    var id: String { rawValue }
}

struct QueueView: View {
    @Bindable var downloadManager: DownloadManager
    var onNavigateToStudio: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.veloraLayout) private var layout
    @State private var expandedLogs: Set<UUID> = []
    @State private var filter: QueueFilter = .all
    @State private var searchQuery: String = ""
    @State private var selectedTaskID: UUID?
    @State private var quickLookURL: URL?
    @State private var isConfirmingCancelAll = false
    @FocusState private var isQueueFocused: Bool
    @FocusState private var isSearchFocused: Bool

    private var filteredTasks: [DownloadTask] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return downloadManager.queue.filter { task in
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .active: task.status.isActive
            case .queued: task.status == .queued
            case .paused: task.status == .paused
            case .completed: task.status == .completed
            case .failed: task.status == .failed || task.status == .cancelled
            }
            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }
            return task.title.lowercased().contains(query) ||
                (task.batchName?.lowercased().contains(query) ?? false) ||
                task.url.lowercased().contains(query)
        }
    }

    private var hasTerminalItems: Bool {
        downloadManager.completedCount > 0 ||
        downloadManager.failedCount > 0 ||
        downloadManager.queue.contains(where: { $0.status == .cancelled })
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                headerBar

                if downloadManager.queue.count > 1 {
                    bulkProgressStrip
                }

                if !downloadManager.queue.isEmpty {
                    filterAndSearchBar
                }
            }
            .frame(maxWidth: layout.listMaxWidth)
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()
                .overlay(VeloraTheme.hairline)

            if downloadManager.queue.isEmpty {
                ContentUnavailableView {
                    Label("Your Queue Is Clear", systemImage: "arrow.down.circle.dotted")
                } description: {
                    Text("Paste any video, playlist, or bulk URL list in Studio to start downloading.")
                } actions: {
                    if let onNavigateToStudio {
                        Button("Open Studio") {
                            onNavigateToStudio()
                        }
                        .buttonStyle(VeloraPrimaryButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredTasks.isEmpty {
                ContentUnavailableView {
                    Label("No Matching Downloads", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Try switching the queue filter or clearing your search query.")
                } actions: {
                    Button("Reset Filters") {
                        filter = .all
                        searchQuery = ""
                    }
                    .buttonStyle(VeloraSecondaryButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredTasks) { task in
                            QueueItemRow(
                                task: task,
                                isSelected: selectedTaskID == task.id,
                                isLogExpanded: expandedLogs.contains(task.id),
                                onSelect: {
                                    selectedTaskID = task.id
                                    isQueueFocused = true
                                },
                                onQuickLook: { url in
                                    quickLookURL = url
                                },
                                onToggleLog: {
                                    toggleLog(for: task.id)
                                },
                                onPause: { downloadManager.pause(id: task.id) },
                                onResume: { downloadManager.resume(id: task.id) },
                                onCancel: { downloadManager.cancel(id: task.id) },
                                onRetry: { downloadManager.retry(id: task.id) },
                                onRemove: {
                                    expandedLogs.remove(task.id)
                                    if selectedTaskID == task.id {
                                        selectedTaskID = nil
                                    }
                                    downloadManager.remove(id: task.id)
                                }
                            )
                        }
                    }
                    .frame(maxWidth: layout.listMaxWidth)
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                }
                .focusable()
                .focused($isQueueFocused)
                .focusEffectDisabled()
                .onKeyPress(.space) {
                    handleSpaceQuickLook()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VeloraTheme.ground)
        .quickLookPreview($quickLookURL)
        .confirmationDialog(
            "Cancel all active and queued downloads?",
            isPresented: $isConfirmingCancelAll,
            titleVisibility: .visible
        ) {
            Button("Cancel All Downloads", role: .destructive) {
                downloadManager.cancelAllActive()
            }
            Button("Keep Downloading", role: .cancel) {}
        } message: {
            Text("Running processes will be stopped and queued items will be marked as cancelled.")
        }
    }

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Download Queue")
                        .font(layout.font(20, weight: .semibold))
                        .foregroundStyle(VeloraTheme.inkPrimary)

                    HStack(spacing: 6) {
                        Text("\(downloadManager.activeCount) active")
                        Text("·")
                        Text("\(downloadManager.queuedCount) queued")
                        if downloadManager.pausedCount > 0 {
                            Text("·")
                            Text("\(downloadManager.pausedCount) paused")
                        }
                        Text("·")
                        Text("\(downloadManager.completedCount) completed")
                        if downloadManager.failedCount > 0 {
                            Text("·")
                            Text("\(downloadManager.failedCount) failed")
                        }
                    }
                    .font(layout.font(12.5).monospacedDigit())
                    .foregroundStyle(VeloraTheme.inkSecondary)
                }

                Spacer()

                Stepper(
                    "Parallel: \(downloadManager.maxConcurrentDownloads)",
                    value: $downloadManager.maxConcurrentDownloads,
                    in: 1...8
                )
                .font(layout.font(12.5, weight: .medium).monospacedDigit())
                .foregroundStyle(VeloraTheme.inkPrimary)
                .fixedSize()
            }

            if layout.widthClass == .compact {
                FlowWrapLayout(alignment: .leading, spacing: 8, lineSpacing: 8) {
                    queueBatchActions
                }
            } else {
                HStack(spacing: 8) {
                    queueBatchActionsLeft
                    Spacer()
                    queueBatchActionsRight
                }
            }
        }
    }

    @ViewBuilder
    private var queueBatchActions: some View {
        queueBatchActionsLeft
        queueBatchActionsRight
    }

    @ViewBuilder
    private var queueBatchActionsLeft: some View {
        if downloadManager.hasPendingOrActiveDownloads {
            Button {
                if downloadManager.isQueuePaused {
                    downloadManager.resumeQueue()
                } else {
                    downloadManager.pauseQueue()
                }
            } label: {
                Label(
                    downloadManager.isQueuePaused ? "Resume Queue" : "Pause Queue",
                    systemImage: downloadManager.isQueuePaused ? "play.fill" : "pause.fill"
                )
                .font(.caption.weight(.medium))
            }
            .buttonStyle(VeloraSecondaryButtonStyle())
        }

        if downloadManager.failedCount > 0 {
            Button {
                downloadManager.retryAllFailed()
            } label: {
                Label("Retry Failed (\(downloadManager.failedCount))", systemImage: "arrow.clockwise")
                    .font(.caption.monospacedDigit().weight(.medium))
            }
            .buttonStyle(VeloraSecondaryButtonStyle())
        }
    }

    @ViewBuilder
    private var queueBatchActionsRight: some View {
        if downloadManager.hasPendingOrActiveDownloads {
            Button("Cancel All", role: .destructive) {
                isConfirmingCancelAll = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundStyle(VeloraTheme.danger)
        }

        Button("Clear Finished") {
            downloadManager.clearFinished()
        }
        .buttonStyle(VeloraSecondaryButtonStyle(isDisabled: !hasTerminalItems))
        .disabled(!hasTerminalItems)
    }

    private var bulkProgressStrip: some View {
        let nonCancelledCount = downloadManager.queue.reduce(into: 0) { count, task in
            if task.status != .cancelled { count += 1 }
        }
        let pct = Int((downloadManager.overallQueueProgress * 100).rounded())

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: downloadManager.isQueuePaused ? "pause.circle.fill" : "square.stack.3d.down.right.fill")
                        .foregroundStyle(downloadManager.isQueuePaused ? VeloraTheme.warning : VeloraTheme.accentText)
                        .accessibilityHidden(true)
                    Text(downloadManager.isQueuePaused ? "Queue Paused (active tasks finish)" : "Batch Progress")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VeloraTheme.inkPrimary)
                }
                Spacer()
                Text("\(downloadManager.completedCount) of \(nonCancelledCount) finished (\(pct)%)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(VeloraTheme.inkSecondary)
            }

            ProgressView(value: downloadManager.overallQueueProgress)
                .tint(downloadManager.overallQueueProgress >= 1.0 ? VeloraTheme.success : VeloraTheme.accent)
        }
        .veloraCard(padding: 12, cornerRadius: 12)
    }

    @ViewBuilder
    private var filterAndSearchBar: some View {
        if layout.width >= 780 {
            HStack(spacing: 12) {
                filterPicker
                    .frame(maxWidth: layout.scaled(460))
                Spacer(minLength: 12)
                searchField
                    .frame(minWidth: 200, maxWidth: layout.scaled(300))
            }
        } else {
            VStack(spacing: 8) {
                filterPicker
                    .frame(maxWidth: .infinity)
                searchField
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var filterPicker: some View {
        Picker("Filter", selection: $filter) {
            ForEach(QueueFilter.allCases) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .accessibilityLabel("Filter queue")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(layout.font(12.5))
                .foregroundStyle(VeloraTheme.inkSecondary)
                .accessibilityHidden(true)
            TextField("Search queue…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(layout.font(13.5))
                .focused($isSearchFocused)
                .accessibilityLabel("Search queue")
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(layout.font(12.5))
                        .foregroundStyle(VeloraTheme.inkSecondary)
                        .frame(minWidth: 24, minHeight: 24)
                        .contentShape(Rectangle())
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .veloraFocusableRing(cornerRadius: 999)
                .help("Clear search")
                .accessibilityLabel("Clear queue search")
            }
        }
        .padding(.horizontal, layout.scaled(11))
        .padding(.vertical, 6)
        .frame(minHeight: layout.scaled(32))
        .background(VeloraTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(VeloraTheme.hairline, lineWidth: 1)
        )
        .veloraFocusRing(isFocused: isSearchFocused, cornerRadius: 8)
    }

    private func toggleLog(for id: UUID) {
        let update = {
            if expandedLogs.contains(id) {
                expandedLogs.remove(id)
            } else {
                expandedLogs.insert(id)
            }
        }
        if reduceMotion {
            update()
        } else {
            withAnimation(.snappy(duration: 0.18), update)
        }
    }

    private func handleSpaceQuickLook() -> KeyPress.Result {
        guard let selectedTaskID,
              let task = filteredTasks.first(where: { $0.id == selectedTaskID }),
              task.status == .completed,
              let path = task.outputFilePath,
              FileManager.default.fileExists(atPath: path) else {
            return .ignored
        }
        quickLookURL = URL(fileURLWithPath: path)
        return .handled
    }
}

private struct QueueItemRow: View {
    let task: DownloadTask
    let isSelected: Bool
    let isLogExpanded: Bool
    let onSelect: () -> Void
    let onQuickLook: (URL) -> Void
    let onToggleLog: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void

    @Environment(\.veloraLayout) private var layout

    var body: some View {
        let thumb = layout.rowThumbnailSize
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                CachedThumbnailView(
                    urlString: task.thumbnailURL,
                    width: thumb.width,
                    height: thumb.height,
                    cornerRadius: 8,
                    maxPixelSize: 220
                )
                .overlay(alignment: .bottomTrailing) {
                    statusBadgeDot
                        .offset(x: 3, y: 3)
                }

                VStack(alignment: .leading, spacing: 4) {
                    FlowWrapLayout(alignment: .leading, spacing: 6, lineSpacing: 4) {
                        if let index = task.playlistIndex, task.batchName != nil {
                            Text(String(format: "#%02d", index))
                                .font(layout.font(12, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(VeloraTheme.accentText)
                        }
                        Text(task.title)
                            .font(layout.font(14.5, weight: .semibold))
                            .foregroundStyle(VeloraTheme.inkPrimary)
                            .lineLimit(1)
                        VeloraBadge(text: task.configuration.summaryBadge, color: VeloraTheme.accentText)
                        if let batchName = task.batchName {
                            VeloraBadge(text: batchName, color: VeloraTheme.info, icon: "list.bullet.rectangle")
                        } else if let extractor = task.extractor {
                            VeloraBadge(text: extractor, color: VeloraTheme.inkSecondary)
                        }
                    }

                    Text(task.url)
                        .font(layout.font(11.5, design: .monospaced))
                        .foregroundStyle(VeloraTheme.inkSecondary.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    FlowWrapLayout(alignment: .leading, spacing: 10, lineSpacing: 4) {
                        Label {
                            Text(task.statusDetail)
                                .monospacedDigit()
                        } icon: {
                            statusSmallIcon
                                .accessibilityHidden(true)
                        }
                        .font(layout.font(12, weight: .medium))
                        .foregroundStyle(statusColor)

                        if let size = task.fileSizeText {
                            Label(size, systemImage: "internaldrive")
                                .font(layout.font(11.5).monospacedDigit())
                                .foregroundStyle(VeloraTheme.inkSecondary)
                        }
                        if let speed = task.speedText {
                            Label(speed, systemImage: "speedometer")
                                .font(layout.font(11.5).monospacedDigit())
                                .foregroundStyle(VeloraTheme.info)
                        }
                        if let eta = task.etaText {
                            Label("ETA \(eta)", systemImage: "timer")
                                .font(layout.font(11.5).monospacedDigit())
                                .foregroundStyle(VeloraTheme.inkSecondary)
                        }
                    }
                }

                Spacer(minLength: 8)

                actionButtons
            }

            if task.status.isActive || task.status == .paused || task.status == .completed {
                HStack(spacing: 10) {
                    ProgressView(value: task.progress)
                        .tint(progressTint)
                    Text("\(Int((task.progress * 100).rounded()))%")
                        .font(layout.font(12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(VeloraTheme.inkSecondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }

            if let error = task.errorMessage, task.status == .failed {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(VeloraTheme.danger)
                        .accessibilityHidden(true)
                    Text(error)
                        .font(layout.font(12))
                        .foregroundStyle(VeloraTheme.danger)
                        .textSelection(.enabled)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(VeloraTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if isLogExpanded {
                LogDrawerView(logBuffer: task.logBuffer)
            }
        }
        .veloraCard(padding: layout.scaled(15), cornerRadius: 14)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(VeloraTheme.accent, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            onSelect()
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 4) {
            if task.status == .completed, let path = task.outputFilePath {
                rowIconButton(
                    systemImage: "eye",
                    label: "Quick Look \(task.title)",
                    helpText: "Quick Look downloaded media (Space)"
                ) {
                    if FileManager.default.fileExists(atPath: path) {
                        onQuickLook(URL(fileURLWithPath: path))
                    } else {
                        let expanded = (task.configuration.outputDirectoryPath as NSString).expandingTildeInPath
                        NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
                    }
                }

                rowIconButton(
                    systemImage: "play.fill",
                    label: "Open \(task.title)",
                    helpText: "Open downloaded file"
                ) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                }

                rowIconButton(
                    systemImage: "folder",
                    label: "Reveal \(task.title) in Finder",
                    helpText: "Reveal in Finder"
                ) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }

            if task.status.isActive || task.status == .queued {
                rowIconButton(
                    systemImage: "pause.fill",
                    label: "Pause \(task.title)",
                    helpText: "Pause download"
                ) {
                    onPause()
                }

                rowIconButton(
                    systemImage: "stop.fill",
                    label: "Cancel \(task.title)",
                    helpText: "Cancel download"
                ) {
                    onCancel()
                }
            }

            if task.status == .paused {
                rowIconButton(
                    systemImage: "play.fill",
                    label: "Resume \(task.title)",
                    helpText: "Resume partial download"
                ) {
                    onResume()
                }
            }

            if task.status == .failed || task.status == .cancelled {
                rowIconButton(
                    systemImage: "arrow.clockwise",
                    label: "Retry \(task.title)",
                    helpText: "Retry download"
                ) {
                    onRetry()
                }
            }

            rowIconButton(
                systemImage: "terminal",
                label: "Toggle console log for \(task.title)",
                helpText: "Toggle live yt-dlp log",
                accessibilityValue: isLogExpanded ? "Expanded" : "Collapsed",
                isActive: isLogExpanded
            ) {
                onToggleLog()
            }

            rowIconButton(
                systemImage: "trash",
                label: "Remove \(task.title) from queue",
                helpText: "Remove from queue",
                isDestructive: true
            ) {
                onRemove()
            }
        }
    }

    private func rowIconButton(
        systemImage: String,
        label: String,
        helpText: String,
        accessibilityValue: String? = nil,
        isActive: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let size = layout.scaled(28)
        return Button(role: isDestructive ? .destructive : nil, action: action) {
            Image(systemName: systemImage)
                .font(layout.font(12, weight: .medium))
                .foregroundStyle(
                    isDestructive
                        ? VeloraTheme.danger
                        : (isActive ? VeloraTheme.accentText : VeloraTheme.inkPrimary)
                )
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isActive ? VeloraTheme.accent.opacity(0.12) : VeloraTheme.surfaceSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isActive ? VeloraTheme.accent.opacity(0.35) : VeloraTheme.hairline, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .frame(minWidth: size, minHeight: size)
        .veloraFocusableRing(cornerRadius: 7)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue ?? "")
        .help(helpText)
    }

    private var statusColor: Color {
        switch task.status {
        case .queued: VeloraTheme.inkSecondary
        case .paused: VeloraTheme.warning
        case .preparing: VeloraTheme.info
        case .downloading: VeloraTheme.accentText
        case .postProcessing: VeloraTheme.warning
        case .completed: VeloraTheme.success
        case .failed: VeloraTheme.danger
        case .cancelled: VeloraTheme.inkSecondary
        }
    }

    private var progressTint: Color {
        switch task.status {
        case .completed: VeloraTheme.success
        case .paused: VeloraTheme.warning
        default: VeloraTheme.accent
        }
    }

    @ViewBuilder
    private var statusSmallIcon: some View {
        switch task.status {
        case .queued:
            Image(systemName: "clock")
        case .paused:
            Image(systemName: "pause.circle.fill")
        case .preparing:
            Image(systemName: "sparkle.magnifyingglass")
        case .downloading:
            Image(systemName: "arrow.down.circle.fill")
        case .postProcessing:
            Image(systemName: "gearshape.2.fill")
        case .completed:
            Image(systemName: "checkmark.circle.fill")
        case .failed:
            Image(systemName: "xmark.octagon.fill")
        case .cancelled:
            Image(systemName: "slash.circle")
        }
    }

    @ViewBuilder
    private var statusBadgeDot: some View {
        ZStack {
            Circle()
                .fill(VeloraTheme.surfaceElevated)
                .frame(width: 16, height: 16)
            switch task.status {
            case .preparing:
                ProgressView()
                    .controlSize(.mini)
            case .queued:
                Image(systemName: "clock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(statusColor)
            case .paused:
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(statusColor)
            case .downloading:
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(statusColor)
            case .postProcessing:
                Image(systemName: "gearshape.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(statusColor)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(statusColor)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(statusColor)
            case .cancelled:
                Image(systemName: "slash.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(statusColor)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct LogDrawerView: View {
    let logBuffer: DownloadLogBuffer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copiedFeedback = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Live yt-dlp Output")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VeloraTheme.inkSecondary)

                Text("\(logBuffer.lines.count) lines")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(VeloraTheme.inkSecondary.opacity(0.75))

                Spacer()

                Button {
                    let text = logBuffer.lines.isEmpty ? "No log output yet." : logBuffer.joinedText
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copiedFeedback = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        copiedFeedback = false
                    }
                } label: {
                    Label(copiedFeedback ? "Copied" : "Copy Log", systemImage: copiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(.caption2.weight(.medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(copiedFeedback ? VeloraTheme.success : VeloraTheme.accentText)
                .frame(minHeight: 24)
                .disabled(logBuffer.lines.isEmpty)
                .accessibilityLabel(copiedFeedback ? "Copied console log" : "Copy console log")
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(logBuffer.lines.isEmpty ? "No log output yet." : logBuffer.joinedText)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(VeloraTheme.inkSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)

                        Color.clear
                            .frame(height: 1)
                            .id("log-bottom")
                    }
                }
                .frame(maxHeight: 160)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(VeloraTheme.surfaceSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(VeloraTheme.hairline, lineWidth: 1)
                )
                .onAppear {
                    proxy.scrollTo("log-bottom", anchor: .bottom)
                }
                .onChange(of: logBuffer.lines.count) { _, _ in
                    if reduceMotion {
                        proxy.scrollTo("log-bottom", anchor: .bottom)
                    } else {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("log-bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .padding(.top, 2)
    }
}
