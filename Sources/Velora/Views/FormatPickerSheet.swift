import SwiftUI
import VeloraCore

private enum FormatFilter: String, CaseIterable, Identifiable {
    case all = "All Streams"
    case video = "Video"
    case audio = "Audio"
    case muxed = "Muxed"

    var id: String { rawValue }
}

struct FormatPickerSheet: View {
    let mediaInfo: MediaInfo
    let selectedFormatID: String?
    let onSelectFormat: (String?, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var filter: FormatFilter = .all
    @State private var combineWithBestAudio: Bool = true
    @State private var activeSelectionID: String?

    init(
        mediaInfo: MediaInfo,
        selectedFormatID: String?,
        onSelectFormat: @escaping (String?, Bool) -> Void
    ) {
        self.mediaInfo = mediaInfo
        self.selectedFormatID = selectedFormatID
        self.onSelectFormat = onSelectFormat
    }

    private var filteredFormats: [MediaFormat] {
        mediaInfo.formats.filter { fmt in
            switch filter {
            case .all: true
            case .video: fmt.hasVideo && !fmt.hasAudio
            case .audio: fmt.hasAudio && !fmt.hasVideo
            case .muxed: fmt.hasVideo && fmt.hasAudio
            }
        }
    }

    private var selectedFormatObject: MediaFormat? {
        guard let activeSelectionID else { return nil }
        return mediaInfo.formats.first(where: { $0.formatID == activeSelectionID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Available Media Streams")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(VeloraTheme.inkPrimary)
                    Text(mediaInfo.title)
                        .font(.caption)
                        .foregroundStyle(VeloraTheme.inkSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Picker("Filter", selection: $filter) {
                    ForEach(FormatFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(minWidth: 220, maxWidth: 320)
                .accessibilityLabel("Filter stream types")
            }

            Group {
                if filteredFormats.isEmpty {
                    ContentUnavailableView(
                        "No Matching Streams",
                        systemImage: "film",
                        description: Text("No \(filter.rawValue.lowercased()) streams were reported for this media URL.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(VeloraTheme.surfaceElevated)
                } else {
                    Table(filteredFormats, selection: $activeSelectionID) {
                        TableColumn("ID") { fmt in
                            Text(fmt.formatID)
                                .font(.system(.callout, design: .monospaced, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(VeloraTheme.inkPrimary)
                        }
                        .width(min: 54, ideal: 68)

                        TableColumn("Type") { fmt in
                            HStack(spacing: 5) {
                                VeloraBadge(
                                    text: fmt.kindLabel,
                                    color: badgeColor(for: fmt)
                                )
                                if fmt.hasVideo && !fmt.hasAudio {
                                    VeloraBadge(
                                        text: "+Auto Audio",
                                        color: VeloraTheme.accentText
                                    )
                                    .help("Video-only stream automatically muxes with +bestaudio/best in Video + Audio mode")
                                }
                            }
                        }
                        .width(min: 128, ideal: 156)

                        TableColumn("Quality") { fmt in
                            Text(fmt.displayResolution)
                                .font(.callout)
                                .monospacedDigit()
                                .foregroundStyle(VeloraTheme.inkPrimary)
                        }
                        .width(min: 76, ideal: 94)

                        TableColumn("Ext") { fmt in
                            Text(fmt.ext.uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(VeloraTheme.inkSecondary)
                        }
                        .width(min: 44, ideal: 54)

                        TableColumn("Codecs") { fmt in
                            Text(fmt.codecSummary.isEmpty ? "—" : fmt.codecSummary)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(VeloraTheme.inkSecondary)
                                .lineLimit(1)
                        }
                        .width(min: 130, ideal: 190)

                        TableColumn("Bitrate") { fmt in
                            Text(fmt.tbr.map { "\(Int($0.rounded())) kbps" } ?? "—")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(VeloraTheme.inkSecondary)
                        }
                        .width(min: 72, ideal: 86)

                        TableColumn("Size") { fmt in
                            Text(fmt.formattedFilesize)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(VeloraTheme.inkPrimary)
                        }
                        .width(min: 74, ideal: 88)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(VeloraTheme.hairline, lineWidth: 1)
            )

            HStack(spacing: 10) {
                Toggle("Auto-pair video-only stream with +bestaudio/best", isOn: $combineWithBestAudio)
                    .font(.callout)
                    .foregroundStyle(VeloraTheme.inkSecondary)

                Spacer()

                if selectedFormatID != nil {
                    Button("Clear Override") {
                        onSelectFormat(nil, false)
                        dismiss()
                    }
                    .buttonStyle(VeloraSecondaryButtonStyle())
                }

                Button("Cancel") { dismiss() }
                    .buttonStyle(VeloraSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)

                Button("Use Selected Format") {
                    guard let chosen = selectedFormatObject else { return }
                    let isVideoOnly = chosen.hasVideo && !chosen.hasAudio
                    let effectiveIsVideoOnly = isVideoOnly && combineWithBestAudio
                    onSelectFormat(chosen.formatID, effectiveIsVideoOnly)
                    dismiss()
                }
                .buttonStyle(VeloraPrimaryButtonStyle(isDisabled: activeSelectionID == nil))
                .disabled(activeSelectionID == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 620, idealWidth: 840, maxWidth: 1140, minHeight: 420, idealHeight: 540, maxHeight: 780)
        .background(VeloraTheme.ground)
        .onAppear {
            activeSelectionID = selectedFormatID?.components(separatedBy: "+").first
        }
    }

    private func badgeColor(for fmt: MediaFormat) -> Color {
        if fmt.hasVideo && fmt.hasAudio {
            return VeloraTheme.success
        }
        if fmt.hasVideo {
            return VeloraTheme.accentText
        }
        return VeloraTheme.info
    }
}
