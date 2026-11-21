import AppKit
import CryptoKit
import Foundation

public enum AppUpdateInstallError: LocalizedError, Sendable {
    case checksumMismatch(expected: String, actual: String)
    case extractionFailed(String)
    case appBundleNotFound
    case bundleIdentifierMismatch(expected: String, actual: String)
    case invalidAppBundle(String)
    case notRunningFromAppBundle(stagedAppPath: String)
    case failedToLaunchUpdater(String)

    public var errorDescription: String? {
        switch self {
        case let .checksumMismatch(expected, actual):
            "Downloaded update failed SHA-256 verification (expected \(expected.prefix(12))…, got \(actual.prefix(12))…)."
        case .extractionFailed(let details):
            "Could not extract update archive: \(details)"
        case .appBundleNotFound:
            "No Velora.app bundle was found inside the downloaded release archive."
        case let .bundleIdentifierMismatch(expected, actual):
            "Update bundle identifier mismatch (expected \(expected), found \(actual))."
        case .invalidAppBundle(let details):
            "Downloaded app bundle is invalid: \(details)"
        case .notRunningFromAppBundle(let stagedPath):
            "Velora is running as a development binary rather than an installed .app bundle. The downloaded update has been extracted to: \(stagedPath)"
        case .failedToLaunchUpdater(let details):
            "Could not launch the external updater helper: \(details)"
        }
    }
}

/// Handles SHA-256 verification, archive extraction, `.app` bundle validation,
/// and detached replace-and-relaunch after closing the running app.
public enum AppUpdateInstaller {

