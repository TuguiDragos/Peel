import Foundation
import Security

public enum CodeSigning {
    /// The markers Apple puts in the leaf of a Developer ID Application certificate and in the leaf of an
    /// Apple Development certificate. Naming them stops any other certificate issued to the same team, such
    /// as an installer or App Store one, from satisfying a requirement that only names the team.
    private static let developerIDLeaf = "field.1.2.840.113635.100.6.1.13"
    private static let developmentLeaf = "field.1.2.840.113635.100.6.1.12"

    /// The team identifier of the running process, or nil for an ad hoc or unsigned build. It is read once,
    /// since it cannot change while the process runs.
    public static let currentTeam: String? = readCurrentTeamIdentifier()

    public static func currentTeamIdentifier() -> String? {
        currentTeam
    }

    private static func readCurrentTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        guard
            SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)), &information) == errSecSuccess,
            let team = (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String,
            isValidTeamIdentifier(team)
        else { return nil }
        return team
    }

    /// The marker Apple puts in the Developer ID Certification Authority certificate, one up from the leaf
    /// (TN3127). Naming it as well pins the whole chain a shipped Peel is signed through.
    private static let developerIDAuthority = "field.1.2.840.113635.100.6.2.6"

    /// A requirement matching code with `identifier` signed by `teamIdentifier` through Apple's certificate
    /// chain.
    ///
    /// Outside a Debug build, it accepts only a Developer ID build that is not debuggable. An Apple
    /// Development build carries `get-task-allow`, so any process of the same user can control it, and
    /// accepting one would let that process move files as root through the helper. A Debug build also
    /// accepts the Apple Development certificate, since both sides are then Debug builds.
    public static func requirement(identifier: String, teamIdentifier: String) -> String {
        requirement(identifier: identifier, teamIdentifier: teamIdentifier, allowingDevelopmentBuilds: isADebugBuild)
    }

    /// Builds either requirement, so a test in a Debug build can check the one a shipped Peel uses.
    static func requirement(identifier: String, teamIdentifier: String, allowingDevelopmentBuilds: Bool) -> String {
        let base = "identifier \"\(identifier)\" and anchor apple generic"
            + " and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        guard !allowingDevelopmentBuilds else {
            return base + " and (certificate leaf[\(developerIDLeaf)] or certificate leaf[\(developmentLeaf)])"
        }
        return base
            + " and certificate 1[\(developerIDAuthority)]"
            + " and certificate leaf[\(developerIDLeaf)]"
            + " and ! entitlement[\"com.apple.security.get-task-allow\"] exists"
    }

    static let isADebugBuild: Bool = {
        #if DEBUG
        true
        #else
        false
        #endif
    }()

    public static func isValidTeamIdentifier(_ team: String) -> Bool {
        team.utf8.count == 10 && team.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) }
    }
}
