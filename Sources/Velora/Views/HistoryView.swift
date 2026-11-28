import AppKit
import QuickLook
import SwiftUI
import VeloraCore

private enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case video = "Video"
    case audio = "Audio"
    case missing = "Missing on Disk"

    var id: String { rawValue }
}

private enum HistorySort: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case largest = "Largest"
    case title = "Title"

    var id: String { rawValue }
}

struct HistoryView: View {
    let downloadManager: DownloadManager
    let onRedownload: (String) -> Void

    @Environment(\.veloraLayout) private var layout
    @State private var searchQuery = ""
    @State private var filter: HistoryFilter = .all
    @State private var sortOrder: HistorySort = .newest
    @State private var fileExistenceMap: [UUID: Bool] = [:]
    @State private var selectedEntryID: UUID?
    @State private var quickLookURL: URL?
    @State private var isConfirmingClearHistory = false
    @State private var diskCheckToken = UUID()
    @FocusState private var isHistoryFocused: Bool
    @FocusState private var isSearchFocused: Bool

    private var missingCount: Int {
        downloadManager.history.reduce(into: 0) { count, entry in
            if fileExistenceMap[entry.id] == false {
                count += 1
            }
        }
    }

    private var filteredEntries: [DownloadHistoryEntry] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered = downloadManager.history.filter { entry in
            let matchesFilter: Bool = switch filter {
            case .all:
                true
            case .video:
                !Self.isAudioEntry(entry)
            case .audio:
                Self.isAudioEntry(entry)
            case .missing:
                fileExistenceMap[entry.id] == false
            }
            guard matchesFilter else { return false }

            guard !query.isEmpty else { return true }
            return entry.title.lowercased().contains(query) ||
                (entry.uploader?.lowercased().contains(query) ?? false) ||
                (entry.extractor?.lowercased().contains(query) ?? false) ||
                entry.url.lowercased().contains(query)
        }

        switch sortOrder {
        case .newest:
            return filtered.sorted { $0.completedAt > $1.completedAt }
        case .largest:
            return filtered.sorted { lhs, rhs in
                let lSize = lhs.fileSizeBytes ?? -1
                let rSize = rhs.fileSizeBytes ?? -1
                if lSize != rSize { return lSize > rSize }
                return lhs.completedAt > rhs.completedAt
            }
        case .title:
            return filtered.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                headerBar

                if !downloadManager.history.isEmpty {
                    filterAndSortBar
                }
            }
            .frame(maxWidth: layout.listMaxWidth)
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()
                .overlay(VeloraTheme.hairline)

