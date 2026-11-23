import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeloraCore

struct StudioView: View {
    let engineManager: EngineManager
    let downloadManager: DownloadManager
    @Bindable var studio: StudioViewModel
    let onNavigateToQueue: () -> Void

    @State private var isDropTargeted = false
    @State private var showCommandPreview = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !engineManager.isFullyReady {
                    engineBanner
                }

                urlInputCard

                if let error = studio.inspectionError {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.primary)
                        Spacer()
                        Button("Dismiss") { studio.inspectionError = nil }
                            .buttonStyle(.borderless)
                    }
                    .veloraCard(padding: 12)
                }

                if studio.isExpandingBulk {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(studio.bulkExpansionStatus.isEmpty ? "Expanding playlist videos…" : studio.bulkExpansionStatus)
                            .font(.callout.weight(.medium))
                        Spacer()
                    }
                    .veloraCard(padding: 12)
                }

                if let media = studio.inspectedMedia {
                    MediaPreviewCard(
                        mediaInfo: media,
                        selectedFormatID: studio.configuration.customFormatID,
                        onOpenFormatPicker: { studio.isShowingFormatPicker = true },
                        onClearFormatOverride: { studio.configuration.customFormatID = nil },
                        onOpenPlaylistPicker: { studio.isShowingPlaylistPicker = true },
                        onQueueAllPlaylist: {
                            studio.queuePlaylistEntries(
                                media.availablePlaylistEntries,
                                mediaInfo: media,
                                downloadManager: downloadManager,
                                createSubfolder: studio.configuration.createPlaylistSubfolder,
                                prefixIndex: true
                            )
                            onNavigateToQueue()
                        },
                        onLoadLinkedPlaylist: {
                            studio.loadLinkedPlaylist(engineManager: engineManager)
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                quickPresetsBar

                ConfigurationPanelView(
                    configuration: $studio.configuration,
                    onSaveAsPreset: { studio.isShowingSavePresetSheet = true }
                )

                cliPreviewBar

                if !downloadManager.queue.isEmpty {
                    activeDownloadsSnippet
                }
            }
            .padding(22)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [.fileURL, .url, .plainText], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(VeloraTheme.cyan, style: StrokeStyle(lineWidth: 2.5, dash: [8, 6]))
                    .background(VeloraTheme.violet.opacity(0.08))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $studio.isShowingSavePresetSheet) {
            SavePresetSheet(configuration: studio.configuration) { name, subtitle, symbol in
                downloadManager.saveCustomPreset(
                    name: name,
                    subtitle: subtitle,
                    symbolName: symbol,
                    configuration: studio.configuration
                )
                studio.showToast("Saved custom preset: \(name)")
            }
        }
    }

    private var engineBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: engineManager.isReadyForBasicDownloads ? "wand.and.stars" : "exclamationmark.octagon.fill")
                .font(.title3)
                .foregroundStyle(engineManager.isReadyForBasicDownloads ? VeloraTheme.amber : .red)

            VStack(alignment: .leading, spacing: 2) {
                Text(engineManager.isReadyForBasicDownloads
                     ? "FFmpeg recommended for 1080p+/4K merging & audio conversion"
                     : "Download engine (yt-dlp) is not installed yet")
                    .font(.callout.weight(.semibold))
                Text(engineManager.isReadyForBasicDownloads
                     ? "You can download progressive streams now, or install FFmpeg in one click for full muxing, MP3/FLAC, and embedded subtitles."
                     : "Velora uses yt-dlp & FFmpeg under the hood to support 1,000+ sites including YouTube, Vimeo, X, TikTok, and Twitch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Open Engine Setup") {
                studio.isShowingEngineSetup = true
            }
            .buttonStyle(.borderedProminent)
            .tint(VeloraTheme.violet)
        }
        .veloraCard(padding: 14)
    }

    private var urlInputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Source Media URL")
                        .font(.headline)
                    Text("Supports YouTube, Vimeo, X, TikTok, Instagram, Twitch, SoundCloud & 1,000+ sites — or drag & drop links here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Input Mode", selection: $studio.isBatchMode) {
                    Text("Single URL").tag(false)
                    Text("Batch URLs").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 190)
            }

            if studio.isBatchMode {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $studio.urlInput)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 96, maxHeight: 150)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(VeloraTheme.subtleCardBorder, lineWidth: 1)
                        )
                        .overlay(alignment: .topLeading) {
                            if studio.urlInput.isEmpty {
                                Text("Paste multiple video or playlist URLs (one per line), or import a .txt list…")
                                    .font(.callout)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .allowsHitTesting(false)
                            }
                        }

                    HStack(spacing: 10) {
                        Button {
                            importURLListFile()
                        } label: {
                            Label("Import .txt…", systemImage: "doc.text")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Toggle("Expand playlists into parallel downloads", isOn: $studio.expandPlaylistsInBatch)
                            .font(.caption)

                        Spacer()

                        let urlCount = studio.detectedBatchURLs.count
                        let playlistCount = studio.detectedBatchPlaylistCount
                        if urlCount > 0 {
                            VeloraBadge(
                                text: "\(urlCount) URL\(urlCount == 1 ? "" : "s")",
                                color: VeloraTheme.cyan
                            )
                            if playlistCount > 0 {
                                VeloraBadge(
                                    text: "\(playlistCount) playlist\(playlistCount == 1 ? "" : "s")",
                                    color: VeloraTheme.violet,
                                    icon: "list.bullet.rectangle"
                                )
                            }
                        }

                        if !studio.urlInput.isEmpty {
                            Button("Clear") {
                                studio.urlInput = ""
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                        TextField("https://www.youtube.com/watch?v=…", text: $studio.urlInput)
                            .textFieldStyle(.plain)
                            .font(.system(.body, design: .rounded))
                            .onSubmit {
                                studio.startInspectingCurrentURL(engineManager: engineManager)
                            }
                        if !studio.urlInput.isEmpty {
                            Button {
                                studio.cancelInspection()
                                studio.urlInput = ""
                                studio.inspectedMedia = nil
                                studio.inspectionError = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(VeloraTheme.subtleCardBorder, lineWidth: 1)
                    )

                    Button {
                        studio.pasteFromClipboardAndInspect(engineManager: engineManager)
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .help("Paste URL from clipboard and inspect")

                    if studio.isInspecting {
                        Button {
                            studio.cancelInspection()
                        } label: {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Cancel")
                            }
                        }
                        .buttonStyle(.bordered)
                        .help("Cancel URL inspection")
                    } else {
                        Button {
                            studio.startInspectingCurrentURL(engineManager: engineManager)
                        } label: {
                            Label("Inspect", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!studio.canDownload)
                    }
                }
            }

            HStack {
                VeloraBadge(
                    text: studio.configuration.summaryBadge,
                    color: VeloraTheme.violet,
                    icon: studio.configuration.mode.systemImage
                )

                if studio.configuration.subtitleMode != .off {
                    VeloraBadge(text: "Subtitles", color: VeloraTheme.cyan, icon: "captions.bubble")
                }

                if studio.configuration.sponsorBlock != .off {
                    VeloraBadge(text: "SponsorBlock", color: VeloraTheme.emerald, icon: "shield.checkered")
                }

                if studio.configuration.clipEnabled {
                    VeloraBadge(text: "Clip Range", color: VeloraTheme.amber, icon: "scissors")
                }

                Spacer()

                Button {
                    studio.startDownload(downloadManager: downloadManager, engineManager: engineManager)
                } label: {
                    HStack(spacing: 6) {
                        if studio.isExpandingBulk {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                        }
                        Text(downloadButtonTitle)
                    }
                }
                .buttonStyle(VeloraPrimaryButtonStyle(isDisabled: !studio.canDownload || studio.isExpandingBulk))
                .disabled(!studio.canDownload || studio.isExpandingBulk)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .veloraCard()
    }

    private var quickPresetsBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quick Presets")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Click a preset to configure quality & container instantly")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(downloadManager.allPresets) { preset in
                        Button {
                            studio.applyPreset(preset)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: preset.symbolName)
                                    .font(.callout)
                                    .foregroundStyle(VeloraTheme.violet)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(preset.name)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(preset.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(VeloraTheme.surfaceFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(VeloraTheme.subtleCardBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var cliPreviewBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showCommandPreview.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showCommandPreview ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                        Image(systemName: "terminal")
                            .font(.caption)
                        Text("Command Preview")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    let preview = YTDLPCommandBuilder.shellPreview(
                        ytdlpPath: engineManager.ytdlpStatus.path ?? "yt-dlp",
                        url: studio.urlInput,
                        configuration: studio.configuration,
                        ffmpegPath: engineManager.ffmpegStatus.path,
                        jsRuntimeArg: engineManager.ytdlpJSRuntimeArgument
                    )
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(preview, forType: .string)
                    studio.showToast("Copied yt-dlp command")
                } label: {
                    Label("Copy CLI", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            if showCommandPreview {
                let cmd = YTDLPCommandBuilder.shellPreview(
                    ytdlpPath: engineManager.ytdlpStatus.path ?? "yt-dlp",
                    url: studio.urlInput,
                    configuration: studio.configuration,
                    ffmpegPath: engineManager.ffmpegStatus.path,
                    jsRuntimeArg: engineManager.ytdlpJSRuntimeArgument
                )
                Text(cmd)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
            }
        }
        .veloraCard(padding: 12)
    }

    private var activeDownloadsSnippet: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Queue Activity")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("View Full Queue →") {
                    onNavigateToQueue()
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
                .foregroundStyle(VeloraTheme.violet)
            }

            ForEach(downloadManager.queue.prefix(3)) { item in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            Text(item.statusDetail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let speed = item.speedText {
                                Text(speed)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(VeloraTheme.cyan)
                            }
                            if let eta = item.etaText {
                                Text("ETA \(eta)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if item.status.isActive || item.status == .completed {
                            ProgressView(value: item.progress)
                                .tint(item.status == .completed ? VeloraTheme.emerald : VeloraTheme.violet)
                        }
                    }

                    Spacer()

                    if item.status == .completed, let path = item.outputFilePath {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.bordered)
                        .help("Reveal in Finder")
                    } else if item.status.isActive {
                        Button {
                            downloadManager.cancel(id: item.id)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.bordered)
                        .help("Cancel download")
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.65))
                )
            }
        }
        .veloraCard(padding: 14)
    }

    private var downloadButtonTitle: String {
        if studio.isExpandingBulk {
            return "Expanding…"
        }
        if studio.isBatchMode {
            let count = studio.detectedBatchURLs.count
            return count > 0 ? "Queue \(count) URL\(count == 1 ? "" : "s")" : "Queue All URLs"
        }
        if let media = studio.inspectedMedia, media.isPlaylist, !media.availablePlaylistEntries.isEmpty {
            return "Queue All \(media.availablePlaylistEntries.count) Videos"
        }
        if PlaylistURLDetector.isPurePlaylistURL(studio.urlInput) {
            return "Expand & Download Playlist"
        }
        return "Download Now"
    }

    private func importURLListFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .commaSeparatedText]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import URLs"

        guard panel.runModal() == .OK, let fileURL = panel.url,
              let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return
        }
        let extracted = YTDLPCommandBuilder.extractURLs(from: contents)
        guard !extracted.isEmpty else {
            studio.showToast("No valid URLs found in \(fileURL.lastPathComponent)")
            return
        }
        let existing = YTDLPCommandBuilder.extractURLs(from: studio.urlInput)
        let merged = existing + extracted.filter { !existing.contains($0) }
        studio.isBatchMode = true
        studio.urlInput = merged.joined(separator: "\n")
        studio.showToast("Imported \(extracted.count) URL\(extracted.count == 1 ? "" : "s") from \(fileURL.lastPathComponent)")
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        if url.isFileURL,
                           let text = try? String(contentsOf: url, encoding: .utf8) {
                            let extracted = YTDLPCommandBuilder.extractURLs(from: text)
                            if !extracted.isEmpty {
                                studio.isBatchMode = true
                                studio.urlInput = extracted.joined(separator: "\n")
                                studio.showToast("Loaded \(extracted.count) URLs from \(url.lastPathComponent)")
                                return
                            }
                        }
                        studio.urlInput = url.absoluteString
                        studio.isBatchMode = false
                        studio.startInspectingCurrentURL(engineManager: engineManager)
                    }
                }
                return true
            }
            if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { str, _ in
                    guard let str else { return }
                    Task { @MainActor in
                        let extracted = YTDLPCommandBuilder.extractURLs(from: str)
                        if extracted.count > 1 {
                            studio.isBatchMode = true
                            studio.urlInput = extracted.joined(separator: "\n")
                        } else {
                            studio.urlInput = str.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
                return true
            }
        }
        return false
    }
}

struct SavePresetSheet: View {
    let configuration: DownloadConfiguration
    let onSave: (String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var subtitle = ""
    @State private var selectedSymbol = "star.fill"

    private let symbols = [
        "star.fill", "film.fill", "music.note", "4k.tv", "sparkles",
        "bolt.fill", "headphones", "iphone", "desktopcomputer", "scissors"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Configuration as Preset")
                .font(.title3.weight(.bold))

            Form {
                TextField("Preset Name", text: $name, prompt: Text("e.g. YouTube 4K Archival"))
                TextField("Description", text: $subtitle, prompt: Text(configuration.summaryBadge))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Icon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(symbols, id: \.self) { sym in
                            Button {
                                selectedSymbol = sym
                            } label: {
                                Image(systemName: sym)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7)
                                            .fill(selectedSymbol == sym ? VeloraTheme.violet.opacity(0.25) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7)
                                            .stroke(selectedSymbol == sym ? VeloraTheme.violet : VeloraTheme.subtleCardBorder, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Preset") {
                    let finalSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? configuration.summaryBadge
                        : subtitle
                    onSave(name, finalSubtitle, selectedSymbol)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(VeloraTheme.violet)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
