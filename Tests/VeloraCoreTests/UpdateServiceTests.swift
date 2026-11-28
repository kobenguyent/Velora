import Foundation
import Testing
@testable import VeloraCore

@Suite("GitHub Release Auto-Updater")
struct UpdateServiceTests {
    @Test("Selects best universal macOS ZIP asset and companion SHA256SUMS")
    func selectBestZipAndChecksumAsset() throws {
        let dmg = GitHubReleaseAsset(
            id: 1,
            name: "Velora-1.2.0-macos-universal.dmg",
            size: 14_000_000,
            browserDownloadURL: URL(string: "https://github.com/kobenguyent/Velora/releases/download/v1.2.0/Velora-1.2.0-macos-universal.dmg")!
        )
        let zip = GitHubReleaseAsset(
            id: 2,
            name: "Velora-1.2.0-macos-universal.zip",
            size: 13_500_000,
            browserDownloadURL: URL(string: "https://github.com/kobenguyent/Velora/releases/download/v1.2.0/Velora-1.2.0-macos-universal.zip")!
        )
        let sha = GitHubReleaseAsset(
            id: 3,
            name: "SHA256SUMS.txt",
            size: 192,
            browserDownloadURL: URL(string: "https://github.com/kobenguyent/Velora/releases/download/v1.2.0/SHA256SUMS.txt")!
        )

        let release = GitHubRelease(
            tagName: "v1.2.0",
            name: "Velora v1.2.0",
            body: "## What's New\n- Faster downloads",
            draft: false,
            prerelease: false,
            htmlURL: URL(string: "https://github.com/kobenguyent/Velora/releases/tag/v1.2.0")!,
            assets: [dmg, zip, sha]
        )

        let current = try #require(SemVer("1.0.0"))
        let update = ReleaseAssetMatcher.evaluateUpdate(currentVersion: current, release: release)
        #expect(update != nil)
        #expect(update?.downloadAsset.name == "Velora-1.2.0-macos-universal.zip")
        #expect(update?.checksumAsset?.name == "SHA256SUMS.txt")

        #expect(ReleaseAssetMatcher.evaluateUpdate(currentVersion: try #require(SemVer("1.2.0")), release: release) == nil)
        #expect(ReleaseAssetMatcher.evaluateUpdate(currentVersion: try #require(SemVer("2.0.0")), release: release) == nil)
    }

