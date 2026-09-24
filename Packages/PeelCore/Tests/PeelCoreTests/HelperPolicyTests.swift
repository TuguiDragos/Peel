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

    /// Which one is compiled in follows the build, so a shipped helper can never be handed the looser text.
    @Test func theTextInUseFollowsTheBuild() {
        let inUse = CodeSigning.requirement(identifier: "com.tuguidragos.Peel", teamIdentifier: "6R6J264YA2")
        #expect(inUse.contains("100.6.1.12") == CodeSigning.isADebugBuild)
    }
}
