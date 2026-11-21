import Foundation

public struct GitHubReleaseAsset: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let contentType: String?
    public let size: Int64
    public let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case contentType = "content_type"
        case size
        case browserDownloadURL = "browser_download_url"
    }

    public init(
        id: Int,
        name: String,
        contentType: String? = nil,
        size: Int64,
        browserDownloadURL: URL
    ) {
        self.id = id
        self.name = name
        self.contentType = contentType
        self.size = size
        self.browserDownloadURL = browserDownloadURL
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

public struct GitHubRelease: Codable, Sendable, Equatable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let draft: Bool
    public let prerelease: Bool
    public let publishedAt: Date?
    public let htmlURL: URL
    public let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case draft
        case prerelease
        case publishedAt = "published_at"
        case htmlURL = "html_url"
        case assets
    }

    public init(
        tagName: String,
        name: String? = nil,
        body: String? = nil,
        draft: Bool = false,
        prerelease: Bool = false,
        publishedAt: Date? = nil,
        htmlURL: URL,
        assets: [GitHubReleaseAsset] = []
    ) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.draft = draft
        self.prerelease = prerelease
        self.publishedAt = publishedAt
        self.htmlURL = htmlURL
        self.assets = assets
    }

    public var semanticVersion: SemVer? {
        SemVer(tagName)
    }

    public var displayTitle: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return tagName
    }
}

public struct AvailableUpdate: Sendable, Equatable {
    public let currentVersion: SemVer
    public let release: GitHubRelease
    public let version: SemVer
    public let downloadAsset: GitHubReleaseAsset
    public let checksumAsset: GitHubReleaseAsset?

    public init(
        currentVersion: SemVer,
        release: GitHubRelease,
        version: SemVer,
        downloadAsset: GitHubReleaseAsset,
        checksumAsset: GitHubReleaseAsset?
    ) {
        self.currentVersion = currentVersion
        self.release = release
        self.version = version
        self.downloadAsset = downloadAsset
        self.checksumAsset = checksumAsset
    }
}

public struct StagedUpdate: Sendable, Equatable {
    public let update: AvailableUpdate
    public let stagedAppURL: URL
    public let stagingDirectoryURL: URL
    public let verifiedSHA256: String?

    public init(
        update: AvailableUpdate,
        stagedAppURL: URL,
        stagingDirectoryURL: URL,
        verifiedSHA256: String?
    ) {
        self.update = update
        self.stagedAppURL = stagedAppURL
        self.stagingDirectoryURL = stagingDirectoryURL
        self.verifiedSHA256 = verifiedSHA256
    }
}

/// Pure, testable logic for selecting macOS release assets, parsing SHA256SUMS, and deciding whether to update.
public enum ReleaseAssetMatcher {

    public static var currentArchitectureToken: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "universal"
        #endif
    }

    /// Picks the best macOS `.zip` bundle artifact for in-app self-updating.
    public static func selectBestZipAsset(
        from assets: [GitHubReleaseAsset],
        architecture: String = currentArchitectureToken
    ) -> GitHubReleaseAsset? {
        let zipAssets = assets.filter { $0.name.lowercased().hasSuffix(".zip") }
        guard !zipAssets.isEmpty else { return nil }

        // Priority 1: explicit universal macOS zip
        if let universal = zipAssets.first(where: {
            let lower = $0.name.lowercased()
            return lower.contains("universal") && (lower.contains("macos") || lower.contains("darwin") || lower.contains("velora"))
        }) {
            return universal
        }

        // Priority 2: current CPU architecture zip
        let archLower = architecture.lowercased()
        let archAliases = archLower == "arm64" ? ["arm64", "aarch64", "apple-silicon"] : ["x86_64", "amd64", "intel"]
        if let archMatch = zipAssets.first(where: { asset in
            let lower = asset.name.lowercased()
            return archAliases.contains(where: { lower.contains($0) })
        }) {
            return archMatch
        }

        // Priority 3: any macOS zip or Velora zip
        if let macMatch = zipAssets.first(where: {
            let lower = $0.name.lowercased()
            return lower.contains("macos") || lower.contains("velora")
        }) {
            return macMatch
        }

        return zipAssets.first
    }

    /// Finds an accompanying SHA-256 checksum manifest if uploaded to the GitHub Release.
    public static func selectChecksumAsset(from assets: [GitHubReleaseAsset]) -> GitHubReleaseAsset? {
        assets.first { asset in
            let lower = asset.name.lowercased()
            return lower.contains("sha256") || lower.contains("checksums")
        }
    }

    /// Parses standard `shasum -a 256` format: `<64-hex-chars>  <filename>`
    public static func extractExpectedSHA256(forFileName fileName: String, from manifestText: String) -> String? {
        let targetName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        for rawLine in manifestText.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { continue }
            let hash = String(parts[0]).lowercased()
            var candidateName = String(parts[1]).trimmingCharacters(in: .whitespaces)
            if candidateName.hasPrefix("*") {
                candidateName.removeFirst()
            }
            let baseName = URL(fileURLWithPath: candidateName).lastPathComponent
            if hash.count == 64 && (candidateName == targetName || baseName == targetName) {
                return hash
            }
        }
        return nil
    }

    /// Picks the newest eligible release from a GitHub releases array.
    public static func selectLatestRelease(
        from releases: [GitHubRelease],
        includePrereleases: Bool
    ) -> GitHubRelease? {
        releases
            .filter { !$0.draft && (includePrereleases || !$0.prerelease) }
            .compactMap { release -> (GitHubRelease, SemVer)? in
                guard let ver = release.semanticVersion else { return nil }
                return (release, ver)
            }
            .max { lhs, rhs in lhs.1 < rhs.1 }?
            .0
    }

    /// Evaluates whether a fetched GitHub release represents a newer installable update.
    public static func evaluateUpdate(
        currentVersion: SemVer,
        release: GitHubRelease,
        architecture: String = currentArchitectureToken
    ) -> AvailableUpdate? {
        guard !release.draft,
              let remoteVersion = release.semanticVersion,
              remoteVersion > currentVersion,
              let zipAsset = selectBestZipAsset(from: release.assets, architecture: architecture) else {
            return nil
        }

        return AvailableUpdate(
            currentVersion: currentVersion,
            release: release,
            version: remoteVersion,
            downloadAsset: zipAsset,
            checksumAsset: selectChecksumAsset(from: release.assets)
        )
    }
}
