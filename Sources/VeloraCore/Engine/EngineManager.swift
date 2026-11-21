import Foundation

/// Thread-safe helper to accumulate UTF-8 lines streamed from a `Process` pipe.
public final class ProcessLineAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    public init() {}

    public func append(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        var lines: [String] = []
        let newline = UInt8(ascii: "\n")
        let carriageReturn = UInt8(ascii: "\r")

        while let idx = buffer.firstIndex(where: { $0 == newline || $0 == carriageReturn }) {
            let slice = buffer.subdata(in: buffer.startIndex..<idx)
            buffer.removeSubrange(buffer.startIndex...idx)
            if let str = String(data: slice, encoding: .utf8), !str.isEmpty {
                lines.append(str)
            }
        }
        return lines
    }

    public func flush() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard !buffer.isEmpty else { return [] }
        defer { buffer.removeAll() }
        if let str = String(data: buffer, encoding: .utf8), !str.isEmpty {
            return [str]
        }
        return []
    }
}

public enum EngineSource: String, Sendable {
    case custom
    case appManaged
    case bundled
    case homebrew
    case system
    case missing

    public var label: String {
        switch self {
        case .custom: "Custom Path"
        case .appManaged: "Velora Managed"
        case .bundled: "Bundled"
        case .homebrew: "Homebrew"
        case .system: "System"
        case .missing: "Not Installed"
        }
    }
}

public struct BinaryStatus: Sendable, Equatable {
    public let name: String
    public let path: String?
    public let version: String?
    public let source: EngineSource

    public var isInstalled: Bool { path != nil }

    public init(name: String, path: String?, version: String?, source: EngineSource) {
        self.name = name
        self.path = path
        self.version = version
        self.source = source
    }
}

/// Discovers, validates, installs, and updates `yt-dlp` and `ffmpeg` binaries on macOS.
@MainActor
@Observable
public final class EngineManager {
    public private(set) var ytdlpStatus = BinaryStatus(name: "yt-dlp", path: nil, version: nil, source: .missing)
    public private(set) var ffmpegStatus = BinaryStatus(name: "ffmpeg", path: nil, version: nil, source: .missing)
    public private(set) var jsRuntimeStatus = BinaryStatus(name: "JS Runtime", path: nil, version: nil, source: .missing)
    public private(set) var ytdlpJSRuntimeArgument: String?
    public private(set) var homebrewPath: String?
    public private(set) var isWorking: Bool = false
    public private(set) var activityMessage: String = ""
    public private(set) var installLogs: [String] = []
    public private(set) var lastError: String?

    public var customYTDLPPath: String {
        didSet {
            UserDefaults.standard.set(customYTDLPPath, forKey: Keys.customYTDLPPath)
            Task { await refresh() }
        }
    }

    public var customFFmpegPath: String {
        didSet {
            UserDefaults.standard.set(customFFmpegPath, forKey: Keys.customFFmpegPath)
            Task { await refresh() }
        }
    }

    private enum Keys {
        static let customYTDLPPath = "velora.engine.customYTDLPPath"
        static let customFFmpegPath = "velora.engine.customFFmpegPath"
    }

    public nonisolated static var managedBinDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("Velora", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }

    public var isReadyForBasicDownloads: Bool {
        ytdlpStatus.isInstalled
    }

    public var isFullyReady: Bool {
        ytdlpStatus.isInstalled && ffmpegStatus.isInstalled
    }

    public init() {
        self.customYTDLPPath = UserDefaults.standard.string(forKey: Keys.customYTDLPPath) ?? ""
        self.customFFmpegPath = UserDefaults.standard.string(forKey: Keys.customFFmpegPath) ?? ""
    }

