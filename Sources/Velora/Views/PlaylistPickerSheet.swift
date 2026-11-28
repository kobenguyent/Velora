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
    @State private var rangeFeedback: String? = nil
    @State private var createSubfolder: Bool
    @State private var prefixIndex: Bool = true
    @FocusState private var isSearchFocused: Bool

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
            headerSection

            toolbarSection

            if let rangeFeedback {
                Text(rangeFeedback)
                    .font(.caption)
                    .foregroundStyle(VeloraTheme.warning)
            }

            entriesListSection

            bottomBar
        }
        .padding(20)
        .frame(minWidth: 620, idealWidth: 860, maxWidth: 1140, minHeight: 460, idealHeight: 600, maxHeight: 820)
        .background(VeloraTheme.ground)
        .onAppear {
            selectedIDs = Set(mediaInfo.availablePlaylistEntries.map(\.id))
        }
        .onChange(of: rangeExpression) { _, _ in
            rangeFeedback = nil
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(VeloraTheme.accent)
                    .frame(width: 42, height: 42)
                Image(systemName: "list.bullet.rectangle.portrait.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(mediaInfo.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(VeloraTheme.inkPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    VeloraBadge(
                        text: "\(selectedIDs.count) of \(mediaInfo.playlistEntries.count) selected",
                        color: VeloraTheme.accentText,
                        icon: "checkmark.circle"
                    )
                    if let totalDuration = mediaInfo.totalPlaylistDurationFormatted {
                        VeloraBadge(text: totalDuration, color: VeloraTheme.info, icon: "clock")
                    }
                    if unavailableCount > 0 {
                        VeloraBadge(text: "\(unavailableCount) unavailable", color: VeloraTheme.warning, icon: "eye.slash")
                    }
                    if let uploader = mediaInfo.uploader {
                        Text(uploader)
                            .font(.caption)
                            .foregroundStyle(VeloraTheme.inkSecondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()
        }
    }

    private var toolbarSection: some View {
        FlowWrapLayout(alignment: .leading, spacing: 10, lineSpacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(VeloraTheme.inkSecondary)
                    .accessibilityHidden(true)
                TextField("Filter by title, channel, or #…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(VeloraTheme.inkPrimary)
                    .focused($isSearchFocused)
                    .accessibilityLabel("Filter playlist videos")
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(VeloraTheme.inkSecondary)
                            .frame(minWidth: 24, minHeight: 24)
                            .contentShape(Rectangle())
                            .accessibilityHidden(true)
                    }
                    .buttonStyle(.plain)
                    .veloraFocusableRing(cornerRadius: 999)
                    .accessibilityLabel("Clear search filter")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 200, maxWidth: 280)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(VeloraTheme.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(VeloraTheme.hairline, lineWidth: 1)
            )
            .veloraFocusRing(isFocused: isSearchFocused, cornerRadius: 8)

            HStack(spacing: 6) {
                TextField("Range (e.g. 1-10, 15)", text: $rangeExpression)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
                    .frame(width: 155)
                    .onSubmit { applyRangeSelection() }
                    .accessibilityLabel("Playlist item range")

                Button("Apply") {
                    applyRangeSelection()
                }
                .buttonStyle(VeloraSecondaryButtonStyle(isDisabled: rangeExpression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                .controlSize(.small)
                .disabled(rangeExpression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 6) {
                Button("All") {
                    for entry in filteredEntries where !entry.isUnavailable {
                        selectedIDs.insert(entry.id)
                    }
                }
                .buttonStyle(VeloraSecondaryButtonStyle())
                .controlSize(.small)
                .accessibilityLabel("Select all visible videos")

                Button("None") {
                    for entry in filteredEntries {
                        selectedIDs.remove(entry.id)
                    }
                }
                .buttonStyle(VeloraSecondaryButtonStyle())
                .controlSize(.small)
                .accessibilityLabel("Deselect all visible videos")

                Button("Invert") {
                    for entry in filteredEntries where !entry.isUnavailable {
                        if selectedIDs.contains(entry.id) {
                            selectedIDs.remove(entry.id)
                        } else {
                            selectedIDs.insert(entry.id)
                        }
                    }
                }
                .buttonStyle(VeloraSecondaryButtonStyle())
                .controlSize(.small)
                .accessibilityLabel("Invert visible video selection")
            }
        }
    }

    @ViewBuilder
    private var entriesListSection: some View {
        Group {
            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    "No Matching Videos",
                    systemImage: "magnifyingglass",
                    description: Text("No playlist entries match \"\(searchQuery)\".")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredEntries) { entry in
                            PlaylistEntryRow(
                                entry: entry,
                                isSelected: selectedIDs.contains(entry.id),
                                onToggle: { isOn in
                                    guard !entry.isUnavailable else { return }
                                    if isOn {
                                        selectedIDs.insert(entry.id)
                                    } else {
                                        selectedIDs.remove(entry.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(VeloraTheme.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(VeloraTheme.hairline, lineWidth: 1)
        )
    }

    private var bottomBar: some View {
        HStack(spacing: 16) {
            Toggle("Create playlist subfolder", isOn: $createSubfolder)
                .font(.callout)
                .foregroundStyle(VeloraTheme.inkPrimary)

            Toggle("Number files (01 - Title)", isOn: $prefixIndex)
                .font(.callout)
                .foregroundStyle(VeloraTheme.inkPrimary)

            Spacer()

            Button("Cancel") { dismiss() }
                .buttonStyle(VeloraSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)

            Button {
                let chosen = selectedEntriesOrdered
                guard !chosen.isEmpty else { return }
                onQueueSelected(chosen, createSubfolder, prefixIndex)
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .accessibilityHidden(true)
                    Text("Queue \(selectedIDs.count) Video\(selectedIDs.count == 1 ? "" : "s")")
                        .monospacedDigit()
                }
            }
            .buttonStyle(VeloraPrimaryButtonStyle(isDisabled: selectedIDs.isEmpty))
            .disabled(selectedIDs.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func applyRangeSelection() {
        let trimmed = rangeExpression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let indices = PlaylistURLDetector.parseSelectionRange(
            trimmed,
            maxIndex: mediaInfo.playlistEntries.count
        )
        let matched = mediaInfo.playlistEntries.filter { indices.contains($0.index) && !$0.isUnavailable }

        guard !matched.isEmpty else {
            rangeFeedback = "No available items matched range \"\(trimmed)\" (valid range: 1–\(mediaInfo.playlistEntries.count))."
            return
        }

        rangeFeedback = nil
        selectedIDs = Set(matched.map(\.id))
    }
}

private struct PlaylistEntryRow: View {
    let entry: PlaylistEntry
    let isSelected: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle(
                entry.title,
                isOn: Binding(
                    get: { isSelected },
                    set: { onToggle($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(entry.isUnavailable)
            .accessibilityLabel("Select #\(entry.index) \(entry.title)")
            .accessibilityValue(entry.isUnavailable ? "Unavailable" : (isSelected ? "Selected" : "Not selected"))

            Text(String(format: "#%02d", entry.index))
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(VeloraTheme.inkSecondary)
                .frame(width: 38, alignment: .leading)

            CachedThumbnailView(
                urlString: entry.thumbnailURL,
                width: 64,
                height: 36,
                cornerRadius: 6,
                maxPixelSize: 160,
                fallbackSymbol: "play.fill"
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(entry.isUnavailable ? VeloraTheme.inkSecondary : VeloraTheme.inkPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let uploader = entry.uploader {
                        Text(uploader)
                            .font(.caption2)
                            .foregroundStyle(VeloraTheme.inkSecondary)
                            .lineLimit(1)
                    }
                    if entry.isUnavailable {
                        VeloraBadge(text: "Unavailable", color: VeloraTheme.warning)
                    }
                }
            }

            Spacer()

            if let duration = entry.formattedDuration {
                Text(duration)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(VeloraTheme.inkSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(VeloraTheme.surfaceSubtle)
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected && !entry.isUnavailable ? VeloraTheme.accent.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard !entry.isUnavailable else { return }
            onToggle(!isSelected)
        }
        .disabled(entry.isUnavailable)
    }
}
