import SwiftUI
import VeloraCore

struct PlaylistPickerSheet: View {
    let mediaInfo: MediaInfo
    let defaultCreateSubfolder: Bool
    let onQueueSelected: ([PlaylistEntry], Bool, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String> = []
    @State private var searchQuery: String = ""
    @State private var rangeExpression: String = ""
    @State private var createSubfolder: Bool
    @State private var prefixIndex: Bool = true

    init(
        mediaInfo: MediaInfo,
        defaultCreateSubfolder: Bool,
        onQueueSelected: @escaping ([PlaylistEntry], Bool, Bool) -> Void
    ) {
        self.mediaInfo = mediaInfo
        self.defaultCreateSubfolder = defaultCreateSubfolder
        self.onQueueSelected = onQueueSelected
        self._createSubfolder = State(initialValue: defaultCreateSubfolder)
    }

    private var filteredEntries: [PlaylistEntry] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return mediaInfo.playlistEntries }
        return mediaInfo.playlistEntries.filter { entry in
            entry.title.lowercased().contains(query) ||
            (entry.uploader?.lowercased().contains(query) ?? false) ||
            "\(entry.index)".contains(query)
        }
    }

    private var selectedEntriesOrdered: [PlaylistEntry] {
        mediaInfo.playlistEntries.filter { selectedIDs.contains($0.id) }
    }

    private var unavailableCount: Int {
        mediaInfo.playlistEntries.filter(\.isUnavailable).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(VeloraTheme.brandGradient)
                        .frame(width: 42, height: 42)
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(mediaInfo.title)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        VeloraBadge(
                            text: "\(selectedIDs.count) of \(mediaInfo.playlistEntries.count) selected",
                            color: VeloraTheme.violet,
                            icon: "checkmark.circle"
                        )
                        if let totalDuration = mediaInfo.totalPlaylistDurationFormatted {
                            VeloraBadge(text: totalDuration, color: VeloraTheme.cyan, icon: "clock")
                        }
                        if unavailableCount > 0 {
                            VeloraBadge(text: "\(unavailableCount) unavailable", color: .orange, icon: "eye.slash")
                        }
                        if let uploader = mediaInfo.uploader {
                            Text(uploader)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
            }

            // Search + Selection Toolbar
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter by title, channel, or #…", text: $searchQuery)
                        .textFieldStyle(.plain)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(VeloraTheme.subtleCardBorder, lineWidth: 1)
                )

                HStack(spacing: 6) {
                    TextField("Range (e.g. 1-10, 15)", text: $rangeExpression)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 155)
                        .onSubmit { applyRangeSelection() }

                    Button("Apply") {
                        applyRangeSelection()
                    }
                    .buttonStyle(.bordered)
                    .disabled(rangeExpression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Divider()
                    .frame(height: 18)

                Button("All") {
                    for entry in filteredEntries where !entry.isUnavailable {
                        selectedIDs.insert(entry.id)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("None") {
                    for entry in filteredEntries {
                        selectedIDs.remove(entry.id)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Invert") {
                    for entry in filteredEntries where !entry.isUnavailable {
                        if selectedIDs.contains(entry.id) {
                            selectedIDs.remove(entry.id)
                        } else {
                            selectedIDs.insert(entry.id)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Entries list
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filteredEntries) { entry in
                        PlaylistEntryRow(
                            entry: entry,
                            isSelected: selectedIDs.contains(entry.id),
                            onToggle: {
                                if selectedIDs.contains(entry.id) {
                                    selectedIDs.remove(entry.id)
                                } else {
                                    selectedIDs.insert(entry.id)
                                }
                            }
                        )
                    }
                }
                .padding(8)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(VeloraTheme.subtleCardBorder, lineWidth: 1)
            )

            // Bottom options & CTA
            HStack(spacing: 16) {
                Toggle("Create playlist subfolder", isOn: $createSubfolder)
                    .font(.callout)
                Toggle("Number files (01 - Title)", isOn: $prefixIndex)
                    .font(.callout)

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button {
                    let chosen = selectedEntriesOrdered
                    guard !chosen.isEmpty else { return }
                    onQueueSelected(chosen, createSubfolder, prefixIndex)
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Queue \(selectedIDs.count) Video\(selectedIDs.count == 1 ? "" : "s")")
                    }
                }
                .buttonStyle(VeloraPrimaryButtonStyle(isDisabled: selectedIDs.isEmpty))
                .disabled(selectedIDs.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 820, height: 580)
        .onAppear {
            selectedIDs = Set(mediaInfo.availablePlaylistEntries.map(\.id))
        }
    }

    private func applyRangeSelection() {
        let indices = PlaylistURLDetector.parseSelectionRange(
            rangeExpression,
            maxIndex: mediaInfo.playlistEntries.count
        )
        guard !indices.isEmpty else { return }
        selectedIDs = Set(
            mediaInfo.playlistEntries
                .filter { indices.contains($0.index) && !$0.isUnavailable }
                .map(\.id)
        )
    }
}

private struct PlaylistEntryRow: View {
    let entry: PlaylistEntry
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.body)
                    .foregroundStyle(isSelected ? VeloraTheme.violet : .secondary)

                Text(String(format: "#%02d", entry.index))
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .leading)

                thumbnail
                    .frame(width: 64, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(entry.isUnavailable ? .secondary : .primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if let uploader = entry.uploader {
                            Text(uploader)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if entry.isUnavailable {
                            VeloraBadge(text: "Unavailable", color: .orange)
                        }
                    }
                }

                Spacer()

                if let duration = entry.formattedDuration {
                    Text(duration)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? VeloraTheme.violet.opacity(0.09) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumbStr = entry.thumbnailURL, let url = URL(string: thumbStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.14)
            Image(systemName: "play.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
