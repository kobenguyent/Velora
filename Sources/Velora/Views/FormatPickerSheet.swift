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
    let onSelect: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var filter: FormatFilter = .all
    @State private var combineWithBestAudio: Bool = true
    @State private var activeSelectionID: String?

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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Available Media Streams")
                        .font(.title3.weight(.bold))
                    Text(mediaInfo.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                .frame(width: 300)
            }

            Table(filteredFormats, selection: $activeSelectionID) {
                TableColumn("ID") { fmt in
                    Text(fmt.formatID)
                        .font(.system(.callout, design: .monospaced, weight: .semibold))
                }
                .width(min: 54, ideal: 68)

                TableColumn("Type") { fmt in
                    VeloraBadge(
                        text: fmt.kindLabel,
                        color: fmt.hasVideo && fmt.hasAudio ? VeloraTheme.emerald : (fmt.hasVideo ? VeloraTheme.violet : VeloraTheme.cyan)
                    )
                }
                .width(min: 66, ideal: 76)

                TableColumn("Quality") { fmt in
                    Text(fmt.displayResolution)
                        .font(.callout.monospacedDigit())
                }
                .width(min: 76, ideal: 94)

                TableColumn("Ext") { fmt in
                    Text(fmt.ext.uppercased())
                        .font(.caption.weight(.semibold))
                }
                .width(min: 44, ideal: 54)

                TableColumn("Codecs") { fmt in
                    Text(fmt.codecSummary.isEmpty ? "—" : fmt.codecSummary)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 140, ideal: 210)

                TableColumn("Bitrate") { fmt in
                    Text(fmt.tbr.map { "\(Int($0.rounded())) kbps" } ?? "—")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .width(min: 72, ideal: 86)

                TableColumn("Size") { fmt in
                    Text(fmt.formattedFilesize)
                        .font(.caption.monospacedDigit())
                }
                .width(min: 74, ideal: 88)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(VeloraTheme.subtleCardBorder, lineWidth: 1)
            )

            HStack {
                Toggle("Pair video-only stream with best audio (+bestaudio)", isOn: $combineWithBestAudio)
                    .font(.callout)

                Spacer()

                if selectedFormatID != nil {
                    Button("Clear Override") {
                        onSelect(nil)
                        dismiss()
                    }
                }

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Use Selected Format") {
                    guard let chosenID = activeSelectionID,
                          let chosen = mediaInfo.formats.first(where: { $0.formatID == chosenID }) else {
                        return
                    }
                    if chosen.hasVideo && !chosen.hasAudio && combineWithBestAudio {
                        onSelect("\(chosen.formatID)+bestaudio/best")
                    } else {
                        onSelect(chosen.formatID)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(VeloraTheme.violet)
                .disabled(activeSelectionID == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 780, height: 500)
        .onAppear {
            activeSelectionID = selectedFormatID?.components(separatedBy: "+").first
        }
    }
}
