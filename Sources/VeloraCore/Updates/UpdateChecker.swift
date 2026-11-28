import Foundation

public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(checkedAt: Date)
    case updateAvailable(AvailableUpdate)
    case downloading(AvailableUpdate, progress: Double, receivedBytes: Int64, totalBytes: Int64)
    case verifying(AvailableUpdate)
    case readyToInstall(StagedUpdate)
    case installing
    case failed(String)

    public var availableUpdate: AvailableUpdate? {
        switch self {
        case .updateAvailable(let u),
             .downloading(let u, _, _, _),
             .verifying(let u):
            return u
        case .readyToInstall(let staged):
            return staged.update
        default:
            return nil
        }
    }

    public var hasActionableUpdate: Bool {
        switch self {
        case .updateAvailable, .readyToInstall: true
        default: false
        }
    }
}

/// Checks GitHub Releases for newer Velora versions, downloads & verifies the macOS artifact,
/// and triggers close-and-update via `AppUpdateInstaller`.
@MainActor
@Observable
public final class UpdateChecker {
    public private(set) var state: UpdateState = .idle
    public private(set) var lastCheckedAt: Date?
    public var isPresentingUpdateSheet: Bool = false

    public var githubRepository: String {
        didSet {
            let cleaned = githubRepository.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(cleaned, forKey: Keys.githubRepository)
        }
    }

    public var autoCheckOnLaunch: Bool {
        didSet {
            UserDefaults.standard.set(autoCheckOnLaunch, forKey: Keys.autoCheckOnLaunch)
        }
    }

    public var includePrereleases: Bool {
        didSet {
            UserDefaults.standard.set(includePrereleases, forKey: Keys.includePrereleases)
        }
    }

    public var skippedVersion: String? {
        didSet {
            UserDefaults.standard.set(skippedVersion, forKey: Keys.skippedVersion)
        }
    }

    private let urlSession: URLSession
    private var activeDownloadDelegate: ReleaseDownloadDelegate?
    private var activeDownloadSession: URLSession?
    private var activeDownloadTask: URLSessionDownloadTask?

    private enum Keys {
        static let githubRepository = "velora.updates.githubRepository"
        static let autoCheckOnLaunch = "velora.updates.autoCheckOnLaunch"
        static let includePrereleases = "velora.updates.includePrereleases"
        static let skippedVersion = "velora.updates.skippedVersion"
        static let lastCheckedAt = "velora.updates.lastCheckedAt"
    }

