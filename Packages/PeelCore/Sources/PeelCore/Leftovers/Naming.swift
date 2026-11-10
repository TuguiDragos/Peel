internal import PeelPrivileged

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

    /// The name a folder is known by: normalized, and without `.localized`, since a folder named `X.localized` is
    /// named `X` (Apple, "Localizing the Name of a Directory").
    static func folderName(_ name: String) -> String {
        let suffix = ".localized"
        return normalized(name.lowercased().hasSuffix(suffix) ? String(name.dropLast(suffix.count)) : name)
    }

    static func isSignificant(_ name: String) -> Bool {
        let normalized = normalized(name)
        return isLongEnough(normalized) && !genericNames.contains(normalized)
    }

    /// Whether a normalized name is long enough to say what it names: three characters, or two in Chinese, Japanese,
    /// or Korean, where two ideographs, kana, or Hangul syllables make a whole word.
    static func isLongEnough(_ normalized: String) -> Bool {
        normalized.count >= (isEastAsian(normalized) ? 2 : 3)
    }

    /// True for a name written only in ideographs, kana, or Hangul, each character read by its first scalar, so a
    /// syllable a disk keeps as its jamo counts once.
    static func isEastAsian(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { character in
            character.unicodeScalars.first.map { scalar in
                scalar.properties.isIdeographic || kanaAndHangul.contains { $0.contains(scalar.value) }
            } ?? false
        }
    }

    /// Unicode's blocks of Hangul Jamo, Hiragana, Katakana and its Phonetic Extensions, Hangul Syllables, and the
    /// halfwidth katakana.
    private static let kanaAndHangul: [ClosedRange<UInt32>] = [
        0x1100...0x11FF, 0x3040...0x30FF, 0x31F0...0x31FF, 0xAC00...0xD7AF, 0xFF66...0xFF9F,
    ]

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

    /// "IntelliJIdea2026.2" → "IntelliJIdea". JetBrains writes the version of a release right after the product's
    /// name in the folders it keeps for it (its "Directories used by the IDE"), and Android Studio names its own the
    /// same way. A number with no dot is kept, since it is as often part of a name.
    static func withoutAttachedVersion(_ name: String) -> String? {
        guard let last = name.lastIndex(where: { !$0.isNumber && $0 != "." }), name[last].isLetter else { return nil }
        let version = name[name.index(after: last)...]
        guard version.contains("."), version.first?.isNumber == true, version.last?.isNumber == true,
              !version.contains("..")
        else { return nil }
        let base = String(name[...last])
        return isSignificant(base) ? base : nil
    }

    /// The words a maker puts after an app's name for a release channel, which its folders carry no more than they
    /// carry a version: Zed Nightly keeps its settings in `zed`.
    static let channelWords: Set<String> = [
        "alpha", "beta", "canary", "dev", "nightly", "preview", "insiders", "ptb", "rc",
    ]

    /// "Zed Nightly" → "Zed", "Xcode-beta" → "Xcode". Only the last word counts, and what is left has to name the
    /// app.
    static func withoutChannel(_ name: String) -> String? {
        guard let separator = name.lastIndex(where: separators.contains) else { return nil }
        guard channelWords.contains(normalized(String(name[name.index(after: separator)...]))) else { return nil }
        var base = String(name[..<separator])
        while let last = base.last, separators.contains(last) { base.removeLast() }
        return isSignificant(base) ? base : nil
    }

    /// True when `key` begins with `name`'s words, whatever separates them, and goes on after them: `tide-pool-sdk`
    /// and `TidePool-Data` begin with Tide Pool, `tide-pooling` doesn't. Expects both arguments lowercased.
    static func hasNamePrefix(_ key: String, name: String) -> Bool {
        let whole = normalized(name)
        let words = key.split(whereSeparator: separators.contains)
        var read = ""
        for (index, word) in words.enumerated() {
            read += normalized(String(word))
            if read == whole { return index < words.count - 1 }
            guard whole.hasPrefix(read) else { return false }
        }
        return false
    }
}

enum Identifier {
    /// What Xcode puts in front of an iPad app's identifier when it builds the app for the Mac under an identifier
    /// of its own (`DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER`). The maker's name begins after it.
    static let catalystPrefix = "maccatalyst."

    /// Leading pairs of components that name no single developer, so the vendor takes three: an account on a code
    /// host, a company under a country's registry (Public Suffix List), or the app under a tool's default prefix.
    private static let sharedDomains: Set<String> = [
        "com.github", "io.github", "com.gitlab", "io.gitlab", "org.sourceforge", "net.sourceforge", "com.googlecode",
        "uk.co", "uk.org", "uk.ac", "au.com", "au.net", "au.org", "jp.co", "jp.ne", "jp.or", "nz.co", "kr.co",
        "za.co", "il.co", "in.co", "br.com", "cn.com", "tw.com", "hk.com", "sg.com", "mx.com", "ar.com", "tr.com",
        "com.electron", "com.yourcompany", "com.todesktop", "com.install4j",
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
    /// lowercase top-level domain after any `catalystPrefix`, and a name among the components after it, not only
    /// numbers, as in a server's folder named for its port and a random number (`tomcat.8080.10018690101673077448`).
    /// Stricter than `isValid`, since a name nobody declared is only a guess.
    static func isReverseDNS(_ identifier: String) -> Bool {
        let components = withoutCatalystPrefix(identifier).split(separator: ".", omittingEmptySubsequences: false)
        guard
            components.count >= 3,
            let domain = components.first,
            (2...6).contains(domain.count),
            domain.allSatisfy({ $0.isASCII && $0.isLowercase }),
            components.dropFirst().contains(where: { component in component.contains { !$0.isNumber } })
        else { return false }
        return components.allSatisfy { component in
            !component.isEmpty
                && component.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        }
    }

    /// True for Peel's identifier and those of its parts (`com.tuguidragos.Peel.Helper`), compared without case.
    static func isPeels(_ identifier: String) -> Bool {
        let identifier = identifier.lowercased(), own = HelperIdentity.appIdentifier.lowercased()
        return identifier == own || identifier.hasPrefix(own + ".")
    }

    /// True for a group name in one of the forms macOS uses: a team identifier and a dot in front, or `group.`
    /// and then a reverse DNS name. Expects the name lowercased, as the matcher keeps its keys.
    static func isGroup(_ name: String) -> Bool {
        if let dot = name.firstIndex(of: "."), name[..<dot].count == 10,
           name[..<dot].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
            return name.index(after: dot) < name.endIndex
        }
        return withoutGroupPrefix(name).map(isReverseDNS) == true
    }

    /// What a group's name carries after `group.`, the prefix macOS gives a group an app shares with its extensions,
    /// or nil for a name without it.
    static func withoutGroupPrefix(_ name: String) -> String? {
        name.hasPrefix("group.") ? String(name.dropFirst("group.".count)) : nil
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

    /// The maker's domain a two-part identifier is shaped like, such as `md.obsidian`, read after any
    /// `catalystPrefix`, or nil for one of more parts, one that isn't valid, or a domain many makers share.
    static func twoPartDomain(_ identifier: String) -> String? {
        let domain = String(withoutCatalystPrefix(identifier.lowercased()))
        guard componentCount(of: domain) == 2, isValid(domain), !sharedDomains.contains(domain) else { return nil }
        return domain
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
