import AppKit
import SwiftUI
import VeloraCore

/// Gallery-minimalist Studio workspace (`M2 · Apple Gallery Minimalist Cobalt`).
struct StudioView: View {
    let engineManager: EngineManager
    let downloadManager: DownloadManager
    @Bindable var studio: StudioViewModel
    let onNavigateToQueue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.veloraLayout) private var layout
    @FocusState private var isURLFocused: Bool

    @State private var requestedConfigTab: ConfigTab = .media
    @State private var hoveredPresetID: UUID? = nil

    private nonisolated static let maxDropFileBytes: Int64 = 1_048_576

    private var isRestingCanvas: Bool {
        !studio.isAllOptionsExpanded &&
        studio.inspectedMedia == nil &&
        !studio.isInspecting &&
        studio.inspectionError == nil &&
        downloadManager.queue.isEmpty &&
        !studio.isExpandingBulk
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isRestingCanvas {
                    Spacer(minLength: 20)

                    VStack(alignment: .leading, spacing: layout.scaled(20)) {
                        restingStudioMasthead
                        studioCoreColumn
                    }
                    .frame(maxWidth: layout.studioMaxWidth(expanded: false), alignment: .leading)

                    Spacer(minLength: 16)
                    Spacer(minLength: 16)

                    restingShortcutFooter
                        .padding(.bottom, 18)
                } else {
                    VStack(alignment: .leading, spacing: layout.scaled(20)) {
                        studioCoreTopSection

                        mediaPreviewSlot

                        allOptionsDisclosure

                        if !downloadManager.queue.isEmpty {
                            recentActivityStrip
                        }
                    }
                    .frame(maxWidth: layout.studioMaxWidth(expanded: studio.isAllOptionsExpanded), alignment: .leading)
                    .padding(.vertical, layout.verticalPadding)
                }
            }
            .padding(.horizontal, layout.horizontalPadding)
            .frame(maxWidth: .infinity, minHeight: layout.contentHeight, alignment: isRestingCanvas ? .center : .top)
        }
        .background(VeloraTheme.ground)
        .onChange(of: studio.focusURLRequestToken) { _, _ in
            isURLFocused = true
        }
        .sheet(isPresented: $studio.isShowingSavePresetSheet) {
            SavePresetSheet(configuration: studio.configuration) { name, subtitle, symbol in
                downloadManager.saveCustomPreset(
                    name: name,
                    subtitle: subtitle,
                    symbolName: symbol,
                    configuration: studio.configuration
                )
                studio.showToast("Saved custom preset: \(name)", kind: .success)
            }
        }
    }

    @ViewBuilder
    private var studioCoreColumn: some View {
        studioCoreTopSection
        allOptionsDisclosure
    }

    @ViewBuilder
    private var studioCoreTopSection: some View {
        if !engineManager.isReadyForBasicDownloads {
            missingEngineBanner
        }

        if let clipURL = studio.clipboardSuggestionURL {
            clipboardSuggestionPill(urlString: clipURL)
        }

        heroCommandSurface

        if studio.isExpandingBulk {
            bulkExpansionBanner
        }

        whisperCapsuleRow

        presetGalleryGrid
    }

    private var restingStudioMasthead: some View {
        VStack(alignment: .leading, spacing: layout.scaled(5)) {
            Text("Velora Studio")
                .font(layout.font(28, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(VeloraTheme.inkPrimary)
            Text("Paste a link or drop a URL list to inspect streams, pick quality, and download.")
                .font(layout.font(14))
                .foregroundStyle(VeloraTheme.inkSecondary)
                .lineLimit(2)
        }
    }

    private var restingShortcutFooter: some View {
        FlowWrapLayout(alignment: .center, spacing: 14, lineSpacing: 6) {
            shortcutHintItem(keys: "⇧⌘V", action: "Paste & Inspect")
            shortcutHintItem(keys: "⌘I", action: "Inspect")
            shortcutHintItem(keys: "⌘↩", action: "Download")
            Text("Drop URL or .txt")
                .font(layout.font(11.5))
                .foregroundStyle(VeloraTheme.inkSecondary.opacity(0.7))
        }
    }

    private func shortcutHintItem(keys: String, action: String) -> some View {
        HStack(spacing: 5) {
            Text(keys)
                .font(layout.font(10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(VeloraTheme.inkSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(VeloraTheme.surfaceSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(VeloraTheme.hairline, lineWidth: 1)
                )
            Text(action)
                .font(layout.font(11.5))
                .foregroundStyle(VeloraTheme.inkSecondary.opacity(0.75))
        }
    }

    // MARK: - 1. Conditional Banners

    private var missingEngineBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.title3)
                .foregroundStyle(VeloraTheme.danger)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("yt-dlp engine is not installed")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(VeloraTheme.inkPrimary)
                Text("Install yt-dlp via Engine Setup to inspect links and download media.")
                    .font(.caption)
                    .foregroundStyle(VeloraTheme.inkSecondary)
            }

            Spacer(minLength: 8)

            Button("Install") {
                studio.isShowingEngineSetup = true
            }
            .buttonStyle(VeloraPrimaryButtonStyle())
            .controlSize(.small)
            .accessibilityLabel("Install download engine via Engine Setup")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(VeloraTheme.danger.opacity(colorScheme == .dark ? 0.14 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(VeloraTheme.danger.opacity(0.28), lineWidth: 1)
        )
    }

    private func clipboardSuggestionPill(urlString: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.caption.weight(.semibold))
                .foregroundStyle(VeloraTheme.accentText)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Clipboard URL detected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VeloraTheme.inkPrimary)
                Text(compactClipboardLabel(for: urlString))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(VeloraTheme.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button("Inspect") {
                acceptClipboardSuggestion(urlString)
            }
            .buttonStyle(VeloraSecondaryButtonStyle())
            .controlSize(.small)
            .accessibilityLabel("Inspect clipboard URL \(compactClipboardLabel(for: urlString))")

            Button {
                dismissClipboardSuggestion()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VeloraTheme.inkSecondary)
                    .frame(minWidth: 24, minHeight: 24)
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .veloraFocusableRing(cornerRadius: 999)
            .help("Dismiss clipboard suggestion")
            .accessibilityLabel("Dismiss clipboard suggestion")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(VeloraTheme.surfaceElevated)
        )
        .overlay(
            Capsule()
                .stroke(VeloraTheme.hairline, lineWidth: 1)
        )
        .shadow(
            color: colorScheme == .dark ? .clear : Color.black.opacity(0.04),
            radius: colorScheme == .dark ? 0 : 8,
            y: colorScheme == .dark ? 0 : 2
        )
    }

    // MARK: - 2. Floating Hero Command Surface

    private var heroCommandSurface: some View {
        let useInline = !studio.isBatchMode && layout.usesInlineHeroBar
        let cornerRadius: CGFloat = useInline ? layout.scaled(18) : 16

        return VStack(alignment: .leading, spacing: 12) {
            if studio.isBatchMode {
                batchEditorArea
                batchActionBar
            } else if useInline {
                inlineSpotlightHeroBar
            } else {
                singleURLFieldArea
                compactSingleActionBar
            }
        }
        .padding(.horizontal, layout.scaled(16))
        .padding(.vertical, useInline ? layout.scaled(12) : layout.scaled(14))
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(VeloraTheme.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    isURLFocused ? VeloraTheme.accent.opacity(0.82) : VeloraTheme.hairline,
                    lineWidth: isURLFocused ? 1.5 : 1
                )
        )
        .shadow(
            color: isURLFocused
                ? VeloraTheme.accent.opacity(colorScheme == .dark ? 0.16 : 0.10)
                : (colorScheme == .dark ? .clear : Color.black.opacity(0.06)),
            radius: isURLFocused ? 12 : (colorScheme == .dark ? 0 : 14),
            y: isURLFocused ? 2 : (colorScheme == .dark ? 0 : 4)
        )
    }

    private var inlineSpotlightHeroBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(layout.font(15, weight: .medium))
                    .foregroundStyle(isURLFocused ? VeloraTheme.accentText : VeloraTheme.inkSecondary)
                    .accessibilityHidden(true)

                TextField("Paste any video or playlist URL…", text: $studio.urlInput)
                    .textFieldStyle(.plain)
                    .font(layout.font(14, design: .monospaced))
                    .foregroundStyle(VeloraTheme.inkPrimary)
                    .focused($isURLFocused)
                    .onSubmit {
                        studio.startInspectingCurrentURL(engineManager: engineManager)
                    }
                    .frame(maxWidth: .infinity, minHeight: layout.scaled(38))
                    .accessibilityLabel("Media URL")

                if !studio.urlInput.isEmpty {
                    Button {
                        clearURLInput()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(layout.font(14))
                            .foregroundStyle(VeloraTheme.inkSecondary.opacity(0.75))
                            .frame(minWidth: 26, minHeight: 26)
                            .contentShape(Rectangle())
                            .accessibilityHidden(true)
                    }
                    .buttonStyle(.plain)
                    .veloraFocusableRing(cornerRadius: 999)
                    .help("Clear URL")
                    .accessibilityLabel("Clear URL")
                }
            }

            Rectangle()
                .fill(VeloraTheme.hairline)
                .frame(width: 1, height: layout.scaled(24))
                .accessibilityHidden(true)

            inputModeSegmentedPill

            pasteHeroButton

            inspectOrCancelButton

            downloadHeroButton
        }
    }

    private var compactSingleActionBar: some View {
        HStack(spacing: 8) {
            inputModeSegmentedPill

            Spacer(minLength: 8)

            pasteHeroButton

            inspectOrCancelButton

            downloadHeroButton
        }
    }

    @ViewBuilder
    private var batchActionBar: some View {
        if layout.widthClass == .compact {
            FlowWrapLayout(alignment: .leading, spacing: 8, lineSpacing: 8) {
                inputModeSegmentedPill
                batchImportButton
                Toggle("Expand playlists", isOn: $studio.expandPlaylistsInBatch)
                    .font(.caption)
                    .foregroundStyle(VeloraTheme.inkSecondary)
                    .toggleStyle(.checkbox)
                batchCountLabel
                downloadHeroButton
            }
        } else {
            HStack(spacing: 8) {
                inputModeSegmentedPill
                batchImportButton

                Toggle("Expand playlists", isOn: $studio.expandPlaylistsInBatch)
                    .font(.caption)
                    .foregroundStyle(VeloraTheme.inkSecondary)
                    .toggleStyle(.checkbox)

                Spacer(minLength: 4)

                batchCountLabel

                downloadHeroButton
            }
        }
    }

    private var batchImportButton: some View {
        Button {
            importURLListFile()
        } label: {
            Label("Import .txt", systemImage: "doc.text")
                .font(.caption.weight(.medium))
        }
        .buttonStyle(VeloraSecondaryButtonStyle())
        .controlSize(.small)
        .accessibilityLabel("Import URLs from text or CSV file")
    }

    @ViewBuilder
    private var batchCountLabel: some View {
        let urlCount = studio.detectedBatchURLs.count
        if urlCount > 0 {
            let plCount = studio.detectedBatchPlaylistCount
            Text(plCount > 0 ? "\(urlCount) URLs · \(plCount) lists" : "\(urlCount) URL\(urlCount == 1 ? "" : "s")")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(VeloraTheme.inkSecondary)
        }
    }

    private var pasteHeroButton: some View {
        Button {
            studio.pasteFromClipboardAndInspect(engineManager: engineManager)
        } label: {
            Label("Paste", systemImage: "doc.on.clipboard")
                .font(layout.font(13, weight: .medium))
                .foregroundStyle(VeloraTheme.inkSecondary)
                .padding(.horizontal, layout.scaled(11))
                .padding(.vertical, layout.scaled(7))
                .frame(minWidth: 24, minHeight: layout.scaled(34))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .veloraFocusableRing(cornerRadius: 999)
        .help("Paste URL from clipboard and inspect (⇧⌘V)")
        .accessibilityLabel("Paste URL from clipboard and inspect")
    }

    @ViewBuilder
    private var inspectOrCancelButton: some View {
        if studio.isInspecting {
            Button {
                studio.cancelInspection()
            } label: {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Cancel")
                        .font(layout.font(13, weight: .medium))
                }
            }
            .buttonStyle(VeloraSecondaryButtonStyle())
            .accessibilityLabel("Cancel inspection")
        } else {
            Button {
                studio.startInspectingCurrentURL(engineManager: engineManager)
            } label: {
                Label("Inspect", systemImage: "magnifyingglass")
                    .font(layout.font(13, weight: .medium))
            }
            .buttonStyle(VeloraSecondaryButtonStyle(isDisabled: !studio.canDownload))
            .disabled(!studio.canDownload)
            .help("Inspect streams and metadata (⌘I)")
            .accessibilityLabel("Inspect media URL")
        }
    }

    private var downloadHeroButton: some View {
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
                        .accessibilityHidden(true)
                }
                Text(downloadButtonTitle)
            }
        }
        .buttonStyle(VeloraPrimaryButtonStyle(isDisabled: !studio.canDownload || studio.isExpandingBulk))
        .disabled(!studio.canDownload || studio.isExpandingBulk)
        .keyboardShortcut(.return, modifiers: [.command])
        .accessibilityLabel(downloadButtonTitle)
    }

    private var singleURLFieldArea: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(layout.font(15, weight: .medium))
                .foregroundStyle(isURLFocused ? VeloraTheme.accentText : VeloraTheme.inkSecondary)
                .accessibilityHidden(true)

            TextField("Paste any video or playlist URL…", text: $studio.urlInput)
                .textFieldStyle(.plain)
                .font(layout.font(14, design: .monospaced))
                .foregroundStyle(VeloraTheme.inkPrimary)
                .focused($isURLFocused)
                .onSubmit {
                    studio.startInspectingCurrentURL(engineManager: engineManager)
                }
                .accessibilityLabel("Media URL")

            if !studio.urlInput.isEmpty {
                Button {
                    clearURLInput()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(layout.font(14))
                        .foregroundStyle(VeloraTheme.inkSecondary.opacity(0.75))
                        .frame(minWidth: 26, minHeight: 26)
                        .contentShape(Rectangle())
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .veloraFocusableRing(cornerRadius: 999)
                .help("Clear URL")
                .accessibilityLabel("Clear URL")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(VeloraTheme.surfaceSubtle.opacity(colorScheme == .dark ? 0.75 : 0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(VeloraTheme.hairline, lineWidth: 1)
        )
    }

    private var batchEditorArea: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $studio.urlInput)
                    .font(layout.font(14, design: .monospaced))
                    .foregroundStyle(VeloraTheme.inkPrimary)
                    .scrollContentBackground(.hidden)
                    .focused($isURLFocused)
                    .frame(minHeight: layout.scaled(96), maxHeight: layout.scaled(168))
                    .padding(10)
                    .accessibilityLabel("Batch media URLs")

                if studio.urlInput.isEmpty {
                    Text("Paste multiple video or playlist URLs (one per line), or drop a .txt file…")
                        .font(layout.font(13, design: .monospaced))
                        .foregroundStyle(VeloraTheme.inkSecondary.opacity(0.65))
                        .padding(.horizontal, 15)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                if !studio.urlInput.isEmpty {
                    HStack {
                        Spacer()
                        Button {
                            clearURLInput()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(layout.font(14))
                                .foregroundStyle(VeloraTheme.inkSecondary.opacity(0.75))
                                .frame(minWidth: 26, minHeight: 26)
                                .contentShape(Rectangle())
                                .accessibilityHidden(true)
                        }
                        .buttonStyle(.plain)
                        .veloraFocusableRing(cornerRadius: 999)
                        .padding(6)
                        .help("Clear batch URLs")
                        .accessibilityLabel("Clear batch URLs")
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(VeloraTheme.surfaceSubtle.opacity(colorScheme == .dark ? 0.75 : 0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(VeloraTheme.hairline, lineWidth: 1)
            )
        }
    }

    private var inputModeSegmentedPill: some View {
        HStack(spacing: 2) {
            modePillButton(title: "Single", isBatch: false)
            modePillButton(title: "Batch", isBatch: true)
        }
        .padding(3)
        .background(
            Capsule()
                .fill(VeloraTheme.surfaceSubtle)
        )
        .overlay(
            Capsule()
                .stroke(VeloraTheme.hairline, lineWidth: 1)
        )
    }

    private func modePillButton(title: String, isBatch: Bool) -> some View {
        let isSelected = studio.isBatchMode == isBatch
        return Button {
            if reduceMotion {
                studio.isBatchMode = isBatch
            } else {
                withAnimation(.snappy(duration: 0.16)) {
                    studio.isBatchMode = isBatch
                }
            }
        } label: {
            Text(title)
                .font(layout.font(12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? VeloraTheme.inkPrimary : VeloraTheme.inkSecondary)
                .padding(.horizontal, layout.scaled(11))
                .padding(.vertical, 4)
                .frame(minHeight: layout.scaled(26))
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
        .accessibilityLabel("\(title) URL mode")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var bulkExpansionBanner: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(studio.bulkExpansionStatus.isEmpty ? "Expanding playlist videos…" : studio.bulkExpansionStatus)
                .font(.callout.weight(.medium))
                .foregroundStyle(VeloraTheme.inkPrimary)
            Spacer()
        }
        .veloraCard(padding: 12, cornerRadius: 12)
    }

    // MARK: - 3. Whisper Capsule Row

    private var whisperCapsuleRow: some View {
        let pillHeight = layout.scaled(30)
        return HStack(spacing: layout.scaled(8)) {
            Menu {
                ForEach(downloadManager.allPresets) { preset in
                    Button {
                        studio.applyPreset(preset)
                    } label: {
                        HStack {
                            Text(preset.name)
                            if isPresetActive(preset) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: studio.configuration.mode.systemImage)
                        .font(layout.font(11.5, weight: .semibold))
                        .foregroundStyle(VeloraTheme.accentText)
                        .accessibilityHidden(true)
                    Text(activePresetTitle)
                        .font(layout.font(12.5, weight: .semibold))
                        .foregroundStyle(VeloraTheme.inkPrimary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(layout.font(10.5, weight: .semibold))
                        .foregroundStyle(VeloraTheme.inkSecondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, layout.scaled(12))
                .padding(.vertical, 5)
                .frame(minHeight: pillHeight)
                .background(Capsule().fill(VeloraTheme.surfaceSubtle))
                .overlay(Capsule().stroke(VeloraTheme.hairline, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Choose active download preset")
            .accessibilityLabel("Active preset: \(activePresetTitle)")

            Button {
                pickOutputDirectory()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(layout.font(11.5, weight: .medium))
                        .foregroundStyle(VeloraTheme.inkSecondary)
                        .accessibilityHidden(true)
                    Text(compactFolderLabel)
                        .font(layout.font(12.5, weight: .medium))
                        .foregroundStyle(VeloraTheme.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, layout.scaled(12))
                .padding(.vertical, 5)
                .frame(minWidth: 24, maxWidth: layout.width >= 1040 ? 240 : 180, minHeight: pillHeight)
                .fixedSize(horizontal: true, vertical: false)
                .background(Capsule().fill(VeloraTheme.surfaceSubtle))
                .overlay(Capsule().stroke(VeloraTheme.hairline, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .veloraFocusableRing(cornerRadius: 999)
            .help("Choose download destination: \(studio.configuration.outputDirectoryPath)")
            .accessibilityLabel("Output folder: \(compactFolderLabel). Change folder")

            let modifiers = studio.configuration.activeModifierSummaries
            if !modifiers.isEmpty {
                if layout.widthClass == .compact {
                    VeloraBadge(
                        text: "\(modifiers.count) active",
                        color: VeloraTheme.accentText
                    )
                } else {
                    HStack(spacing: 8) {
                        ForEach(modifiers.prefix(3), id: \.self) { item in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(VeloraTheme.accent)
                                    .frame(width: 5, height: 5)
                                    .accessibilityHidden(true)
                                Text(item)
                                    .font(layout.font(11.5, weight: .medium))
                                    .foregroundStyle(VeloraTheme.inkSecondary)
                                    .lineLimit(1)
                            }
                        }
                        if modifiers.count > 3 {
                            Text("+\(modifiers.count - 3)")
                                .font(layout.font(11.5, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(VeloraTheme.inkSecondary)
                        }
                    }
                    .padding(.horizontal, 6)
                }
            }

            Spacer(minLength: 6)

            Button {
                toggleAllOptions()
            } label: {
                HStack(spacing: 5) {
                    Text("All Options")
                        .font(layout.font(12.5, weight: .medium))
                    Image(systemName: studio.isAllOptionsExpanded ? "chevron.up" : "chevron.down")
                        .font(layout.font(10.5, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(studio.isAllOptionsExpanded ? VeloraTheme.accentText : VeloraTheme.inkSecondary)
                .padding(.horizontal, layout.scaled(12))
                .padding(.vertical, 5)
                .frame(minWidth: 24, minHeight: pillHeight)
                .background(
                    Capsule()
                        .fill(studio.isAllOptionsExpanded ? VeloraTheme.accent.opacity(0.12) : VeloraTheme.surfaceSubtle)
                )
                .overlay(
                    Capsule()
                        .stroke(studio.isAllOptionsExpanded ? VeloraTheme.accent.opacity(0.28) : VeloraTheme.hairline, lineWidth: 1)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .veloraFocusableRing(cornerRadius: 999)
            .accessibilityLabel("All Download Options")
            .accessibilityValue(studio.isAllOptionsExpanded ? "Expanded" : "Collapsed")
        }
    }

    // MARK: - 4. Full-Width Symmetric 6-Preset Gallery Grid

    private var presetGalleryGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: layout.scaled(11), alignment: .top),
                count: layout.studioPresetColumnCount
            ),
            spacing: layout.scaled(11)
        ) {
            ForEach(DownloadPreset.builtInPresets) { preset in
                let isSelected = isPresetActive(preset)
                let isHovered = hoveredPresetID == preset.id
                let iconBoxSize = layout.scaled(34)

                Button {
                    studio.applyPreset(preset)
                } label: {
                    HStack(spacing: layout.scaled(11)) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isSelected ? VeloraTheme.accent : VeloraTheme.surfaceSubtle)
                            Image(systemName: preset.symbolName)
                                .font(layout.font(14, weight: .semibold))
                                .foregroundStyle(
                                    isSelected
                                        ? .white
                                        : (isHovered ? VeloraTheme.accentText : VeloraTheme.inkSecondary)
                                )
                        }
                        .frame(width: iconBoxSize, height: iconBoxSize)
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                                .font(layout.font(13.5, weight: .semibold))
                                .foregroundStyle(VeloraTheme.inkPrimary)
                                .lineLimit(1)
                            Text(preset.subtitle)
                                .font(layout.font(11.5))
                                .foregroundStyle(VeloraTheme.inkSecondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(layout.font(14))
                                .foregroundStyle(VeloraTheme.accentText)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, layout.scaled(13))
                    .padding(.vertical, layout.scaled(11))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(
                                isSelected
                                    ? VeloraTheme.accent.opacity(colorScheme == .dark ? 0.14 : 0.07)
                                    : (isHovered ? VeloraTheme.surfaceHover : VeloraTheme.surfaceElevated)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(
                                isSelected
                                    ? VeloraTheme.accent.opacity(0.65)
                                    : (isHovered ? VeloraTheme.borderStrong : VeloraTheme.hairline),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredPresetID = hovering ? preset.id : (hoveredPresetID == preset.id ? nil : hoveredPresetID)
                }
                .veloraFocusableRing(cornerRadius: 13)
                .help("\(preset.name) — \(preset.subtitle)")
                .accessibilityLabel("\(preset.name) preset, \(preset.subtitle)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    // MARK: - 5. Media Preview Slot (Loading / Error / Populated)

    @ViewBuilder
    private var mediaPreviewSlot: some View {
        if studio.isInspecting {
            MediaPreviewSkeletonCard(
                thumbnailSize: layout.thumbnailSize,
                onCancel: {
                    studio.cancelInspection()
                }
            )
            .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
        } else if let error = studio.inspectionError {
            inspectionErrorBanner(error: error)
                .transition(reduceMotion ? .identity : .opacity)
        } else if let media = studio.inspectedMedia {
            MediaPreviewCard(
                mediaInfo: media,
                selectedFormatID: studio.configuration.customFormatID,
                onOpenFormatPicker: { studio.isShowingFormatPicker = true },
                onClearFormatOverride: {
                    studio.configuration.customFormatID = nil
                    studio.customFormatIsVideoOnly = false
                },
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
            .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
        }
    }

    private func inspectionErrorBanner(error: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.body)
                    .foregroundStyle(VeloraTheme.danger)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Unable to inspect media URL")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(VeloraTheme.inkPrimary)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(VeloraTheme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 8) {
                Button("Retry") {
                    studio.startInspectingCurrentURL(engineManager: engineManager)
                }
                .buttonStyle(VeloraSecondaryButtonStyle())
                .controlSize(.small)

                Button("Try Browser Cookies") {
                    applyBrowserCookiesAndOpenNetwork()
                }
                .buttonStyle(VeloraSecondaryButtonStyle())
                .controlSize(.small)

                if !engineManager.isReadyForBasicDownloads {
                    Button("Open Engine Setup") {
                        studio.isShowingEngineSetup = true
                    }
                    .buttonStyle(VeloraSecondaryButtonStyle())
                    .controlSize(.small)
                }

                Spacer()

                Button("Dismiss") {
                    studio.inspectionError = nil
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(VeloraTheme.inkSecondary)
                .padding(.horizontal, 6)
                .frame(minWidth: 24, minHeight: 24)
                .contentShape(Rectangle())
                .veloraFocusableRing(cornerRadius: 6)
                .accessibilityLabel("Dismiss inspection error")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(VeloraTheme.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(VeloraTheme.danger.opacity(0.32), lineWidth: 1)
        )
        .shadow(
            color: colorScheme == .dark ? .clear : Color.black.opacity(0.04),
            radius: colorScheme == .dark ? 0 : 10,
            y: colorScheme == .dark ? 0 : 3
        )
    }

    // MARK: - 6. Collapsed-by-Default All Download Options

    private var allOptionsDisclosure: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleAllOptions()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: studio.isAllOptionsExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(VeloraTheme.inkSecondary)
                        .frame(width: 12)
                        .accessibilityHidden(true)

                    Text(
                        layout.widthClass == .compact
                            ? "All Download Options"
                            : "All Download Options — Quality, Subtitles, Clip, Playlist & Network"
                    )
                    .font(layout.font(13.5, weight: .medium))
                    .foregroundStyle(VeloraTheme.inkPrimary)
                    .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(allOptionsTrailingSummary)
                        .font(layout.font(12.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(VeloraTheme.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, layout.scaled(16))
                .padding(.vertical, layout.scaled(14))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .veloraFocusableRing(cornerRadius: 12)
            .accessibilityLabel("All Download Options — Quality, Subtitles, Clip, Playlist & Network")
            .accessibilityValue(studio.isAllOptionsExpanded ? "Expanded, \(allOptionsTrailingSummary)" : "Collapsed, \(allOptionsTrailingSummary)")

            if studio.isAllOptionsExpanded {
                Divider()
                    .overlay(VeloraTheme.hairline)

                ConfigurationPanelView(
                    configuration: $studio.configuration,
                    engineManager: engineManager,
                    currentURL: studio.urlInput,
                    customFormatIsVideoOnly: studio.customFormatIsVideoOnly,
                    selectedTab: $requestedConfigTab,
                    onSaveAsPreset: { studio.isShowingSavePresetSheet = true },
                    onToast: { message in
                        studio.showToast(message, kind: .success)
                    }
                )
                .padding(14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(VeloraTheme.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(VeloraTheme.hairline, lineWidth: 1)
        )
        .shadow(
            color: colorScheme == .dark ? .clear : Color.black.opacity(0.04),
            radius: colorScheme == .dark ? 0 : 10,
            y: colorScheme == .dark ? 0 : 3
        )
    }

    // MARK: - 7. Quiet Hairline Recent Activity Strip

    private var recentActivityStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent Activity")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VeloraTheme.inkSecondary)

                Spacer()

                Button("View all →") {
                    onNavigateToQueue()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(VeloraTheme.accentText)
                .padding(.horizontal, 4)
                .frame(minWidth: 24, minHeight: 24)
                .contentShape(Rectangle())
                .veloraFocusableRing(cornerRadius: 6)
                .accessibilityLabel("View all downloads in Queue")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            ForEach(Array(downloadManager.queue.prefix(3))) { task in
                Divider()
                    .overlay(VeloraTheme.hairline)

                StudioRecentTaskRow(
                    task: task,
                    onPause: { downloadManager.pause(id: task.id) },
                    onResume: { downloadManager.resume(id: task.id) },
                    onRetry: { downloadManager.retry(id: task.id) },
                    onCancel: { downloadManager.cancel(id: task.id) },
                    onReveal: { path in
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(VeloraTheme.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(VeloraTheme.hairline, lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private var downloadButtonTitle: String {
        if studio.isExpandingBulk {
            return "Expanding…"
        }
        if studio.isBatchMode {
            let count = studio.detectedBatchURLs.count
            return count > 0 ? "Queue \(count)" : "Queue All"
        }
        if let media = studio.inspectedMedia, media.isPlaylist, !media.availablePlaylistEntries.isEmpty {
            return "Queue \(media.availablePlaylistEntries.count)"
        }
        if PlaylistURLDetector.isPurePlaylistURL(studio.urlInput) {
            return "Download List"
        }
        return "Download"
    }

    private var activePresetTitle: String {
        if let matched = downloadManager.allPresets.first(where: { isPresetActive($0) }) {
            return matched.name
        }
        return studio.configuration.summaryBadge
    }

    private var compactFolderLabel: String {
        let path = studio.configuration.outputDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty { return "Downloads" }
        let expanded = (path as NSString).expandingTildeInPath
        if layout.width >= 1040 {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            if expanded == home { return "~" }
            if expanded.hasPrefix(home + "/") {
                let relative = String(expanded.dropFirst(home.count + 1))
                return "~/\(relative)"
            }
        }
        let name = URL(fileURLWithPath: expanded).lastPathComponent
        return name.isEmpty ? "Downloads" : name
    }

    private var allOptionsTrailingSummary: String {
        let modifiers = studio.configuration.activeModifierSummaries
        if modifiers.isEmpty {
            return "Default"
        }
        return modifiers.joined(separator: " · ")
    }

    private func isPresetActive(_ preset: DownloadPreset) -> Bool {
        var current = studio.configuration
        current.outputDirectoryPath = preset.configuration.outputDirectoryPath
        return current == preset.configuration
    }

    private func compactClipboardLabel(for urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else {
            return urlString
        }
        let cleanHost = host.replacingOccurrences(of: "www.", with: "")
        let path = url.path
        if path.isEmpty || path == "/" {
            return urlString
        }
        return "\(cleanHost)\(path)"
    }

    private func acceptClipboardSuggestion(_ clipURL: String) {
        studio.isBatchMode = false
        studio.urlInput = clipURL
        studio.clipboardSuggestionURL = nil
        studio.startInspectingCurrentURL(engineManager: engineManager)
    }

    private func dismissClipboardSuggestion() {
        studio.clipboardSuggestionURL = nil
    }

    private func clearURLInput() {
        studio.cancelInspection()
        studio.urlInput = ""
        studio.inspectedMedia = nil
        studio.inspectionError = nil
    }

    private func toggleAllOptions() {
        if reduceMotion {
            studio.isAllOptionsExpanded.toggle()
        } else {
            withAnimation(.snappy(duration: 0.18)) {
                studio.isAllOptionsExpanded.toggle()
            }
        }
    }

    private func applyBrowserCookiesAndOpenNetwork() {
        if studio.configuration.browserCookies == .none {
            studio.configuration.browserCookies = .safari
            studio.showToast("Enabled Safari cookies for inspection", kind: .info)
        } else if studio.configuration.browserCookies == .safari {
            studio.configuration.browserCookies = .chrome
            studio.showToast("Switched to Chrome cookies", kind: .info)
        }
        requestedConfigTab = .outputNetwork
        if !studio.isAllOptionsExpanded {
            toggleAllOptions()
        }
    }

    private func pickOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Output Folder"
        let expanded = (studio.configuration.outputDirectoryPath as NSString).expandingTildeInPath
        panel.directoryURL = URL(fileURLWithPath: expanded)

        if panel.runModal() == .OK, let selected = panel.url {
            studio.configuration.outputDirectoryPath = selected.path
        }
    }

    private func importURLListFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .commaSeparatedText]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import URLs"

        guard panel.runModal() == .OK, let fileURL = panel.url else {
            return
        }

        Task.detached(priority: .utility) {
            let outcome = Self.readURLsSafely(from: fileURL)
            await MainActor.run {
                switch outcome {
                case .urls(let extracted):
                    let existing = YTDLPCommandBuilder.extractURLs(from: studio.urlInput)
                    let merged = existing + extracted.filter { !existing.contains($0) }
                    studio.isBatchMode = true
                    studio.urlInput = merged.joined(separator: "\n")
                    studio.showToast("Imported \(extracted.count) URL\(extracted.count == 1 ? "" : "s") from \(fileURL.lastPathComponent)", kind: .success)
                case .tooLarge:
                    studio.showToast("File exceeds 1 MB limit.", kind: .warning)
                case .empty:
                    studio.showToast("No valid URLs found in \(fileURL.lastPathComponent)", kind: .warning)
                }
            }
        }
    }

    private enum SafeURLReadOutcome: Sendable {
        case urls([String])
        case tooLarge
        case empty
    }

    private nonisolated static func readURLsSafely(from fileURL: URL) -> SafeURLReadOutcome {
        let ext = fileURL.pathExtension.lowercased()
        guard ext == "txt" || ext == "csv" || ext.isEmpty else {
            return .empty
        }
        if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
           let size = values.fileSize,
           Int64(size) > maxDropFileBytes {
            return .tooLarge
        }
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return .empty
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Int(maxDropFileBytes) + 1) else {
            return .empty
        }
        if Int64(data.count) > maxDropFileBytes {
            return .tooLarge
        }
        let text = String(decoding: data, as: UTF8.self)
        let extracted = YTDLPCommandBuilder.extractURLs(from: text)
        return extracted.isEmpty ? .empty : .urls(extracted)
    }
}

// MARK: - Fine-Grained Recent Activity Row (10Hz Isolated)

private struct StudioRecentTaskRow: View {
    let task: DownloadTask
    let onPause: () -> Void
    let onResume: () -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void
    let onReveal: (String) -> Void

    @Environment(\.veloraLayout) private var layout

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(layout.font(13.5, weight: .medium))
                        .foregroundStyle(VeloraTheme.inkPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Text(statusPercentOrLabel)
                        .font(layout.font(12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(statusColor)
                }

                if task.status.isActive || task.status == .paused {
                    ProgressView(value: task.progress)
                        .progressViewStyle(.linear)
                        .tint(statusColor)
                }

                HStack(spacing: 8) {
                    Text(task.statusDetail)
                        .font(layout.font(11.5))
                        .foregroundStyle(VeloraTheme.inkSecondary)
                        .lineLimit(1)

                    if let speed = task.speedText, task.status == .downloading {
                        Text(speed)
                            .font(layout.font(11.5))
                            .monospacedDigit()
                            .foregroundStyle(VeloraTheme.info)
                    }

                    if let eta = task.etaText, task.status == .downloading {
                        Text("ETA \(eta)")
                            .font(layout.font(11.5))
                            .monospacedDigit()
                            .foregroundStyle(VeloraTheme.inkSecondary)
                    }
                }
            }

            rowActionCluster
        }
        .padding(.horizontal, layout.scaled(16))
        .padding(.vertical, layout.scaled(11))
    }

    @ViewBuilder
    private var rowActionCluster: some View {
        HStack(spacing: 4) {
            if task.status == .completed, let path = task.outputFilePath {
                iconButton(systemImage: "folder", label: "Reveal \(task.title) in Finder", action: { onReveal(path) })
            } else if task.status.isActive || task.status == .queued {
                iconButton(systemImage: "pause.fill", label: "Pause \(task.title)", action: onPause)
                iconButton(systemImage: "xmark", label: "Cancel \(task.title)", action: onCancel)
            } else if task.status == .paused {
                iconButton(systemImage: "play.fill", label: "Resume \(task.title)", action: onResume)
                iconButton(systemImage: "xmark", label: "Cancel \(task.title)", action: onCancel)
            } else if task.status == .failed || task.status == .cancelled {
                iconButton(systemImage: "arrow.clockwise", label: "Retry \(task.title)", action: onRetry)
            }
        }
    }

    private func iconButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        let size = layout.scaled(28)
        return Button(action: action) {
            Image(systemName: systemImage)
                .font(layout.font(12, weight: .semibold))
                .foregroundStyle(VeloraTheme.inkSecondary)
                .frame(width: size, height: size)
                .background(Circle().fill(VeloraTheme.surfaceSubtle))
                .overlay(Circle().stroke(VeloraTheme.hairline, lineWidth: 1))
                .contentShape(Circle())
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .frame(minWidth: size, minHeight: size)
        .veloraFocusableRing(cornerRadius: 999)
        .help(label)
        .accessibilityLabel(label)
    }

    private var statusPercentOrLabel: String {
        switch task.status {
        case .downloading, .postProcessing, .paused:
            return "\(Int((task.progress * 100).rounded()))%"
        default:
            return task.status.displayName
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .completed: VeloraTheme.success
        case .failed, .cancelled: VeloraTheme.danger
        case .paused: VeloraTheme.warning
        case .downloading, .preparing, .postProcessing: VeloraTheme.accentText
        case .queued: VeloraTheme.inkSecondary
        }
    }
}

// MARK: - Layout-Matched CLS = 0 Inspection Skeleton

private struct MediaPreviewSkeletonCard: View {
    let thumbnailSize: CGSize
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(VeloraTheme.surfaceSubtle)
                .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(VeloraTheme.hairline, lineWidth: 1)
                )
                .overlay {
                    ProgressView()
                        .controlSize(.small)
                }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(VeloraTheme.surfaceSubtle)
                        .frame(width: 68, height: 18)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(VeloraTheme.surfaceSubtle)
                        .frame(width: 48, height: 18)
                    Spacer()
                }

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(VeloraTheme.surfaceSubtle)
                    .frame(height: 16)
                    .frame(maxWidth: 340)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(VeloraTheme.surfaceSubtle)
                    .frame(width: 190, height: 12)

                HStack {
                    Text("Inspecting streams and metadata…")
                        .font(.caption)
                        .foregroundStyle(VeloraTheme.inkSecondary)

                    Spacer()

                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(VeloraSecondaryButtonStyle())
                    .controlSize(.small)
                }
                .padding(.top, 2)
            }
        }
        .veloraCard(padding: 14, cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspecting media URL")
    }
}

// MARK: - Save Preset Sheet

struct SavePresetSheet: View {
    let configuration: DownloadConfiguration
    let onSave: (String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var subtitle = ""
    @State private var selectedSymbol = "star.fill"

    private let symbols: [(id: String, label: String)] = [
        ("star.fill", "Star"),
        ("film.fill", "Film"),
        ("music.note", "Music"),
        ("4k.tv", "4K Display"),
        ("sparkles", "Sparkles"),
        ("bolt.fill", "Fast"),
        ("headphones", "Headphones"),
        ("iphone", "iPhone"),
        ("desktopcomputer", "Mac"),
        ("scissors", "Trim")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Configuration as Preset")
                .font(.title3.weight(.semibold))
                .foregroundStyle(VeloraTheme.inkPrimary)

            Form {
                TextField("Preset Name", text: $name, prompt: Text("e.g. YouTube 4K Archival"))
                    .accessibilityLabel("Preset Name")
                TextField("Description", text: $subtitle, prompt: Text(configuration.summaryBadge))
                    .accessibilityLabel("Preset Description")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Icon")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(VeloraTheme.inkSecondary)

                    FlowWrapLayout(alignment: .leading, spacing: 8, lineSpacing: 8) {
                        ForEach(symbols, id: \.id) { sym in
                            let isSelected = selectedSymbol == sym.id
                            Button {
                                selectedSymbol = sym.id
                            } label: {
                                Image(systemName: sym.id)
                                    .font(.callout)
                                    .foregroundStyle(isSelected ? VeloraTheme.accentText : VeloraTheme.inkSecondary)
                                    .frame(width: 30, height: 30)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(isSelected ? VeloraTheme.accent.opacity(0.14) : VeloraTheme.surfaceSubtle)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(isSelected ? VeloraTheme.accent : VeloraTheme.hairline, lineWidth: 1)
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .accessibilityHidden(true)
                            }
                            .buttonStyle(.plain)
                            .frame(minWidth: 30, minHeight: 30)
                            .veloraFocusableRing(cornerRadius: 8)
                            .accessibilityLabel("\(sym.label) icon")
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(VeloraSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)

                Button("Save Preset") {
                    let finalSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? configuration.summaryBadge
                        : subtitle
                    onSave(name, finalSubtitle, selectedSymbol)
                    dismiss()
                }
                .buttonStyle(VeloraPrimaryButtonStyle(isDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420, idealWidth: 460, maxWidth: 540)
        .background(VeloraTheme.ground)
    }
}