    nonisolated public static func isValidGitHubRepository(_ repo: String) -> Bool {
        let trimmed = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#
        guard trimmed.range(of: pattern, options: .regularExpression) != nil else {
            return false
        }
        let parts = trimmed.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return false }
        let owner = parts[0]
        let name = parts[1]
        return owner != "." && owner != ".." && name != "." && name != ".."
    }

    nonisolated public static func isAllowedGitHubDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return false
        }
        return host == "github.com"
            || host == "api.github.com"
            || host == "objects.githubusercontent.com"
            || host == "release-assets.githubusercontent.com"
            || host.hasSuffix(".githubusercontent.com")
    }

    public static var currentVersionString: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0-dev"
    }

    public static var currentBuildNumber: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }

    public static var currentSemVer: SemVer {
        SemVer(currentVersionString) ?? SemVer(major: 0, minor: 1, patch: 0)
    }

    public static var defaultRepository: String {
        if let configured = Bundle.main.infoDictionary?["VeloraGitHubRepository"] as? String,
           !configured.isEmpty,
           configured != "__GITHUB_REPO__" {
            return configured
        }
        return "kobenguyent/Velora"
    }

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        let savedRepo = UserDefaults.standard.string(forKey: Keys.githubRepository)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.githubRepository = (savedRepo?.isEmpty == false) ? savedRepo! : Self.defaultRepository

        if UserDefaults.standard.object(forKey: Keys.autoCheckOnLaunch) != nil {
            self.autoCheckOnLaunch = UserDefaults.standard.bool(forKey: Keys.autoCheckOnLaunch)
        } else {
            self.autoCheckOnLaunch = true
        }

        self.includePrereleases = UserDefaults.standard.bool(forKey: Keys.includePrereleases)
        self.skippedVersion = UserDefaults.standard.string(forKey: Keys.skippedVersion)
        self.lastCheckedAt = UserDefaults.standard.object(forKey: Keys.lastCheckedAt) as? Date
    }

    public func performLaunchCheckIfEnabled() async {
        guard autoCheckOnLaunch else { return }
        await checkForUpdates(userInitiated: false)
    }

    public func checkForUpdates(userInitiated: Bool) async {
        if case .downloading = state { return }
        if case .installing = state { return }

        let repo = githubRepository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidGitHubRepository(repo) else {
            if userInitiated {
                state = .failed(AppUpdateInstallError.invalidRepository(repo).localizedDescription)
                isPresentingUpdateSheet = true
            }
            return
        }

        state = .checking

        do {
            let latestRelease = try await fetchLatestRelease(repository: repo, includePrereleases: includePrereleases)
            let now = Date()
            lastCheckedAt = now
            UserDefaults.standard.set(now, forKey: Keys.lastCheckedAt)

            guard let latestRelease,
                  let available = ReleaseAssetMatcher.evaluateUpdate(
                    currentVersion: Self.currentSemVer,
                    release: latestRelease
                  ) else {
                state = .upToDate(checkedAt: now)
                if userInitiated {
                    isPresentingUpdateSheet = true
                }
                return
            }

            if !userInitiated && skippedVersion == available.version.description {
                state = .upToDate(checkedAt: now)
                return
            }

            state = .updateAvailable(available)
            isPresentingUpdateSheet = true
        } catch {
            if userInitiated {
                state = .failed(error.localizedDescription)
                isPresentingUpdateSheet = true
            } else {
                state = .idle
            }
        }
    }

    public func skipCurrentAvailableVersion() {
        guard let version = state.availableUpdate?.version.description else { return }
        skippedVersion = version
        isPresentingUpdateSheet = false
    }

    public func cancelDownload() {
        activeDownloadTask?.cancel()
        activeDownloadSession?.invalidateAndCancel()
        activeDownloadTask = nil
        activeDownloadSession = nil
        activeDownloadDelegate = nil

        if case let .downloading(update, _, _, _) = state {
            state = .updateAvailable(update)
        }
    }

    /// Downloads the release `.zip`, verifies its mandatory SHA-256 checksum, extracts & validates `.app`.
    /// When `autoInstallAfterDownload` is true, immediately closes the running app to apply the update.
    public func downloadUpdate(_ update: AvailableUpdate, autoInstallAfterDownload: Bool = false) async {
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VeloraUpdate-\(UUID().uuidString)", isDirectory: true)

        do {
            guard let checksumAsset = update.checksumAsset else {
                throw AppUpdateInstallError.missingChecksumManifest
            }

            guard Self.isAllowedGitHubDownloadURL(update.downloadAsset.browserDownloadURL) else {
                throw NSError(
                    domain: "Velora.UpdateChecker",
                    code: NSURLErrorUnsupportedURL,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Refusing update download from untrusted URL: \(update.downloadAsset.browserDownloadURL.absoluteString)"
                    ]
                )
            }

            guard Self.isAllowedGitHubDownloadURL(checksumAsset.browserDownloadURL) else {
                throw NSError(
                    domain: "Velora.UpdateChecker",
                    code: NSURLErrorUnsupportedURL,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Refusing checksum manifest download from untrusted URL: \(checksumAsset.browserDownloadURL.absoluteString)"
                    ]
                )
            }

            let assetFileName = (update.downloadAsset.name as NSString).lastPathComponent
            guard !assetFileName.isEmpty, assetFileName != ".", assetFileName != ".." else {
                throw AppUpdateInstallError.invalidAppBundle("Invalid release asset filename.")
            }
            let zipDestination = stagingDir.appendingPathComponent(assetFileName, isDirectory: false)

            try FileManager.default.createDirectory(
                at: stagingDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            state = .downloading(update, progress: 0, receivedBytes: 0, totalBytes: update.downloadAsset.size)

            try await downloadFile(
                from: update.downloadAsset.browserDownloadURL,
                to: zipDestination
            ) { [weak self] received, expected in
                Task { @MainActor [weak self] in
                    let total = expected > 0 ? expected : update.downloadAsset.size
                    let fraction = total > 0 ? min(1.0, Double(received) / Double(total)) : 0
                    self?.state = .downloading(
                        update,
                        progress: fraction,
                        receivedBytes: received,
                        totalBytes: total
                    )
                }
            }

            state = .verifying(update)

            // Fail-closed SHA-256 verification against the release checksum manifest
            var request = URLRequest(url: checksumAsset.browserDownloadURL)
            request.setValue("Velora/\(Self.currentVersionString)", forHTTPHeaderField: "User-Agent")
            let (manifestData, manifestResponse) = try await urlSession.data(for: request)
            guard let httpResponse = manifestResponse as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let manifestText = String(data: manifestData, encoding: .utf8),
                  let expectedHash = ReleaseAssetMatcher.extractExpectedSHA256(
                    forFileName: assetFileName,
                    from: manifestText
                  ) else {
                throw AppUpdateInstallError.missingChecksumManifest
            }

            let actualHash = try await Task.detached(priority: .userInitiated) {
                try AppUpdateInstaller.sha256Hex(of: zipDestination)
            }.value

            guard actualHash.lowercased() == expectedHash.lowercased() else {
                throw AppUpdateInstallError.checksumMismatch(expected: expectedHash, actual: actualHash)
            }

            let expectedBundleID = Bundle.main.bundleIdentifier
            let stagedAppURL = try await Task.detached(priority: .userInitiated) {
                try AppUpdateInstaller.extractAndValidate(
                    zipURL: zipDestination,
                    stagingDirectory: stagingDir,
                    expectedBundleIdentifier: expectedBundleID
                )
            }.value

            let staged = StagedUpdate(
                update: update,
                stagedAppURL: stagedAppURL,
                stagingDirectoryURL: stagingDir,
                verifiedSHA256: actualHash
            )
            state = .readyToInstall(staged)

            if autoInstallAfterDownload {
                installStagedUpdate(staged)
            }
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: stagingDir)
            state = .updateAvailable(update)
        } catch let urlError as URLError where urlError.code == .cancelled {
            try? FileManager.default.removeItem(at: stagingDir)
            state = .updateAvailable(update)
        } catch {
            try? FileManager.default.removeItem(at: stagingDir)
            state = .failed(error.localizedDescription)
        }
    }

    public func installStagedUpdate(_ staged: StagedUpdate) {
        state = .installing
        do {
            try AppUpdateInstaller.installAndRelaunch(staged: staged)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - GitHub API & Download Helpers

    private func fetchLatestRelease(repository: String, includePrereleases: Bool) async throws -> GitHubRelease? {
        guard Self.isValidGitHubRepository(repository) else {
            throw AppUpdateInstallError.invalidRepository(repository)
        }

        let endpoint: String
        if includePrereleases {
            endpoint = "https://api.github.com/repos/\(repository)/releases?per_page=10"
        } else {
            endpoint = "https://api.github.com/repos/\(repository)/releases/latest"
        }

        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Velora/\(Self.currentVersionString)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if http.statusCode == 404 {
            return nil
        }

        guard (200...299).contains(http.statusCode) else {
            let apiMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw NSError(
                domain: "Velora.UpdateChecker",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: apiMsg
                        ?? "GitHub Releases returned HTTP \(http.statusCode) for \(repository)."
                ]
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if includePrereleases {
            let releases = try decoder.decode([GitHubRelease].self, from: data)
            return ReleaseAssetMatcher.selectLatestRelease(from: releases, includePrereleases: true)
        } else {
            return try decoder.decode(GitHubRelease.self, from: data)
        }
    }

    private func downloadFile(
        from remoteURL: URL,
        to destinationURL: URL,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = ReleaseDownloadDelegate(
                destinationURL: destinationURL,
                onProgress: onProgress,
                completion: { [weak self] result in
                    Task { @MainActor [weak self] in
                        self?.activeDownloadSession?.finishTasksAndInvalidate()
                        self?.activeDownloadTask = nil
                        self?.activeDownloadSession = nil
                        self?.activeDownloadDelegate = nil
                    }
                    continuation.resume(with: result)
                }
            )
            let session = URLSession(configuration: urlSession.configuration, delegate: delegate, delegateQueue: nil)
            var request = URLRequest(url: remoteURL)
            request.setValue("Velora/\(Self.currentVersionString)", forHTTPHeaderField: "User-Agent")
            let task = session.downloadTask(with: request)

            self.activeDownloadDelegate = delegate
            self.activeDownloadSession = session
            self.activeDownloadTask = task
            task.resume()
        }
    }
}

private final class ReleaseDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destinationURL: URL
    private let onProgress: @Sendable (Int64, Int64) -> Void
    private let lock = NSLock()
    private var completion: (@Sendable (Result<Void, Error>) -> Void)?
    private var lastProgressReportTime: ContinuousClock.Instant?

    init(
        destinationURL: URL,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        self.destinationURL = destinationURL
        self.onProgress = onProgress
        self.completion = completion
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        let handler = completion
        completion = nil
        lock.unlock()
        handler?(result)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        if let redirectURL = request.url, UpdateChecker.isAllowedGitHubDownloadURL(redirectURL) {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let now = ContinuousClock.now
        lock.lock()
        let shouldReport: Bool
        if let last = lastProgressReportTime {
            shouldReport = (now - last) >= .milliseconds(100)
                || (totalBytesExpectedToWrite > 0 && totalBytesWritten >= totalBytesExpectedToWrite)
        } else {
            shouldReport = true
        }
        if shouldReport {
            lastProgressReportTime = now
        }
        lock.unlock()

        if shouldReport {
            onProgress(totalBytesWritten, totalBytesExpectedToWrite)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            finish(.failure(NSError(
                domain: "Velora.UpdateDownload",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Release download failed with HTTP \(http.statusCode)."]
            )))
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        }
    }
}
