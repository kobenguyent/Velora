import AppKit
import SwiftUI
import VeloraCore

struct EngineSetupSheet: View {
    let engineManager: EngineManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var copiedLog = false
    @State private var copiedBrew = false

    private var actionNeededCount: Int {
        var count = 0
        if !engineManager.ytdlpStatus.isInstalled || engineManager.ytdlpUpdateState.needsUpdate { count += 1 }
        if !engineManager.ffmpegStatus.isInstalled || engineManager.ffmpegUpdateState.needsUpdate { count += 1 }
        if !engineManager.jsRuntimeStatus.isInstalled || engineManager.jsRuntimeUpdateState.needsUpdate { count += 1 }
        return count
    }

    private var jsRuntimeCardTitle: String {
        let name = engineManager.jsRuntimeStatus.name
        if engineManager.jsRuntimeStatus.isInstalled && name.lowercased() != "deno" && name != "JS Runtime" {
            return "\(name.capitalized) JS Runtime"
        }
        return "Deno JS Runtime"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 10) {
                        engineRow(
                            title: "yt-dlp",
                            status: engineManager.ytdlpStatus,
                            updateState: engineManager.ytdlpUpdateState,
                            description: "Core media extractor for YouTube, Vimeo, X, TikTok, Twitch & 1,000+ sites.",
                            installLabel: "Install",
                            isRequired: true
                        ) {
                            Task { await engineManager.installOrUpdateManagedYTDLP() }
                        }

                        engineRow(
                            title: "FFmpeg & FFprobe",
                            status: engineManager.ffmpegStatus,
                            updateState: engineManager.ffmpegUpdateState,
                            description: "Zero-Homebrew standalone builds for 4K muxing, MP3/FLAC extraction, and subtitles.",
                            installLabel: "Install",
                            isRequired: true
                        ) {
                            Task { await engineManager.installOrUpdateManagedFFmpeg() }
                        }

                        engineRow(
                            title: jsRuntimeCardTitle,
                            status: engineManager.jsRuntimeStatus,
                            updateState: engineManager.jsRuntimeUpdateState,
                            description: "Zero-Homebrew standalone JS runtime for YouTube 4K/EJS stream challenges.",
                            installLabel: "Install",
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
        .frame(minWidth: 620, idealWidth: 760, maxWidth: 920, minHeight: 460, idealHeight: 580)
        .background(VeloraTheme.ground)
        .task {
            await engineManager.refresh()
            await engineManager.checkForEngineUpdates()
        }
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
                Text("Install and keep yt-dlp, FFmpeg & FFprobe, and Deno up to date with zero Homebrew required.")
                    .font(.caption)
                    .foregroundStyle(VeloraTheme.inkSecondary)
            }

            Spacer()
        }
    }

    private func engineRow(
        title: String,
        status: BinaryStatus,
        updateState: EngineUpdateState,
        description: String,
        installLabel: String,
        isRequired: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let toneColor = rowStatusColor(status: status, updateState: updateState, isRequired: isRequired)
        let isExternalNonDeno = title != "Deno JS Runtime" && status.isInstalled && status.name.lowercased() != "deno"

        return HStack(alignment: .center, spacing: 14) {
            leadingStatusIcon(status: status, updateState: updateState, toneColor: toneColor)

            VStack(alignment: .leading, spacing: 5) {
                FlowWrapLayout(alignment: .leading, spacing: 7, lineSpacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(VeloraTheme.inkPrimary)
                        .fixedSize()

                    VeloraBadge(
                        text: status.source.label,
                        color: status.isInstalled ? VeloraTheme.inkSecondary : toneColor
                    )

                    updateStatusBadge(
                        status: status,
                        updateState: updateState,
                        isRequired: isRequired,
                        isExternalNonDeno: isExternalNonDeno
                    )
                }

                Text(description)
                    .font(.caption)
                    .foregroundStyle(VeloraTheme.inkSecondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    versionComparisonText(
                        status: status,
                        updateState: updateState,
                        isExternalNonDeno: isExternalNonDeno
                    )

                    if let path = status.path {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(VeloraTheme.inkSecondary.opacity(0.5))
                        Text(abbreviateHomePath(path))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(VeloraTheme.inkSecondary.opacity(0.75))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer(minLength: 8)

            rowActionButton(
                title: title,
                status: status,
                updateState: updateState,
                installLabel: installLabel,
                action: action
            )
        }
        .veloraCard(padding: 14, cornerRadius: 14)
        .overlay {
            if updateState.needsUpdate {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(VeloraTheme.accent.opacity(0.45), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func leadingStatusIcon(
        status: BinaryStatus,
        updateState: EngineUpdateState,
        toneColor: Color
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(toneColor.opacity(colorScheme == .dark ? 0.16 : 0.08))
            if case .checking = updateState {
                ProgressView()
                    .controlSize(.small)
            } else {
                let symbol: String = {
                    if !status.isInstalled { return "exclamationmark.circle.fill" }
                    if updateState.needsUpdate { return "arrow.up.circle.fill" }
                    return "checkmark.circle.fill"
                }()
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(toneColor)
            }
        }
        .frame(width: 38, height: 38)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func updateStatusBadge(
        status: BinaryStatus,
        updateState: EngineUpdateState,
        isRequired: Bool,
        isExternalNonDeno: Bool
    ) -> some View {
        switch updateState {
        case .checking:
            VeloraBadge(text: "Checking…", color: VeloraTheme.inkSecondary)
        case .upToDate:
            VeloraBadge(
                text: isExternalNonDeno ? "External ready" : "Up to date",
                color: VeloraTheme.success,
                icon: "checkmark"
            )
        case .updateAvailable(_, let latest):
            VeloraBadge(
                text: "Update available · \(latest)",
                color: VeloraTheme.accentText,
                icon: "arrow.up.circle"
            )
        case .notInstalled:
            VeloraBadge(
                text: isRequired ? "Required" : "Optional",
                color: isRequired ? VeloraTheme.danger : VeloraTheme.warning
            )
        case .unknown:
            if status.isInstalled {
                VeloraBadge(text: "Installed", color: VeloraTheme.success, icon: "checkmark")
            }
        }
    }

    @ViewBuilder
    private func versionComparisonText(
        status: BinaryStatus,
        updateState: EngineUpdateState,
        isExternalNonDeno: Bool
    ) -> some View {
        switch updateState {
        case .upToDate(let latest):
            if let installed = status.version {
                if isExternalNonDeno {
                    Text("Installed \(installed)")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(VeloraTheme.inkPrimary)
                } else {
                    HStack(spacing: 5) {
                        Text("Installed \(installed)")
                            .foregroundStyle(VeloraTheme.inkPrimary)
                        Text("·")
                            .foregroundStyle(VeloraTheme.inkSecondary.opacity(0.6))
                        Text("Latest \(latest)")
                            .foregroundStyle(VeloraTheme.success)
                    }
                    .font(.caption.monospacedDigit().weight(.medium))
                }
            }
        case .updateAvailable(let installed, let latest):
            HStack(spacing: 5) {
                Text("Installed \(installed)")
                    .foregroundStyle(VeloraTheme.inkPrimary)
                Text("→")
                    .foregroundStyle(VeloraTheme.inkSecondary)
                Text("Latest \(latest)")
                    .foregroundStyle(VeloraTheme.accentText)
            }
            .font(.caption.monospacedDigit().weight(.semibold))
        case .notInstalled(let latest):
            HStack(spacing: 5) {
                Text("Not installed")
                    .foregroundStyle(VeloraTheme.inkSecondary)
                if let latest {
                    Text("·")
                        .foregroundStyle(VeloraTheme.inkSecondary.opacity(0.6))
                    Text("Latest \(latest)")
                        .foregroundStyle(VeloraTheme.inkSecondary)
                }
            }
            .font(.caption.monospacedDigit().weight(.medium))
        case .checking, .unknown:
            if let installed = status.version {
                Text("Installed \(installed)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(VeloraTheme.inkPrimary)
            } else {
                Text("Not detected")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(VeloraTheme.inkSecondary)
            }
        }
    }

    @ViewBuilder
    private func rowActionButton(
        title: String,
        status: BinaryStatus,
        updateState: EngineUpdateState,
        installLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        if !status.isInstalled {
            let label = updateState.latestVersion.map { "Install \($0)" } ?? installLabel
            Button(label, action: action)
                .buttonStyle(VeloraPrimaryButtonStyle(isDisabled: engineManager.isWorking))
                .controlSize(.small)
                .disabled(engineManager.isWorking)
                .accessibilityLabel("Install \(title)")
        } else if case .updateAvailable(_, let latest) = updateState {
            Button("Update to \(latest)", action: action)
                .buttonStyle(VeloraPrimaryButtonStyle(isDisabled: engineManager.isWorking))
                .controlSize(.small)
                .disabled(engineManager.isWorking)
                .accessibilityLabel("Update \(title) to \(latest)")
        } else if updateState.isUpToDate {
            Button("Reinstall", action: action)
                .buttonStyle(VeloraSecondaryButtonStyle(isDisabled: engineManager.isWorking))
                .controlSize(.small)
                .disabled(engineManager.isWorking)
                .accessibilityLabel("Reinstall \(title)")
        } else {
            Button("Update", action: action)
                .buttonStyle(VeloraSecondaryButtonStyle(isDisabled: engineManager.isWorking))
                .controlSize(.small)
                .disabled(engineManager.isWorking)
                .accessibilityLabel("Update \(title)")
        }
    }

    private var bulkActionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                overallSummaryBanner
                Spacer()
                if let checkedAt = engineManager.lastUpdateCheckAt, !engineManager.isCheckingUpdates {
                    Text("Checked \(checkedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(VeloraTheme.inkSecondary.opacity(0.75))
                }
            }

            FlowWrapLayout(alignment: .leading, spacing: 10, lineSpacing: 8) {
                if actionNeededCount > 0 {
                    Button {
                        Task { await engineManager.installMissingOrOutdatedManagedEngines() }
                    } label: {
                        Label(
                            smartBulkButtonTitle,
                            systemImage: "arrow.down.circle.fill"
                        )
                        .monospacedDigit()
                    }
                    .buttonStyle(VeloraPrimaryButtonStyle(isDisabled: engineManager.isWorking))
                    .disabled(engineManager.isWorking)
                }

                Button {
                    Task {
                        await engineManager.refresh()
                        await engineManager.checkForEngineUpdates()
                    }
                } label: {
                    Label(
                        engineManager.isCheckingUpdates ? "Checking…" : "Check for Updates",
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(VeloraSecondaryButtonStyle(isDisabled: engineManager.isWorking || engineManager.isCheckingUpdates))
                .disabled(engineManager.isWorking || engineManager.isCheckingUpdates)

                if actionNeededCount == 0 && engineManager.allEnginesUpToDate {
                    Button {
                        Task { await engineManager.installAllManagedEngines() }
                    } label: {
                        Label("Reinstall All", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(VeloraSecondaryButtonStyle(isDisabled: engineManager.isWorking))
                    .disabled(engineManager.isWorking)
                }

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

    @ViewBuilder
    private var overallSummaryBanner: some View {
        let missing = engineManager.missingEngineCount
        let outdated = engineManager.outdatedEngineCount

        if engineManager.isCheckingUpdates {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking latest upstream versions…")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(VeloraTheme.inkSecondary)
            }
        } else if missing > 0 && outdated > 0 {
            Label("\(missing) missing, \(outdated) update\(outdated == 1 ? "" : "s") available", systemImage: "exclamationmark.circle.fill")
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(VeloraTheme.warning)
        } else if missing > 0 {
            Label("\(missing) engine\(missing == 1 ? "" : "s") missing", systemImage: "exclamationmark.circle.fill")
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(VeloraTheme.danger)
        } else if outdated > 0 {
            Label("\(outdated) engine update\(outdated == 1 ? "" : "s") available", systemImage: "arrow.up.circle.fill")
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(VeloraTheme.accentText)
        } else if engineManager.allEnginesUpToDate {
            Label("All engines are up to date", systemImage: "checkmark.seal.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(VeloraTheme.success)
        } else {
            Label("Installed engines verified", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(VeloraTheme.success)
        }
    }

    private var smartBulkButtonTitle: String {
        let missing = engineManager.missingEngineCount
        let outdated = engineManager.outdatedEngineCount
        if missing > 0 && outdated == 0 {
            return "Install Missing (\(missing))"
        }
        if outdated > 0 && missing == 0 {
            return "Update Outdated (\(outdated))"
        }
        return "Install & Update (\(actionNeededCount))"
    }

    private func rowStatusColor(
        status: BinaryStatus,
        updateState: EngineUpdateState,
        isRequired: Bool
    ) -> Color {
        if !status.isInstalled {
            return isRequired ? VeloraTheme.danger : VeloraTheme.warning
        }
        if updateState.needsUpdate {
            return VeloraTheme.accentText
        }
        return VeloraTheme.success
    }

    private func abbreviateHomePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~/" + path.dropFirst(home.count + 1)
        }
        return path
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
