import SwiftUI
import VeloraCore

struct PresetsView: View {
    let downloadManager: DownloadManager
    @Bindable var studio: StudioViewModel
    let onApplied: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 270, maximum: 360), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Configuration Presets")
                        .font(.title2.weight(.bold))
                    Text("Instant profiles for cinema 4K, Apple devices, universal MP4, and lossless audio.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    studio.isShowingSavePresetSheet = true
                } label: {
                    Label("Save Current Config as Preset", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(VeloraTheme.violet)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sectionBlock(title: "Built-In Presets", presets: DownloadPreset.builtInPresets)

                    if !downloadManager.customPresets.isEmpty {
                        sectionBlock(title: "Your Custom Presets", presets: downloadManager.customPresets)
                    }
                }
                .padding(22)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
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

    private func sectionBlock(title: String, presets: [DownloadPreset]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(presets) { preset in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: preset.symbolName)
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(VeloraTheme.brandGradient, in: RoundedRectangle(cornerRadius: 9))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(.headline)
                                Text(preset.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }

                        HStack(spacing: 6) {
                            VeloraBadge(text: preset.configuration.summaryBadge, color: VeloraTheme.violet)
                            if preset.configuration.subtitleMode != .off {
                                VeloraBadge(text: "Subs", color: VeloraTheme.cyan)
                            }
                            if preset.configuration.embedChapters {
                                VeloraBadge(text: "Chapters", color: .secondary)
                            }
                        }

                        Spacer(minLength: 2)

                        HStack {
                            Button("Apply in Studio") {
                                studio.applyPreset(preset)
                                onApplied()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(VeloraTheme.violet)
                            .controlSize(.small)

                            Spacer()

                            if !preset.isBuiltIn {
                                Button(role: .destructive) {
                                    downloadManager.deleteCustomPreset(id: preset.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Delete custom preset")
                            }
                        }
                    }
                    .veloraCard(padding: 14)
                }
            }
        }
    }
}
