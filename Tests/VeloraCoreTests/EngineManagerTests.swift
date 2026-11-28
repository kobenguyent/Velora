import CryptoKit
import Foundation
import Testing
@testable import VeloraCore

@Suite("Engine Manager & Process Supervisor")
struct EngineManagerTests {

    @Test("ProcessLineAccumulator handles CRLF, partial chunks, invalid UTF-8, and 256 KB cap")
    func processLineAccumulatorEdgeCases() {
        let acc = ProcessLineAccumulator()

        // Partial chunk + CRLF + CR
        #expect(acc.append(Data("hel".utf8)) == [])
        #expect(acc.append(Data("lo\r\nworld\rnext".utf8)) == ["hello", "world"])
        #expect(acc.flush() == ["next"])

        // Invalid UTF-8 bytes recover lossily instead of dropping the line
        let invalidUTF8 = Data([0x41, 0xFF, 0xFE, 0x42, 0x0A])
        let recovered = acc.append(invalidUTF8)
        #expect(recovered.count == 1)
        #expect(recovered[0].hasPrefix("A"))
        #expect(recovered[0].hasSuffix("B"))
        #expect(recovered[0].contains("\u{FFFD}"))

        // 256 KB cap prevents unbounded memory growth on newline-less floods
        let oversized = Data(repeating: UInt8(ascii: "x"), count: 300_000)
        let capped = acc.append(oversized)
        #expect(capped.count == 1)
        #expect(capped[0].utf8.count == 256 * 1024)
        #expect(acc.append(Data("tail\n".utf8)) == [])
        #expect(acc.append(Data("after\n".utf8)) == ["after"])
    }

    @Test("enrichedEnvironment places system and Homebrew paths before managed and user directories")
    func enrichedEnvironmentOrdering() throws {
        let env = EngineManager.enrichedEnvironment()
        let pathEntries = (env["PATH"] ?? "").split(separator: ":").map(String.init)

        let usrBinIdx = try #require(pathEntries.firstIndex(of: "/usr/bin"))
        let homebrewIdx = try #require(pathEntries.firstIndex(of: "/opt/homebrew/bin"))
        let managedIdx = try #require(pathEntries.firstIndex(of: EngineManager.managedBinDirectory.path))
        let localBinIdx = try #require(pathEntries.firstIndex(of: "\(NSHomeDirectory())/.local/bin"))

        #expect(usrBinIdx < managedIdx)
        #expect(homebrewIdx < managedIdx)
        #expect(managedIdx < localBinIdx)
    }

