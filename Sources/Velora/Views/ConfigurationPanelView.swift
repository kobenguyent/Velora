import AppKit
import SwiftUI
import VeloraCore

private enum ConfigTab: String, CaseIterable, Identifiable {
    case media = "Media & Quality"
    case metadata = "Subtitles & Meta"
    case clipPlaylist = "Clip & Playlist"
    case outputNetwork = "Output & Network"

    var id: String { rawValue }
}

struct ConfigurationPanelView: View {
    @Binding var configuration: DownloadConfiguration
    let onSaveAsPreset: () -> Void

    @State private var selectedTab: ConfigTab = .media

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Download Configuration")
                    .font(.headline)
                Spacer()
                Button {
                    onSaveAsPreset()
                } label: {
                    Label("Save Preset", systemImage: "plus.square.on.square")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Picker("Section", selection: $selectedTab) {
                ForEach(ConfigTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Group {
                switch selectedTab {
                case .media:
                    mediaTab
                case .metadata:
                    metadataTab
                case .clipPlaylist:
                    clipPlaylistTab
                case .outputNetwork:
                    outputNetworkTab
                }
            }
            .padding(.top, 4)
        }
        .veloraCard()
    }

    // MARK: - Tab 1: Media & Quality

    private var mediaTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let customID = configuration.customFormatID, !customID.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(VeloraTheme.cyan)
                    Text("Exact Stream Override Active: format ID **\(customID)**")
                        .font(.callout)
                    Spacer()
                    Button("Use Automatic Quality") {
                        configuration.customFormatID = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(10)
                .background(VeloraTheme.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    fieldLabel("Download Mode")
                    Picker("Mode", selection: $configuration.mode) {
                        ForEach(MediaMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                if configuration.mode == .audioOnly {
                    GridRow {
                        fieldLabel("Audio Format")
                        Picker("Audio Format", selection: $configuration.audioFormat) {
                            ForEach(AudioFormat.allCases) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        .labelsHidden()
                    }

                    GridRow {
                        fieldLabel("Audio Quality")
                        Picker("Audio Quality", selection: $configuration.audioBitrate) {
                            ForEach(AudioBitrate.allCases) { rate in
                                Text(rate.displayName).tag(rate)
                            }
                        }
                        .labelsHidden()
                    }
                } else {
                    GridRow {
                        fieldLabel("Target Quality")
                        Picker("Quality", selection: $configuration.videoQuality) {
                            ForEach(VideoQuality.allCases) { q in
                                Text(q.displayName).tag(q)
                            }
                        }
                        .labelsHidden()
                    }

                    GridRow {
                        fieldLabel("Container Format")
                        Picker("Container", selection: $configuration.videoContainer) {
                            ForEach(VideoContainer.allCases) { c in
                                Text(c.displayName).tag(c)
                            }
                        }
                        .labelsHidden()
                    }

                    GridRow {
                        fieldLabel("Preferred Codec")
                        Picker("Codec", selection: $configuration.preferredCodec) {
                            ForEach(PreferredVideoCodec.allCases) { codec in
                                Text(codec.displayName).tag(codec)
                            }
                        }
                        .labelsHidden()
                    }

                    GridRow {
                        fieldLabel("Frame Rate Cap")
                        Picker("Frame Rate", selection: $configuration.frameRateCap) {
                            ForEach(FrameRateCap.allCases) { fps in
                                Text(fps.displayName).tag(fps)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                }
            }
        }
    }

    // MARK: - Tab 2: Subtitles & Metadata

    private var metadataTab: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
            GridRow {
                fieldLabel("Subtitles")
                Picker("Subtitles", selection: $configuration.subtitleMode) {
                    ForEach(SubtitleMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            if configuration.subtitleMode == .preferredLanguages {
                GridRow {
                    fieldLabel("Languages")
                    TextField("en,vi,ja", text: $configuration.subtitleLanguages)
                        .textFieldStyle(.roundedBorder)
                        .help("Comma-separated ISO language codes (e.g. en,es,ja)")
                }
            }

            if configuration.subtitleMode != .off {
                GridRow {
                    fieldLabel("Subtitle Options")
                    HStack(spacing: 18) {
                        Toggle("Include Auto-Generated", isOn: $configuration.includeAutoSubtitles)
                        if configuration.mode != .audioOnly {
                            Toggle("Embed inside Video", isOn: $configuration.embedSubtitles)
                        }
                    }
                }
            }

            GridRow {
                fieldLabel("Metadata & Art")
                HStack(spacing: 18) {
                    Toggle("Embed Thumbnail", isOn: $configuration.embedThumbnail)
                    Toggle("Embed Metadata", isOn: $configuration.embedMetadata)
                    Toggle("Embed Chapters", isOn: $configuration.embedChapters)
                }
            }

            GridRow {
                fieldLabel("Chapters")
                Toggle("Split video into separate files per chapter", isOn: $configuration.splitChapters)
            }

            GridRow {
                fieldLabel("SponsorBlock")
                Picker("SponsorBlock", selection: $configuration.sponsorBlock) {
                    ForEach(SponsorBlockMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
            }
        }
    }

    // MARK: - Tab 3: Clip & Playlist

    private var clipPlaylistTab: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
            GridRow {
                fieldLabel("Time-Range Clip")
                Toggle("Download only a specific clip segment", isOn: $configuration.clipEnabled)
            }

            if configuration.clipEnabled {
                GridRow {
                    fieldLabel("Clip Window")
                    HStack(spacing: 10) {
                        TextField("Start (e.g. 00:01:10)", text: $configuration.clipStart)
                            .textFieldStyle(.roundedBorder)
                        Text("to")
                            .foregroundStyle(.secondary)
                        TextField("End (e.g. 00:03:45)", text: $configuration.clipEnd)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                GridRow {
                    fieldLabel("Cut Accuracy")
                    Toggle("Force keyframes at cuts (frame-accurate trim, re-encodes cut points)", isOn: $configuration.forceKeyframesAtCuts)
                }
            }

            GridRow {
                fieldLabel("Playlist Mode")
                Picker("Playlist", selection: $configuration.playlistBehavior) {
                    ForEach(PlaylistBehavior.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            if configuration.playlistBehavior == .downloadEntirePlaylist {
                GridRow {
                    fieldLabel("Playlist Range")
                    TextField("Optional item range (e.g. 1-10 or 1,3,5-8)", text: $configuration.playlistItems)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    fieldLabel("Organization")
                    Toggle("Create a dedicated subfolder per playlist", isOn: $configuration.createPlaylistSubfolder)
                }
            }
        }
    }

    // MARK: - Tab 4: Output & Network

    private var outputNetworkTab: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
            GridRow {
                fieldLabel("Save Location")
                HStack(spacing: 8) {
                    Text(configuration.outputDirectoryPath)
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(VeloraTheme.subtleCardBorder, lineWidth: 1)
                        )

                    Button("Choose…") {
                        pickOutputDirectory()
                    }
                    .buttonStyle(.bordered)

                    Button {
                        let expanded = (configuration.outputDirectoryPath as NSString).expandingTildeInPath
                        try? FileManager.default.createDirectory(atPath: expanded, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                    .help("Open folder in Finder")
                }
            }

            GridRow {
                fieldLabel("Filename Template")
                Picker("Template", selection: $configuration.filenamePreset) {
                    ForEach(FilenameTemplatePreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .labelsHidden()
            }

            if configuration.filenamePreset == .custom {
                GridRow {
                    fieldLabel("Custom Pattern")
                    TextField("%(title)s [%(id)s].%(ext)s", text: $configuration.customFilenameTemplate)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.callout, design: .monospaced))
                }
            }

            GridRow {
                fieldLabel("File Rules")
                HStack(spacing: 18) {
                    Toggle("ASCII-only filenames", isOn: $configuration.restrictFilenames)
                    Toggle("Overwrite existing files", isOn: $configuration.overwriteExisting)
                }
            }

            GridRow {
                fieldLabel("Network IP")
                HStack(spacing: 10) {
                    Picker("Network IP", selection: $configuration.networkIPVersion) {
                        ForEach(NetworkIPVersion.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)

                    Text("IPv4 prevents stalls on networks with broken IPv6 routing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GridRow {
                fieldLabel("Browser Cookies")
                HStack(spacing: 10) {
                    Picker("Cookies", selection: $configuration.browserCookies) {
                        ForEach(BrowserCookiesSource.allCases) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)

                    Text("Use for private, age-gated, or member-only media")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GridRow {
                fieldLabel("Performance")
                HStack(spacing: 16) {
                    Stepper("Fragments: \(configuration.concurrentFragments)", value: $configuration.concurrentFragments, in: 1...16)
                        .frame(width: 155, alignment: .leading)
                    TextField("Rate Limit (e.g. 5M)", text: $configuration.rateLimit)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                    TextField("Proxy (http:// or socks5://)", text: $configuration.proxyURL)
                        .textFieldStyle(.roundedBorder)
                }
            }

            GridRow {
                fieldLabel("Extra yt-dlp Args")
                TextField("Optional raw flags (e.g. --write-description --geo-bypass)", text: $configuration.extraArguments)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
            }
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: 132, alignment: .trailing)
    }

    private func pickOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Output Folder"
        let expanded = (configuration.outputDirectoryPath as NSString).expandingTildeInPath
        panel.directoryURL = URL(fileURLWithPath: expanded)

        if panel.runModal() == .OK, let selected = panel.url {
            configuration.outputDirectoryPath = selected.path
        }
    }
}
