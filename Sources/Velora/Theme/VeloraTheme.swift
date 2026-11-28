import AppKit
import SwiftUI

/// Adaptive semantic design tokens for Velora (`M2 · Apple Gallery Minimalist Cobalt`).
enum VeloraTheme {
    // MARK: - Canvas & Surfaces

    /// Root canvas background: Light `#F9FAFC` / Dark `#0E1014`.
    static let ground = adaptiveColor(light: 0xF9FAFC, dark: 0x0E1014)

    /// Elevated card, command bar, and modal surface: Light `#FFFFFF` / Dark `#161920`.
    static let surfaceElevated = adaptiveColor(light: 0xFFFFFF, dark: 0x161920)

    /// Subtle surface for segmented pills, preset chips, code blocks, and skeletons: Light `#F0F2F6` / Dark `#1D212B`.
    static let surfaceSubtle = adaptiveColor(light: 0xF0F2F6, dark: 0x1D212B)

    /// Hover surface for interactive rows and chips: Light `#E6E9F0` / Dark `#232834`.
    static let surfaceHover = adaptiveColor(light: 0xE6E9F0, dark: 0x232834)

    // MARK: - Borders

    /// Hairline divider/border: Light `rgba(15,23,42,0.07)` / Dark `rgba(255,255,255,0.06)`.
    static let hairline = adaptiveColor(
        light: 0x0F172A, lightAlpha: 0.07,
        dark: 0xFFFFFF, darkAlpha: 0.06
    )

    /// Strong border for focused/active inputs and secondary controls: Light `rgba(15,23,42,0.15)` / Dark `rgba(255,255,255,0.14)`.
    static let borderStrong = adaptiveColor(
        light: 0x0F172A, lightAlpha: 0.15,
        dark: 0xFFFFFF, darkAlpha: 0.14
    )

    // MARK: - Typography Ink

    /// Primary ink: Light `#0F172A` / Dark `#F4F6FA`.
    static let inkPrimary = adaptiveColor(light: 0x0F172A, dark: 0xF4F6FA)

    /// Secondary ink: Light `#64748B` / Dark `#8B95A7`.
    static let inkSecondary = adaptiveColor(light: 0x64748B, dark: 0x8B95A7)

    // MARK: - Cobalt Accent & Semantic Status

    /// Primary Cobalt brand accent fill (Download pill & root `.tint`): Light `#3B49DF` / Dark `#5B6CFF`.
    static let accent = adaptiveColor(light: 0x3B49DF, dark: 0x5B6CFF)

    /// High-contrast Cobalt text/badge ink: Light `#313ECB` / Dark `#8C98FF`.
    static let accentText = adaptiveColor(light: 0x313ECB, dark: 0x8C98FF)

    /// Verified/completed semantic green: Light `#0E7A4E` / Dark `#34D399`.
    static let success = adaptiveColor(light: 0x0E7A4E, dark: 0x34D399)

    /// Warning/paused semantic amber: Light `#B45309` / Dark `#FBBF24`.
    static let warning = adaptiveColor(light: 0xB45309, dark: 0xFBBF24)

    /// Error/destructive semantic red: Light `#C81E1E` / Dark `#F87171`.
    static let danger = adaptiveColor(light: 0xC81E1E, dark: 0xF87171)

    /// Telemetry/info semantic blue: Light `#0369A1` / Dark `#38BDF8`.
    static let info = adaptiveColor(light: 0x0369A1, dark: 0x38BDF8)

    // MARK: - Legacy Compatibility Aliases (Semantic)

    static let subtleCardBorder = hairline
    static let surfaceFill = surfaceElevated
    static let emerald = success
    static let amber = warning

    // MARK: - Dynamic Color Helper

    private static func adaptiveColor(
        light: UInt32,
        lightAlpha: CGFloat = 1.0,
        dark: UInt32,
        darkAlpha: CGFloat = 1.0
    ) -> Color {
        let dynamic = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            let alpha = isDark ? darkAlpha : lightAlpha
            return nsColor(hex: hex, alpha: alpha)
        }
        return Color(nsColor: dynamic)
    }

    private static func nsColor(hex: UInt32, alpha: CGFloat) -> NSColor {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}

// MARK: - Surface Card Modifier

struct VeloraSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(VeloraTheme.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(VeloraTheme.hairline, lineWidth: 1)
            )
            .shadow(
                color: colorScheme == .dark ? .clear : Color.black.opacity(0.05),
                radius: colorScheme == .dark ? 0 : 12,
                y: colorScheme == .dark ? 0 : 4
            )
    }
}

