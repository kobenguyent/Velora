import SwiftUI
import VeloraCore

struct MediaPreviewCard: View {
    let mediaInfo: MediaInfo
    let selectedFormatID: String?
    let onOpenFormatPicker: () -> Void
    let onClearFormatOverride: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            thumbnailView
                .frame(width: 196, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(VeloraTheme.subtleCardBorder, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    if let extractor = mediaInfo.extractor {
                        VeloraBadge(text: extractor, color: VeloraTheme.violet, icon: "globe")
                    }
                    if mediaInfo.isPlaylist, let count = mediaInfo.playlistCount {
                        VeloraBadge(text: "Playlist · \(count) items", color: VeloraTheme.cyan, icon: "list.bullet.rectangle")
                    }
                    if let duration = mediaInfo.formattedDuration {
                        VeloraBadge(text: duration, color: .secondary, icon: "clock")
                    }
                    Spacer()
                }

                Text(mediaInfo.title)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    if let uploader = mediaInfo.uploader {
                        Label(uploader, systemImage: "person.crop.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let views = mediaInfo.formattedViewCount {
                        Label("\(views) views", systemImage: "eye")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !mediaInfo.availableHeights.isEmpty {
                    HStack(spacing: 6) {
                        Text("Detected:")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        ForEach(mediaInfo.availableHeights.prefix(6), id: \.self) { h in
                            Text("\(h)p")
                                .font(.caption2.weight(.medium).monospacedDigit())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }

                Spacer(minLength: 2)

                HStack(spacing: 8) {
                    if !mediaInfo.formats.isEmpty {
                        Button {
                            onOpenFormatPicker()
                        } label: {
                            Label(
                                selectedFormatID == nil ? "Pick Exact Format (\(mediaInfo.formats.count))" : "Format: \(selectedFormatID!)",
                                systemImage: "list.bullet.indent"
                            )
                            .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if selectedFormatID != nil {
                        Button("Reset Format") {
                            onClearFormatOverride()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .veloraCard(padding: 14)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbStr = mediaInfo.thumbnailURL, let url = URL(string: thumbStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholderThumb
                case .empty:
                    ZStack {
                        placeholderThumb
                        ProgressView().controlSize(.small)
                    }
                @unknown default:
                    placeholderThumb
                }
            }
        } else {
            placeholderThumb
        }
    }

    private var placeholderThumb: some View {
        ZStack {
            VeloraTheme.brandGradient.opacity(0.22)
            Image(systemName: "play.rectangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }
}
