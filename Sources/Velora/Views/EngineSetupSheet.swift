import AppKit
import SwiftUI
import VeloraCore

struct EngineSetupSheet: View {
    let engineManager: EngineManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(VeloraTheme.brandGradient)
                        .frame(width: 44, height: 44)
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Download Engine Setup")
                        .font(.title3.weight(.bold))
                    Text("Velora relies on yt-dlp for multi-site extraction and FFmpeg for 4K/1080p stream merging, audio extraction & metadata.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Status Cards
            HStack(spacing: 12) {
                binaryCard(
                    status: engineManager.ytdlpStatus,
                    description: "Required for YouTube, Vimeo, TikTok, X, Twitch & 1,000+ sites."
                )
                binaryCard(
                    status: engineManager.ffmpegStatus,
                    description: "Required for merging HD video+audio, MP3/FLAC conversion & embedding."
                )
                binaryCard(
                    status: engineManager.jsRuntimeStatus,
                    description: "Used by yt-dlp for YouTube 4K/EJS stream challenges (deno, bun, or node)."
                )
            }

            // Actions
            VStack(alignment: .leading, spacing: 10) {
                Text("One-Click Installers")
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 10) {
                    Button {
                        Task { await engineManager.installOrUpdateManagedYTDLP() }
                    } label: {
                        Label(
                            engineManager.ytdlpStatus.isInstalled ? "Update Managed yt-dlp" : "Download Standalone yt-dlp",
                            systemImage: "arrow.down.circle.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VeloraTheme.violet)
                    .disabled(engineManager.isWorking)

                    if engineManager.homebrewPath != nil {
                        Button {
                            let missing = [
                                engineManager.ytdlpStatus.isInstalled ? nil : "yt-dlp",
                                engineManager.ffmpegStatus.isInstalled ? nil : "ffmpeg"
                            ].compactMap { $0 }
                            let target = missing.isEmpty ? ["yt-dlp", "ffmpeg"] : missing
                            Task { await engineManager.installViaHomebrew(packages: target) }
                        } label: {
                            Label(
                                engineManager.ffmpegStatus.isInstalled ? "Install / Upgrade via Homebrew" : "Install FFmpeg via Homebrew",
                                systemImage: "shippingbox.fill"
                            )
                        }
                        .buttonStyle(.bordered)
                        .disabled(engineManager.isWorking)
                    }

                    Spacer()

                    Button {
                        Task { await engineManager.refresh() }
                    } label: {
                        Label("Re-scan", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(engineManager.isWorking)
                }

                HStack(spacing: 8) {
                    Text("Or run in Terminal:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("brew install yt-dlp ffmpeg")
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew install yt-dlp ffmpeg", forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy Homebrew command")
                }
            }
            .veloraCard(padding: 14)

            if engineManager.isWorking {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(engineManager.activityMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = engineManager.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if !engineManager.installLogs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Setup Output")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") { engineManager.clearLogs() }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                    ScrollView {
                        Text(engineManager.installLogs.joined(separator: "\n"))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 120)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 740)
    }

    private func binaryCard(status: BinaryStatus, description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: status.isInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(status.isInstalled ? VeloraTheme.emerald : .orange)
                Text(status.name)
                    .font(.headline)
                Spacer()
                VeloraBadge(
                    text: status.source.label,
                    color: status.isInstalled ? VeloraTheme.emerald : .orange
                )
            }

            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let version = status.version {
                Text("Version: \(version)")
                    .font(.caption.monospacedDigit().weight(.medium))
            }
            if let path = status.path {
                Text(path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .veloraCard(padding: 13)
    }
}
