import Testing
@testable import VeloraCore

@Suite("SemVer Parsing and Ordering")
struct SemVerTests {
    @Test("Parses valid version formats and rejects malformed versions")
    func parsingVariants() {
        #expect(SemVer("1.2.3") == SemVer(major: 1, minor: 2, patch: 3))
        #expect(SemVer("v2.0.1") == SemVer(major: 2, minor: 0, patch: 1))
        #expect(SemVer("V3.4") == SemVer(major: 3, minor: 4, patch: 0))
        #expect(SemVer("1.0.0-beta.2+build42")?.prerelease == ["beta", "2"])
        #expect(SemVer("1.0.0-beta.2+build42")?.buildMetadata == "build42")

        #expect(SemVer("") == nil)
        #expect(SemVer("v") == nil)
        #expect(SemVer("1") == nil)
        #expect(SemVer("1.2.3.4") == nil)
        #expect(SemVer("1.2.3-") == nil)
        #expect(SemVer("1.2.3+") == nil)
    }

    @Test("Compares semantic versions and prerelease precedence per SemVer 2.0.0")
    func orderingAndPrereleasePrecedence() throws {
        let v100Alpha1 = try #require(SemVer("1.0.0-alpha.1"))
        let v100Alpha2 = try #require(SemVer("1.0.0-alpha.2"))
        let v100Alpha10 = try #require(SemVer("1.0.0-alpha.10"))
        let v100Beta1 = try #require(SemVer("1.0.0-beta.1"))
        let v100 = try #require(SemVer("1.0.0"))
        let v101 = try #require(SemVer("1.0.1"))
        let v110 = try #require(SemVer("1.1.0"))
        let v200 = try #require(SemVer("2.0.0"))

        #expect(v100Alpha1 < v100Alpha2)
        #expect(v100Alpha2 < v100Alpha10)
        #expect(v100Alpha10 < v100Beta1)
        #expect(v100Beta1 < v100)
        #expect(v100 < v101)
        #expect(v101 < v110)
        #expect(v110 < v200)

        let b1 = try #require(SemVer("1.2.3+build1"))
        let b2 = try #require(SemVer("1.2.3+build2"))
        #expect(b1 == b2)
        #expect(!(b1 < b2))
    }
}