    @Test("installViaHomebrew strictly enforces yt-dlp/ffmpeg/deno package allowlist")
    @MainActor
    func homebrewAllowlist() async {
        let tempBin = FileManager.default.temporaryDirectory
            .appendingPathComponent("velora-brew-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempBin) }

        let manager = EngineManager(urlSession: .shared, binDirectory: tempBin)
        await manager.refresh()
        await manager.installViaHomebrew(packages: ["yt-dlp", "--HEAD"])
        #expect(manager.lastError != nil)
    }

    @Test("installOrUpdateManagedYTDLP verifies SHA2-256SUMS and fails closed on mismatch or missing entry")
    @MainActor
    func managedYTDLPInstallationAndFailClosed() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("velora-ytdlp-inst-\(UUID().uuidString)", isDirectory: true)
        let binDir = workspace.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let payload = Data("#!/bin/sh\necho 2026.01.01\n".utf8)
        let digest = sha256Hex(payload)
        let manifest = Data("\(digest)  yt-dlp_macos\n".utf8)

        let session = makeMockSession { request in
            switch request.url?.lastPathComponent {
            case "yt-dlp_macos":
                return (200, payload, request.url!)
            case "SHA2-256SUMS":
                return (200, manifest, request.url!)
            default:
                return (404, Data(), request.url!)
            }
        }

        let manager = EngineManager(urlSession: session, binDirectory: binDir)
        await manager.installOrUpdateManagedYTDLP()
        #expect(manager.lastError == nil)
        let installedPath = binDir.appendingPathComponent("yt-dlp").path
        #expect(FileManager.default.isExecutableFile(atPath: installedPath))
        #expect(try Data(contentsOf: URL(fileURLWithPath: installedPath)) == payload)

        // Mismatch must fail closed without overwriting existing binary
        let tamperedPayload = Data("#!/bin/sh\necho pwned\n".utf8)
        let badSession = makeMockSession { request in
            switch request.url?.lastPathComponent {
            case "yt-dlp_macos":
                return (200, tamperedPayload, request.url!)
            case "SHA2-256SUMS":
                return (200, manifest, request.url!)
            default:
                return (404, Data(), request.url!)
            }
        }
        let failingManager = EngineManager(urlSession: badSession, binDirectory: binDir)
        await failingManager.installOrUpdateManagedYTDLP()
        #expect(failingManager.lastError != nil)
        #expect(try Data(contentsOf: URL(fileURLWithPath: installedPath)) == payload)

        // Missing entry in manifest must fail closed
        let missingEntrySession = makeMockSession { request in
            switch request.url?.lastPathComponent {
            case "yt-dlp_macos":
                return (200, payload, request.url!)
            case "SHA2-256SUMS":
                return (200, Data("\(digest)  yt-dlp_linux\n".utf8), request.url!)
            default:
                return (404, Data(), request.url!)
            }
        }
        let missingBinDir = workspace.appendingPathComponent("bin-missing", isDirectory: true)
        let missingManager = EngineManager(urlSession: missingEntrySession, binDirectory: missingBinDir)
        await missingManager.installOrUpdateManagedYTDLP()
        #expect(missingManager.lastError != nil)
        #expect(!FileManager.default.fileExists(atPath: missingBinDir.appendingPathComponent("yt-dlp").path))
    }

    @Test("installOrUpdateManagedFFmpeg verifies SHA-256 and rejects symlinked zip entries")
    @MainActor
    func managedFFmpegInstallationAndSymlinkRejection() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("velora-ffmpeg-inst-\(UUID().uuidString)", isDirectory: true)
        let binDir = workspace.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let ffmpegData = Data("#!/bin/sh\necho ffmpeg version 7.1\n".utf8)
        let ffprobeData = Data("#!/bin/sh\necho ffprobe version 7.1\n".utf8)
        let ffmpegZip = try createExecutableZip(name: "ffmpeg", contents: ffmpegData, in: workspace)
        let ffprobeZip = try createExecutableZip(name: "ffprobe", contents: ffprobeData, in: workspace)
        let ffmpegSHA = Data("\(sha256Hex(ffmpegZip))  ffmpeg.zip\n".utf8)
        let ffprobeSHA = Data("\(sha256Hex(ffprobeZip))\n".utf8)

        let session = makeMockSession { request in
            let urlStr = request.url!.absoluteString
            if urlStr.hasSuffix("/ffmpeg.zip") {
                let resolved = URL(string: "https://ffmpeg.martin-riedl.de/download/macos/ffmpeg.zip")!
                return (200, ffmpegZip, resolved)
            } else if urlStr == "https://ffmpeg.martin-riedl.de/download/macos/ffmpeg.zip.sha256" {
                return (200, ffmpegSHA, request.url!)
            } else if urlStr.hasSuffix("/ffprobe.zip") {
                let resolved = URL(string: "https://ffmpeg.martin-riedl.de/download/macos/ffprobe.zip")!
                return (200, ffprobeZip, resolved)
            } else if urlStr == "https://ffmpeg.martin-riedl.de/download/macos/ffprobe.zip.sha256" {
                return (200, ffprobeSHA, request.url!)
            }
            return (404, Data(), request.url!)
        }

        let manager = EngineManager(urlSession: session, binDirectory: binDir)
        await manager.installOrUpdateManagedFFmpeg()
        #expect(manager.lastError == nil)
        #expect(FileManager.default.isExecutableFile(atPath: binDir.appendingPathComponent("ffmpeg").path))
        #expect(FileManager.default.isExecutableFile(atPath: binDir.appendingPathComponent("ffprobe").path))

