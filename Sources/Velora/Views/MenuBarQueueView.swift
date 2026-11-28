import AppKit
import SwiftUI
import VeloraCore

/// Minimalist native MenuBarExtra popover showing aggregate progress, quick actions, and live task rows.
struct MenuBarQueueView: View {
    let engineManager: EngineManager
    let downloadManager: DownloadManager
    let studio: StudioViewModel
    let onOpenMainWindow: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow

            actionRow

            Divider()
                .overlay(VeloraTheme.hairline)

            queueSection

            Divider()
                .overlay(VeloraTheme.hairline)

            footerRow
        }
        .padding(14)
        .frame(width: 320)
        .background(VeloraTheme.ground)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("Velora")
                .font(.headline)
                .foregroundStyle(VeloraTheme.inkPrimary)

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(engineStatusColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(engineStatusLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(VeloraTheme.inkSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Engine status: \(engineStatusLabel)")
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                pasteAndDownload()
            } label: {
                Label("Paste & Download", systemImage: "doc.on.clipboard")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(VeloraPrimaryButtonStyle())
            .accessibilityLabel("Paste URL from clipboard and download")

            Button {
                if downloadManager.isQueuePaused {
                    downloadManager.resumeQueue()
                } else {
                    downloadManager.pauseQueue()
                }
            } label: {
                Label(
                    downloadManager.isQueuePaused ? "Resume All" : "Pause All",
                    systemImage: downloadManager.isQueuePaused ? "play.fill" : "pause.fill"
                )
                .font(.subheadline.weight(.medium))
            }
            .buttonStyle(VeloraSecondaryButtonStyle())
            .disabled(downloadManager.queue.isEmpty)
            .accessibilityLabel(downloadManager.isQueuePaused ? "Resume all downloads" : "Pause all downloads")
        }
    }

    @ViewBuilder
    private var queueSection: some View {
        let slice = Array(downloadManager.queue.prefix(3))
        if slice.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray")
                    .font(.title3)
                    .foregroundStyle(VeloraTheme.inkSecondary.opacity(0.6))
                    .accessibilityHidden(true)
                Text("No downloads in queue")
                    .font(.subheadline)
                    .foregroundStyle(VeloraTheme.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        } else {
            VStack(spacing: 8) {
                ForEach(slice) { task in
                    MenuBarTaskRow(task: task)
                }
            }
        }
    }

    private var footerRow: some View {
        HStack(spacing: 8) {
            Text(aggregateSummary)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(VeloraTheme.inkSecondary)

            Spacer()

            Button("Open Velora") {
                dismiss()
                onOpenMainWindow()
            }
            .buttonStyle(VeloraSecondaryButtonStyle())
            .controlSize(.small)
        }
    }

    private var engineStatusColor: Color {
        if engineManager.isFullyReady { return VeloraTheme.success }
        if engineManager.isReadyForBasicDownloads { return VeloraTheme.warning }
        return VeloraTheme.danger
    }

    private var engineStatusLabel: String {
        engineManager.isReadyForBasicDownloads ? "Engines Ready" : "Setup Needed"
    }

    private var aggregateSummary: String {
        if downloadManager.activeCount > 0 || downloadManager.queuedCount > 0 {
            return "\(downloadManager.activeCount) active · \(downloadManager.queuedCount) queued"
        }
        if downloadManager.pausedCount > 0 {
            return "\(downloadManager.pausedCount) paused"
        }
        return "\(downloadManager.completedCount) completed"
    }

    private func pasteAndDownload() {
        guard let raw = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty else {
            dismiss()
            onOpenMainWindow()
            studio.showToast("Clipboard does not contain a media URL.", kind: .warning)
            return
        }

        let urls = YTDLPCommandBuilder.extractURLs(from: raw)
        guard !urls.isEmpty else {
            dismiss()
            onOpenMainWindow()
            studio.showToast("No valid http/https URL found on clipboard.", kind: .warning)
            return
        }

        if !engineManager.isReadyForBasicDownloads {
            studio.isBatchMode = urls.count > 1
            studio.urlInput = urls.joined(separator: "\n")
            studio.isShowingEngineSetup = true
            studio.showToast("Install yt-dlp via Engine Setup first.", kind: .warning)
            dismiss()
            onOpenMainWindow()
            return
        }

        if urls.count > 1 {
            studio.isBatchMode = true
            studio.urlInput = urls.joined(separator: "\n")
            studio.startDownload(downloadManager: downloadManager, engineManager: engineManager)
        } else if let single = urls.first {
            if downloadManager.hasPendingOrActiveDownload(for: single) {
                studio.showToast("This URL is already active or queued.", kind: .info)
            } else {
                studio.isBatchMode = false
                studio.urlInput = single
                studio.startDownload(downloadManager: downloadManager, engineManager: engineManager)
            }
        }
    }
}

/// Observes a single `DownloadTask` so 10Hz progress ticks update only this row.
private struct MenuBarTaskRow: View {
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(task.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(VeloraTheme.inkPrimary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(trailingLabel)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(statusColor)
            }

            if task.status.isActive || task.status == .paused {
                ProgressView(value: task.progress)
                    .progressViewStyle(.linear)
                    .tint(statusColor)
            }

            HStack(spacing: 6) {
                Text(task.statusDetail)
                    .font(.caption2)
                    .foregroundStyle(VeloraTheme.inkSecondary)
                    .lineLimit(1)
                Spacer()
                if let speed = task.speedText, task.status == .downloading {
                    Text(speed)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(VeloraTheme.info)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(VeloraTheme.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(VeloraTheme.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.title), \(task.status.displayName), \(task.statusDetail)")
    }

    private var trailingLabel: String {
        switch task.status {
        case .downloading, .postProcessing, .paused:
            return "\(Int((task.progress * 100).rounded()))%"
        default:
            return task.status.displayName
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .completed: VeloraTheme.success
        case .failed, .cancelled: VeloraTheme.danger
        case .paused: VeloraTheme.warning
        case .downloading, .preparing, .postProcessing: VeloraTheme.accent
        case .queued: VeloraTheme.inkSecondary
        }
    }
}
