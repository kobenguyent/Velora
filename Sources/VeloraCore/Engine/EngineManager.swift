import Foundation

/// Thread-safe helper to accumulate UTF-8 lines streamed from a `Process` pipe with bounded line size.
public final class ProcessLineAccumulator: @unchecked Sendable {
    public static let maxLineBufferBytes = 256 * 1024

    private let lock = NSLock()
    private var buffer = Data()
    private var isTruncatingOversizedLine = false

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
            if isTruncatingOversizedLine {
                isTruncatingOversizedLine = false
                continue
            }
            let capped = slice.count > Self.maxLineBufferBytes ? slice.prefix(Self.maxLineBufferBytes) : slice[...]
            let str = String(decoding: capped, as: UTF8.self)
            if !str.isEmpty {
                lines.append(str)
            }
        }

        if isTruncatingOversizedLine {
            buffer.removeAll()
        } else if buffer.count > Self.maxLineBufferBytes {
            let capped = buffer.prefix(Self.maxLineBufferBytes)
            let str = String(decoding: capped, as: UTF8.self)
            if !str.isEmpty {
                lines.append(str)
            }
            buffer.removeAll()
            isTruncatingOversizedLine = true
        }
        return lines
    }

    public func flush() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        defer {
            buffer.removeAll()
            isTruncatingOversizedLine = false
        }
        guard !isTruncatingOversizedLine, !buffer.isEmpty else { return [] }
        let capped = buffer.count > Self.maxLineBufferBytes ? buffer.prefix(Self.maxLineBufferBytes) : buffer[...]
        let str = String(decoding: capped, as: UTF8.self)
        return str.isEmpty ? [] : [str]
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

public enum EngineUpdateState: Sendable, Equatable {
    case unknown
    case checking
    case notInstalled(latest: String?)
    case upToDate(latest: String)
    case updateAvailable(installed: String, latest: String)

    public var needsUpdate: Bool {
        if case .updateAvailable = self { return true }
        return false
    }

    public var isUpToDate: Bool {
        if case .upToDate = self { return true }
        return false
    }

    public var latestVersion: String? {
        switch self {
        case .unknown, .checking:
            return nil
        case .notInstalled(let latest):
            return latest
        case .upToDate(let latest):
            return latest
        case .updateAvailable(_, let latest):
            return latest
        }
    }
}

/// Discovers, validates, installs, and updates `yt-dlp` and `ffmpeg` binaries on macOS.
@MainActor
@Observable
public final class EngineManager {
    public private(set) var ytdlpStatus = BinaryStatus(name: "yt-dlp", path: nil, version: nil, source: .missing)
    public private(set) var ffmpegStatus = BinaryStatus(name: "ffmpeg", path: nil, version: nil, source: .missing)
    public private(set) var jsRuntimeStatus = BinaryStatus(name: "JS Runtime", path: nil, version: nil, source: .missing)
    public private(set) var ytdlpUpdateState: EngineUpdateState = .unknown
    public private(set) var ffmpegUpdateState: EngineUpdateState = .unknown
    public private(set) var jsRuntimeUpdateState: EngineUpdateState = .unknown
    public private(set) var isCheckingUpdates: Bool = false
    public private(set) var lastUpdateCheckAt: Date?
    public private(set) var ytdlpJSRuntimeArgument: String?
    public private(set) var homebrewPath: String?
    public private(set) var isWorking: Bool = false
    public private(set) var activityMessage: String = ""
    public private(set) var installLogs: [String] = []
    public private(set) var lastError: String?

    public var customYTDLPPath: String {
        didSet {
            UserDefaults.standard.set(customYTDLPPath, forKey: Keys.customYTDLPPath)
            scheduleDebouncedRefresh()
        }
    }

    public var customFFmpegPath: String {
        didSet {
            UserDefaults.standard.set(customFFmpegPath, forKey: Keys.customFFmpegPath)
            scheduleDebouncedRefresh()
        }
    }

    private let urlSession: URLSession
    private let binDirectory: URL
    private var refreshDebounceTask: Task<Void, Never>?

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

