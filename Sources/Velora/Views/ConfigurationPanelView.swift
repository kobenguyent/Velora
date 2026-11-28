import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeloraCore

enum ConfigTab: String, CaseIterable, Identifiable {
    case media = "Media"
    case subtitles = "Subtitles"
    case clipPlaylist = "Clip & List"
    case outputNetwork = "Network"

    var id: String { rawValue }
}

struct ConfigurationPanelView: View {
    @Binding var configuration: DownloadConfiguration
    var engineManager: EngineManager? = nil
    var currentURL: String = ""
    var customFormatIsVideoOnly: Bool = false
    @Binding var selectedTab: ConfigTab
    let onSaveAsPreset: () -> Void
    var onToast: ((String) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.veloraLayout) private var layout
    @State private var showCLIDisclosure = false

    private var controlMaxWidth: CGFloat {
        if layout.widthClass == .compact { return 180 }
        return layout.usesTwoColumnConfig ? layout.scaled(230) : 260
    }

    init(
        configuration: Binding<DownloadConfiguration>,
        engineManager: EngineManager? = nil,
        currentURL: String = "",
        customFormatIsVideoOnly: Bool = false,
        selectedTab: Binding<ConfigTab> = .constant(.media),
        onSaveAsPreset: @escaping () -> Void,
        onToast: ((String) -> Void)? = nil
    ) {
        self._configuration = configuration
        self.engineManager = engineManager
        self.currentURL = currentURL
        self.customFormatIsVideoOnly = customFormatIsVideoOnly
        self._selectedTab = selectedTab
        self.onSaveAsPreset = onSaveAsPreset
        self.onToast = onToast
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            tabBar

            groupedSettingsSurface

            bottomUtilityBar
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(ConfigTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    if reduceMotion {
                        selectedTab = tab
                    } else {
                        withAnimation(.snappy(duration: 0.16)) {
                            selectedTab = tab
                        }
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(layout.font(12.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? VeloraTheme.inkPrimary : VeloraTheme.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .frame(minHeight: layout.scaled(28))
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(VeloraTheme.surfaceElevated)
                                    .overlay(Capsule().stroke(VeloraTheme.hairline, lineWidth: 1))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .veloraFocusableRing(cornerRadius: 999)
                .accessibilityLabel("\(tab.rawValue) configuration tab")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(VeloraTheme.surfaceSubtle))
        .overlay(Capsule().stroke(VeloraTheme.hairline, lineWidth: 1))
    }

    @ViewBuilder
    private var groupedSettingsSurface: some View {
        switch selectedTab {
        case .media:
            settingsCard {
                mediaTab
            }

        case .subtitles:
            if layout.usesTwoColumnConfig {
                HStack(alignment: .top, spacing: 12) {
                    settingsCard(title: "Subtitles & SponsorBlock") {
                        subtitlesCoreRows
                    }
                    settingsCard(title: "Metadata & Chapters") {
                        metadataChaptersRows
                    }
                }
            } else {
                settingsCard {
                    subtitlesCoreRows
                    rowDivider
                    metadataChaptersRows
                }
            }

        case .clipPlaylist:
            if layout.usesTwoColumnConfig {
                HStack(alignment: .top, spacing: 12) {
                    settingsCard(title: "Time-Range Clip") {
                        clipRows
                    }
                    settingsCard(title: "Playlist Behavior") {
                        playlistRows
                    }
                }
            } else {
                settingsCard {
                    clipRows
                    rowDivider
                    playlistRows
                }
            }

        case .outputNetwork:
            if layout.usesTwoColumnConfig {
                HStack(alignment: .top, spacing: 12) {
                    settingsCard(title: "Output & Performance") {
                        outputPerformanceRows
                    }
                    settingsCard(title: "Network, Cookies & Retries") {
                        networkRetriesRows
                    }
                }
            } else {
                settingsCard {
                    outputPerformanceRows
                    rowDivider
                    networkRetriesRows
                }
            }
        }
    }

    private func settingsCard<Content: View>(
        title: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(layout.font(12, weight: .semibold))
                    .foregroundStyle(VeloraTheme.inkSecondary)
                    .padding(.horizontal, layout.scaled(14))
                    .padding(.top, 10)
                    .padding(.bottom, 7)

                Divider()
                    .overlay(VeloraTheme.hairline)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(VeloraTheme.ground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(VeloraTheme.hairline, lineWidth: 1)
        )
    }

    // MARK: - Tab 1: Media

    @ViewBuilder
    private var mediaTab: some View {
        settingsRow("Exact Stream") {
            HStack(spacing: 8) {
                if let customID = configuration.customFormatID?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !customID.isEmpty {
                    Text(customFormatIsVideoOnly ? "#\(customID) (+Audio)" : "#\(customID)")
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundStyle(VeloraTheme.accentText)
                    Button("Clear") {
                        configuration.customFormatID = nil
                    }
                    .buttonStyle(VeloraSecondaryButtonStyle())
                    .controlSize(.small)
                } else {
                    Text("Automatic")
                        .font(.caption)
                        .foregroundStyle(VeloraTheme.inkSecondary)
                }
            }
        }

        rowDivider

        settingsRow("Mode") {
            Picker("Mode", selection: $configuration.mode) {
                ForEach(MediaMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .frame(maxWidth: controlMaxWidth, alignment: .trailing)
        }

        if configuration.mode == .audioOnly {
            rowDivider

            settingsRow("Audio Format") {
                Picker("Audio Format", selection: $configuration.audioFormat) {
                    ForEach(AudioFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: controlMaxWidth, alignment: .trailing)
            }

            rowDivider

            settingsRow("Audio Bitrate") {
                Picker("Audio Bitrate", selection: $configuration.audioBitrate) {
                    ForEach(AudioBitrate.allCases) { rate in
                        Text(rate.displayName).tag(rate)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: controlMaxWidth, alignment: .trailing)
            }
        } else {
            rowDivider

            settingsRow("Target Quality") {
                Picker("Quality", selection: $configuration.videoQuality) {
                    ForEach(VideoQuality.allCases) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: controlMaxWidth, alignment: .trailing)
            }

            rowDivider

            settingsRow("Container") {
                Picker("Container", selection: $configuration.videoContainer) {
                    ForEach(VideoContainer.allCases) { container in
                        Text(container.displayName).tag(container)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: controlMaxWidth, alignment: .trailing)
            }

            rowDivider

            settingsRow("Preferred Codec") {
                Picker("Codec", selection: $configuration.preferredCodec) {
                    ForEach(PreferredVideoCodec.allCases) { codec in
                        Text(codec.displayName).tag(codec)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: controlMaxWidth, alignment: .trailing)
            }

            rowDivider

            settingsRow("Frame Rate Cap") {
                Picker("Frame Rate", selection: $configuration.frameRateCap) {
                    ForEach(FrameRateCap.allCases) { fps in
                        Text(fps.displayName).tag(fps)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: controlMaxWidth, alignment: .trailing)
            }
        }
    }

    // MARK: - Tab 2: Subtitles & Metadata

    @ViewBuilder
    private var subtitlesCoreRows: some View {
        settingsRow(
            "Subtitles",
            note: configuration.subtitleMode == .allAvailable ? "Fetches all subtitle tracks except live chat (all,-live_chat)." : nil
        ) {
            Picker("Subtitles", selection: $configuration.subtitleMode) {
                ForEach(SubtitleMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .frame(maxWidth: controlMaxWidth, alignment: .trailing)
        }

        if configuration.subtitleMode == .preferredLanguages {
            rowDivider

            settingsRow("Languages", note: "Comma-separated ISO codes (e.g. en,vi,ja)") {
                TextField("en,vi,ja", text: $configuration.subtitleLanguages)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: controlMaxWidth, alignment: .trailing)
                    .accessibilityLabel("Subtitle Languages")
            }
        }

        if configuration.subtitleMode != .off {
            rowDivider

            settingsRow("Include Auto-Captions") {
                Toggle("Include Auto-Captions", isOn: $configuration.includeAutoSubtitles)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            if configuration.mode != .audioOnly {
                rowDivider

                settingsRow("Embed Subtitles") {
                    Toggle("Embed Subtitles", isOn: $configuration.embedSubtitles)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
        }

        rowDivider

        settingsRow("SponsorBlock") {
            Picker("SponsorBlock", selection: $configuration.sponsorBlock) {
                ForEach(SponsorBlockMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .frame(maxWidth: controlMaxWidth, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var metadataChaptersRows: some View {
        settingsRow(
            "Embed Cover Art",
            note: thumbnailAutoSkipNote
        ) {
            Toggle("Embed Cover Art", isOn: $configuration.embedThumbnail)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }

        rowDivider

        settingsRow("Embed Metadata") {
            Toggle("Embed Metadata", isOn: $configuration.embedMetadata)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }

        rowDivider

        settingsRow("Embed Chapters") {
            Toggle("Embed Chapters", isOn: $configuration.embedChapters)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }

        rowDivider

        settingsRow("Split Chapters", note: "Export each chapter into its own media file") {
            Toggle("Split Chapters", isOn: $configuration.splitChapters)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    // MARK: - Tab 3: Clip & List

    @ViewBuilder
    private var clipRows: some View {
        settingsRow("Time-Range Clip") {
            Toggle("Time-Range Clip", isOn: $configuration.clipEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }

        if configuration.clipEnabled {
            rowDivider

            settingsRow(
                "Clip Window",
                note: clipValidationWarning,
                noteIsError: clipValidationWarning != nil
            ) {
                let fieldWidth: CGFloat = layout.widthClass == .compact ? 74 : 92
                HStack(spacing: 6) {
                    TextField("00:00", text: $configuration.clipStart)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: fieldWidth)
                        .accessibilityLabel("Clip start timestamp")
                    Text("–")
                        .font(.caption)
                        .foregroundStyle(VeloraTheme.inkSecondary)
                    TextField("02:30", text: $configuration.clipEnd)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: fieldWidth)
                        .accessibilityLabel("Clip end timestamp")
                }
                .frame(maxWidth: controlMaxWidth, alignment: .trailing)
            }

            rowDivider

            settingsRow("Force Keyframes at Cuts", note: "Frame-accurate trim (re-encodes cut boundaries)") {
                Toggle("Force Keyframes at Cuts", isOn: $configuration.forceKeyframesAtCuts)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var playlistRows: some View {
        settingsRow("Playlist Mode") {
            Picker("Playlist Mode", selection: $configuration.playlistBehavior) {
                ForEach(PlaylistBehavior.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .frame(maxWidth: controlMaxWidth, alignment: .trailing)
        }

        if configuration.playlistBehavior == .downloadEntirePlaylist {
            rowDivider

            settingsRow("Playlist Range", note: "Optional indices (e.g. 1-10 or 1,3,5-8)") {
                TextField("e.g. 1-10", text: $configuration.playlistItems)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: controlMaxWidth, alignment: .trailing)
                    .accessibilityLabel("Playlist Range")
            }

            rowDivider

            settingsRow("Create Playlist Subfolder") {
                Toggle("Create Playlist Subfolder", isOn: $configuration.createPlaylistSubfolder)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Tab 4: Output & Network

    @ViewBuilder
    private var outputPerformanceRows: some View {
        settingsRow("Output Folder", note: configuration.outputDirectoryPath) {
            HStack(spacing: 6) {
                Button("Choose…") {
                    pickOutputDirectory()
                }
                .buttonStyle(VeloraSecondaryButtonStyle())
                .controlSize(.small)

                Button {
                    let expanded = (configuration.outputDirectoryPath as NSString).expandingTildeInPath
                    try? FileManager.default.createDirectory(atPath: expanded, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
                } label: {
                    Image(systemName: "folder")
                        .font(.caption.weight(.medium))
                        .frame(minWidth: 24, minHeight: 24)
                        .contentShape(Rectangle())
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .veloraFocusableRing(cornerRadius: 6)
                .help("Open folder in Finder")
                .accessibilityLabel("Open output folder in Finder")
            }
            .frame(maxWidth: controlMaxWidth, alignment: .trailing)
        }

        rowDivider

        settingsRow("Filename Template") {
            Picker("Filename Template", selection: $configuration.filenamePreset) {
                ForEach(FilenameTemplatePreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .labelsHidden()
            .frame(maxWidth: controlMaxWidth, alignment: .trailing)
        }

        if configuration.filenamePreset == .custom {
            rowDivider

            settingsRow("Custom Template") {
                TextField("%(title)s [%(id)s].%(ext)s", text: $configuration.customFilenameTemplate)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: controlMaxWidth, alignment: .trailing)
                    .accessibilityLabel("Custom Filename Template")
            }
        }

        rowDivider

        settingsRow("ASCII-Safe Filenames") {
            Toggle("ASCII-Safe Filenames", isOn: $configuration.restrictFilenames)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }

        rowDivider

        settingsRow("Overwrite Existing Files") {
            Toggle("Overwrite Existing Files", isOn: $configuration.overwriteExisting)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }

        rowDivider

        settingsRow("Concurrent Fragments") {
            HStack(spacing: 8) {
                Text("\(configuration.concurrentFragments)")
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(VeloraTheme.inkPrimary)
                Stepper("Concurrent Fragments", value: $configuration.concurrentFragments, in: 1...16)
                    .labelsHidden()
            }
            .frame(maxWidth: controlMaxWidth, alignment: .trailing)
        }

        rowDivider

        settingsRow("Speed Limit", note: "e.g. 5M or 800K (empty for unlimited)") {
            TextField("Unlimited", text: $configuration.rateLimit)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: controlMaxWidth, alignment: .trailing)
                .accessibilityLabel("Speed Limit")
        }
    }

    @ViewBuilder
    private var networkRetriesRows: some View {
        settingsRow(
            "Proxy URL",
            note: proxyValidationWarning,
            noteIsError: proxyValidationWarning != nil
        ) {
            TextField("http:// or socks5://", text: $configuration.proxyURL)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: controlMaxWidth, alignment: .trailing)
                .accessibilityLabel("Proxy URL")
        }

        rowDivider

        settingsRow("Network IP") {
            Picker("Network IP", selection: $configuration.networkIPVersion) {
                ForEach(NetworkIPVersion.allCases) { version in
                    Text(version.displayName).tag(version)
                }
            }
            .labelsHidden()
            .frame(maxWidth: controlMaxWidth, alignment: .trailing)
        }

        rowDivider

        settingsRow("Socket Timeout") {
            HStack(spacing: 8) {
                Text("\(configuration.socketTimeoutSeconds)s")
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(VeloraTheme.inkPrimary)
                Stepper("Socket Timeout", value: $configuration.socketTimeoutSeconds, in: 5...120, step: 5)
                    .labelsHidden()
            }
            .frame(maxWidth: controlMaxWidth, alignment: .trailing)
        }

        rowDivider

        settingsRow("Browser Cookies") {
            Picker("Browser Cookies", selection: $configuration.browserCookies) {
                ForEach(BrowserCookiesSource.allCases) { source in
                    Text(source.displayName).tag(source)
                }
            }
            .labelsHidden()
            .frame(maxWidth: controlMaxWidth, alignment: .trailing)
        }

        rowDivider

        settingsRow(
            "cookies.txt Path",
            note: configuration.cookieFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Optional Netscape cookies file"
                : configuration.cookieFilePath
        ) {
            HStack(spacing: 6) {
                Button("Choose…") {
                    pickCookieFile()
                }
                .buttonStyle(VeloraSecondaryButtonStyle())
                .controlSize(.small)

                if !configuration.cookieFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        configuration.cookieFilePath = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(VeloraTheme.inkSecondary)
                            .frame(minWidth: 24, minHeight: 24)
                            .contentShape(Rectangle())
                            .accessibilityHidden(true)
                    }
                    .buttonStyle(.plain)
                    .veloraFocusableRing(cornerRadius: 999)
                    .help("Clear cookies.txt path")
                    .accessibilityLabel("Clear cookies.txt path")
                }
            }
            .frame(maxWidth: controlMaxWidth, alignment: .trailing)
        }

        rowDivider

        settingsRow("Resume Partial (--continue)") {
            Toggle("Resume Partial Downloads", isOn: $configuration.resumePartialDownloads)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }

        rowDivider

        settingsRow("Auto-Retry Count") {
            HStack(spacing: 8) {
                Text("\(configuration.autoRetryCount)")
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(VeloraTheme.inkPrimary)
                Stepper("Auto-Retry Count", value: $configuration.autoRetryCount, in: 0...10)
                    .labelsHidden()
            }
            .frame(maxWidth: controlMaxWidth, alignment: .trailing)
        }

        rowDivider

        let dangerousFlags = YTDLPCommandBuilder.dangerousExtraArgumentFlags(in: configuration.extraArguments)
        settingsRow(
            "Extra Arguments",
            note: dangerousFlags.isEmpty
                ? nil
                : "Blocked unsafe flags detected: \(dangerousFlags.joined(separator: ", ")). These are stripped automatically.",
            noteIsError: !dangerousFlags.isEmpty
        ) {
            TextField("--geo-bypass …", text: $configuration.extraArguments)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: controlMaxWidth, alignment: .trailing)
                .accessibilityLabel("Extra yt-dlp Arguments")
        }
    }

    // MARK: - Bottom Hardened CLI Preview + Actions

    private var bottomUtilityBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if layout.widthClass == .compact {
                FlowWrapLayout(alignment: .leading, spacing: 8, lineSpacing: 8) {
                    cliPreviewToggleButton
                    copyCLIButton
                    savePresetButton
                }
            } else {
                HStack(spacing: 8) {
                    cliPreviewToggleButton
                    Spacer()
                    copyCLIButton
                    savePresetButton
                }
            }

            if showCLIDisclosure {
                Text(cliPreviewString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(VeloraTheme.inkSecondary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(VeloraTheme.surfaceSubtle)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(VeloraTheme.hairline, lineWidth: 1)
                    )
            }
        }
    }

    private var cliPreviewToggleButton: some View {
        Button {
            if reduceMotion {
                showCLIDisclosure.toggle()
            } else {
                withAnimation(.snappy(duration: 0.16)) {
                    showCLIDisclosure.toggle()
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: showCLIDisclosure ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
                Image(systemName: "terminal")
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text("Hardened CLI Preview")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(VeloraTheme.inkSecondary)
            .padding(.horizontal, 4)
            .frame(minWidth: 24, minHeight: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .veloraFocusableRing(cornerRadius: 6)
        .accessibilityLabel("Hardened CLI Preview")
        .accessibilityValue(showCLIDisclosure ? "Expanded" : "Collapsed")
    }

    private var copyCLIButton: some View {
        Button {
            let preview = cliPreviewString
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(preview, forType: .string)
            onToast?("Copied yt-dlp command")
        } label: {
            Label("Copy CLI", systemImage: "doc.on.doc")
                .font(.caption.weight(.medium))
        }
        .buttonStyle(VeloraSecondaryButtonStyle())
        .controlSize(.small)
        .accessibilityLabel("Copy yt-dlp command")
    }

    private var savePresetButton: some View {
        Button {
            onSaveAsPreset()
        } label: {
            Label("Save Preset", systemImage: "plus.square.on.square")
                .font(.caption.weight(.medium))
        }
        .buttonStyle(VeloraSecondaryButtonStyle())
        .controlSize(.small)
        .accessibilityLabel("Save configuration as preset")
    }

    // MARK: - Row Builder & Validation Helpers

    private func settingsRow<Control: View>(
        _ title: String,
        note: String? = nil,
        noteIsError: Bool = false,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(layout.font(13.5))
                    .foregroundStyle(VeloraTheme.inkPrimary)

                Spacer(minLength: 12)

                control()
            }

            if let note, !note.isEmpty {
                Text(note)
                    .font(layout.font(11.5))
                    .foregroundStyle(noteIsError ? VeloraTheme.danger : VeloraTheme.inkSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, layout.scaled(14))
        .padding(.vertical, layout.scaled(10.5))
    }

    private var rowDivider: some View {
        Divider()
            .overlay(VeloraTheme.hairline)
            .padding(.leading, 14)
    }

    private var cliPreviewString: String {
        YTDLPCommandBuilder.shellPreview(
            ytdlpPath: engineManager?.ytdlpStatus.path ?? "yt-dlp",
            url: currentURL,
            configuration: configuration,
            ffmpegPath: engineManager?.ffmpegStatus.path,
            jsRuntimeArg: engineManager?.ytdlpJSRuntimeArgument,
            customFormatIsVideoOnly: customFormatIsVideoOnly
        )
    }

    private var thumbnailAutoSkipNote: String? {
        guard configuration.embedThumbnail else { return nil }
        switch configuration.mode {
        case .audioOnly:
            if configuration.audioFormat == .wav || configuration.audioFormat == .aac {
                return "\(configuration.audioFormat.rawValue.uppercased()) does not support embedded cover art; automatically skipped."
            }
        case .videoOnly, .videoAndAudio:
            if configuration.videoContainer == .webm {
                return "WebM does not support embedded cover art; automatically skipped."
            }
        }
        return nil
    }

    private var clipValidationWarning: String? {
        guard configuration.clipEnabled else { return nil }
        let start = configuration.clipStart.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = configuration.clipEnd.trimmingCharacters(in: .whitespacesAndNewlines)
        if start.isEmpty && end.isEmpty {
            return "Enter a start or end timestamp (e.g. 00:15 or 01:30)."
        }
        if !start.isEmpty && !Self.isValidTimestamp(start, allowInf: false) {
            return "Invalid start timestamp. Use SS, MM:SS, or HH:MM:SS."
        }
        if !end.isEmpty && !Self.isValidTimestamp(end, allowInf: true) {
            return "Invalid end timestamp. Use SS, MM:SS, HH:MM:SS, or inf."
        }
        return nil
    }

    private var proxyValidationWarning: String? {
        let trimmed = configuration.proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https", "socks4", "socks4a", "socks5", "socks5h"].contains(scheme),
              let host = components.host,
              !host.isEmpty else {
            return "Enter a valid proxy URL (e.g. http://127.0.0.1:8080 or socks5://127.0.0.1:1080)."
        }
        return nil
    }

    private static func isValidTimestamp(_ value: String, allowInf: Bool) -> Bool {
        if allowInf && value.lowercased() == "inf" {
            return true
        }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return false }
        for (idx, part) in parts.enumerated() {
            let str = String(part)
            guard !str.isEmpty else { return false }
            if idx == parts.count - 1 {
                guard Double(str) != nil, !str.hasPrefix("-") else { return false }
            } else {
                guard let num = Int(str), num >= 0 else { return false }
                if parts.count == 3 && idx == 1 && num >= 60 { return false }
            }
        }
        return true
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

    private func pickCookieFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .data]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select cookies.txt"

        if !configuration.cookieFilePath.isEmpty {
            let expanded = (configuration.cookieFilePath as NSString).expandingTildeInPath
            panel.directoryURL = URL(fileURLWithPath: expanded).deletingLastPathComponent()
        }

        if panel.runModal() == .OK, let selected = panel.url {
            configuration.cookieFilePath = selected.path
        }
    }
}
