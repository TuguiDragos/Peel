enum Naming {
    static let separators: Set<Character> = [" ", "-", "_", "."]

    static let genericNames: Set<String> = [
        "adobe", "agent", "app", "apple", "application", "applications", "backup", "backups", "browser",
        "byhost", "cache", "caches", "cloud", "common", "config", "crashpad", "crashreporter", "data",
        "default", "documents", "downloads", "editor", "electron", "extension", "extensions", "files",
        "google", "helper", "helpers", "installer", "jetbrains", "launcher", "library", "logs", "manager",
        "microsoft", "mozilla", "player", "plugin", "plugins", "preferences", "reader", "service",
        "services", "settings", "setup", "shared", "support", "sync", "temp", "tmp", "tools",
        "uninstaller", "update", "updater", "updates", "user", "viewer",
    ]

    static func normalized(_ string: String) -> String {
        String(string.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    static func isSignificant(_ name: String) -> Bool {
        let normalized = normalized(name)
        return normalized.count >= 3 && !genericNames.contains(normalized)
    }

    /// "MuseScore 4" → "MuseScore". Apps carry their major version in the name while their folders don't.
    static func withoutTrailingVersion(_ name: String) -> String? {
        guard let space = name.lastIndex(of: " ") else { return nil }
        let version = name[name.index(after: space)...]
        guard !version.isEmpty, version.allSatisfy({ $0.isNumber || $0 == "." }), version.contains(where: \.isNumber)
        else { return nil }
        var base = String(name[..<space])
        while base.hasSuffix(" ") { base.removeLast() }
        return isSignificant(base) ? base : nil
    }

    /// True when `key` starts with `name` followed by a separator. Expects both arguments lowercased.
    static func hasNamePrefix(_ key: String, name: String) -> Bool {
        guard key.count > name.count, key.hasPrefix(name) else { return false }
        return key.dropFirst(name.count).first.map(separators.contains) ?? false
    }
}

enum Identifier {
    /// What Xcode puts in front of an iPad app's identifier when it builds the app for the Mac under an identifier
    /// of its own (`DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER`). The maker's name begins after it.
    static let catalystPrefix = "maccatalyst."

    /// Leading pairs of components that name no single developer, so for these the vendor takes three components.
    /// On a code host the third is the account, and under a country's registry (`uk.co`, which is `co.uk`
    /// reversed) it is the company. All of these are in the Public Suffix List.
    private static let sharedDomains: Set<String> = [
        "com.github", "io.github", "com.gitlab", "io.gitlab", "org.sourceforge", "net.sourceforge", "com.googlecode",
        "uk.co", "uk.org", "uk.ac", "au.com", "au.net", "au.org", "jp.co", "jp.ne", "jp.or", "nz.co", "kr.co",
        "za.co", "il.co", "in.co", "br.com", "cn.com", "tw.com", "hk.com", "sg.com", "mx.com", "ar.com", "tr.com",
    ]

    static func componentCount(of identifier: String) -> Int {
        identifier.split(separator: ".").count
    }

    /// Whether an identifier an app declares is shaped like one app's: two components or more (Obsidian's is
    /// `md.obsidian`), none empty, only ASCII letters, digits, `-` and `_`, and no leading `-`. A single word, or
    /// anything else, is too generic to prove what it names.
    static func isValid(_ identifier: String) -> Bool {
        let components = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2, !identifier.hasPrefix("-") else { return false }
        return components.allSatisfy { component in
            !component.isEmpty
                && component.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        }
    }

    /// Whether a name found on disk reads as an app's identifier, "com.example.app": at least three components and a
    /// lowercase top-level domain after any `catalystPrefix`. Stricter than `isValid`, since a name nobody declared
    /// is only a guess.
    static func isReverseDNS(_ identifier: String) -> Bool {
        let components = withoutCatalystPrefix(identifier).split(separator: ".", omittingEmptySubsequences: false)
        guard
            components.count >= 3,
            let domain = components.first,
            (2...6).contains(domain.count),
            domain.allSatisfy({ $0.isASCII && $0.isLowercase })
        else { return false }
        return components.allSatisfy { component in
            !component.isEmpty
                && component.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        }
    }

    /// True for a group name in one of the forms macOS uses: a team identifier and a dot in front, or `group.`
    /// and then a reverse DNS name. Expects the name lowercased, as the matcher keeps its keys.
    static func isGroup(_ name: String) -> Bool {
        if let dot = name.firstIndex(of: "."), name[..<dot].count == 10,
           name[..<dot].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
            return name.index(after: dot) < name.endIndex
        }
        return name.hasPrefix("group.") && isReverseDNS(String(name.dropFirst("group.".count)))
    }

    /// Splits "ABCDE12345.shared" into the team identifier and the rest.
    static func teamScoped(_ name: String) -> (team: String, remainder: String)? {
        guard let dot = name.firstIndex(of: ".") else { return nil }
        let team = name[..<dot]
        let remainder = name[name.index(after: dot)...]
        guard team.count == 10, team.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }), !remainder.isEmpty
        else { return nil }
        return (String(team), String(remainder))
    }

    static func vendor(of identifier: String) -> String? {
        let components = withoutCatalystPrefix(identifier.lowercased()).split(separator: ".")
        guard components.count >= 3 else { return nil }
        let domain = components.prefix(2).joined(separator: ".")
        guard sharedDomains.contains(domain) else { return domain }
        return components.count >= 4 ? components.prefix(3).joined(separator: ".") : nil
    }

    static func withoutCatalystPrefix(_ identifier: String) -> Substring {
        identifier.hasPrefix(catalystPrefix) ? identifier.dropFirst(catalystPrefix.count) : identifier[...]
    }
}

extension String {
    func removingSuffix(_ suffix: String) -> String {
        guard count > suffix.count, lowercased().hasSuffix(suffix.lowercased()) else { return self }
        return String(dropLast(suffix.count))
    }
}