    public func refresh() async {
        homebrewPath = Self.locateBinary(named: "brew", customPath: nil)?.0

        let ytdlpFound = Self.locateBinary(named: "yt-dlp", customPath: customYTDLPPath)
        let ffmpegFound = Self.locateBinary(named: "ffmpeg", customPath: customFFmpegPath)
        let jsFound = Self.locateJSRuntime()

        async let ytdlpVer: String? = {
            guard let path = ytdlpFound?.0 else { return nil }
            return await Self.readCommandFirstLine(executable: path, arguments: ["--version"])
        }()

        async let ffmpegVer: String? = {
            guard let path = ffmpegFound?.0 else { return nil }
            guard let line = await Self.readCommandFirstLine(executable: path, arguments: ["-version"]) else {
                return nil
            }
            // "ffmpeg version 7.1 Copyright ..." -> "7.1"
            let tokens = line.split(separator: " ")
            if tokens.count >= 3 && tokens[0] == "ffmpeg" && tokens[1] == "version" {
                return String(tokens[2])
            }
            return line
        }()

        async let jsVer: String? = {
            guard let jsFound else { return nil }
            return await Self.readCommandFirstLine(executable: jsFound.path, arguments: ["--version"])
        }()

        ytdlpStatus = BinaryStatus(
            name: "yt-dlp",
            path: ytdlpFound?.0,
            version: await ytdlpVer,
            source: ytdlpFound?.1 ?? .missing
        )
        ffmpegStatus = BinaryStatus(
            name: "ffmpeg",
            path: ffmpegFound?.0,
            version: await ffmpegVer,
            source: ffmpegFound?.1 ?? .missing
        )
        if let jsFound {
            jsRuntimeStatus = BinaryStatus(
                name: jsFound.runtimeName,
                path: jsFound.path,
                version: await jsVer,
                source: jsFound.source
            )
            ytdlpJSRuntimeArgument = "\(jsFound.runtimeName):\(jsFound.path)"
        } else {
            jsRuntimeStatus = BinaryStatus(name: "JS Runtime", path: nil, version: nil, source: .missing)
            ytdlpJSRuntimeArgument = nil
        }
    }

    /// Builds an enriched `PATH` environment dictionary so GUI-launched `.app` child processes find Homebrew & managed binaries.
    public nonisolated static func enrichedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extraPaths = [
            managedBinDirectory.path,
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/opt/local/bin",
            "\(NSHomeDirectory())/.deno/bin",
            "\(NSHomeDirectory())/.bun/bin",
            "\(NSHomeDirectory())/.volta/bin",
            "\(NSHomeDirectory())/.local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let existing = env["PATH"]?.split(separator: ":").map(String.init) ?? []
        var merged: [String] = []
        for path in extraPaths + existing where !merged.contains(path) {
            merged.append(path)
        }
        env["PATH"] = merged.joined(separator: ":")
        return env
    }

    /// Downloads the official standalone universal `yt-dlp_macos` binary directly from GitHub Releases.
    public func installOrUpdateManagedYTDLP() async {
        guard !isWorking else { return }
        isWorking = true
        lastError = nil
        activityMessage = "Downloading official yt-dlp_macos binary…"
        installLogs.append("→ Fetching https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")

        defer {
            isWorking = false
            activityMessage = ""
        }

        do {
            let binDir = Self.managedBinDirectory
            try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

            guard let url = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos") else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)
            request.setValue("Velora/1.0", forHTTPHeaderField: "User-Agent")

            let (tempFileURL, response) = try await URLSession.shared.download(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw NSError(
                    domain: "Velora.EngineManager",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "GitHub download failed with HTTP \(http.statusCode)."]
                )
            }

            let destinationURL = binDir.appendingPathComponent("yt-dlp")
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: tempFileURL, to: destinationURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)

            // Strip any quarantine attribute so macOS runs the binary without warning.
            _ = await Self.runQuickCommand(
                executable: "/usr/bin/xattr",
                arguments: ["-dr", "com.apple.quarantine", destinationURL.path]
            )