            if downloadManager.history.isEmpty {
                ContentUnavailableView(
                    "No Completed Downloads Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Finished downloads appear here with Quick Look, Reveal in Finder, and one-click re-download.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredEntries.isEmpty {
                ContentUnavailableView {
                    Label("No Matching History", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Try switching filters or searching with another keyword.")
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
                    LazyVStack(spacing: 10) {
                        ForEach(filteredEntries) { entry in
                            let existsOnDisk = fileExistenceMap[entry.id] ?? (entry.outputFilePath != nil)
                            HistoryEntryRow(
                                entry: entry,
                                existsOnDisk: existsOnDisk,
                                isSelected: selectedEntryID == entry.id,
                                onSelect: {
                                    selectedEntryID = entry.id
                                    isHistoryFocused = true
                                },
                                onQuickLook: { url in
                                    quickLookURL = url
                                },
                                onRedownload: {
                                    onRedownload(entry.url)
                                },
                                onRemove: {
                                    if selectedEntryID == entry.id {
                                        selectedEntryID = nil
                                    }
                                    downloadManager.removeHistoryEntry(id: entry.id)
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
                .focused($isHistoryFocused)
                .focusEffectDisabled()
                .onKeyPress(.space) {
                    handleSpaceQuickLook()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VeloraTheme.ground)
        .quickLookPreview($quickLookURL)
        .task(id: HistoryRefreshKey(entries: downloadManager.history, token: diskCheckToken)) {
            await refreshFileExistence()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            diskCheckToken = UUID()
        }
        .confirmationDialog(
            "Clear all download history?",
            isPresented: $isConfirmingClearHistory,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                downloadManager.clearHistory()
            }
            Button("Keep History", role: .cancel) {}
        } message: {
            Text("This removes all \(downloadManager.history.count) history entries from Velora. Downloaded files on disk are not deleted.")
        }
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Download History")
                    .font(layout.font(20, weight: .semibold))
                    .foregroundStyle(VeloraTheme.inkPrimary)

                HStack(spacing: 6) {
                    Text("\(downloadManager.history.count) completed downloads")
                    if missingCount > 0 {
                        Text("·")
                        Text("\(missingCount) missing on disk")
                            .foregroundStyle(VeloraTheme.warning)
                    }
                }
                .font(layout.font(12.5).monospacedDigit())
                .foregroundStyle(VeloraTheme.inkSecondary)
            }

            Spacer()

            if missingCount > 0 {
                Button {
                    cleanUpMissingEntries()
                } label: {
                    Label("Clean Up Missing (\(missingCount))", systemImage: "sparkles")
                        .font(.caption.monospacedDigit().weight(.medium))
                }
                .buttonStyle(VeloraSecondaryButtonStyle())
            }

            Button("Clear History", role: .destructive) {
                isConfirmingClearHistory = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundStyle(VeloraTheme.danger)
            .disabled(downloadManager.history.isEmpty)
        }
    }

    @ViewBuilder
    private var filterAndSortBar: some View {
        if layout.width >= 860 {
            HStack(spacing: 10) {
                filterPicker
                    .frame(maxWidth: layout.scaled(380))

                Spacer(minLength: 10)

                sortPicker

                searchField
                    .frame(minWidth: 200, maxWidth: layout.scaled(280))
            }
        } else {
            VStack(spacing: 8) {
                filterPicker
                    .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    sortPicker
                    searchField
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var filterPicker: some View {
        Picker("Filter", selection: $filter) {
            ForEach(HistoryFilter.allCases) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .accessibilityLabel("Filter history")
    }

    private var sortPicker: some View {
        Picker("Sort", selection: $sortOrder) {
            ForEach(HistorySort.allCases) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .labelsHidden()
        .frame(width: 110)
        .accessibilityLabel("Sort history")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(layout.font(12.5))
                .foregroundStyle(VeloraTheme.inkSecondary)
                .accessibilityHidden(true)
            TextField("Search title, channel, URL…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(layout.font(13.5))
                .focused($isSearchFocused)
                .accessibilityLabel("Search download history")
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
                .accessibilityLabel("Clear history search")
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

    private func refreshFileExistence() async {
        let pairs = downloadManager.history.map { ($0.id, $0.outputFilePath) }
        let computed = await Task.detached(priority: .utility) {
            var map: [UUID: Bool] = [:]
            map.reserveCapacity(pairs.count)
            let fm = FileManager.default
            for (id, path) in pairs {
                if let path, !path.isEmpty {
                    map[id] = fm.fileExists(atPath: path)
                } else {
                    map[id] = false
                }
            }
            return map
        }.value

        guard !Task.isCancelled else { return }
        fileExistenceMap = computed
    }

    private func cleanUpMissingEntries() {
        let missingIDs = downloadManager.history
            .filter { fileExistenceMap[$0.id] == false }
            .map(\.id)
        for id in missingIDs {
            downloadManager.removeHistoryEntry(id: id)
        }
    }

    private func handleSpaceQuickLook() -> KeyPress.Result {
        guard let selectedEntryID,
              let entry = filteredEntries.first(where: { $0.id == selectedEntryID }),
              let path = entry.outputFilePath,
              fileExistenceMap[entry.id] == true else {
            return .ignored
        }
        quickLookURL = URL(fileURLWithPath: path)
        return .handled
    }

    private static func isAudioEntry(_ entry: DownloadHistoryEntry) -> Bool {
        let upper = entry.formatSummary.uppercased()
        let audioPrefixes = ["M4A", "MP3", "FLAC", "WAV", "OPUS", "AAC"]
        return audioPrefixes.contains { prefix in
            upper.hasPrefix(prefix) || upper.contains("· \(prefix)")
        }
    }

    private struct HistoryRefreshKey: Equatable {
        let entries: [DownloadHistoryEntry]
        let token: UUID
    }
}

private struct HistoryEntryRow: View {
    let entry: DownloadHistoryEntry
    let existsOnDisk: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onQuickLook: (URL) -> Void
    let onRedownload: () -> Void
    let onRemove: () -> Void

    @Environment(\.veloraLayout) private var layout

    var body: some View {
        let thumb = layout.rowThumbnailSize
        HStack(spacing: 14) {
            CachedThumbnailView(
                urlString: entry.thumbnailURL,
                width: thumb.width,
                height: thumb.height,
                cornerRadius: 8,
                maxPixelSize: 220,
                fallbackSymbol: existsOnDisk ? "play.rectangle" : "doc.questionmark"
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(layout.font(14.5, weight: .semibold))
                        .foregroundStyle(VeloraTheme.inkPrimary)
                        .lineLimit(1)
                    VeloraBadge(text: entry.formatSummary, color: VeloraTheme.accentText)
                    if let extractor = entry.extractor {
                        VeloraBadge(text: extractor, color: VeloraTheme.inkSecondary)
                    }
                    if !existsOnDisk {
                        VeloraBadge(text: "Missing", color: VeloraTheme.warning, icon: "exclamationmark.circle")
                    }
                }

                HStack(spacing: 10) {
                    if let uploader = entry.uploader {
                        Text(uploader)
                            .font(layout.font(12))
                            .foregroundStyle(VeloraTheme.inkSecondary)
                            .lineLimit(1)
                    }
                    if let size = entry.formattedSize {
                        Text(size)
                            .font(layout.font(12).monospacedDigit())
                            .foregroundStyle(VeloraTheme.inkSecondary)
                    }
                    Text(entry.completedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(layout.font(12).monospacedDigit())
                        .foregroundStyle(VeloraTheme.inkSecondary.opacity(0.75))
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                if let path = entry.outputFilePath, existsOnDisk {
                    iconButton(systemImage: "eye", label: "Quick Look \(entry.title)", helpText: "Quick Look media (Space)") {
                        onQuickLook(URL(fileURLWithPath: path))
                    }

                    iconButton(systemImage: "play.fill", label: "Open \(entry.title)", helpText: "Open downloaded file") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }

                    iconButton(systemImage: "folder", label: "Reveal \(entry.title) in Finder", helpText: "Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                } else {
                    iconButton(systemImage: "folder", label: "Open output folder for \(entry.title)", helpText: "Open output folder") {
                        let expanded = (entry.outputDirectoryPath as NSString).expandingTildeInPath
                        NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
                    }
                }

                iconButton(systemImage: "arrow.uturn.backward", label: "Re-download \(entry.title)", helpText: "Load URL back into Studio") {
                    onRedownload()
                }

                iconButton(systemImage: "trash", label: "Remove \(entry.title) from history", helpText: "Remove from history", isDestructive: true) {
                    onRemove()
                }
            }
        }
        .veloraCard(padding: layout.scaled(14), cornerRadius: 14)
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

    private func iconButton(
        systemImage: String,
        label: String,
        helpText: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let size = layout.scaled(28)
        return Button(role: isDestructive ? .destructive : nil, action: action) {
            Image(systemName: systemImage)
                .font(layout.font(12, weight: .medium))
                .foregroundStyle(isDestructive ? VeloraTheme.danger : VeloraTheme.inkPrimary)
                .frame(width: size, height: size)
                .background(VeloraTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(VeloraTheme.hairline, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .frame(minWidth: size, minHeight: size)
        .veloraFocusableRing(cornerRadius: 7)
        .accessibilityLabel(label)
        .help(helpText)
    }
}