extension View {
    func veloraCard(padding: CGFloat = 16, cornerRadius: CGFloat = 14) -> some View {
        modifier(VeloraSurfaceModifier(padding: padding, cornerRadius: cornerRadius))
    }

    func veloraFocusRing(isFocused: Bool, cornerRadius: CGFloat = 10, inset: CGFloat = -2) -> some View {
        modifier(VeloraFocusRingModifier(isFocused: isFocused, cornerRadius: cornerRadius, inset: inset))
    }

    func veloraFocusableRing(cornerRadius: CGFloat = 10, inset: CGFloat = -2) -> some View {
        modifier(VeloraKeyboardFocusRingModifier(cornerRadius: cornerRadius, inset: inset))
    }
}

// MARK: - Focus Ring Modifiers (:focus-visible)

struct VeloraFocusRingModifier: ViewModifier {
    var isFocused: Bool
    var cornerRadius: CGFloat = 10
    var inset: CGFloat = -2

    func body(content: Content) -> some View {
        content.overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(VeloraTheme.accent, lineWidth: 2)
                    .padding(inset)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct VeloraKeyboardFocusRingModifier: ViewModifier {
    var cornerRadius: CGFloat = 10
    var inset: CGFloat = -2
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .veloraFocusRing(isFocused: isFocused, cornerRadius: cornerRadius, inset: inset)
    }
}

// MARK: - High-Contrast Capsule Badge

struct VeloraBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.veloraLayout) private var layout
    let text: String
    var color: Color = VeloraTheme.accentText
    var icon: String? = nil

    var body: some View {
        let fontSize = (10.5 * layout.badgeScale).rounded()
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: fontSize, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.system(size: fontSize, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, (8 * layout.badgeScale).rounded())
        .padding(.vertical, (3.5 * layout.badgeScale).rounded())
        .foregroundStyle(color)
        .background(
            Capsule()
                // Light mode uses a whisper tint so >= 4.5:1 ink contrast holds on all semantic hues.
                .fill(color.opacity(colorScheme == .dark ? 0.14 : 0.06))
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(colorScheme == .dark ? 0.26 : 0.22), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Button Styles

struct VeloraPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.veloraLayout) private var layout
    @Environment(\.controlSize) private var controlSize
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let disabled = isDisabled || !isEnabled
        let isSmall = controlSize == .small || controlSize == .mini
        configuration.label
            .font(isSmall ? .system(size: 12.5, weight: .semibold) : layout.font(13.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, isSmall ? 12 : layout.scaled(18))
            .padding(.vertical, isSmall ? 5 : layout.scaled(8))
            .frame(minHeight: isSmall ? 28 : layout.scaled(36))
            .background(
                Capsule()
                    .fill(VeloraTheme.accent)
                    .opacity(disabled ? 0.45 : (configuration.isPressed ? 0.86 : 1.0))
            )
            .overlay {
                if isFocused {
                    Capsule()
                        .strokeBorder(VeloraTheme.inkPrimary.opacity(0.9), lineWidth: 2)
                        .padding(-2)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: VeloraTheme.accent.opacity(disabled ? 0 : 0.18), radius: 6, y: 2)
            .scaleEffect(reduceMotion || disabled ? 1.0 : (configuration.isPressed ? 0.98 : 1.0))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct VeloraSecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.veloraLayout) private var layout
    @Environment(\.controlSize) private var controlSize
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let disabled = isDisabled || !isEnabled
        let isSmall = controlSize == .small || controlSize == .mini
        configuration.label
            .font(isSmall ? .system(size: 12.5, weight: .medium) : layout.font(13, weight: .medium))
            .foregroundStyle(VeloraTheme.inkPrimary.opacity(disabled ? 0.45 : 1.0))
            .padding(.horizontal, isSmall ? 11 : layout.scaled(15))
            .padding(.vertical, isSmall ? 5 : layout.scaled(7))
            .frame(minHeight: isSmall ? 28 : layout.scaled(34))
            .background(
                Capsule()
                    .fill(configuration.isPressed && !disabled ? VeloraTheme.surfaceHover : VeloraTheme.surfaceSubtle)
            )
            .overlay(
                Capsule()
                    .stroke(VeloraTheme.borderStrong.opacity(disabled ? 0.5 : 1.0), lineWidth: 1)
            )
            .overlay {
                if isFocused {
                    Capsule()
                        .strokeBorder(VeloraTheme.accent, lineWidth: 2)
                        .padding(-2)
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(reduceMotion || disabled ? 1.0 : (configuration.isPressed ? 0.98 : 1.0))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