    public static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Extracts a downloaded `.zip` via `ditto`, locates & validates the `.app` bundle, and strips quarantine.
    public static func extractAndValidate(
        zipURL: URL,
        stagingDirectory: URL,
        expectedBundleIdentifier: String?
    ) throws -> URL {
        let extractedDir = stagingDirectory.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractedDir, withIntermediateDirectories: true)

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zipURL.path, extractedDir.path]
        let stderr = Pipe()
        ditto.standardError = stderr
        ditto.standardOutput = Pipe()

        try ditto.run()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        ditto.waitUntilExit()

        guard ditto.terminationStatus == 0 else {
            let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "ditto failed"
            throw AppUpdateInstallError.extractionFailed(errText)
        }

        guard let appBundleURL = locateAppBundle(inside: extractedDir) else {
            throw AppUpdateInstallError.appBundleNotFound
        }

        try validateAppBundle(at: appBundleURL, expectedBundleIdentifier: expectedBundleIdentifier)

        // Strip com.apple.quarantine so Gatekeeper does not block relaunching unsigned/ad-hoc builds.
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", appBundleURL.path]
        xattr.standardOutput = Pipe()
        xattr.standardError = Pipe()
        try? xattr.run()
        xattr.waitUntilExit()

        return appBundleURL
    }

    public static func locateAppBundle(inside directory: URL) -> URL? {
        let fm = FileManager.default
        guard let topLevel = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        if let direct = topLevel.first(where: { $0.pathExtension.lowercased() == "app" }) {
            return direct
        }

        // Check one directory level deeper (in case archive contains a wrapper folder)
        for item in topLevel {
            guard let children = try? fm.contentsOfDirectory(
                at: item,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            if let nested = children.first(where: { $0.pathExtension.lowercased() == "app" }) {
                return nested
            }
        }
        return nil
    }

    public static func validateAppBundle(at appURL: URL, expectedBundleIdentifier: String?) throws {
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let plistData = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            throw AppUpdateInstallError.invalidAppBundle("Missing or unreadable Contents/Info.plist.")
        }

        guard let bundleID = plist["CFBundleIdentifier"] as? String, !bundleID.isEmpty else {
            throw AppUpdateInstallError.invalidAppBundle("Missing CFBundleIdentifier in Info.plist.")
        }

        if let expectedBundleIdentifier,
           !expectedBundleIdentifier.isEmpty,
           bundleID != expectedBundleIdentifier {
            throw AppUpdateInstallError.bundleIdentifierMismatch(expected: expectedBundleIdentifier, actual: bundleID)
        }

        guard let executableName = plist["CFBundleExecutable"] as? String, !executableName.isEmpty else {
            throw AppUpdateInstallError.invalidAppBundle("Missing CFBundleExecutable in Info.plist.")
        }

        let executableURL = appURL.appendingPathComponent("Contents/MacOS/\(executableName)")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw AppUpdateInstallError.invalidAppBundle("Executable \(executableName) is missing or not executable.")
        }
    }

    /// Generates an atomic, self-deleting POSIX shell script that waits for the current app to exit,
    /// swaps the `.app` bundle with rollback protection, strips quarantine, and relaunches the new version.
    public static func buildUpdaterScript(
        oldPID: Int32,
        targetAppPath: String,
        stagedAppPath: String,
        stagingDirectoryPath: String,
        logFilePath: String
    ) -> String {
        let qTarget = shellSingleQuote(targetAppPath)
        let qStaged = shellSingleQuote(stagedAppPath)
        let qStaging = shellSingleQuote(stagingDirectoryPath)
        let qLog = shellSingleQuote(logFilePath)
        let parentDir = URL(fileURLWithPath: targetAppPath).deletingLastPathComponent().path
        let qParent = shellSingleQuote(parentDir)

        return """
        #!/bin/sh
        set -u

        OLD_PID=\(oldPID)
        TARGET_APP=\(qTarget)
        TARGET_DIR=\(qParent)
        STAGED_APP=\(qStaged)
        STAGING_DIR=\(qStaging)
        BACKUP_APP="${TARGET_APP}.velora-backup"
        LOG_FILE=\(qLog)

        mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
        exec >>"$LOG_FILE" 2>&1

        echo "========================================"
        echo "[Velora Updater] Starting update at $(date)"
        echo "[Velora Updater] Waiting for PID $OLD_PID to close..."

        # 1. Wait cleanly for current Velora process to terminate (up to 15 seconds)
        ATTEMPTS=0
        while kill -0 "$OLD_PID" 2>/dev/null; do
            ATTEMPTS=$((ATTEMPTS + 1))
            if [ "$ATTEMPTS" -ge 60 ]; then
                echo "[Velora Updater] Process $OLD_PID still running; sending SIGTERM."
                kill -TERM "$OLD_PID" 2>/dev/null || true
                sleep 1
                break
            fi
            sleep 0.25
        done

        echo "[Velora Updater] Current app closed. Swapping bundle at $TARGET_APP"

        swap_direct() {
            rm -rf "$BACKUP_APP"
            if [ -e "$TARGET_APP" ]; then
                mv "$TARGET_APP" "$BACKUP_APP" || return 1
            fi
            if /usr/bin/ditto "$STAGED_APP" "$TARGET_APP" && [ -d "$TARGET_APP/Contents/MacOS" ]; then
                /usr/bin/xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
                touch "$TARGET_APP" 2>/dev/null || true
                rm -rf "$BACKUP_APP"
                return 0
            else
                echo "[Velora Updater] Copy failed; rolling back previous app bundle."
                rm -rf "$TARGET_APP"
                if [ -e "$BACKUP_APP" ]; then
                    mv "$BACKUP_APP" "$TARGET_APP" || true
                fi
                return 1
            fi
        }

        if [ "${1:-}" = "--swap-only" ]; then
            swap_direct
            exit $?
        fi

        if [ -w "$TARGET_DIR" ] && { [ ! -e "$TARGET_APP" ] || [ -w "$TARGET_APP" ]; }; then
            if ! swap_direct; then
                echo "[Velora Updater] Direct update failed."
                exit 1
            fi
        else
            echo "[Velora Updater] Elevated permissions required for $TARGET_DIR; prompting via macOS authorization."
            export VELORA_UPDATER_SCRIPT="$0"
            /usr/bin/osascript -e 'do shell script "/bin/sh " & quoted form of (system attribute "VELORA_UPDATER_SCRIPT") & " --swap-only" with administrator privileges'
            if [ $? -ne 0 ] || [ ! -d "$TARGET_APP/Contents/MacOS" ]; then
                echo "[Velora Updater] Elevated update cancelled or failed."
                exit 1
            fi
        fi

        echo "[Velora Updater] Update installed successfully. Relaunching Velora..."
        /usr/bin/open -n "$TARGET_APP"

        # Clean up staging workspace and self-delete
        rm -rf "$STAGING_DIR" 2>/dev/null || true
        rm -f "$0" 2>/dev/null || true
        echo "[Velora Updater] Finished cleanly at $(date)"
        """
    }

    /// Spawns the detached updater helper and immediately terminates the running Velora app so it can be replaced.
    @MainActor
    public static func installAndRelaunch(staged: StagedUpdate) throws {
        let currentBundleURL = Bundle.main.bundleURL
        guard currentBundleURL.pathExtension.lowercased() == "app" else {
            throw AppUpdateInstallError.notRunningFromAppBundle(stagedAppPath: staged.stagedAppURL.path)
        }

        let logsDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Logs/Velora", isDirectory: true)
        let logFile = logsDir.appendingPathComponent("updater.log")

        let scriptContents = buildUpdaterScript(
            oldPID: ProcessInfo.processInfo.processIdentifier,
            targetAppPath: currentBundleURL.path,
            stagedAppPath: staged.stagedAppURL.path,
            stagingDirectoryPath: staged.stagingDirectoryURL.path,
            logFilePath: logFile.path
        )

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("velora-updater-\(UUID().uuidString).sh")

        do {
            try scriptContents.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        } catch {
            throw AppUpdateInstallError.failedToLaunchUpdater(error.localizedDescription)
        }

        // Launch detached via `nohup ... &` so it survives NSApp.terminate(nil).
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
        launcher.arguments = ["-c", "nohup /bin/sh \(shellSingleQuote(scriptURL.path)) >/dev/null 2>&1 &"]
        launcher.standardInput = FileHandle.nullDevice
        launcher.standardOutput = FileHandle.nullDevice
        launcher.standardError = FileHandle.nullDevice

        do {
            try launcher.run()
            launcher.waitUntilExit()
            guard launcher.terminationStatus == 0 else {
                throw AppUpdateInstallError.failedToLaunchUpdater("Launcher exited with code \(launcher.terminationStatus).")
            }
        } catch let error as AppUpdateInstallError {
            throw error
        } catch {
            throw AppUpdateInstallError.failedToLaunchUpdater(error.localizedDescription)
        }

        // Close the current app cleanly so the detached updater can swap the bundle and relaunch.
        NSApplication.shared.terminate(nil)
    }

    public static func shellSingleQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
