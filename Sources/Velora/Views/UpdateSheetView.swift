import AppKit
import SwiftUI
import VeloraCore

struct UpdateSheetView: View {
    @Bindable var updateChecker: UpdateChecker
    let downloadManager: DownloadManager

    @Environment(\.dismiss) private var dismiss
    @State private var showActiveDownloadsAlert = false
    @State private var pendingAction: PendingInstallAction?

    private enum PendingInstallAction {
        case downloadAndAutoInstall(AvailableUpdate)
        case installStaged(StagedUpdate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection

            Divider()
                .overlay(VeloraTheme.hairline)

            contentSection

            Divider()
                .overlay(VeloraTheme.hairline)

            footerSection
        }
        .padding(24)
        .frame(minWidth: 480, idealWidth: 580, maxWidth: 720)
        .background(VeloraTheme.ground)
        .alert("Active Downloads in Progress", isPresented: $showActiveDownloadsAlert) {
            Button("Cancel Update", role: .cancel) {
                pendingAction = nil
            }
            Button("Stop Downloads & Update", role: .destructive) {
                downloadManager.cancelAllActive()
                executePendingAction()
            }
        } message: {
            Text("Velora must close to replace itself with the new version. Active downloads will be cancelled.")
        }
    }

    private var headerSection: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(VeloraTheme.accent.opacity(0.12))
                    .frame(width: 46, height: 46)
                Image(systemName: "arrow.down.app.fill")
                    .font(.title2)
                    .foregroundStyle(VeloraTheme.accentText)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(VeloraTheme.inkPrimary)
                Text("GitHub Releases · \(updateChecker.githubRepository)")
                    .font(.caption)
                    .foregroundStyle(VeloraTheme.inkSecondary)
            }

            Spacer()

            VeloraBadge(text: "v\(UpdateChecker.currentVersionString)", color: VeloraTheme.inkSecondary)
        }
    }

    private var headerTitle: String {
        switch updateChecker.state {
        case .checking:
            "Checking GitHub Releases…"
        case .upToDate:
            "Velora Is Up to Date"
        case .updateAvailable(let u):
            "Velora v\(u.version.description) Available"
        case .downloading(let u, _, _, _):
            "Downloading Velora v\(u.version.description)…"
        case .verifying(let u):
            "Verifying Velora v\(u.version.description)…"
        case .readyToInstall(let staged):
            "Ready to Install Velora v\(staged.update.version.description)"
        case .installing:
            "Closing Velora to Install Update…"
        case .failed:
            "Update Check Issue"
        case .idle:
            "Software Updates"
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        switch updateChecker.state {
        case .idle, .checking:
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Contacting GitHub Releases API for \(updateChecker.githubRepository)…")
                    .font(.callout)
                    .foregroundStyle(VeloraTheme.inkSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)

        case .upToDate(let checkedAt):
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(VeloraTheme.success)
                    .accessibilityHidden(true)
                Text("You're running the latest version of Velora (v\(UpdateChecker.currentVersionString)).")
                    .font(.callout.monospacedDigit().weight(.medium))
                    .foregroundStyle(VeloraTheme.inkPrimary)
                Text("Last checked \(checkedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(VeloraTheme.inkSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 130)

        case .updateAvailable(let available):
            releaseDetailsView(available)

        case let .downloading(available, progress, received, total):
            VStack(alignment: .leading, spacing: 12) {
                releaseDetailsView(available)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Downloading \(available.downloadAsset.name)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VeloraTheme.inkPrimary)
                        Spacer()
                        let pct = Int((progress * 100).rounded())
                        Text("\(ByteCountFormatter.string(fromByteCount: received, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)) (\(pct)%)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(VeloraTheme.inkSecondary)
                    }
                    ProgressView(value: progress)
                        .tint(VeloraTheme.accent)
                }
                .veloraCard(padding: 12, cornerRadius: 12)
            }

        case .verifying(let available):
            VStack(spacing: 12) {
                ProgressView()
                Text("Verifying SHA-256 checksum & validating \(available.downloadAsset.name)…")
                    .font(.callout)
                    .foregroundStyle(VeloraTheme.inkSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 130)

        case .readyToInstall(let staged):
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title2)
                        .foregroundStyle(VeloraTheme.success)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Velora v\(staged.update.version.description) has been downloaded & verified.")
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .foregroundStyle(VeloraTheme.inkPrimary)
                        Text("Clicking below will close the current Velora app, replace it with the new release, and automatically relaunch.")
                            .font(.caption)
                            .foregroundStyle(VeloraTheme.inkSecondary)
                    }
                }
                .veloraCard(padding: 14, cornerRadius: 14)

                if let sha = staged.verifiedSHA256 {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(VeloraTheme.success)
                            .accessibilityHidden(true)
                        Text("SHA-256 Verified: \(sha.prefix(24))…")
                            .font(.system(.caption2, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(VeloraTheme.inkSecondary)
                    }
                }
            }

        case .installing:
            VStack(spacing: 10) {
                ProgressView()
                Text("Handing off to Velora updater and closing current app…")
                    .font(.callout)
                    .foregroundStyle(VeloraTheme.inkSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(VeloraTheme.danger)
                        .accessibilityHidden(true)
                    Text("Unable to complete update")
                        .font(.headline)
                        .foregroundStyle(VeloraTheme.inkPrimary)
                }
                Text(message)
                    .font(.callout)
                    .foregroundStyle(VeloraTheme.inkSecondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .veloraCard(padding: 14, cornerRadius: 14)
        }
    }

    @ViewBuilder
    private var footerSection: some View {
        HStack(spacing: 8) {
            if let releaseURL = updateChecker.state.availableUpdate?.release.htmlURL {
                Link("View on GitHub", destination: releaseURL)
                    .font(.callout)
            }

            Spacer()

            switch updateChecker.state {
            case .updateAvailable(let available):
                Button("Skip Version") {
                    updateChecker.skipCurrentAvailableVersion()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(VeloraTheme.inkSecondary)
                .frame(minHeight: 24)

                Button("Later") { dismiss() }
                    .buttonStyle(VeloraSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)

                Button {
                    triggerAction(.downloadAndAutoInstall(available))
                } label: {
                    Label("Download & Restart to Update", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(VeloraPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)

            case .downloading:
                Button("Cancel Download") {
                    updateChecker.cancelDownload()
                }
                .buttonStyle(VeloraSecondaryButtonStyle())

            case .readyToInstall(let staged):
                Button("Later") { dismiss() }
                    .buttonStyle(VeloraSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)

                Button {
                    triggerAction(.installStaged(staged))
                } label: {
                    Label("Close App & Install Update", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                }
                .buttonStyle(VeloraPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)

            case .failed:
                Button("Retry") {
                    Task { await updateChecker.checkForUpdates(userInitiated: true) }
                }
                .buttonStyle(VeloraSecondaryButtonStyle())

                Button("Close") { dismiss() }
                    .buttonStyle(VeloraPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)

            default:
                Button("Close") { dismiss() }
                    .buttonStyle(VeloraSecondaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func releaseDetailsView(_ available: AvailableUpdate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                VeloraBadge(
                    text: "v\(available.currentVersion.description) → v\(available.version.description)",
                    color: VeloraTheme.accentText
                )
                VeloraBadge(
                    text: available.downloadAsset.formattedSize,
                    color: VeloraTheme.inkSecondary,
                    icon: "doc.zipper"
                )
                if available.release.prerelease {
                    VeloraBadge(text: "Pre-release", color: VeloraTheme.warning)
                }
                if available.checksumAsset != nil {
                    VeloraBadge(text: "SHA-256", color: VeloraTheme.success, icon: "checkmark.shield")
                }
                Spacer()
                if let date = available.release.publishedAt {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(VeloraTheme.inkSecondary)
                }
            }

            ScrollView {
                let rawNotes = available.release.body?.trimmingCharacters(in: .whitespacesAndNewlines)
                let notesText = (rawNotes?.isEmpty == false) ? rawNotes! : "No release notes provided for this version."
                MarkdownReleaseNotesView(markdown: notesText)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 150, idealHeight: 200, maxHeight: 280)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(VeloraTheme.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(VeloraTheme.hairline, lineWidth: 1)
            )
        }
    }

    private func triggerAction(_ action: PendingInstallAction) {
        if downloadManager.hasActiveDownloads {
            pendingAction = action
            showActiveDownloadsAlert = true
        } else {
            pendingAction = action
            executePendingAction()
        }
    }

    private func executePendingAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        switch action {
        case .downloadAndAutoInstall(let available):
            Task {
                await updateChecker.downloadUpdate(available, autoInstallAfterDownload: true)
            }
        case .installStaged(let staged):
            updateChecker.installStagedUpdate(staged)
        }
    }
}

private struct MarkdownReleaseNotesView: View {
    let markdown: String

    private enum Block: Identifiable {
        case heading(id: Int, level: Int, text: String)
        case bullet(id: Int, indent: Int, text: String)
        case paragraph(id: Int, text: String)

        var id: Int {
            switch self {
            case .heading(let id, _, _),
                 .bullet(let id, _, _),
                 .paragraph(let id, _):
                return id
            }
        }
    }

    private var blocks: [Block] {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var result: [Block] = []
        var nextID = 0

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                continue
            }

            if trimmed.hasPrefix("### ") {
                result.append(.heading(id: nextID, level: 3, text: String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("## ") {
                result.append(.heading(id: nextID, level: 2, text: String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("# ") {
                result.append(.heading(id: nextID, level: 1, text: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                let leadingSpaces = rawLine.prefix(while: { $0 == " " || $0 == "\t" }).count
                let indent = leadingSpaces >= 2 ? 1 : 0
                result.append(.bullet(id: nextID, indent: indent, text: String(trimmed.dropFirst(2))))
            } else {
                result.append(.paragraph(id: nextID, text: trimmed))
            }
            nextID += 1
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(blocks) { block in
                switch block {
                case .heading(_, let level, let text):
                    inlineMarkdownText(text)
                        .font(level <= 2 ? .headline : .subheadline.weight(.semibold))
                        .foregroundStyle(VeloraTheme.inkPrimary)
                        .padding(.top, level <= 2 ? 4 : 2)

                case .bullet(_, let indent, let text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(indent > 0 ? "◦" : "•")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(VeloraTheme.accentText)
                            .accessibilityHidden(true)
                        inlineMarkdownText(text)
                            .font(.callout)
                            .foregroundStyle(VeloraTheme.inkPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(indent) * 14)

                case .paragraph(_, let text):
                    inlineMarkdownText(text)
                        .font(.callout)
                        .foregroundStyle(VeloraTheme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func inlineMarkdownText(_ raw: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(raw)
    }
}
