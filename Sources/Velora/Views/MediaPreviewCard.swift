import SwiftUI
import VeloraCore

struct MediaPreviewCard: View {
    let mediaInfo: MediaInfo
    let selectedFormatID: String?
    let onOpenFormatPicker: () -> Void
    let onClearFormatOverride: () -> Void
    let onOpenPlaylistPicker: () -> Void
    let onQueueAllPlaylist: () -> Void
    let onLoadLinkedPlaylist: () -> Void

    @Environment(\.veloraLayout) private var layout

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            thumbnailWithBadges

            VStack(alignment: .leading, spacing: 7) {
                metadataBadgesRow

                Text(mediaInfo.title)
                    .font(layout.font(16, weight: .semibold))
                    .foregroundStyle(VeloraTheme.inkPrimary)
                    .lineLimit(2)

                uploaderAndViewsRow

                if mediaInfo.isPlaylist && !mediaInfo.playlistEntries.isEmpty {
                    playlistPreviewList
                } else if !mediaInfo.availableHeights.isEmpty {
                    detectedHeightsRow
                }

                Spacer(minLength: 2)

                actionBar
            }
        }
        .veloraCard(padding: layout.scaled(16), cornerRadius: 14)
    }

    private var thumbnailWithBadges: some View {
        let thumbSize = layout.thumbnailSize
        return ZStack(alignment: .bottomTrailing) {
            CachedThumbnailView(
                urlString: mediaInfo.thumbnailURL,
                width: thumbSize.width,
                height: thumbSize.height,
                cornerRadius: 10,
                maxPixelSize: 400,
                fallbackSymbol: mediaInfo.isPlaylist ? "list.bullet.rectangle" : "play.rectangle"
            )

            if mediaInfo.isLive {
                Text("LIVE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(VeloraTheme.danger))
                    .padding(6)
            } else if mediaInfo.isPlaylist, let totalDur = mediaInfo.totalPlaylistDurationFormatted {
                durationOverlayPill(totalDur)
            } else if let duration = mediaInfo.formattedDuration {
                durationOverlayPill(duration)
            }
        }
    }

    private func durationOverlayPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.black.opacity(0.75)))
            .padding(6)
            .accessibilityLabel("Duration \(text)")
    }

    private var metadataBadgesRow: some View {
        FlowWrapLayout(alignment: .leading, spacing: 6, lineSpacing: 6) {
            if let extractor = mediaInfo.extractor {
                VeloraBadge(text: extractor, color: VeloraTheme.accentText, icon: "globe")
            }
            if mediaInfo.isPlaylist, let count = mediaInfo.playlistCount {
                VeloraBadge(text: "Playlist · \(count)", color: VeloraTheme.info, icon: "list.bullet.rectangle")
            }
            if mediaInfo.isLive {
                VeloraBadge(text: "Live Stream", color: VeloraTheme.danger, icon: "dot.radiowaves.left.and.right")
            }
        }
    }

    private var uploaderAndViewsRow: some View {
        HStack(spacing: 12) {
            if let uploader = mediaInfo.uploader {
                Label(uploader, systemImage: "person.crop.circle")
                    .font(layout.font(12.5))
                    .foregroundStyle(VeloraTheme.inkSecondary)
                    .lineLimit(1)
            }
            if let views = mediaInfo.formattedViewCount {
                Label("\(views) views", systemImage: "eye")
                    .font(layout.font(12.5))
                    .monospacedDigit()
                    .foregroundStyle(VeloraTheme.inkSecondary)
            }
        }
    }

    private var playlistPreviewList: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(mediaInfo.playlistEntries.prefix(3)) { entry in
                HStack(spacing: 6) {
                    Text(String(format: "#%02d", entry.index))
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(VeloraTheme.inkSecondary)
                    Text(entry.title)
                        .font(.caption2)
                        .foregroundStyle(VeloraTheme.inkPrimary)
                        .lineLimit(1)
                    Spacer()
                    if let dur = entry.formattedDuration {
                        Text(dur)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(VeloraTheme.inkSecondary)
                    }
                }
            }
            if mediaInfo.playlistEntries.count > 3 {
                Text("…and \(mediaInfo.playlistEntries.count - 3) more videos")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(VeloraTheme.inkSecondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(VeloraTheme.surfaceSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(VeloraTheme.hairline, lineWidth: 1)
        )
    }

    private var detectedHeightsRow: some View {
        FlowWrapLayout(alignment: .leading, spacing: 5, lineSpacing: 5) {
            Text("Streams:")
                .font(layout.font(11.5))
                .foregroundStyle(VeloraTheme.inkSecondary)

            ForEach(mediaInfo.availableHeights.prefix(5), id: \.self) { h in
                Text("\(h)p")
                    .font(layout.font(11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(VeloraTheme.inkPrimary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(VeloraTheme.surfaceSubtle)
                    )
            }
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        FlowWrapLayout(alignment: .leading, spacing: 8, lineSpacing: 6) {
            if mediaInfo.isPlaylist && !mediaInfo.playlistEntries.isEmpty {
                Button {
                    onOpenPlaylistPicker()
                } label: {
                    Label(
                        "Select Videos (\(mediaInfo.availablePlaylistEntries.count))…",
                        systemImage: "checklist"
                    )
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                }
                .buttonStyle(VeloraPrimaryButtonStyle())
                .controlSize(.small)

                Button {
                    onQueueAllPlaylist()
                } label: {
                    Label(
                        "Queue All \(mediaInfo.availablePlaylistEntries.count)",
                        systemImage: "arrow.down.circle"
                    )
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                }
                .buttonStyle(VeloraSecondaryButtonStyle())
                .controlSize(.small)
            } else {
                if !mediaInfo.formats.isEmpty {
                    Button {
                        onOpenFormatPicker()
                    } label: {
                        Label(
                            selectedFormatID == nil
                                ? "Pick Format (\(mediaInfo.formats.count))"
                                : "Format: \(selectedFormatID!)",
                            systemImage: "list.bullet.indent"
                        )
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                    }
                    .buttonStyle(VeloraSecondaryButtonStyle())
                    .controlSize(.small)
                } else {
                    Text("No selectable streams")
                        .font(.caption)
                        .foregroundStyle(VeloraTheme.inkSecondary)
                }

                if selectedFormatID != nil {
                    Button("Reset Format") {
                        onClearFormatOverride()
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(VeloraTheme.inkSecondary)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 24, minHeight: 24)
                    .contentShape(Rectangle())
                    .veloraFocusableRing(cornerRadius: 6)
                    .accessibilityLabel("Reset custom format override")
                }

                if mediaInfo.linkedPlaylistURL != nil {
                    Button {
                        onLoadLinkedPlaylist()
                    } label: {
                        Label("Load Full Playlist", systemImage: "list.bullet.rectangle.portrait")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(VeloraSecondaryButtonStyle())
                    .controlSize(.small)
                    .help("This video is part of a playlist — expand to select and bulk-download videos")
                }
            }
        }
    }
}
