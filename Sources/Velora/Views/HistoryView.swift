import AppKit
import SwiftUI
import VeloraCore

struct HistoryView: View {
    let downloadManager: DownloadManager
    let onRedownload: (String) -> Void

    @State private var searchQuery = ""

    private var filteredEntries: [DownloadHistoryEntry] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return downloadManager.history }
        return downloadManager.history.filter { entry in
            entry.title.lowercased().contains(query) ||
            (entry.uploader?.lowercased().contains(query) ?? false) ||
            (entry.extractor?.lowercased().contains(query) ?? false) ||
            entry.url.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Download History")
                        .font(.title2.weight(.bold))
                    Text("\(downloadManager.history.count) completed downloads")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                TextField("Search title, channel, or URL…", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)

                Button("Clear History", role: .destructive) {
                    downloadManager.clearHistory()
                }
                .buttonStyle(.bordered)
                .disabled(downloadManager.history.isEmpty)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)

            Divider()

            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    downloadManager.history.isEmpty ? "No Completed Downloads Yet" : "No Matching History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(downloadManager.history.isEmpty
                                      ? "Finished downloads will appear here with quick Reveal in Finder actions."
                                      : "Try a different search keyword.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredEntries) { entry in
                            HStack(spacing: 14) {
                                Image(systemName: entry.fileExistsOnDisk ? "film.fill" : "doc.questionmark")
                                    .font(.title3)
                                    .foregroundStyle(entry.fileExistsOnDisk ? VeloraTheme.violet : .secondary)
                                    .frame(width: 36, height: 36)
                                    .background(VeloraTheme.violet.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(entry.title)
                                            .font(.headline)
                                            .lineLimit(1)
                                        VeloraBadge(text: entry.formatSummary, color: VeloraTheme.cyan)
                                        if let extractor = entry.extractor {
                                            VeloraBadge(text: extractor, color: .secondary)
                                        }
                                    }

                                    HStack(spacing: 12) {
                                        if let uploader = entry.uploader {
                                            Text(uploader)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let size = entry.formattedSize {
                                            Text(size)
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(entry.completedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }

                                Spacer()

                                HStack(spacing: 6) {
                                    if let path = entry.outputFilePath, entry.fileExistsOnDisk {
                                        Button {
                                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                                        } label: {
                                            Label("Open", systemImage: "play.fill")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.bordered)

                                        Button {
                                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                                        } label: {
                                            Image(systemName: "folder")
                                        }
                                        .buttonStyle(.bordered)
                                        .help("Reveal in Finder")
                                    } else {
                                        Button {
                                            let expanded = (entry.outputDirectoryPath as NSString).expandingTildeInPath
                                            NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
                                        } label: {
                                            Image(systemName: "folder")
                                        }
                                        .buttonStyle(.bordered)
                                        .help("Open output folder")
                                    }

                                    Button {
                                        onRedownload(entry.url)
                                    } label: {
                                        Image(systemName: "arrow.uturn.backward")
                                    }
                                    .buttonStyle(.bordered)
                                    .help("Load URL back into Studio")

                                    Button(role: .destructive) {
                                        downloadManager.removeHistoryEntry(id: entry.id)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .veloraCard(padding: 13)
                        }
                    }
                    .padding(22)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
