import SwiftUI

enum VeloraTheme {
    static let violet = Color(red: 0.49, green: 0.36, blue: 1.0)
    static let cyan = Color(red: 0.13, green: 0.83, blue: 0.93)
    static let magenta = Color(red: 0.85, green: 0.27, blue: 0.94)
    static let emerald = Color(red: 0.16, green: 0.78, blue: 0.55)
    static let amber = Color(red: 0.96, green: 0.65, blue: 0.14)

    static let brandGradient = LinearGradient(
        colors: [violet, cyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let subtleCardBorder = Color.primary.opacity(0.08)
    static let surfaceFill = Color(nsColor: .controlBackgroundColor)
}

struct VeloraCardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(VeloraTheme.surfaceFill.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(VeloraTheme.subtleCardBorder, lineWidth: 1)
            )
    }
}

extension View {
    func veloraCard(padding: CGFloat = 16) -> some View {
        modifier(VeloraCardModifier(padding: padding))
    }
}

struct VeloraBadge: View {
    let text: String
    var color: Color = VeloraTheme.violet
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(
            Capsule()
                .fill(color.opacity(0.14))
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(0.25), lineWidth: 0.5)
        )
    }
}

struct VeloraPrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(VeloraTheme.brandGradient)
                    .opacity(isDisabled ? 0.45 : (configuration.isPressed ? 0.85 : 1.0))
            )
            .shadow(color: VeloraTheme.violet.opacity(isDisabled ? 0 : 0.25), radius: 6, y: 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
