import AppKit
import SwiftUI
import VeloraCore

struct QueueView: View {
    let downloadManager: DownloadManager
    @State private var expandedLogs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Download Queue")
                        .font(.title2.weight(.bold))
                    Text("\(downloadManager.activeCount) active · \(downloadManager.queuedCount) queued · \(downloadManager.queue.count) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if downloadManager.hasActiveDownloads {
                    Button("Cancel All Active", role: .destructive) {
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
            .padding(.vertical, 16)

            Divider()

            if downloadManager.queue.isEmpty {
                ContentUnavailableView(
                    "Your Queue Is Clear",
                    systemImage: "arrow.down.circle.dotted",
                    description: Text("Paste any video or playlist link in Studio to start downloading.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(downloadManager.queue) { item in
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
                        Text(item.title)
                            .font(.headline)
                            .lineLimit(1)
                        VeloraBadge(text: item.configuration.summaryBadge, color: VeloraTheme.violet)
                        if let extractor = item.extractor {
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
