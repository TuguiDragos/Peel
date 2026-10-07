import Foundation
@testable import PeelPrivileged
import Security
import Testing

struct HelperPolicyTests {
    /// What the root helper accepts as its app, and what the app accepts as its helper. A shipped build must be
    /// Developer ID and not debuggable: an Apple Development build carries `get-task-allow`, so any process of
    /// the same user could take control of it and, through it, move files as root.
    @Test func theShippedRequirementTakesOnlyADeveloperIDBuildThatIsNotDebuggable() throws {
        let shipped = CodeSigning.requirement(
            identifier: "com.tuguidragos.Peel",
            teamIdentifier: "6R6J264YA2",
            allowingDevelopmentBuilds: false
        )

        #expect(shipped.contains("certificate 1[field.1.2.840.113635.100.6.2.6]"), "the Developer ID authority is not named")
        #expect(shipped.contains("certificate leaf[field.1.2.840.113635.100.6.1.13]"))
        #expect(shipped.contains("! entitlement[\"com.apple.security.get-task-allow\"] exists"))
        #expect(!shipped.contains("100.6.1.12"), "an Apple Development build satisfies the shipped requirement")

        // A Debug build also accepts an Apple Development certificate, for the Debug build beside it.
        let development = CodeSigning.requirement(
            identifier: "com.tuguidragos.Peel",
            teamIdentifier: "6R6J264YA2",
            allowingDevelopmentBuilds: true
        )
        #expect(development.contains("100.6.1.12"))
        #expect(development.hasPrefix("identifier \"com.tuguidragos.Peel\" and anchor apple generic"))

        // Both are the requirement language, not strings that only look like it.
        for text in [shipped, development] {
            var requirement: SecRequirement?
            #expect(SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, "\(text) is not a requirement")
        }
    }

    @Test func theHelperServesNoCopyOfPeelOlderThanItself() {
        for allowing in [false, true] {
            let text = CodeSigning.requirement(
                identifier: "com.tuguidragos.Peel",
                teamIdentifier: "6R6J264YA2",
                allowingDevelopmentBuilds: allowing,
                minimumBuild: "261006"
            )
            #expect(text.contains("info[CFBundleVersion] >= \"261006\""), "an older Peel is served")
            var requirement: SecRequirement?
            #expect(SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess)
        }
    }

    @Test func aBuildFloorRefusesOlderCode() throws {
        let calculator = URL(filePath: "/System/Applications/Calculator.app")
        var code: SecStaticCode?
        #expect(SecStaticCodeCreateWithPath(calculator as CFURL, [], &code) == errSecSuccess)
        let signed = try #require(code)
        let build = try #require(CodeSigning.build(of: signed))
        #expect(build == Bundle(url: calculator)?.infoDictionary?["CFBundleVersion"] as? String)

        let satisfies = { (text: String) -> Bool in
            var requirement: SecRequirement?
            guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else {
                return false
            }
            return SecStaticCodeCheckValidity(signed, [], requirement) == errSecSuccess
        }
        #expect(satisfies("info[CFBundleVersion] >= \"\(build)\""))
        #expect(!satisfies("info[CFBundleVersion] >= \"\(build)9\""), "a floor above the build let the code through")
    }

    /// The team in `SpawnConstraint` has to be the one every target of the project signs with.
    @Test func launchdStartsOnlyTheTeamsOwnHelper() throws {
        let repository = StringCatalogTests.repository
        let plist = try Data(contentsOf: repository.appending(path: "Support/\(HelperIdentity.launchdPlistName)"))
        let job = try #require(try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any])
        let project = try String(contentsOf: repository.appending(path: "Peel.xcodeproj/project.pbxproj"), encoding: .utf8)
        let teams = Set(project.matches(of: /DEVELOPMENT_TEAM = (\w+);/).map { String($0.output.1) })

        let constraint = try #require(job["SpawnConstraint"] as? [String: String], "launchd would start any code as the helper")
        #expect(teams.count == 1)
        let team = try #require(teams.first)
        #expect(constraint == ["team-identifier": team, "signing-identifier": HelperIdentity.helperIdentifier])
    }

    /// Which one is compiled in follows the build, so a shipped helper can never be handed the looser text.
    @Test func theTextInUseFollowsTheBuild() {
        let inUse = CodeSigning.requirement(identifier: "com.tuguidragos.Peel", teamIdentifier: "6R6J264YA2")
        #expect(inUse.contains("100.6.1.12") == CodeSigning.isADebugBuild)
    }
}
