import Foundation
internal import PeelPrivileged
import Security

/// Reads what a code signature says about a bundle or a program, trusted only once the signature is checked.
/// `SecCode.h`: "To ensure that only valid data is returned [...] you must successfully call one of the
/// CheckValidity functions on the code before calling CopySigningInformation."
enum CodeSignature {
    /// The certificate field that marks the leaf of a Mac App Store app. Apple signs such apps again itself, on
    /// the developer's behalf.
    private static let appStoreLeaf = "field.1.2.840.113635.100.6.1.9"

    /// Returns the signing information of the code at `url`, or nil unless the signature is valid, leads back to
    /// Apple, and backs up the team it names. The team is a field the signer fills in, so it counts only when
    /// the leaf certificate was issued to that team, or when Apple did the signing. The information is read
    /// before the check only to build its requirement, and is returned only if the check passes.
    ///
    /// The executable and the sealed resources are not hashed: the identifier, the team, and the entitlements
    /// are covered without them, and hashing them costs seconds per app.
    static func information(at url: URL) -> [String: Any]? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var copied: CFDictionary?
        let flags = SecCSFlags(rawValue: UInt32(kSecCSSigningInformation))
        guard SecCodeCopySigningInformation(staticCode, flags, &copied) == errSecSuccess, let information = copied as? [String: Any] else {
            return nil
        }

        var text = "anchor apple generic"
        if let team = information[kSecCodeInfoTeamIdentifier as String] as? String {
            // The team is written into the requirement's text, so a malformed one could change what it asks.
            guard CodeSigning.isValidTeamIdentifier(team) else { return nil }
            text += " and (anchor apple or certificate leaf[\(appStoreLeaf)] or certificate leaf[subject.OU] = \"\(team)\")"
        }
        var requirement: SecRequirement?
        guard
            SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement,
            SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: UInt32(kSecCSBasicValidateOnly)), requirement) == errSecSuccess
        else { return nil }
        return information
    }

    /// Returns the maker that a checked signature's leaf certificate names, read from its subject:
    /// `Developer ID Application: <name> (<team>)`, where the team must be the one the signature carries, or
    /// "Apple" for Apple's own software, which has no team (`macOS Software Signing` for what macOS ships,
    /// `Software Signing` for Safari). An App Store app's leaf, `Apple Mac OS Application Signing`, names
    /// nobody, and a development build names a person rather than a maker, so both give nil.
    static func developer(fromLeaf summary: String, team: String?) -> String? {
        if team == nil, summary.hasSuffix("Software Signing") { return "Apple" }
        let prefix = "Developer ID Application: "
        guard summary.hasPrefix(prefix), let team, summary.hasSuffix(" (\(team))") else { return nil }
        let name = summary.dropFirst(prefix.count).dropLast(team.count + 3).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    static func teamIdentifier(at url: URL) -> String? {
        information(at: url)?[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