    @Test("Filters drafts and respects prerelease channel setting")
    func prereleaseFiltering() {
        let stable = GitHubRelease(
            tagName: "v1.1.0",
            prerelease: false,
            htmlURL: URL(string: "https://example.com/1.1.0")!
        )
        let beta = GitHubRelease(
            tagName: "v1.2.0-beta.1",
            prerelease: true,
            htmlURL: URL(string: "https://example.com/1.2.0-beta.1")!
        )
        let draft = GitHubRelease(
            tagName: "v2.0.0",
            draft: true,
            prerelease: false,
            htmlURL: URL(string: "https://example.com/2.0.0")!
        )

        #expect(
            ReleaseAssetMatcher.selectLatestRelease(from: [stable, beta, draft], includePrereleases: false)?.tagName
            == "v1.1.0"
        )
        #expect(
            ReleaseAssetMatcher.selectLatestRelease(from: [stable, beta, draft], includePrereleases: true)?.tagName
            == "v1.2.0-beta.1"
        )
    }

    @Test("Parses SHA256SUMS manifest and computes CryptoKit SHA-256 digest")
    func sha256ManifestParsingAndFileHashing() throws {
        let expectedHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        let manifest = """
        # Release checksums
        \(expectedHash)  Velora-1.2.0-macos-universal.zip
        0000000000000000000000000000000000000000000000000000000000000000  Velora-1.2.0-macos-universal.dmg
        """

        #expect(
            ReleaseAssetMatcher.extractExpectedSHA256(
                forFileName: "Velora-1.2.0-macos-universal.zip",
                from: manifest
            ) == expectedHash
        )

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("velora-empty-\(UUID().uuidString)")
        try Data().write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        #expect(try AppUpdateInstaller.sha256Hex(of: tempFile) == expectedHash)
    }

    @Test("Generates safe atomic close-and-relaunch updater script")
    func updaterScriptGenerationAndQuoting() {
        let script = AppUpdateInstaller.buildUpdaterScript(
            oldPID: 4242,
            targetAppPath: "/Applications/Velora.app",
            stagedAppPath: "/tmp/stage dir/Velora.app",
            stagingDirectoryPath: "/tmp/stage dir",
            logFilePath: "/Users/test/Library/Logs/Velora/updater.log"
        )

        #expect(script.contains("OLD_PID=4242"))
        #expect(script.contains("TARGET_APP='/Applications/Velora.app'"))
        #expect(script.contains("STAGED_APP='/tmp/stage dir/Velora.app'"))
        #expect(script.contains("/usr/bin/ditto \"$STAGED_APP\" \"$TARGET_APP\""))
        #expect(script.contains("/usr/bin/xattr -dr com.apple.quarantine \"$TARGET_APP\""))
        #expect(script.contains("/usr/bin/open -n \"$TARGET_APP\""))
        #expect(script.contains("trap 'rm -rf \"$STAGING_DIR\" 2>/dev/null || true; rm -f \"$0\" 2>/dev/null || true' EXIT"))
        #expect(!script.contains("--swap-only"))
        #expect(script.contains("VELORA_TARGET_APP"))
        #expect(script.contains("VELORA_STAGED_APP"))
        #expect(script.contains("VELORA_BACKUP_APP"))
        #expect(script.contains("/bin/mv"))
        #expect(script.contains("/bin/rm"))
    }

    @Test("Preserves backup bundle when target app is missing and cleans up staging via EXIT trap")
    func updaterScriptPreservesBackupAndRunsExitTrap() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("velora-script-exec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let targetApp = workspace.appendingPathComponent("Velora.app", isDirectory: true)
        let backupApp = workspace.appendingPathComponent("Velora.app.velora-backup", isDirectory: true)
        let stagingDir = workspace.appendingPathComponent("staging", isDirectory: true)
        let missingStaged = stagingDir.appendingPathComponent("DoesNotExist.app", isDirectory: true)
        let logFile = workspace.appendingPathComponent("updater.log")

        // Simulate a prior crashed swap where TARGET_APP is gone and only BACKUP_APP remains.
        try FileManager.default.createDirectory(
            at: backupApp.appendingPathComponent("Contents/MacOS", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "preserved".write(
            to: backupApp.appendingPathComponent("Contents/MacOS/Velora"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        let script = AppUpdateInstaller.buildUpdaterScript(
            oldPID: 999_999,
            targetAppPath: targetApp.path,
            stagedAppPath: missingStaged.path,
            stagingDirectoryPath: stagingDir.path,
            logFilePath: logFile.path
        )
        let scriptURL = workspace.appendingPathComponent("updater.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = [scriptURL.path]
        try proc.run()
        proc.waitUntilExit()

        #expect(proc.terminationStatus != 0)
        // Rollback should restore BACKUP_APP back to TARGET_APP instead of deleting it!
        #expect(FileManager.default.fileExists(atPath: targetApp.appendingPathComponent("Contents/MacOS/Velora").path))
        // EXIT trap should have removed stagingDir and self-deleted scriptURL
        #expect(!FileManager.default.fileExists(atPath: stagingDir.path))
        #expect(!FileManager.default.fileExists(atPath: scriptURL.path))
    }

    @Test("Extracts zipped app bundle and validates Info.plist and bundle identifier")
    func extractAndValidateAppArchive() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("velora-zip-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        // Create a synthetic minimal Velora.app
        let fakeApp = workspace.appendingPathComponent("Velora.app", isDirectory: true)
        let macOSDir = fakeApp.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.kobenguyent.velora</string>
            <key>CFBundleExecutable</key>
            <string>Velora</string>
            <key>CFBundleShortVersionString</key>
            <string>1.2.0</string>
        </dict>
        </plist>
        """
        try plist.write(to: fakeApp.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)

        let exe = macOSDir.appendingPathComponent("Velora")
        try "#!/bin/sh\nexit 0\n".write(to: exe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)

        let zipURL = workspace.appendingPathComponent("Velora-1.2.0-macos-universal.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", fakeApp.path, zipURL.path]
        try ditto.run()
        ditto.waitUntilExit()
        #expect(ditto.terminationStatus == 0)

        let stageGood = workspace.appendingPathComponent("stage-good", isDirectory: true)
        let extractedApp = try AppUpdateInstaller.extractAndValidate(
            zipURL: zipURL,
            stagingDirectory: stageGood,
            expectedBundleIdentifier: "com.kobenguyent.velora"
        )
        #expect(extractedApp.lastPathComponent == "Velora.app")

        let stageBad = workspace.appendingPathComponent("stage-bad", isDirectory: true)
        #expect(throws: AppUpdateInstallError.self) {
            _ = try AppUpdateInstaller.extractAndValidate(
                zipURL: zipURL,
                stagingDirectory: stageBad,
                expectedBundleIdentifier: "com.other.app"
            )
        }
    }

    @Test("Validates GitHub repository owner/repo format strictly")
    func githubRepositoryValidation() {
        #expect(UpdateChecker.isValidGitHubRepository("kobenguyent/Velora"))
        #expect(UpdateChecker.isValidGitHubRepository("owner_1/repo-2.0"))
        #expect(!UpdateChecker.isValidGitHubRepository(""))
        #expect(!UpdateChecker.isValidGitHubRepository("noslash"))
        #expect(!UpdateChecker.isValidGitHubRepository("owner/repo/extra"))
        #expect(!UpdateChecker.isValidGitHubRepository("../Velora"))
        #expect(!UpdateChecker.isValidGitHubRepository("kobenguyent/.."))
        #expect(!UpdateChecker.isValidGitHubRepository("./Velora"))
        #expect(!UpdateChecker.isValidGitHubRepository("kobenguyent/Velora?foo=bar"))
        #expect(!UpdateChecker.isValidGitHubRepository("kobenguyent/Velora#frag"))
        #expect(!UpdateChecker.isValidGitHubRepository("owner /repo"))
    }

    @Test("Rejects symbolic links inside extracted .app bundle")
    func validateAppBundleRejectsSymlinks() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("velora-symlink-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let fakeApp = workspace.appendingPathComponent("Velora.app", isDirectory: true)
        let macOSDir = fakeApp.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.kobenguyent.velora</string>
            <key>CFBundleExecutable</key>
            <string>Velora</string>
        </dict>
        </plist>
        """
        try plist.write(to: fakeApp.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            atPath: macOSDir.appendingPathComponent("Velora").path,
            withDestinationPath: "/bin/sh"
        )

        #expect(throws: AppUpdateInstallError.self) {
            try AppUpdateInstaller.validateAppBundle(
                at: fakeApp,
                expectedBundleIdentifier: "com.kobenguyent.velora"
            )
        }
        do {
            try AppUpdateInstaller.validateAppBundle(
                at: fakeApp,
                expectedBundleIdentifier: "com.kobenguyent.velora"
            )
            Issue.record("Expected symlinkNotAllowed error")
        } catch let error as AppUpdateInstallError {
            guard case .symlinkNotAllowed = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test("Rejects path traversal in CFBundleExecutable")
    func validateAppBundleRejectsExecutableTraversal() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("velora-exec-traversal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let fakeApp = workspace.appendingPathComponent("Velora.app", isDirectory: true)
        let macOSDir = fakeApp.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.kobenguyent.velora</string>
            <key>CFBundleExecutable</key>
            <string>../../bin/sh</string>
        </dict>
        </plist>
        """
        try plist.write(to: fakeApp.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)

        #expect(throws: AppUpdateInstallError.self) {
            try AppUpdateInstaller.validateAppBundle(
                at: fakeApp,
                expectedBundleIdentifier: "com.kobenguyent.velora"
            )
        }
    }

    @Test("Verifies code signatures and rejects unsigned, tampered, or mismatched-team bundles")
    func validateCodeSignatureChecks() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("velora-codesign-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let fakeApp = workspace.appendingPathComponent("Velora.app", isDirectory: true)
        let macOSDir = fakeApp.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.kobenguyent.velora</string>
            <key>CFBundleExecutable</key>
            <string>Velora</string>
        </dict>
        </plist>
        """
        try plist.write(to: fakeApp.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)

        let exe = macOSDir.appendingPathComponent("Velora")
        try "#!/bin/sh\nexit 0\n".write(to: exe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)

        // Unsigned must fail when requireSigned is true
        #expect(throws: AppUpdateInstallError.self) {
            try AppUpdateInstaller.validateCodeSignature(at: fakeApp, requireSigned: true, expectedTeamIdentifier: nil)
        }

        // Ad-hoc sign the bundle
        let signProc = Process()
        signProc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signProc.arguments = ["--force", "--deep", "--sign", "-", fakeApp.path]
        try signProc.run()
        signProc.waitUntilExit()
        #expect(signProc.terminationStatus == 0)

        // Valid ad-hoc signed bundle passes
        try AppUpdateInstaller.validateCodeSignature(at: fakeApp, requireSigned: true, expectedTeamIdentifier: nil)
        try AppUpdateInstaller.validateAppBundle(at: fakeApp, expectedBundleIdentifier: "com.kobenguyent.velora")

        // Expected team identifier mismatch fails
        #expect(throws: AppUpdateInstallError.self) {
            try AppUpdateInstaller.validateCodeSignature(at: fakeApp, requireSigned: true, expectedTeamIdentifier: "TEAM123456")
        }

        // Tamper with executable after signing -> validateAppBundle must reject signature
        try "#!/bin/sh\necho pwned\n".write(to: exe, atomically: true, encoding: .utf8)
        #expect(throws: AppUpdateInstallError.self) {
            try AppUpdateInstaller.validateAppBundle(at: fakeApp, expectedBundleIdentifier: "com.kobenguyent.velora")
        }
    }

    @Test("Fails closed on missing SHA256SUMS.txt, HTTP 404, and unmatched manifest entry")
    @MainActor
    func downloadUpdateFailClosedChecksum() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("velora-dl-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let zipData = try makeSyntheticAppZip(in: workspace)
        let zipHash = try AppUpdateInstaller.sha256Hex(of: zipData.fileURL)

        let zipURL = URL(string: "https://github.com/kobenguyent/Velora/releases/download/v2.0.0/Velora-2.0.0-macos-universal.zip")!
        let shaURL = URL(string: "https://github.com/kobenguyent/Velora/releases/download/v2.0.0/SHA256SUMS.txt")!

        let zipAsset = GitHubReleaseAsset(
            id: 1,
            name: "Velora-2.0.0-macos-universal.zip",
            size: Int64(zipData.bytes.count),
            browserDownloadURL: zipURL
        )
        let shaAsset = GitHubReleaseAsset(
            id: 2,
            name: "SHA256SUMS.txt",
            size: 128,
            browserDownloadURL: shaURL
        )
        let release = GitHubRelease(
            tagName: "v2.0.0",
            htmlURL: URL(string: "https://github.com/kobenguyent/Velora/releases/tag/v2.0.0")!,
            assets: [zipAsset, shaAsset]
        )

        // 1. Missing checksumAsset -> fails closed immediately
        let updateWithoutChecksum = AvailableUpdate(
            currentVersion: try #require(SemVer("1.0.0")),
            release: release,
            version: try #require(SemVer("2.0.0")),
            downloadAsset: zipAsset,
            checksumAsset: nil
        )
        let session = makeMockSession { request in
            let url = try #require(request.url)
            if url == zipURL {
                return (200, zipData.bytes)
            }
            return (404, Data())
        }
        let checker = UpdateChecker(urlSession: session)
        await checker.downloadUpdate(updateWithoutChecksum)
        if case .failed = checker.state {
            // expected
        } else {
            Issue.record("Expected .failed state when SHA256SUMS.txt is missing, got \(checker.state)")
        }

        // 2. HTTP 404 on SHA256SUMS.txt -> fails closed
        let updateWithChecksum = AvailableUpdate(
            currentVersion: try #require(SemVer("1.0.0")),
            release: release,
            version: try #require(SemVer("2.0.0")),
            downloadAsset: zipAsset,
            checksumAsset: shaAsset
        )
        await checker.downloadUpdate(updateWithChecksum)
        if case .failed = checker.state {
            // expected
        } else {
            Issue.record("Expected .failed state on HTTP 404 checksum fetch, got \(checker.state)")
        }

        // 3. Unmatched filename in SHA256SUMS.txt -> fails closed
        let unmatchedSession = makeMockSession { request in
            let url = try #require(request.url)
            if url == zipURL {
                return (200, zipData.bytes)
            }
            if url == shaURL {
                let body = "\(zipHash)  OtherFile.zip\n".data(using: .utf8)!
                return (200, body)
            }
            return (404, Data())
        }
        let checkerUnmatched = UpdateChecker(urlSession: unmatchedSession)
        await checkerUnmatched.downloadUpdate(updateWithChecksum)
        if case .failed = checkerUnmatched.state {
            // expected
        } else {
            Issue.record("Expected .failed state when filename is absent from SHA256SUMS.txt, got \(checkerUnmatched.state)")
        }

        // 4. Untrusted URL (non-HTTPS or non-GitHub host) -> fails closed
        let untrustedAsset = GitHubReleaseAsset(
            id: 3,
            name: "Velora-2.0.0-macos-universal.zip",
            size: Int64(zipData.bytes.count),
            browserDownloadURL: URL(string: "https://evil.example.com/Velora-2.0.0-macos-universal.zip")!
        )
        let updateUntrusted = AvailableUpdate(
            currentVersion: try #require(SemVer("1.0.0")),
            release: release,
            version: try #require(SemVer("2.0.0")),
            downloadAsset: untrustedAsset,
            checksumAsset: shaAsset
        )
        await checker.downloadUpdate(updateUntrusted)
        if case .failed = checker.state {
            // expected
        } else {
            Issue.record("Expected .failed state for untrusted host, got \(checker.state)")
        }

        // 5. Valid SHA256SUMS.txt -> succeeds and stages verified update
        let validSession = makeMockSession { request in
            let url = try #require(request.url)
            if url == zipURL {
                return (200, zipData.bytes)
            }
            if url == shaURL {
                let body = "\(zipHash)  Velora-2.0.0-macos-universal.zip\n".data(using: .utf8)!
                return (200, body)
            }
            return (404, Data())
        }
        let checkerValid = UpdateChecker(urlSession: validSession)
        await checkerValid.downloadUpdate(updateWithChecksum)
        if case let .readyToInstall(staged) = checkerValid.state {
            #expect(staged.verifiedSHA256 == zipHash)
            try? FileManager.default.removeItem(at: staged.stagingDirectoryURL)
        } else {
            Issue.record("Expected .readyToInstall state with valid SHA256SUMS.txt, got \(checkerValid.state)")
        }
    }

    private func makeSyntheticAppZip(in workspace: URL) throws -> (fileURL: URL, bytes: Data) {
        let fakeApp = workspace.appendingPathComponent("Velora.app", isDirectory: true)
        let macOSDir = fakeApp.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)

        let bundleID = Bundle.main.bundleIdentifier ?? "com.kobenguyent.velora"
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>\(bundleID)</string>
            <key>CFBundleExecutable</key>
            <string>Velora</string>
        </dict>
        </plist>
        """
        try plist.write(to: fakeApp.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)

        let exe = macOSDir.appendingPathComponent("Velora")
        try "#!/bin/sh\nexit 0\n".write(to: exe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)

        let zipURL = workspace.appendingPathComponent("Velora-2.0.0-macos-universal.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", fakeApp.path, zipURL.path]
        try ditto.run()
        ditto.waitUntilExit()
        #expect(ditto.terminationStatus == 0)
        return (zipURL, try Data(contentsOf: zipURL))
    }

    private func makeMockSession(
        handler: @escaping @Sendable (URLRequest) throws -> (statusCode: Int, data: Data)
    ) -> URLSession {
        let token = MockURLProtocol.register(handler: handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Velora-Mock-ID": token]
        return URLSession(configuration: config)
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (statusCode: Int, data: Data)

    private final class HandlerStore: @unchecked Sendable {
        private let lock = NSLock()
        private var handlers: [String: Handler] = [:]

        func register(_ handler: @escaping Handler) -> String {
            let id = UUID().uuidString
            lock.lock()
            handlers[id] = handler
            lock.unlock()
            return id
        }

        func handler(for id: String) -> Handler? {
            lock.lock()
            let h = handlers[id]
            lock.unlock()
            return h
        }
    }

    private static let store = HandlerStore()

    static func register(handler: @escaping Handler) -> String {
        store.register(handler)
    }

    private static func handler(for request: URLRequest) -> Handler? {
        guard let id = request.value(forHTTPHeaderField: "X-Velora-Mock-ID") else { return nil }
        return store.handler(for: id)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler(for: request), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": "\(data.count)"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
