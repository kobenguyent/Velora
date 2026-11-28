import AppKit
import SwiftUI
import VeloraCore

struct EngineSetupSheet: View {
    let engineManager: EngineManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copiedLog = false
    @State private var copiedBrew = false

    private var allInstalled: Bool {
        engineManager.ytdlpStatus.isInstalled &&
        engineManager.ffmpegStatus.isInstalled &&
        engineManager.jsRuntimeStatus.isInstalled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 205), spacing: 12, alignment: .top)],
                        spacing: 12
                    ) {
                        engineCard(
                            title: "yt-dlp",
                            status: engineManager.ytdlpStatus,
                            description: "Core media extractor for YouTube, Vimeo, X, TikTok, Twitch & 1,000+ sites.",
                            actionTitle: engineManager.ytdlpStatus.isInstalled ? "Update yt-dlp" : "Install yt-dlp",
                            isRequired: true
                        ) {
                            Task { await engineManager.installOrUpdateManagedYTDLP() }
                        }

                        engineCard(
                            title: "FFmpeg & FFprobe",
                            status: engineManager.ffmpegStatus,
                            description: "Zero-Homebrew standalone builds for 4K muxing, MP3/FLAC, & subtitles.",
                            actionTitle: engineManager.ffmpegStatus.isInstalled ? "Update FFmpeg" : "Install FFmpeg",
                            isRequired: true
                        ) {
                            Task { await engineManager.installOrUpdateManagedFFmpeg() }
                        }

                        engineCard(
                            title: "Deno JS Runtime",
                            status: engineManager.jsRuntimeStatus,
                            description: "Zero-Homebrew standalone runtime for YouTube 4K/EJS stream challenges.",
                            actionTitle: engineManager.jsRuntimeStatus.isInstalled ? "Update Deno" : "Install Deno",
                            isRequired: false
                        ) {
                            Task { await engineManager.installOrUpdateManagedDeno() }
                        }
                    }

                    bulkActionsCard

                    if engineManager.isWorking {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text(engineManager.activityMessage.isEmpty ? "Working…" : engineManager.activityMessage)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(VeloraTheme.inkPrimary)
                            Spacer()
                        }
                        .veloraCard(padding: 12, cornerRadius: 12)
                    }

                    if let error = engineManager.lastError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(VeloraTheme.danger)
                                .accessibilityHidden(true)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(VeloraTheme.danger)
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(VeloraTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    if !engineManager.installLogs.isEmpty {
                        verificationLogSection
                    }
                }
                .padding(.vertical, 2)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(VeloraSecondaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 540, idealWidth: 760, maxWidth: 920, minHeight: 420, idealHeight: 540)
        .background(VeloraTheme.ground)
    }

    private var headerSection: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(VeloraTheme.accent.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.title3)
                    .foregroundStyle(VeloraTheme.accentText)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Download Engine Setup")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(VeloraTheme.inkPrimary)
                    VeloraBadge(
                        text: "CryptoKit SHA-256 verified",
                        color: VeloraTheme.success,
                        icon: "checkmark.shield.fill"
                    )
                }
                Text("Install standalone, cryptographically verified binaries into Velora's Application Support bin folder with zero Homebrew required.")
                    .font(.caption)
                    .foregroundStyle(VeloraTheme.inkSecondary)
            }

            Spacer()
        }
    }

    private func engineCard(
        title: String,
        status: BinaryStatus,
        description: String,
        actionTitle: String,
        isRequired: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let statusColor: Color = status.isInstalled
            ? VeloraTheme.success
            : (isRequired ? VeloraTheme.danger : VeloraTheme.warning)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: status.isInstalled ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(statusColor)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(VeloraTheme.inkPrimary)
                    .lineLimit(1)
                Spacer()
                VeloraBadge(
                    text: status.source.label,
                    color: statusColor
                )
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(VeloraTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 2) {
                if let version = status.version {
                    Text("Version \(version)")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(VeloraTheme.inkPrimary)
                } else {
                    Text("Not detected")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(VeloraTheme.inkSecondary)
                }

                if let path = status.path {
                    Text(path)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(VeloraTheme.inkSecondary.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)

            Button(actionTitle, action: action)
                .buttonStyle(VeloraSecondaryButtonStyle(isDisabled: engineManager.isWorking))
                .controlSize(.small)
                .disabled(engineManager.isWorking)
        }
        .frame(maxWidth: .infinity, minHeight: 158, maxHeight: .infinity, alignment: .topLeading)
        .veloraCard(padding: 14, cornerRadius: 14)
    }

    private var bulkActionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowWrapLayout(alignment: .leading, spacing: 10, lineSpacing: 8) {
                Button {
                    Task { await engineManager.installAllManagedEngines() }
                } label: {
                    Label(
                        allInstalled ? "Update All Managed Engines" : "Install Missing Engines",
                        systemImage: "arrow.down.circle.fill"
                    )
                }
                .buttonStyle(VeloraPrimaryButtonStyle(isDisabled: engineManager.isWorking))
                .disabled(engineManager.isWorking)

                if engineManager.homebrewPath != nil {
                    Button {
                        let missing = [
                            engineManager.ytdlpStatus.isInstalled ? nil : "yt-dlp",
                            engineManager.ffmpegStatus.isInstalled ? nil : "ffmpeg",
                            engineManager.jsRuntimeStatus.isInstalled ? nil : "deno"
                        ].compactMap { $0 }
                        let target = missing.isEmpty ? ["yt-dlp", "ffmpeg", "deno"] : missing
                        Task { await engineManager.installViaHomebrew(packages: target) }
                    } label: {
                        Label(
                            engineManager.ffmpegStatus.isInstalled ? "Upgrade via Homebrew" : "Install via Homebrew",
                            systemImage: "shippingbox.fill"
                        )
                    }
                    .buttonStyle(VeloraSecondaryButtonStyle(isDisabled: engineManager.isWorking))
                    .disabled(engineManager.isWorking)
                }

                Button {
                    Task { await engineManager.refresh() }
                } label: {
                    Label("Re-scan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(VeloraSecondaryButtonStyle(isDisabled: engineManager.isWorking))
                .disabled(engineManager.isWorking)
            }

            HStack(spacing: 8) {
                Text("Optional Terminal command:")
                    .font(.caption)
                    .foregroundStyle(VeloraTheme.inkSecondary)
                Text("brew install yt-dlp ffmpeg deno")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(VeloraTheme.inkPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(VeloraTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("brew install yt-dlp ffmpeg deno", forType: .string)
                    copiedBrew = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        copiedBrew = false
                    }
                } label: {
                    Label(copiedBrew ? "Copied" : "Copy", systemImage: copiedBrew ? "checkmark" : "doc.on.doc")
                        .font(.caption2.weight(.medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(copiedBrew ? VeloraTheme.success : VeloraTheme.accentText)
                .frame(minHeight: 24)
                .help("Copy Homebrew command")
                .accessibilityLabel(copiedBrew ? "Copied Homebrew command" : "Copy Homebrew command")
            }
        }
        .veloraCard(padding: 14, cornerRadius: 14)
    }

    private var verificationLogSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Verification & Install Log")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VeloraTheme.inkSecondary)
                Text("\(engineManager.installLogs.count) entries")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(VeloraTheme.inkSecondary.opacity(0.75))
                Spacer()
                Button {
                    let text = engineManager.installLogs.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copiedLog = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        copiedLog = false
                    }
                } label: {
                    Label(copiedLog ? "Copied" : "Copy Log", systemImage: copiedLog ? "checkmark" : "doc.on.doc")
                        .font(.caption2.weight(.medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(copiedLog ? VeloraTheme.success : VeloraTheme.accentText)
                .frame(minHeight: 24)
                .accessibilityLabel(copiedLog ? "Copied install log" : "Copy verification and install log")

                Button("Clear") {
                    engineManager.clearLogs()
                }
                .buttonStyle(.borderless)
                .font(.caption2)
                .foregroundStyle(VeloraTheme.inkSecondary)
                .frame(minHeight: 24)
                .accessibilityLabel("Clear verification and install log")
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(engineManager.installLogs.joined(separator: "\n"))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(VeloraTheme.inkSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                        Color.clear
                            .frame(height: 1)
                            .id("setup-log-bottom")
                    }
                }
                .frame(height: 120)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(VeloraTheme.surfaceSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(VeloraTheme.hairline, lineWidth: 1)
                )
                .onAppear {
                    proxy.scrollTo("setup-log-bottom", anchor: .bottom)
                }
                .onChange(of: engineManager.installLogs.count) { _, _ in
                    if reduceMotion {
                        proxy.scrollTo("setup-log-bottom", anchor: .bottom)
                    } else {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("setup-log-bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}
