import AppKit
import Foundation
@preconcurrency import UserNotifications
import VeloraCore

public enum VeloraDeepLinkAction: Equatable, Sendable {
    case inspect(url: String)
    case download(url: String, presetQuery: String?)
}

/// Strictly parses `velora://inspect?url=...` and `velora://download?url=...&preset=...`,
/// validating `http`/`https` media URLs and ignoring all unapproved query parameters.
public enum VeloraDeepLinkParser {
    private static let maxMediaURLLength = 4096
    private static let maxPresetQueryLength = 128

    public static func parse(_ deepLinkURL: URL) -> VeloraDeepLinkAction? {
        guard deepLinkURL.scheme?.lowercased() == "velora" else {
            return nil
        }

        let hostAction = deepLinkURL.host?.lowercased()
        let pathAction = deepLinkURL.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        let action = (hostAction?.isEmpty == false ? hostAction : nil) ?? pathAction

        guard action == "inspect" || action == "download" else {
            return nil
        }

        guard let components = URLComponents(url: deepLinkURL, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }

        guard let rawMediaURL = queryItems.first(where: { $0.name.lowercased() == "url" })?.value else {
            return nil
        }

        let sanitizedURL = YTDLPCommandBuilder.sanitizeURL(rawMediaURL)
        guard !sanitizedURL.isEmpty,
              sanitizedURL.count <= maxMediaURLLength,
              YTDLPCommandBuilder.isValidMediaURL(sanitizedURL) else {
            return nil
        }

        if action == "inspect" {
            return .inspect(url: sanitizedURL)
        }

        let rawPreset = queryItems.first(where: { $0.name.lowercased() == "preset" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safePreset: String?
        if let rawPreset, !rawPreset.isEmpty, rawPreset.count <= maxPresetQueryLength {
            safePreset = rawPreset
        } else {
            safePreset = nil
        }
        return .download(url: sanitizedURL, presetQuery: safePreset)
    }
}

/// Coordinates native macOS integrations: Dock tile badge, UserNotifications, and opt-in NSPasteboard detection.
@MainActor
final class MacSystemBridge {
    static let shared = MacSystemBridge()

    private var lastSeenClipboardChangeCount: Int = -1

    private init() {}

    func updateDockBadge(activeCount: Int, pausedCount: Int) {
        _ = pausedCount
        NSApp.dockTile.badgeLabel = activeCount > 0 ? "\(activeCount)" : nil
        NSApp.dockTile.display()
    }

    func requestNotificationPermissionIfBundled() {
        guard isRunningInAppBundle else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func postCompletionNotification(title: String, succeeded: Bool, detail: String, enabled: Bool) {
        guard enabled, !NSApp.isActive, isRunningInAppBundle else { return }

        let content = UNMutableNotificationContent()
        content.title = succeeded ? "Download Completed" : "Download Failed"
        content.subtitle = title
        if !detail.isEmpty {
            content.body = detail
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "velora.download.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func detectClipboardMediaURL(currentInput: String) -> String? {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastSeenClipboardChangeCount else {
            return nil
        }
        lastSeenClipboardChangeCount = currentChangeCount

        guard let rawText = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawText.isEmpty,
            rawText.count <= 4096 else {
            return nil
        }

        let extracted = YTDLPCommandBuilder.extractURLs(from: rawText)
        guard extracted.count == 1,
              let candidate = extracted.first,
              YTDLPCommandBuilder.isValidMediaURL(candidate) else {
            return nil
        }

        let normalizedCurrent = YTDLPCommandBuilder.sanitizeURL(currentInput)
        guard candidate != normalizedCurrent else {
            return nil
        }
        return candidate
    }

    private var isRunningInAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }
}