    public var outdatedEngineCount: Int {
        [ytdlpUpdateState, ffmpegUpdateState, jsRuntimeUpdateState].filter(\.needsUpdate).count
    }

    public var missingEngineCount: Int {
        [ytdlpStatus, ffmpegStatus, jsRuntimeStatus].filter { !$0.isInstalled }.count
    }

    public var allEnginesUpToDate: Bool {
        ytdlpStatus.isInstalled &&
        ffmpegStatus.isInstalled &&
        jsRuntimeStatus.isInstalled &&
        ytdlpUpdateState.isUpToDate &&
        ffmpegUpdateState.isUpToDate &&
        (jsRuntimeUpdateState.isUpToDate || jsRuntimeStatus.name.lowercased() != "deno")
    }

    public init(
        urlSession: URLSession = .shared,
        binDirectory: URL = EngineManager.managedBinDirectory
    ) {
        self.urlSession = urlSession
        self.binDirectory = binDirectory
        self.customYTDLPPath = UserDefaults.standard.string(forKey: Keys.customYTDLPPath) ?? ""
        self.customFFmpegPath = UserDefaults.standard.string(forKey: Keys.customFFmpegPath) ?? ""
    }

    private func scheduleDebouncedRefresh() {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    public func refresh() async {
        homebrewPath = Self.locateHomebrewBinary()

        let ytdlpFound = Self.locateBinary(named: "yt-dlp", customPath: customYTDLPPath, binDirectory: binDirectory)
        let ffmpegFound = Self.locateBinary(named: "ffmpeg", customPath: customFFmpegPath, binDirectory: binDirectory)
        let jsFound = Self.locateJSRuntime(binDirectory: binDirectory)

        async let ytdlpVer: String? = {
            guard let path = ytdlpFound?.0 else { return nil }
            let raw = await Self.readCommandFirstLine(executable: path, arguments: ["--version"])
            return Self.normalizeVersion(raw, for: "yt-dlp")
        }()

        async let ffmpegVer: String? = {
            guard let path = ffmpegFound?.0 else { return nil }
            let line = await Self.readCommandFirstLine(executable: path, arguments: ["-version"])
            return Self.normalizeVersion(line, for: "ffmpeg")
        }()

        async let jsVer: String? = {
            guard let jsFound else { return nil }
            let raw = await Self.readCommandFirstLine(executable: jsFound.path, arguments: ["--version"])
            return Self.normalizeVersion(raw, for: jsFound.runtimeName)
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

        recomputeUpdateStates(
            ytdlpLatest: ytdlpUpdateState.latestVersion,
            ffmpegLatest: ffmpegUpdateState.latestVersion,
            denoLatest: jsRuntimeStatus.name.lowercased() == "deno" ? jsRuntimeUpdateState.latestVersion : nil
        )
    }

    /// Queries upstream release redirect headers (without downloading binary payloads) to report exact installed vs. latest versions.
    public func checkForEngineUpdates() async {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        ytdlpUpdateState = .checking
        ffmpegUpdateState = .checking
        jsRuntimeUpdateState = .checking

        defer {
            isCheckingUpdates = false
        }

        #if arch(arm64)
        let ffmpegArch = "arm64"
        #else
        let ffmpegArch = "amd64"
        #endif

        async let ytdlpLatest: String? = {
            guard let url = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest") else { return nil }
            guard let loc = await fetchRedirectLocation(from: url) else { return nil }
            return Self.parseLatestVersion(fromRedirectLocation: loc, for: "yt-dlp")
        }()

        async let ffmpegLatest: String? = {
            guard let url = URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/\(ffmpegArch)/release/ffmpeg.zip") else { return nil }
            guard let loc = await fetchRedirectLocation(from: url) else { return nil }
            return Self.parseLatestVersion(fromRedirectLocation: loc, for: "ffmpeg")
        }()

        async let denoLatest: String? = {
            guard let url = URL(string: "https://github.com/denoland/deno/releases/latest") else { return nil }
            guard let loc = await fetchRedirectLocation(from: url) else { return nil }
            return Self.parseLatestVersion(fromRedirectLocation: loc, for: "deno")
        }()

        let resolvedYTDLP = await ytdlpLatest
        let resolvedFFmpeg = await ffmpegLatest
        let resolvedDeno = await denoLatest

        recomputeUpdateStates(
            ytdlpLatest: resolvedYTDLP,
            ffmpegLatest: resolvedFFmpeg,
            denoLatest: resolvedDeno
        )
        lastUpdateCheckAt = Date()
    }

    private func recomputeUpdateStates(
        ytdlpLatest: String?,
        ffmpegLatest: String?,
        denoLatest: String?
    ) {
        ytdlpUpdateState = Self.resolveUpdateState(status: ytdlpStatus, latest: ytdlpLatest)
        ffmpegUpdateState = Self.resolveUpdateState(status: ffmpegStatus, latest: ffmpegLatest)

        if jsRuntimeStatus.isInstalled && jsRuntimeStatus.name.lowercased() != "deno" {
            // External Node/Bun/QuickJS runtimes are managed outside Deno release numbering.
            if let installed = jsRuntimeStatus.version {
                jsRuntimeUpdateState = .upToDate(latest: installed)
            } else {
                jsRuntimeUpdateState = .unknown
            }
        } else {
            jsRuntimeUpdateState = Self.resolveUpdateState(status: jsRuntimeStatus, latest: denoLatest)
        }
    }

    private nonisolated static func resolveUpdateState(status: BinaryStatus, latest: String?) -> EngineUpdateState {
        guard status.isInstalled else {
            return .notInstalled(latest: latest)
        }
        guard let installed = status.version, let latest else {
            return .unknown
        }
        if compareVersions(installed, latest) == .orderedAscending {
            return .updateAvailable(installed: installed, latest: latest)
        }
        return .upToDate(latest: latest)
    }

    /// Normalizes CLI `--version` strings into clean numeric version tokens (e.g. `9.1`, `2.9.8`, `2026.11.23`).
    public nonisolated static func normalizeVersion(_ raw: String?, for engine: String) -> String? {
        guard let raw else { return nil }
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let loweredEngine = engine.lowercased()
        let knownPrefixes = [
            "ffmpeg version ",
            "ffprobe version ",
            "\(loweredEngine) version ",
            "\(loweredEngine) ",
            "deno ",
            "bun ",
            "node ",
            "quickjs "
        ]
        for prefix in knownPrefixes {
            if cleaned.lowercased().hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        if (cleaned.hasPrefix("v") || cleaned.hasPrefix("V")) && cleaned.dropFirst().first?.isNumber == true {
            cleaned = String(cleaned.dropFirst())
        }

        if let range = cleaned.range(of: #"^\d+(?:\.\d+)*"#, options: .regularExpression) {
            return String(cleaned[range])
        }

        if let firstToken = cleaned.split(whereSeparator: \.isWhitespace).first {
            return String(firstToken)
        }
        return cleaned
    }

    /// Compares dot-separated numeric versions semantically (`9.1` == `9.1.0`, `2.9.7` < `2.9.8`).
    public nonisolated static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let leftParts = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rightParts = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(leftParts.count, rightParts.count)

        for idx in 0..<count {
            let l = idx < leftParts.count ? leftParts[idx] : 0
            let r = idx < rightParts.count ? rightParts[idx] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    /// Extracts upstream version from release tag URLs or martin-riedl build paths.
    public nonisolated static func parseLatestVersion(fromRedirectLocation location: String, for engine: String) -> String? {
        let cleanedLocation = location
            .split(separator: "#", maxSplits: 1).first.map(String.init) ?? location
        let withoutQuery = cleanedLocation
            .split(separator: "?", maxSplits: 1).first.map(String.init) ?? cleanedLocation

        let lowered = engine.lowercased()
        if lowered == "ffmpeg" || lowered == "ffprobe" {
            let components = withoutQuery.split(separator: "/").map(String.init)
            for component in components {
                if let underscoreIndex = component.firstIndex(of: "_"),
                   component[..<underscoreIndex].allSatisfy(\.isNumber) {
                    let candidate = String(component[component.index(after: underscoreIndex)...])
                    if let normalized = normalizeVersion(candidate, for: engine),
                       normalized.first?.isNumber == true {
                        return normalized
                    }
                }
            }
            if let range = withoutQuery.range(of: #"ffmpeg-(\d+(?:\.\d+)*)"#, options: .regularExpression) {
                let matched = String(withoutQuery[range]).replacingOccurrences(of: "ffmpeg-", with: "")
                return normalizeVersion(matched, for: engine)
            }
            return nil
        }

        if let tagRange = withoutQuery.range(of: "/tag/") {
            let afterTag = String(withoutQuery[tagRange.upperBound...])
            let tagToken = afterTag.split(separator: "/").first.map(String.init) ?? afterTag
            return normalizeVersion(tagToken, for: engine)
        }

        if let last = withoutQuery.split(separator: "/").last.map(String.init) {
            return normalizeVersion(last, for: engine)
        }
        return nil
    }

    private func fetchRedirectLocation(from url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        request.setValue("Velora/2.0", forHTTPHeaderField: "User-Agent")

        let delegate = NoRedirectTaskDelegate()
        do {
            let (_, response) = try await urlSession.data(for: request, delegate: delegate)
            if let captured = delegate.redirectLocation, !captured.isEmpty {
                return captured
            }
            if let http = response as? HTTPURLResponse,
               let headerLocation = http.value(forHTTPHeaderField: "Location"),
               !headerLocation.isEmpty {
                return headerLocation
            }
            if let resolved = response.url?.absoluteString, resolved != url.absoluteString {
                return resolved
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Builds an enriched `PATH` environment dictionary placing system and Homebrew directories ahead of user-writable bins.
    public nonisolated static func enrichedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let extraPaths = [
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/opt/local/bin",
            managedBinDirectory.path,
            "\(home)/.deno/bin",
            "\(home)/.bun/bin",
            "\(home)/.volta/bin",
            "\(home)/.local/bin"
        ]
        let existing = env["PATH"]?.split(separator: ":").map(String.init) ?? []
        var merged: [String] = []
        for path in extraPaths + existing where !merged.contains(path) {
            merged.append(path)
        }
        env["PATH"] = merged.joined(separator: ":")
        return env
    }

    /// Downloads and SHA-256 verifies the official standalone universal `yt-dlp_macos` binary from GitHub Releases.
    public func installOrUpdateManagedYTDLP() async {
        guard !isWorking else { return }
        isWorking = true
        lastError = nil
        activityMessage = "Downloading official yt-dlp_macos binary…"

        defer {
            isWorking = false
            activityMessage = ""
        }

        do {
            try await performInstallYTDLP()
            await refresh()
        } catch {
            lastError = error.localizedDescription
            installLogs.append("✗ Failed to install yt-dlp: \(error.localizedDescription)")
        }
    }

    /// Downloads and SHA-256 verifies standalone `ffmpeg` and `ffprobe` builds for the current macOS architecture.
    public func installOrUpdateManagedFFmpeg() async {
        guard !isWorking else { return }
        isWorking = true
        lastError = nil
        activityMessage = "Downloading official FFmpeg & FFprobe binaries…"

        defer {
            isWorking = false
            activityMessage = ""
        }

        do {
            try await performInstallFFmpeg()
            await refresh()
        } catch {
            lastError = error.localizedDescription
            installLogs.append("✗ Failed to install FFmpeg: \(error.localizedDescription)")
        }
    }

    /// Downloads and SHA-256 verifies standalone `deno` JS runtime for the current macOS architecture.
    public func installOrUpdateManagedDeno() async {
        guard !isWorking else { return }
        isWorking = true
        lastError = nil
        activityMessage = "Downloading Deno JS runtime…"

        defer {
            isWorking = false
            activityMessage = ""
        }

        do {
            try await performInstallDeno()
            await refresh()
        } catch {
            lastError = error.localizedDescription
            installLogs.append("✗ Failed to install Deno: \(error.localizedDescription)")
        }
    }

    /// Installs missing or outdated engines (`yt-dlp`, `ffmpeg` + `ffprobe`, and `deno`) while skipping ones already up to date.
    public func installMissingOrOutdatedManagedEngines() async {
        guard !isWorking else { return }
        isWorking = true
        lastError = nil

        defer {
            isWorking = false
            activityMessage = ""
        }

        do {
            if !ytdlpStatus.isInstalled || ytdlpUpdateState.needsUpdate || ytdlpUpdateState == .unknown {
                activityMessage = "Downloading official yt-dlp_macos binary…"
                try await performInstallYTDLP()
            } else if let ver = ytdlpStatus.version {
                installLogs.append("✓ yt-dlp is already up to date (\(ver)), skipping.")
            }

            if !ffmpegStatus.isInstalled || ffmpegUpdateState.needsUpdate || ffmpegUpdateState == .unknown {
                activityMessage = "Downloading official FFmpeg & FFprobe binaries…"
                try await performInstallFFmpeg()
            } else if let ver = ffmpegStatus.version {
                installLogs.append("✓ ffmpeg is already up to date (\(ver)), skipping.")
            }

            if !jsRuntimeStatus.isInstalled || jsRuntimeUpdateState.needsUpdate || (jsRuntimeStatus.name.lowercased() == "deno" && jsRuntimeUpdateState == .unknown) {
                activityMessage = "Downloading Deno JS runtime…"
                try await performInstallDeno()
            } else if let ver = jsRuntimeStatus.version {
                installLogs.append("✓ \(jsRuntimeStatus.name) is already up to date (\(ver)), skipping.")
            }

            await refresh()
        } catch {
            lastError = error.localizedDescription
            installLogs.append("✗ Engine update failed: \(error.localizedDescription)")
            await refresh()
        }
    }

    /// Installs or updates all managed engines (`yt-dlp`, `ffmpeg` + `ffprobe`, and `deno`) with fail-closed SHA-256 verification.
    public func installAllManagedEngines() async {
        guard !isWorking else { return }
        isWorking = true
        lastError = nil

        defer {
            isWorking = false
            activityMessage = ""
        }

        do {
            activityMessage = "Downloading official yt-dlp_macos binary…"
            try await performInstallYTDLP()
            activityMessage = "Downloading official FFmpeg & FFprobe binaries…"
            try await performInstallFFmpeg()
            activityMessage = "Downloading Deno JS runtime…"
            try await performInstallDeno()
            await refresh()
        } catch {
            lastError = error.localizedDescription
            installLogs.append("✗ Engine installation failed: \(error.localizedDescription)")
            await refresh()
        }
    }

    private func performInstallYTDLP() async throws {
        guard let binaryURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"),
              let sumsURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS") else {
            throw URLError(.badURL)
        }

        installLogs.append("→ Fetching \(binaryURL.absoluteString)")
        let stagingDir = try makeStagingDirectory()
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        let (downloadedURL, _) = try await downloadVerifiedFile(from: binaryURL, into: stagingDir, filename: "yt-dlp_macos")
        let manifest = try await fetchManifestText(from: sumsURL)
        guard let expectedSHA = ReleaseAssetMatcher.extractExpectedSHA256(forFileName: "yt-dlp_macos", from: manifest) else {
            throw AppUpdateInstallError.missingChecksumManifest
        }
        try verifySHA256(of: downloadedURL, expected: expectedSHA)

        let destinationURL = try await installVerifiedBinary(at: downloadedURL, binaryName: "yt-dlp")
        installLogs.append("✓ Verified & installed yt-dlp at \(destinationURL.path)")
    }

    private func performInstallFFmpeg() async throws {
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "amd64"
        #endif

        for toolName in ["ffmpeg", "ffprobe"] {
            guard let archiveURL = URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/\(arch)/release/\(toolName).zip") else {
                throw URLError(.badURL)
            }
            installLogs.append("→ Fetching \(archiveURL.absoluteString)")
            let stagingDir = try makeStagingDirectory()
            defer { try? FileManager.default.removeItem(at: stagingDir) }

            let (zipURL, responseURL) = try await downloadVerifiedFile(from: archiveURL, into: stagingDir, filename: "\(toolName).zip")
            let resolvedBase = responseURL?.absoluteString ?? archiveURL.absoluteString
            guard let shaURL = URL(string: "\(resolvedBase).sha256"),
                  shaURL.scheme?.lowercased() == "https" else {
                throw AppUpdateInstallError.missingChecksumManifest
            }

            let manifest = try await fetchManifestText(from: shaURL)
            guard let expectedSHA = Self.extractSHA256(forFileName: "\(toolName).zip", from: manifest) else {
                throw AppUpdateInstallError.missingChecksumManifest
            }
            try verifySHA256(of: zipURL, expected: expectedSHA)

            let extractedBinary = try await extractAndLocateBinary(named: toolName, fromZip: zipURL, stagingDir: stagingDir)
            let destinationURL = try await installVerifiedBinary(at: extractedBinary, binaryName: toolName)
            installLogs.append("✓ Verified & installed \(toolName) at \(destinationURL.path)")
        }
    }

    private func performInstallDeno() async throws {
        #if arch(arm64)
        let arch = "aarch64"
        #else
        let arch = "x86_64"
        #endif

        let assetName = "deno-\(arch)-apple-darwin.zip"
        guard let zipRemoteURL = URL(string: "https://github.com/denoland/deno/releases/latest/download/\(assetName)"),
              let shaURL = URL(string: "https://github.com/denoland/deno/releases/latest/download/\(assetName).sha256sum") else {
            throw URLError(.badURL)
        }

        installLogs.append("→ Fetching \(zipRemoteURL.absoluteString)")
        let stagingDir = try makeStagingDirectory()
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        let (zipURL, _) = try await downloadVerifiedFile(from: zipRemoteURL, into: stagingDir, filename: assetName)
        let manifest = try await fetchManifestText(from: shaURL)
        guard let expectedSHA = Self.extractSHA256(forFileName: assetName, from: manifest) else {
            throw AppUpdateInstallError.missingChecksumManifest
        }
        try verifySHA256(of: zipURL, expected: expectedSHA)

        let extractedBinary = try await extractAndLocateBinary(named: "deno", fromZip: zipURL, stagingDir: stagingDir)
        let destinationURL = try await installVerifiedBinary(at: extractedBinary, binaryName: "deno")
        installLogs.append("✓ Verified & installed deno at \(destinationURL.path)")
    }

    private func makeStagingDirectory() throws -> URL {
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let stagingDir = binDirectory.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stagingDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return stagingDir
    }

    private func downloadVerifiedFile(from url: URL, into stagingDir: URL, filename: String) async throws -> (fileURL: URL, resolvedURL: URL?) {
        var request = URLRequest(url: url)
        request.setValue("Velora/1.0", forHTTPHeaderField: "User-Agent")

        let (tempURL, response) = try await urlSession.download(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: tempURL)
            throw NSError(
                domain: "Velora.EngineManager",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Download failed with HTTP \(http.statusCode) for \(url.lastPathComponent)."]
            )
        }

        let stagedFile = stagingDir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: stagedFile.path) {
            try FileManager.default.removeItem(at: stagedFile)
        }
        try FileManager.default.moveItem(at: tempURL, to: stagedFile)
        return (stagedFile, response.url)
    }

    private func fetchManifestText(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("Velora/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AppUpdateInstallError.missingChecksumManifest
        }
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw AppUpdateInstallError.missingChecksumManifest
        }
        return text
    }

    private func verifySHA256(of fileURL: URL, expected: String) throws {
        let actual = try AppUpdateInstaller.sha256Hex(of: fileURL)
        guard actual.lowercased() == expected.lowercased() else {
            throw AppUpdateInstallError.checksumMismatch(expected: expected, actual: actual)
        }
    }

    private func extractAndLocateBinary(named binaryName: String, fromZip zipURL: URL, stagingDir: URL) async throws -> URL {
        let extractedDir = stagingDir.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(
            at: extractedDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let result = await ProcessSupervisor.runCollectingOutput(
            executable: "/usr/bin/ditto",
            arguments: ["-x", "-k", zipURL.path, extractedDir.path],
            environment: Self.enrichedEnvironment(),
            timeoutSeconds: 60
        )
        guard result.exitCode == 0, !result.timedOut else {
            let errText = String(decoding: result.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw AppUpdateInstallError.extractionFailed(errText.isEmpty ? "ditto exited with \(result.exitCode)" : errText)
        }

        return try Self.scanAndLocateBinary(named: binaryName, in: extractedDir)
    }

    private nonisolated static func scanAndLocateBinary(named binaryName: String, in directory: URL) throws -> URL {
        let fm = FileManager.default
        var foundBinaryURL: URL?
        if let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey]
        ) {
            for case let itemURL as URL in enumerator {
                let attrs = try? fm.attributesOfItem(atPath: itemURL.path)
                if (attrs?[.type] as? FileAttributeType) == .typeSymbolicLink ||
                   (try? itemURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    throw AppUpdateInstallError.symlinkNotAllowed(itemURL.path)
                }
                if itemURL.lastPathComponent == binaryName &&
                   (try? itemURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    foundBinaryURL = itemURL
                }
            }
        }

        guard let binaryURL = foundBinaryURL else {
            throw AppUpdateInstallError.extractionFailed("Binary '\(binaryName)' not found in archive.")
        }
        return binaryURL
    }

    private func installVerifiedBinary(at stagedBinaryURL: URL, binaryName: String) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagedBinaryURL.path)

