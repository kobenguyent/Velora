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
        #expect(script.contains("--swap-only"))
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
}
