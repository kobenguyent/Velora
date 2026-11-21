import Foundation

/// Semantic Version (SemVer 2.0.0) parser and comparator supporting optional leading `v`,
/// pre-release identifiers (e.g. `1.2.0-beta.1`), and build metadata (`+20261121`).
public struct SemVer: Sendable, Hashable, Comparable, CustomStringConvertible, Codable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: [String]
    public let buildMetadata: String?

    public init(
        major: Int,
        minor: Int,
        patch: Int,
        prerelease: [String] = [],
        buildMetadata: String? = nil
    ) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.buildMetadata = buildMetadata
    }

    public init?(_ raw: String) {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            trimmed.removeFirst()
        }
        guard !trimmed.isEmpty else { return nil }

        let buildSplit = trimmed.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        let withoutBuild = String(buildSplit[0])
        let build = buildSplit.count > 1 ? String(buildSplit[1]) : nil
        if let build, build.isEmpty { return nil }

        let preSplit = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let corePart = String(preSplit[0])
        let prePart = preSplit.count > 1 ? String(preSplit[1]) : nil

        let numbers = corePart.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(numbers.count) else { return nil }
        guard let major = Int(numbers[0]), major >= 0,
              let minor = Int(numbers[1]), minor >= 0 else {
            return nil
        }
        let patch: Int
        if numbers.count == 3 {
            guard let parsedPatch = Int(numbers[2]), parsedPatch >= 0 else { return nil }
            patch = parsedPatch
        } else {
            patch = 0
        }

        var preIdentifiers: [String] = []
        if let prePart {
            guard !prePart.isEmpty else { return nil }
            let ids = prePart.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard !ids.contains(where: \.isEmpty) else { return nil }
            preIdentifiers = ids
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = preIdentifiers
        self.buildMetadata = build
    }

    public var isPrerelease: Bool {
        !prerelease.isEmpty
    }

    public var description: String {
        var base = "\(major).\(minor).\(patch)"
        if !prerelease.isEmpty {
            base += "-" + prerelease.joined(separator: ".")
        }
        if let buildMetadata {
            base += "+\(buildMetadata)"
        }
        return base
    }

    public static func == (lhs: SemVer, rhs: SemVer) -> Bool {
        lhs.major == rhs.major &&
        lhs.minor == rhs.minor &&
        lhs.patch == rhs.patch &&
        lhs.prerelease == rhs.prerelease
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(major)
        hasher.combine(minor)
        hasher.combine(patch)
        hasher.combine(prerelease)
    }

    public static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        // Per SemVer 2.0.0: normal version has higher precedence than a pre-release version.
        if lhs.prerelease.isEmpty && rhs.prerelease.isEmpty { return false }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }

        let count = min(lhs.prerelease.count, rhs.prerelease.count)
        for index in 0..<count {
            let left = lhs.prerelease[index]
            let right = rhs.prerelease[index]
            if left == right { continue }

            let leftInt = Int(left)
            let rightInt = Int(right)
            switch (leftInt, rightInt) {
            case let (l?, r?):
                return l < r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return left < right
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}
