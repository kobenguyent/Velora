import AppKit
import SwiftUI

/// Responsive window width buckets across Split View, laptop, desktop, and ultrawide displays.
enum VeloraWidthClass: Equatable, Sendable {
    case compact     // < 780
    case regular     // 780 ..< 1180
    case wide        // 1180 ..< 1560
    case ultrawide   // >= 1560
}

/// Shared layout geometry computed once at MainWindowView root and propagated via EnvironmentValues.
struct VeloraLayoutMetrics: Equatable, Sendable {
    let windowSize: CGSize

    init(windowSize: CGSize = CGSize(width: 760, height: 600)) {
        self.windowSize = windowSize
    }

    var width: CGFloat { windowSize.width }
    var height: CGFloat { windowSize.height }

    /// Smooth proportional scale curve: 1.0x at <=760pt -> ~1.10x at 1040pt -> ~1.20x at 1440pt -> 1.28x at >=1700pt.
    var uiScale: CGFloat {
        let t = min(max((width - 760) / 940, 0), 1)
        return 1.0 + t * 0.28
    }

    /// Gentler badge scale clamped around 1.0x..1.15x so capsule pills stay sharp.
    var badgeScale: CGFloat {
        1.0 + (uiScale - 1.0) * 0.55
    }

    func scaled(_ value: CGFloat) -> CGFloat {
        (value * uiScale).rounded()
    }

    func font(_ baseSize: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: (baseSize * uiScale).rounded(), weight: weight, design: design)
    }

    var topBarHeight: CGFloat {
        scaled(50)
    }

    var contentHeight: CGFloat {
        max(0, windowSize.height - topBarHeight)
    }

    var widthClass: VeloraWidthClass {
        if width < 780 { return .compact }
        if width < 1180 { return .regular }
        if width < 1560 { return .wide }
        return .ultrawide
    }

    var horizontalPadding: CGFloat {
        switch widthClass {
        case .compact: 18
        case .regular: 32
        case .wide: 44
        case .ultrawide: 56
        }
    }

    var verticalPadding: CGFloat {
        switch widthClass {
        case .compact: 18
        case .regular: 26
        case .wide: 34
        case .ultrawide: 40
        }
    }

    func studioMaxWidth(expanded: Bool) -> CGFloat {
        let available = max(320, width - horizontalPadding * 2)
        let target = max(640, min(width * 0.78, expanded ? 1360 : 1200))
        return min(available, target)
    }

    var listMaxWidth: CGFloat {
        let available = max(320, width - horizontalPadding * 2)
        return min(available, max(640, min(width * 0.84, 1440)))
    }

    var gridMaxWidth: CGFloat {
        let available = max(320, width - horizontalPadding * 2)
        return min(available, max(640, min(width * 0.88, 1520)))
    }

    var studioPresetColumnCount: Int {
        width < 720 ? 2 : 3
    }

    var presetColumnCount: Int {
        if width < 660 { return 1 }
        if width < 1040 { return 2 }
        return 3
    }

    var usesInlineHeroBar: Bool { width >= 780 }
    var usesTwoColumnConfig: Bool { width >= 940 }
    var usesCenteredTopBar: Bool { width >= 820 }
    var showsBrandWordmark: Bool { width >= 760 }

    var thumbnailSize: CGSize {
        switch widthClass {
        case .compact: CGSize(width: 160, height: 90)
        case .regular: CGSize(width: 192, height: 108)
        case .wide: CGSize(width: 224, height: 126)
        case .ultrawide: CGSize(width: 248, height: 140)
        }
    }

    var rowThumbnailSize: CGSize {
        switch widthClass {
        case .compact: CGSize(width: 72, height: 41)
        case .regular: CGSize(width: 84, height: 47)
        case .wide, .ultrawide: CGSize(width: 96, height: 54)
        }
    }
}

private struct VeloraLayoutMetricsKey: EnvironmentKey {
    static let defaultValue = VeloraLayoutMetrics(windowSize: CGSize(width: 760, height: 600))
}

extension EnvironmentValues {
    var veloraLayout: VeloraLayoutMetrics {
        get { self[VeloraLayoutMetricsKey.self] }
        set { self[VeloraLayoutMetricsKey.self] = newValue }
    }
}

/// Multi-line wrapping layout used across chips, badges, toolbars, and action bars.
struct FlowWrapLayout: Layout {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
        let totalHeight = rows.reduce(CGFloat(0)) { partial, row in
            partial + row.height
        } + CGFloat(max(0, rows.count - 1)) * lineSpacing
        let longestRow = rows.map(\.width).max() ?? 0
        let resolvedWidth = proposal.width ?? longestRow
        return CGSize(width: resolvedWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var currentY = bounds.minY

        for row in rows {
            let startX: CGFloat
            switch alignment {
            case .center:
                startX = bounds.minX + max(0, (bounds.width - row.width) / 2)
            case .trailing:
                startX = bounds.minX + max(0, bounds.width - row.width)
            default:
                startX = bounds.minX
            }

            var currentX = startX
            for item in row.items {
                let yOffset = currentY + (row.height - item.size.height) / 2
                item.subview.place(
                    at: CGPoint(x: currentX, y: yOffset),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                currentX += item.size.width + spacing
            }
            currentY += row.height + lineSpacing
        }
    }

    private struct RowItem {
        let subview: LayoutSubview
        let size: CGSize
    }

    private struct Row {
        var items: [RowItem] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentRow = Row()

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedWidth = currentRow.items.isEmpty ? size.width : currentRow.width + spacing + size.width
            if !currentRow.items.isEmpty && proposedWidth > maxWidth {
                rows.append(currentRow)
                currentRow = Row(
                    items: [RowItem(subview: subview, size: size)],
                    width: size.width,
                    height: size.height
                )
            } else {
                currentRow.items.append(RowItem(subview: subview, size: size))
                currentRow.width = proposedWidth
                currentRow.height = max(currentRow.height, size.height)
            }
        }

        if !currentRow.items.isEmpty {
            rows.append(currentRow)
        }
        return rows
    }
}

/// Bridges native macOS hidden-titlebar window dragging and fullscreen state into SwiftUI top chrome.
struct WindowChromeBridge: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeNSView(context: Context) -> VeloraWindowDragNSView {
        let view = VeloraWindowDragNSView()
        view.onFullScreenChange = { fullScreen in
            if isFullScreen != fullScreen {
                isFullScreen = fullScreen
            }
        }
        return view
    }

    func updateNSView(_ nsView: VeloraWindowDragNSView, context: Context) {
        nsView.onFullScreenChange = { fullScreen in
            if isFullScreen != fullScreen {
                isFullScreen = fullScreen
            }
        }
    }
}

@MainActor
final class VeloraWindowDragNSView: NSView {
    var onFullScreenChange: ((Bool) -> Void)?

    override var mouseDownCanMoveWindow: Bool { true }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let oldWindow = window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didEnterFullScreenNotification, object: oldWindow)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didExitFullScreenNotification, object: oldWindow)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false

        let fullScreenNow = window.styleMask.contains(.fullScreen)
        onFullScreenChange?(fullScreenNow)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFullScreenNotification(_:)),
            name: NSWindow.didEnterFullScreenNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFullScreenNotification(_:)),
            name: NSWindow.didExitFullScreenNotification,
            object: window
        )
    }

    @objc private func handleFullScreenNotification(_ notification: Notification) {
        let fullScreenNow = window?.styleMask.contains(.fullScreen) ?? false
        onFullScreenChange?(fullScreenNow)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
