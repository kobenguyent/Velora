import AppKit
import SwiftUI
import VeloraCore

private enum QueueFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case queued = "Queued"
    case completed = "Completed"
    case failed = "Failed"

    var id: String { rawValue }
}

struct QueueView: View {
    @Bindable var downloadManager: DownloadManager
    @State private var expandedLogs: Set<UUID> = []
    @State private var filter: QueueFilter = .all
    @State private var searchQuery: String = ""

    private var filteredItems: [DownloadTaskItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return downloadManager.queue.filter { item in
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .active: item.status.isActive
            case .queued: item.status == .queued
            case .completed: item.status == .completed
            case .failed: item.status == .failed || item.status == .cancelled
            }
            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }
            return item.title.lowercased().contains(query) ||
                (item.batchName?.lowercased().contains(query) ?? false) ||
                item.url.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Download Queue")
                        .font(.title2.weight(.bold))
                    Text("\(downloadManager.activeCount) active · \(downloadManager.queuedCount) queued · \(downloadManager.completedCount) completed · \(downloadManager.queue.count) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Stepper(
                    "Parallel: \(downloadManager.maxConcurrentDownloads)",
                    value: $downloadManager.maxConcurrentDownloads,
                    in: 1...8
                )
                .font(.caption.weight(.medium))
                .frame(width: 132)

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
                    }
                    .buttonStyle(.bordered)
                }

                if downloadManager.failedCount > 0 {
                    Button {
                        downloadManager.retryAllFailed()
                    } label: {
                        Label("Retry Failed (\(downloadManager.failedCount))", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                if downloadManager.hasPendingOrActiveDownloads {
                    Button("Cancel All", role: .destructive) {
                        downloadManager.cancelAllActive()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Clear Finished") {
                    downloadManager.clearFinished()
                }
                .buttonStyle(.bordered)
                .disabled(!downloadManager.queue.contains(where: { $0.status.isTerminal }))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)

            if downloadManager.queue.count > 1 {
                bulkProgressStrip
            }

            if !downloadManager.queue.isEmpty {
                HStack(spacing: 12) {
                    Picker("Filter", selection: $filter) {
                        ForEach(QueueFilter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 380)

                    Spacer()

                    TextField("Search queue or playlist…", text: $searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 230)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 10)
            }

            Divider()

            if downloadManager.queue.isEmpty {
                ContentUnavailableView(
                    "Your Queue Is Clear",
                    systemImage: "arrow.down.circle.dotted",
                    description: Text("Paste any video, playlist, or bulk URL list in Studio to start downloading.")
                )
            } else if filteredItems.isEmpty {
                ContentUnavailableView(
                    "No Matching Downloads",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Try switching the queue filter or clearing your search query.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredItems) { item in
                            QueueItemCard(
                                item: item,
                                isLogExpanded: expandedLogs.contains(item.id),
                                onToggleLog: {
                                    if expandedLogs.contains(item.id) {
                                        expandedLogs.remove(item.id)
                                    } else {
                                        expandedLogs.insert(item.id)
                                    }
                                },
                                onCancel: { downloadManager.cancel(id: item.id) },
                                onRetry: { downloadManager.retry(id: item.id) },
                                onRemove: { downloadManager.remove(id: item.id) }
                            )
                        }
                    }
                    .padding(22)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var bulkProgressStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: downloadManager.isQueuePaused ? "pause.circle.fill" : "square.stack.3d.down.right.fill")
                        .foregroundStyle(downloadManager.isQueuePaused ? VeloraTheme.amber : VeloraTheme.cyan)
                    Text(downloadManager.isQueuePaused ? "Bulk Queue Paused (active items will finish)" : "Bulk Progress")
                        .font(.caption.weight(.semibold))
                }
                Spacer()
                Text("\(downloadManager.completedCount) of \(downloadManager.queue.filter { $0.status != .cancelled }.count) finished (\(Int((downloadManager.overallQueueProgress * 100).rounded()))%)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: downloadManager.overallQueueProgress)
                .tint(downloadManager.overallQueueProgress >= 1.0 ? VeloraTheme.emerald : VeloraTheme.cyan)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 10)
    }
}

private struct QueueItemCard: View {
    let item: DownloadTaskItem
    let isLogExpanded: Bool
    let onToggleLog: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                statusIcon
                    .frame(width: 34, height: 34)
                    .background(statusColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if let index = item.playlistIndex, item.batchName != nil {
                            Text(String(format: "#%02d", index))
                                .font(.system(.caption, design: .monospaced, weight: .bold))
                                .foregroundStyle(VeloraTheme.cyan)
                        }
                        Text(item.title)
                            .font(.headline)
                            .lineLimit(1)
                        VeloraBadge(text: item.configuration.summaryBadge, color: VeloraTheme.violet)
                        if let batchName = item.batchName {
                            VeloraBadge(text: batchName, color: VeloraTheme.cyan, icon: "list.bullet.rectangle")
                        } else if let extractor = item.extractor {
                            VeloraBadge(text: extractor, color: .secondary)
                        }
                    }

                    Text(item.url)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 12) {
                        Text(item.statusDetail)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(statusColor)

                        if let size = item.fileSizeText {
                            Label(size, systemImage: "internaldrive")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if let speed = item.speedText {
                            Label(speed, systemImage: "speedometer")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(VeloraTheme.cyan)
                        }
                        if let eta = item.etaText {
                            Label("ETA \(eta)", systemImage: "timer")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    if item.status == .completed, let path = item.outputFilePath {
                        Button {
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.bordered)
                        .help("Open downloaded file")

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.bordered)
                        .help("Reveal in Finder")
                    }

                    if item.status.isActive || item.status == .queued {
                        Button {
                            onCancel()
                        } label: {
                            Image(systemName: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                        .help("Cancel download")
                    }

                    if item.status == .failed || item.status == .cancelled {
                        Button {
                            onRetry()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .help("Retry download")
                    }

                    Button {
                        onToggleLog()
                    } label: {
                        Image(systemName: "terminal")
                    }
                    .buttonStyle(.bordered)
                    .help("Toggle live yt-dlp log")

                    Button(role: .destructive) {
                        onRemove()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove from queue")
                }
            }

            if item.status.isActive || item.status == .completed {
                HStack(spacing: 10) {
                    ProgressView(value: item.progress)
                        .tint(item.status == .completed ? VeloraTheme.emerald : VeloraTheme.violet)
                    Text("\(Int((item.progress * 100).rounded()))%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            }

            if let error = item.errorMessage, item.status == .failed {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            if isLogExpanded {
                ScrollView {
                    Text(item.logs.isEmpty ? "No log output yet." : item.logs.joined(separator: "\n"))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 160)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
            }
        }
        .veloraCard(padding: 14)
    }

    private var statusColor: Color {
        switch item.status {
        case .queued: .secondary
        case .preparing: VeloraTheme.cyan
        case .downloading: VeloraTheme.violet
        case .postProcessing: VeloraTheme.amber
        case .completed: VeloraTheme.emerald
        case .failed: .red
        case .cancelled: .secondary
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .queued:
            Image(systemName: "clock").foregroundStyle(statusColor)
        case .preparing:
            ProgressView().controlSize(.small)
        case .downloading:
            Image(systemName: "arrow.down").foregroundStyle(statusColor)
        case .postProcessing:
            Image(systemName: "gearshape.2.fill").foregroundStyle(statusColor)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(statusColor)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(statusColor)
        case .cancelled:
            Image(systemName: "slash.circle").foregroundStyle(statusColor)
        }
    }
}