        // Symlink inside zip must be rejected even with valid SHA-256
        let symlinkZip = try createSymlinkZip(name: "ffmpeg", in: workspace)
        let symlinkSHA = Data("\(sha256Hex(symlinkZip))\n".utf8)
        let symlinkBinDir = workspace.appendingPathComponent("bin-symlink", isDirectory: true)
        let symlinkSession = makeMockSession { request in
            let urlStr = request.url!.absoluteString
            if urlStr.hasSuffix("/ffmpeg.zip") {
                return (200, symlinkZip, request.url!)
            } else if urlStr.hasSuffix("/ffmpeg.zip.sha256") {
                return (200, symlinkSHA, request.url!)
            }
            return (404, Data(), request.url!)
        }
        let symlinkManager = EngineManager(urlSession: symlinkSession, binDirectory: symlinkBinDir)
        await symlinkManager.installOrUpdateManagedFFmpeg()
        #expect(symlinkManager.lastError != nil)
        #expect(!FileManager.default.fileExists(atPath: symlinkBinDir.appendingPathComponent("ffmpeg").path))
    }

    @Test("installOrUpdateManagedDeno verifies SHA-256 and installs deno binary")
    @MainActor
    func managedDenoInstallation() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("velora-deno-inst-\(UUID().uuidString)", isDirectory: true)
        let binDir = workspace.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let denoData = Data("#!/bin/sh\necho deno 2.2.0\n".utf8)
        let denoZip = try createExecutableZip(name: "deno", contents: denoData, in: workspace)
        let expectedDigest = sha256Hex(denoZip)

        let session = makeMockSession { request in
            let path = request.url!.path
            if path.hasSuffix(".zip") {
                return (200, denoZip, request.url!)
            } else if path.hasSuffix(".sha256sum") {
                let archiveName = request.url!.lastPathComponent.replacingOccurrences(of: ".sha256sum", with: "")
                let denoSHA = Data("\(expectedDigest)  \(archiveName)\n".utf8)
                return (200, denoSHA, request.url!)
            }
            return (404, Data(), request.url!)
        }

        let manager = EngineManager(urlSession: session, binDirectory: binDir)
        await manager.installOrUpdateManagedDeno()
        #expect(manager.lastError == nil)
        #expect(FileManager.default.isExecutableFile(atPath: binDir.appendingPathComponent("deno").path))

        // Checksum mismatch must fail closed without installing
        let badSession = makeMockSession { request in
            let path = request.url!.path
            if path.hasSuffix(".zip") {
                return (200, denoZip, request.url!)
            } else if path.hasSuffix(".sha256sum") {
                let archiveName = request.url!.lastPathComponent.replacingOccurrences(of: ".sha256sum", with: "")
                let wrongSHA = Data("\(String(repeating: "0", count: 64))  \(archiveName)\n".utf8)
                return (200, wrongSHA, request.url!)
            }
            return (404, Data(), request.url!)
        }
        let failBin = workspace.appendingPathComponent("bin-fail", isDirectory: true)
        let failManager = EngineManager(urlSession: badSession, binDirectory: failBin)
        await failManager.installOrUpdateManagedDeno()
        #expect(failManager.lastError != nil)
        #expect(!FileManager.default.fileExists(atPath: failBin.appendingPathComponent("deno").path))
    }

    @Test("ProcessSupervisor collects stdout/stderr and terminates timed-out process groups")
    func processSupervisorCollectionAndTimeout() async {
        let ok = await ProcessSupervisor.runCollectingOutput(
            executable: "/bin/echo",
            arguments: ["velora-ok"],
            environment: EngineManager.enrichedEnvironment(),
            timeoutSeconds: 5
        )
        #expect(ok.exitCode == 0)
        #expect(!ok.timedOut)
        #expect(String(decoding: ok.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "velora-ok")

        let timedOut = await ProcessSupervisor.runCollectingOutput(
            executable: "/bin/sleep",
            arguments: ["5"],
            environment: EngineManager.enrichedEnvironment(),
            timeoutSeconds: 0.2
        )
        #expect(timedOut.timedOut)
    }

    @Test("Normalizes CLI version output and compares numeric versions accurately")
    func versionNormalizationAndComparison() {
        #expect(EngineManager.normalizeVersion("2026.11.23", for: "yt-dlp") == "2026.11.23")
        #expect(EngineManager.normalizeVersion("ffmpeg version 9.1-https://www.martin-riedl.de Copyright (c)", for: "ffmpeg") == "9.1")
        #expect(EngineManager.normalizeVersion("deno 2.9.8 (stable, release, aarch64-apple-darwin)", for: "deno") == "2.9.8")
        #expect(EngineManager.normalizeVersion("v22.12.0", for: "node") == "22.12.0")

        #expect(EngineManager.compareVersions("9.1", "9.1.0") == .orderedSame)
        #expect(EngineManager.compareVersions("2026.11.09", "2026.11.23") == .orderedAscending)
        #expect(EngineManager.compareVersions("2.9.7", "2.9.8") == .orderedAscending)
        #expect(EngineManager.compareVersions("9.2", "9.1") == .orderedDescending)

        #expect(EngineManager.parseLatestVersion(fromRedirectLocation: "https://github.com/yt-dlp/yt-dlp/releases/tag/2026.11.23", for: "yt-dlp") == "2026.11.23")
        #expect(EngineManager.parseLatestVersion(fromRedirectLocation: "/download/macos/arm64/1795207104_9.1/ffmpeg.zip", for: "ffmpeg") == "9.1")
        #expect(EngineManager.parseLatestVersion(fromRedirectLocation: "https://github.com/denoland/deno/releases/tag/v2.9.8", for: "deno") == "2.9.8")
    }

    @Test("checkForEngineUpdates detects outdated vs up-to-date engines and installMissingOrOutdatedManagedEngines skips current ones")
    @MainActor
    func updateCheckAndSelectiveInstaller() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("velora-update-check-\(UUID().uuidString)", isDirectory: true)
        let binDir = workspace.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        func writeScript(_ name: String, output: String) throws {
            let url = binDir.appendingPathComponent(name)
            try Data("#!/bin/sh\necho '\(output)'\n".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        // yt-dlp outdated (2026.11.09 vs 2026.11.23), ffmpeg current (9.1 vs 9.1), deno missing
        try writeScript("yt-dlp", output: "2026.11.09")
        try writeScript("ffmpeg", output: "ffmpeg version 9.1-https://www.martin-riedl.de")

        let newYTDLPPayload = Data("#!/bin/sh\necho '2026.11.23'\n".utf8)
        let ytdlpDigest = sha256Hex(newYTDLPPayload)
        let ytdlpManifest = Data("\(ytdlpDigest)  yt-dlp_macos\n".utf8)

        let denoPayload = Data("#!/bin/sh\necho 'deno 2.9.8 (stable, release, aarch64-apple-darwin)'\n".utf8)
        let denoZip = try createExecutableZip(name: "deno", contents: denoPayload, in: workspace)
        let denoDigest = sha256Hex(denoZip)

        let session = makeMockSession { request in
            let urlStr = request.url!.absoluteString
            if urlStr == "https://github.com/yt-dlp/yt-dlp/releases/latest" {
                return (
                    302,
                    Data(),
                    request.url!,
                    ["Location": "https://github.com/yt-dlp/yt-dlp/releases/tag/2026.11.23"]
                )
            } else if urlStr.hasSuffix("/release/ffmpeg.zip") {
                return (
                    307,
                    Data(),
                    request.url!,
                    ["Location": "/download/macos/arm64/1795207104_9.1/ffmpeg.zip"]
                )
            } else if urlStr == "https://github.com/denoland/deno/releases/latest" {
                return (
                    302,
                    Data(),
                    request.url!,
                    ["Location": "https://github.com/denoland/deno/releases/tag/v2.9.8"]
                )
            } else if request.url?.lastPathComponent == "yt-dlp_macos" {
                return (200, newYTDLPPayload, request.url!, [:])
            } else if request.url?.lastPathComponent == "SHA2-256SUMS" {
                return (200, ytdlpManifest, request.url!, [:])
            } else if urlStr.contains("/deno-") && urlStr.hasSuffix(".zip") {
                return (200, denoZip, request.url!, [:])
            } else if urlStr.contains("/deno-") && urlStr.hasSuffix(".sha256sum") {
                let archiveName = request.url!.lastPathComponent.replacingOccurrences(of: ".sha256sum", with: "")
                return (200, Data("\(denoDigest)  \(archiveName)\n".utf8), request.url!, [:])
            }
            // ffmpeg archive should NEVER be fetched by selective update because ffmpeg is already 9.1
            if urlStr.contains("/download/macos/") {
                Issue.record("Unexpected download for up-to-date ffmpeg")
            }
            return (404, Data(), request.url!, [:])
        }

        let manager = EngineManager(urlSession: session, binDirectory: binDir)
        await manager.refresh()
        await manager.checkForEngineUpdates()

        #expect(manager.ytdlpUpdateState == .updateAvailable(installed: "2026.11.09", latest: "2026.11.23"))
        #expect(manager.ffmpegUpdateState == .upToDate(latest: "9.1"))
        #expect(manager.outdatedEngineCount == 1)
        #expect(manager.missingEngineCount >= 0)

        // Make sure JS runtime state reflects notInstalled when deno isn't in PATH or if external node exists
        let beforeFFmpegBytes = try Data(contentsOf: binDir.appendingPathComponent("ffmpeg"))
        await manager.installMissingOrOutdatedManagedEngines()
        #expect(manager.lastError == nil)
        #expect(manager.ytdlpUpdateState == .upToDate(latest: "2026.11.23"))
        #expect(manager.ffmpegUpdateState == .upToDate(latest: "9.1"))
        #expect(try Data(contentsOf: binDir.appendingPathComponent("ffmpeg")) == beforeFFmpegBytes)
        #expect(manager.installLogs.contains(where: { $0.contains("ffmpeg is already up to date (9.1), skipping.") }))
    }

    // MARK: - Helpers

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func createExecutableZip(name: String, contents: Data, in workspace: URL) throws -> Data {
        let stage = workspace.appendingPathComponent("zip-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        let bin = stage.appendingPathComponent(name)
        try contents.write(to: bin)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)

        let zipURL = workspace.appendingPathComponent("\(name)-\(UUID().uuidString).zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", bin.path, zipURL.path]
        try ditto.run()
        ditto.waitUntilExit()
        #expect(ditto.terminationStatus == 0)
        return try Data(contentsOf: zipURL)
    }

    private func createSymlinkZip(name: String, in workspace: URL) throws -> Data {
        let stage = workspace.appendingPathComponent("zip-sym-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        let linkURL = stage.appendingPathComponent(name)
        try FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: "/bin/sh")

        let zipURL = workspace.appendingPathComponent("\(name)-sym-\(UUID().uuidString).zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", stage.path, zipURL.path]
        try ditto.run()
        ditto.waitUntilExit()
        #expect(ditto.terminationStatus == 0)
        return try Data(contentsOf: zipURL)
    }

    private func makeMockSession(
        handler: @escaping @Sendable (URLRequest) throws -> (statusCode: Int, data: Data, responseURL: URL)
    ) -> URLSession {
        makeMockSession { request in
            let (statusCode, data, responseURL) = try handler(request)
            return (statusCode, data, responseURL, [:])
        }
    }

    private func makeMockSession(
        handler: @escaping @Sendable (URLRequest) throws -> (statusCode: Int, data: Data, responseURL: URL, headers: [String: String])
    ) -> URLSession {
        let token = EngineMockURLProtocol.register(handler: handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EngineMockURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Velora-Engine-Mock-ID": token]
        return URLSession(configuration: config)
    }
}

private final class EngineMockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (statusCode: Int, data: Data, responseURL: URL, headers: [String: String])

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
        guard let id = request.value(forHTTPHeaderField: "X-Velora-Engine-Mock-ID") else { return nil }
        return store.handler(for: id)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler(for: request), request.url != nil else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (statusCode, data, responseURL, customHeaders) = try handler(request)
            var headerFields = customHeaders
            headerFields["Content-Length"] = "\(data.count)"
            let response = HTTPURLResponse(
                url: responseURL,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headerFields
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