        _ = await ProcessSupervisor.runCollectingOutput(
            executable: "/usr/bin/xattr",
            arguments: ["-dr", "com.apple.quarantine", stagedBinaryURL.path],
            environment: Self.enrichedEnvironment(),
            timeoutSeconds: 5
        )

        let destinationURL = binDirectory.appendingPathComponent(binaryName)
        if fm.fileExists(atPath: destinationURL.path) {
            _ = try fm.replaceItemAt(destinationURL, withItemAt: stagedBinaryURL)
        } else {
            try fm.moveItem(at: stagedBinaryURL, to: destinationURL)
        }
        return destinationURL
    }

    private static func extractSHA256(forFileName fileName: String, from manifest: String) -> String? {
        if let matched = ReleaseAssetMatcher.extractExpectedSHA256(forFileName: fileName, from: manifest) {
            return matched
        }
        let trimmed = manifest.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isSingleHexDigest = trimmed.count == 64 && trimmed.unicodeScalars.allSatisfy {
            ("0"..."9").contains($0) || ("a"..."f").contains($0)
        }
        return isSingleHexDigest ? trimmed : nil
    }

    /// Installs allowlisted formulas (`yt-dlp`, `ffmpeg`, `deno`) via Homebrew if installed in a trusted location.
    public func installViaHomebrew(packages: [String]) async {
        guard !isWorking else { return }

        let allowedPackages: Set<String> = ["yt-dlp", "ffmpeg", "deno"]
        let sanitizedPackages = packages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { allowedPackages.contains($0) }

        guard !sanitizedPackages.isEmpty, sanitizedPackages.count == packages.count else {
            lastError = "Unsupported Homebrew package requested. Allowed formulas: yt-dlp, ffmpeg, deno."
            return
        }

        guard let brewPath = homebrewPath else {
            lastError = "Homebrew was not found on this Mac. Install Homebrew or download standalone yt-dlp."
            return
        }

        isWorking = true
        lastError = nil
        activityMessage = "Installing \(sanitizedPackages.joined(separator: ", ")) via Homebrew…"
        installLogs.append("→ Running: \(brewPath) install --formula -- \(sanitizedPackages.joined(separator: " "))")

        defer {
            isWorking = false
            activityMessage = ""
        }

        let exitCode = await Self.streamCommand(
            executable: brewPath,
            arguments: ["install", "--formula", "--"] + sanitizedPackages
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

    private static func locateHomebrewBinary() -> String? {
        let fm = FileManager.default
        for path in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] where fm.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private static func locateJSRuntime(
        binDirectory: URL = EngineManager.managedBinDirectory
    ) -> (runtimeName: String, path: String, source: EngineSource)? {
        let fm = FileManager.default
        let home = NSHomeDirectory()

        let nvmNodeDirs: [String] = {
            let nvmRoot = "\(home)/.nvm/versions/node"
            guard let versions = try? fm.contentsOfDirectory(atPath: nvmRoot) else { return [] }
            return versions.sorted(by: >).map { "\(nvmRoot)/\($0)/bin" }
        }()

        let fnmNodeDirs: [String] = {
            var dirs = [
                "\(home)/.local/share/fnm/aliases/default/bin",
                "\(home)/.fnm/aliases/default/bin",
                "\(home)/Library/Application Support/fnm/aliases/default/bin"
            ]
            let fnmVersionsRoot = "\(home)/.local/share/fnm/node-versions"
            if let versions = try? fm.contentsOfDirectory(atPath: fnmVersionsRoot) {
                dirs.append(contentsOf: versions.sorted(by: >).map { "\(fnmVersionsRoot)/\($0)/installation/bin" })
            }
            return dirs
        }()

        let miseShims = "\(home)/.local/share/mise/shims"
        let asdfShims = "\(home)/.asdf/shims"

        // yt-dlp 2026+ supports deno, bun, node, quickjs via --js-runtimes RUNTIME:PATH
        let candidates: [(runtime: String, binary: String, extraDirs: [String])] = [
            ("deno", "deno", ["\(home)/.deno/bin", miseShims, asdfShims]),
            ("bun", "bun", ["\(home)/.bun/bin", miseShims, asdfShims]),
            ("node", "node", ["\(home)/.volta/bin"] + nvmNodeDirs + fnmNodeDirs + [miseShims, asdfShims]),
            ("quickjs", "qjs", [])
        ]

        for candidate in candidates {
            if let found = locateBinary(named: candidate.binary, customPath: nil, binDirectory: binDirectory) {
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

    private static func locateBinary(
        named name: String,
        customPath: String?,
        binDirectory: URL = EngineManager.managedBinDirectory
    ) -> (String, EngineSource)? {
        let fm = FileManager.default

        if let customPath {
            let expanded = (customPath as NSString).expandingTildeInPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !expanded.isEmpty && fm.isExecutableFile(atPath: expanded) {
                return (expanded, .custom)
            }
        }

        let managed = binDirectory.appendingPathComponent(name).path
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
        let result = await ProcessSupervisor.runCollectingOutput(
            executable: executable,
            arguments: arguments,
            environment: enrichedEnvironment(),
            timeoutSeconds: 10
        )
        guard result.exitCode == 0, !result.timedOut else { return nil }
        let output = String(decoding: result.stdout, as: UTF8.self)
        return output
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func runQuickCommand(executable: String, arguments: [String]) async -> Int32 {
        let result = await ProcessSupervisor.runCollectingOutput(
            executable: executable,
            arguments: arguments,
            environment: enrichedEnvironment(),
            timeoutSeconds: 10
        )
        return result.exitCode
    }

    private static func streamCommand(
        executable: String,
        arguments: [String],
        onLine: @escaping @Sendable (String) -> Void
    ) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                ProcessSupervisor.configure(
                    process,
                    executableURL: URL(fileURLWithPath: executable),
                    arguments: arguments,
                    environment: enrichedEnvironment()
                )

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
                    _ = try ProcessSupervisor.launchInNewProcessGroup(process)
                    process.waitUntilExit()
                    pipe.fileHandleForReading.readabilityHandler = nil

                    let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
                    if !remaining.isEmpty {
                        for line in accumulator.append(remaining) {
                            onLine(line)
                        }
                    }
                    for line in accumulator.flush() {
                        onLine(line)
                    }
                    continuation.resume(returning: process.terminationStatus)
                } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    onLine("Process failed: \(error.localizedDescription)")
                    continuation.resume(returning: -1)
                }
            }
        }
    }
}

private final class NoRedirectTaskDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var capturedLocation: String?

    var redirectLocation: String? {
        lock.lock()
        defer { lock.unlock() }
        return capturedLocation
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let location = request.url?.absoluteString ?? response.value(forHTTPHeaderField: "Location")
        lock.lock()
        if capturedLocation == nil {
            capturedLocation = location
        }
        lock.unlock()
        completionHandler(nil)
    }
}
