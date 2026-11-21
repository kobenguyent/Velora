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

            contentSection

            Divider()

            footerSection
        }
        .padding(22)
        .frame(width: 560)
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
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(VeloraTheme.brandGradient)
                    .frame(width: 48, height: 48)
                Image(systemName: "arrow.down.app.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle)
                    .font(.title3.weight(.bold))
                Text("GitHub Releases · \(updateChecker.githubRepository)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VeloraBadge(text: "v\(UpdateChecker.currentVersionString)", color: .secondary)
        }
    }

    private var headerTitle: String {
        switch updateChecker.state {
        case .checking:
            "Checking GitHub Releases…"
        case .upToDate:
            "Velora Is Up to Date"
        case .updateAvailable(let u):
            "Velora \(u.version.description) Available"
        case .downloading(let u, _, _, _):
            "Downloading Velora \(u.version.description)…"
        case .verifying(let u):
            "Verifying Velora \(u.version.description)…"
        case .readyToInstall(let staged):
            "Ready to Install Velora \(staged.update.version.description)"
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
                Text("Contacting GitHub Releases API for \(updateChecker.githubRepository)…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 110)

        case .upToDate(let checkedAt):
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(VeloraTheme.emerald)
                Text("You're running the latest version of Velora (v\(UpdateChecker.currentVersionString)).")
                    .font(.callout.weight(.medium))
                Text("Last checked \(checkedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        Spacer()
                        Text("\(ByteCountFormatter.string(fromByteCount: received, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: progress)
                        .tint(VeloraTheme.violet)
                }
                .veloraCard(padding: 12)
            }

        case .verifying(let available):
            VStack(spacing: 12) {
                ProgressView()
                Text("Verifying SHA-256 checksum & extracting \(available.downloadAsset.name)…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 130)

        case .readyToInstall(let staged):
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title2)
                        .foregroundStyle(VeloraTheme.emerald)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Velora v\(staged.update.version.description) has been downloaded & verified.")
                            .font(.callout.weight(.semibold))
                        Text("Clicking below will close the current Velora app, replace it with the new release, and automatically relaunch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .veloraCard(padding: 13)

                if let sha = staged.verifiedSHA256 {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(VeloraTheme.emerald)
                        Text("SHA-256 Verified: \(sha.prefix(24))…")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

        case .installing:
            VStack(spacing: 10) {
                ProgressView()
                Text("Handing off to Velora updater and closing current app…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Unable to complete update")
                        .font(.headline)
                }
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .veloraCard(padding: 14)
        }
    }

    @ViewBuilder
    private var footerSection: some View {
        HStack {
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

                Button("Later") { dismiss() }
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
                .buttonStyle(.bordered)

            case .readyToInstall(let staged):
                Button("Later") { dismiss() }
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
                .buttonStyle(.bordered)
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)

            default:
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func releaseDetailsView(_ available: AvailableUpdate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VeloraBadge(text: "v\(available.currentVersion.description) → v\(available.version.description)", color: VeloraTheme.cyan)
                VeloraBadge(text: available.downloadAsset.formattedSize, color: .secondary, icon: "doc.zipper")
                if available.release.prerelease {
                    VeloraBadge(text: "Pre-release", color: VeloraTheme.amber)
                }
                if available.checksumAsset != nil {
                    VeloraBadge(text: "SHA-256", color: VeloraTheme.emerald, icon: "checkmark.shield")
                }
                Spacer()
                if let date = available.release.publishedAt {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                let rawNotes = available.release.body?.trimmingCharacters(in: .whitespacesAndNewlines)
                let notesText = (rawNotes?.isEmpty == false) ? rawNotes! : "No release notes provided for this version."
                if let attributed = try? AttributedString(
                    markdown: notesText,
                    options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                ) {
                    Text(attributed)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                } else {
                    Text(notesText)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
            }
            .frame(height: 170)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(VeloraTheme.subtleCardBorder, lineWidth: 1)
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
