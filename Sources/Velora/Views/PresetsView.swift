import SwiftUI
import VeloraCore

struct PresetsView: View {
    let downloadManager: DownloadManager
    @Bindable var studio: StudioViewModel
    let onApplied: () -> Void

    @Environment(\.veloraLayout) private var layout
    @State private var presetPendingDelete: DownloadPreset?
    @State private var presetBeingEdited: DownloadPreset?

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 14, alignment: .top),
            count: layout.presetColumnCount
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .frame(maxWidth: layout.gridMaxWidth)
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.top, 20)
                .padding(.bottom, 14)

            Divider()
                .overlay(VeloraTheme.hairline)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    sectionBlock(title: "Built-In Presets", presets: DownloadPreset.builtInPresets)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Custom Presets")
                                .font(.headline)
                                .foregroundStyle(VeloraTheme.inkPrimary)
                            Text("\(downloadManager.customPresets.count)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(VeloraTheme.inkSecondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(VeloraTheme.surfaceSubtle, in: Capsule())
                        }

                        if downloadManager.customPresets.isEmpty {
                            ContentUnavailableView {
                                Label("No Custom Presets Yet", systemImage: "slider.horizontal.3")
                            } description: {
                                Text("Configure your preferred format, codec, subtitles, or cookies in Studio, then save it here for 1-click reuse.")
                            } actions: {
                                Button("Save Current Config as Preset") {
                                    studio.isShowingSavePresetSheet = true
                                }
                                .buttonStyle(VeloraSecondaryButtonStyle())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .veloraCard(padding: 16)
                        } else {
                            presetGrid(downloadManager.customPresets)
                        }
                    }
                }
                .frame(maxWidth: layout.gridMaxWidth)
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VeloraTheme.ground)
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
        .sheet(item: $presetBeingEdited) { preset in
            EditCustomPresetSheet(
                preset: preset,
                studioConfiguration: studio.configuration
            ) { updatedName, updatedSubtitle, updatedSymbol, updatedConfig in
                downloadManager.deleteCustomPreset(id: preset.id)
                downloadManager.saveCustomPreset(
                    name: updatedName,
                    subtitle: updatedSubtitle,
                    symbolName: updatedSymbol,
                    configuration: updatedConfig
                )
                studio.showToast("Updated preset: \(updatedName)", kind: .success)
            }
        }
        .confirmationDialog(
            "Delete custom preset \"\(presetPendingDelete?.name ?? "")\"?",
            isPresented: Binding(
                get: { presetPendingDelete != nil },
                set: { if !$0 { presetPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Preset", role: .destructive) {
                if let preset = presetPendingDelete {
                    downloadManager.deleteCustomPreset(id: preset.id)
                    studio.showToast("Deleted preset: \(preset.name)", kind: .info)
                }
                presetPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                presetPendingDelete = nil
            }
        } message: {
            Text("This custom preset will be permanently removed.")
        }
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Configuration Presets")
                    .font(layout.font(20, weight: .semibold))
                    .foregroundStyle(VeloraTheme.inkPrimary)
                Text("Instant profiles for cinema 4K, Apple devices, universal MP4, and lossless audio.")
                    .font(layout.font(12.5))
                    .foregroundStyle(VeloraTheme.inkSecondary)
            }

            Spacer()

            Button {
                studio.isShowingSavePresetSheet = true
            } label: {
                Label("Save Current Config", systemImage: "plus")
            }
            .buttonStyle(VeloraPrimaryButtonStyle())
        }
    }

    private func sectionBlock(title: String, presets: [DownloadPreset]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(layout.font(15, weight: .semibold))
                .foregroundStyle(VeloraTheme.inkPrimary)

            presetGrid(presets)
        }
    }

    private func presetGrid(_ presets: [DownloadPreset]) -> some View {
        LazyVGrid(columns: gridColumns, spacing: 14) {
            ForEach(presets) { preset in
                let isActive = isPresetActive(preset)
                presetCard(preset, isActive: isActive)
            }
        }
    }

    private func presetCard(_ preset: DownloadPreset, isActive: Bool) -> some View {
        let iconBoxSize = layout.scaled(38)
        let actionBtnSize = layout.scaled(28)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: preset.symbolName)
                    .font(layout.font(15, weight: .semibold))
                    .foregroundStyle(isActive ? .white : VeloraTheme.accentText)
                    .frame(width: iconBoxSize, height: iconBoxSize)
                    .background(
                        isActive ? VeloraTheme.accent : VeloraTheme.accent.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(preset.name)
                            .font(layout.font(14.5, weight: .semibold))
                            .foregroundStyle(VeloraTheme.inkPrimary)
                            .lineLimit(1)
                        if isActive {
                            VeloraBadge(text: "Active", color: VeloraTheme.accentText, icon: "checkmark.circle.fill")
                        }
                    }
                    Text(preset.subtitle)
                        .font(layout.font(12))
                        .foregroundStyle(VeloraTheme.inkSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                VeloraBadge(text: preset.configuration.summaryBadge, color: VeloraTheme.accentText)
                if preset.configuration.subtitleMode != .off {
                    VeloraBadge(text: "Subs", color: VeloraTheme.info)
                }
                if preset.configuration.embedChapters {
                    VeloraBadge(text: "Chapters", color: VeloraTheme.inkSecondary)
                }
                if preset.configuration.sponsorBlock != .off {
                    VeloraBadge(text: "SponsorBlock", color: VeloraTheme.success)
                }
            }

            Spacer(minLength: 2)

            HStack(spacing: 6) {
                if isActive {
                    Button("Applied in Studio") {
                        studio.applyPreset(preset)
                        onApplied()
                    }
                    .buttonStyle(VeloraSecondaryButtonStyle())
                    .controlSize(.small)
                    .accessibilityLabel("\(preset.name) applied in Studio")
                    .accessibilityAddTraits(.isSelected)
                } else {
                    Button("Apply in Studio") {
                        studio.applyPreset(preset)
                        onApplied()
                    }
                    .buttonStyle(VeloraPrimaryButtonStyle())
                    .controlSize(.small)
                    .accessibilityLabel("Apply \(preset.name) preset in Studio")
                }

                Spacer()

                Button {
                    let duplicateName = "\(preset.name) Copy"
                    downloadManager.saveCustomPreset(
                        name: duplicateName,
                        subtitle: preset.subtitle,
                        symbolName: preset.symbolName,
                        configuration: preset.configuration
                    )
                    studio.showToast("Duplicated preset as \"\(duplicateName)\"", kind: .success)
                } label: {
                    Image(systemName: "plus.square.on.square")
                        .font(layout.font(12, weight: .medium))
                        .foregroundStyle(VeloraTheme.inkPrimary)
                        .frame(width: actionBtnSize, height: actionBtnSize)
                        .background(VeloraTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(VeloraTheme.hairline, lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .frame(minWidth: actionBtnSize, minHeight: actionBtnSize)
                .veloraFocusableRing(cornerRadius: 7)
                .accessibilityLabel("Duplicate preset \(preset.name)")
                .help("Duplicate as custom preset")

                if !preset.isBuiltIn {
                    Button {
                        presetBeingEdited = preset
                    } label: {
                        Image(systemName: "pencil")
                            .font(layout.font(12, weight: .medium))
                            .foregroundStyle(VeloraTheme.inkPrimary)
                            .frame(width: actionBtnSize, height: actionBtnSize)
                            .background(VeloraTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(VeloraTheme.hairline, lineWidth: 1)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .accessibilityHidden(true)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: actionBtnSize, minHeight: actionBtnSize)
                    .veloraFocusableRing(cornerRadius: 7)
                    .accessibilityLabel("Edit custom preset \(preset.name)")
                    .help("Edit custom preset")

                    Button(role: .destructive) {
                        presetPendingDelete = preset
                    } label: {
                        Image(systemName: "trash")
                            .font(layout.font(12, weight: .medium))
                            .foregroundStyle(VeloraTheme.danger)
                            .frame(width: actionBtnSize, height: actionBtnSize)
                            .background(VeloraTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(VeloraTheme.hairline, lineWidth: 1)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .accessibilityHidden(true)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: actionBtnSize, minHeight: actionBtnSize)
                    .veloraFocusableRing(cornerRadius: 7)
                    .accessibilityLabel("Delete custom preset \(preset.name)")
                    .help("Delete custom preset")
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .veloraCard(padding: layout.scaled(16), cornerRadius: 14)
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(VeloraTheme.accent, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
    }

    private func isPresetActive(_ preset: DownloadPreset) -> Bool {
        var lhs = preset.configuration
        var rhs = studio.configuration
        lhs.outputDirectoryPath = ""
        rhs.outputDirectoryPath = ""
        return lhs == rhs
    }
}

private struct EditCustomPresetSheet: View {
    let preset: DownloadPreset
    let studioConfiguration: DownloadConfiguration
    let onSave: (String, String, String, DownloadConfiguration) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var subtitle: String
    @State private var selectedSymbol: String
    @State private var replaceWithCurrentStudioConfig = false

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

    init(
        preset: DownloadPreset,
        studioConfiguration: DownloadConfiguration,
        onSave: @escaping (String, String, String, DownloadConfiguration) -> Void
    ) {
        self.preset = preset
        self.studioConfiguration = studioConfiguration
        self.onSave = onSave
        _name = State(initialValue: preset.name)
        _subtitle = State(initialValue: preset.subtitle)
        _selectedSymbol = State(initialValue: preset.symbolName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Custom Preset")
                .font(.title3.weight(.semibold))
                .foregroundStyle(VeloraTheme.inkPrimary)

            Form {
                TextField("Preset Name", text: $name)
                    .accessibilityLabel("Preset Name")
                TextField("Subtitle", text: $subtitle)
                    .accessibilityLabel("Preset Subtitle")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Icon")
                        .font(.caption)
                        .foregroundStyle(VeloraTheme.inkSecondary)

                    FlowWrapLayout(alignment: .leading, spacing: 8, lineSpacing: 8) {
                        ForEach(symbols, id: \.id) { sym in
                            let isSelected = selectedSymbol == sym.id
                            Button {
                                selectedSymbol = sym.id
                            } label: {
                                Image(systemName: sym.id)
                                    .foregroundStyle(isSelected ? VeloraTheme.accentText : VeloraTheme.inkPrimary)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(isSelected ? VeloraTheme.accent.opacity(0.14) : VeloraTheme.surfaceSubtle)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(isSelected ? VeloraTheme.accent : VeloraTheme.hairline, lineWidth: 1)
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    .accessibilityHidden(true)
                            }
                            .buttonStyle(.plain)
                            .frame(minWidth: 28, minHeight: 28)
                            .veloraFocusableRing(cornerRadius: 7)
                            .accessibilityLabel("\(sym.label) icon")
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }

                Toggle("Update preset profile to match current Studio settings", isOn: $replaceWithCurrentStudioConfig)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Changes") {
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let targetConfig = replaceWithCurrentStudioConfig ? studioConfiguration : preset.configuration
                    let trimmedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalSubtitle = trimmedSubtitle.isEmpty ? targetConfig.summaryBadge : trimmedSubtitle
                    onSave(trimmedName, finalSubtitle, selectedSymbol, targetConfig)
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