            installLogs.append("✓ Installed yt-dlp at \(destinationURL.path)")
            await refresh()
        } catch {
            lastError = error.localizedDescription
            installLogs.append("✗ Failed to install yt-dlp: \(error.localizedDescription)")
        }
    }

    /// Installs `yt-dlp` and/or `ffmpeg` via Homebrew if installed on the user's Mac.
    public func installViaHomebrew(packages: [String]) async {
        guard !isWorking else { return }
        guard let brewPath = homebrewPath else {
            lastError = "Homebrew was not found on this Mac. Install Homebrew or download standalone yt-dlp."
            return
        }

        isWorking = true
        lastError = nil
        activityMessage = "Installing \(packages.joined(separator: ", ")) via Homebrew…"
        installLogs.append("→ Running: \(brewPath) install \(packages.joined(separator: " "))")

        defer {
            isWorking = false
            activityMessage = ""
        }

        let exitCode = await Self.streamCommand(
            executable: brewPath,
            arguments: ["install"] + packages
        ) { [weak self] line in
            Task { @MainActor [weak self] in
                self?.installLogs.append(line)
            }
        }

        if exitCode == 0 {
            installLogs.append("✓ Homebrew installation succeeded.")
            await refresh()
        } else {
            lastError = "Homebrew exited with status \(exitCode). See setup logs for details."
            installLogs.append("✗ Homebrew exited with code \(exitCode).")
        }
    }

    public func clearLogs() {
        installLogs.removeAll()
        lastError = nil
    }

    // MARK: - Discovery & Process Utilities

    private static func locateJSRuntime() -> (runtimeName: String, path: String, source: EngineSource)? {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        // yt-dlp 2026+ supports deno, bun, node, quickjs via --js-runtimes RUNTIME:PATH
        let candidates: [(runtime: String, binary: String, extraDirs: [String])] = [
            ("deno", "deno", ["\(home)/.deno/bin"]),
            ("bun", "bun", ["\(home)/.bun/bin"]),
            ("node", "node", ["\(home)/.volta/bin"]),
            ("quickjs", "qjs", [])
        ]

        for candidate in candidates {
            if let found = locateBinary(named: candidate.binary, customPath: nil) {
                return (candidate.runtime, found.0, found.1)
            }
            for dir in candidate.extraDirs {
                let fullPath = "\(dir)/\(candidate.binary)"
                if fm.isExecutableFile(atPath: fullPath) {
                    return (candidate.runtime, fullPath, .system)
                }
            }
        }
        return nil
    }

    private static func locateBinary(named name: String, customPath: String?) -> (String, EngineSource)? {
        let fm = FileManager.default

        if let customPath {
            let expanded = (customPath as NSString).expandingTildeInPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !expanded.isEmpty && fm.isExecutableFile(atPath: expanded) {
                return (expanded, .custom)
            }
        }

        let managed = managedBinDirectory.appendingPathComponent(name).path
        if fm.isExecutableFile(atPath: managed) {
            return (managed, .appManaged)
        }

        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("bin/\(name)").path
            if fm.isExecutableFile(atPath: bundled) {
                return (bundled, .bundled)
            }
        }

        let homebrewPaths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)"
        ]
        for path in homebrewPaths where fm.isExecutableFile(atPath: path) {
            return (path, .homebrew)
        }

        let systemPaths = [
            "/opt/local/bin/\(name)",
            "\(NSHomeDirectory())/.local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        for path in systemPaths where fm.isExecutableFile(atPath: path) {
            return (path, .system)
        }

        return nil
    }

    private static func readCommandFirstLine(executable: String, arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.environment = enrichedEnvironment()

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0,
                          let output = String(data: data, encoding: .utf8) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let firstLine = output
                        .split(whereSeparator: \.isNewline)
                        .first
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    continuation.resume(returning: firstLine)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func runQuickCommand(executable: String, arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus)
                } catch {
                    continuation.resume(returning: -1)
                }
            }
        }
    }

    private static func streamCommand(
        executable: String,
        arguments: [String],
        onLine: @escaping @Sendable (String) -> Void
    ) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.environment = enrichedEnvironment()

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                let accumulator = ProcessLineAccumulator()
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    for line in accumulator.append(data) {
                        onLine(line)
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()
                    pipe.fileHandleForReading.readabilityHandler = nil
                    for line in accumulator.flush() {
                        onLine(line)
                    }
                    continuation.resume(returning: process.terminationStatus)
                } catch {
                    onLine("Process failed: \(error.localizedDescription)")
                    continuation.resume(returning: -1)
                }
            }
        }
    }
}
