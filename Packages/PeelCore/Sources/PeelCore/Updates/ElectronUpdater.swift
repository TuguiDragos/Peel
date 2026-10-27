import Foundation

enum ElectronUpdater {
    /// Where electron-updater kept downloads before version 6, which keeps them in `Library/Caches` (`AppAdapter.ts`).
    static let formerPlace = "Library/Application Support/Caches"
    static let places = ["Library/Caches", formerPlace]

    /// A real `app-update.yml` is a few lines, so one over 64 KB is ignored.
    static func configuration(in contents: URL) -> String? {
        BoundedRead.data(at: contents.appending(path: "Resources/app-update.yml"), maximum: 64 * 1_024)
            .map { String(decoding: $0, as: UTF8.self) }
    }

    static func downloadsFolder(fromConfiguration text: String) -> String? {
        guard let name = topLevelFields(in: text)["updaterCacheDirName"], !name.contains("/"), name != ".", name != ".."
        else { return nil }
        return name
    }

    static func holdsADownload(_ folder: URL) -> Bool {
        ["update.zip", "pending/update-info.json"].contains { name in
            var info = stat()
            return lstat(folder.appending(path: name).path(percentEncoded: false), &info) == 0
                && info.st_mode & S_IFMT == S_IFREG
        }
    }

    static func feedURL(fromConfiguration text: String) -> URL? {
        let fields = topLevelFields(in: text)
        let file = "\(fields["channel"] ?? "latest")-mac.yml"

        switch fields["provider"] {
        case "generic":
            guard let base = fields["url"].flatMap(URL.init(string:)), base.scheme == "https" else { return nil }
            return base.appending(path: file)
        case "github":
            // A `host` other than github.com is a company's own server. The owner and repository were never meant
            // to leave that server, so they are not sent to github.com.
            guard fields["host"] == nil || fields["host"] == "github.com" else { return nil }
            guard let owner = fields["owner"], let repository = fields["repo"] else { return nil }
            return URL(string: "https://github.com/\(owner)/\(repository)/releases/latest/download/\(file)")
        default:
            return nil
        }
    }

    static func version(fromFeed text: String) -> String? {
        topLevelFields(in: text)["version"]
    }

    /// Whether electron-updater offers the release `text` describes to this Mac, as its `AppUpdater` decides unless
    /// the app replaces the rule: not when the Darwin release (`os.release()`) is below the feed's
    /// `minimumSystemVersion` as semver compares them, a version semver can't read deciding nothing, and with a
    /// `stagingPercentage`, only when the app's own `updaterID` falls within it. With no id yet, the app's first
    /// check makes one at random, so Peel can't tell, and says it is offered.
    static func isOffered(fromFeed text: String, darwinRelease: String, updaterID: UUID?) -> Bool {
        let fields = topLevelFields(in: text)
        if let minimum = fields["minimumSystemVersion"].flatMap(SemanticVersion.init),
           let current = SemanticVersion(darwinRelease), current < minimum {
            return false
        }
        guard let staging = fields["stagingPercentage"].flatMap({ Double($0) }), staging.isFinite, let updaterID else {
            return true
        }
        let bytes = withUnsafeBytes(of: updaterID.uuid) { Array($0) }
        let value = bytes[12...].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return Double(value) / Double(UInt32.max) < staging / 100
    }

    /// The id electron-updater keeps for an app's staged releases, in `.updaterId` in the app's own data folder, or nil
    /// until it has made one.
    static func updaterID(of app: InstalledApp, home: URL) -> UUID? {
        guard let name = app.bundleName, !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { return nil }
        let file = home.appending(path: "Library/Application Support/\(name)/.updaterId")
        return BoundedRead.data(at: file, maximum: 1_024).flatMap {
            UUID(uuidString: String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// The Darwin release, which electron-updater reads with `os.release()`, such as 25.6.0.
    static var darwinRelease: String {
        var system = utsname()
        guard uname(&system) == 0 else { return "" }
        return withUnsafeBytes(of: system.release) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    /// A version as semver reads it strictly: three numbers with no leading zero, after an optional `v`, then an
    /// optional prerelease, which comes before the release, and build metadata, which counts for nothing.
    private struct SemanticVersion: Comparable {
        let numbers: [Int]
        let prerelease: [Substring]

        init?(_ text: String) {
            let pattern = #/
                v? (?<major> 0|[1-9][0-9]* ) \. (?<minor> 0|[1-9][0-9]* ) \. (?<patch> 0|[1-9][0-9]* )
                (?: - (?<prerelease>
                    (?: 0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]* )
                    (?: \. (?: 0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]* ) )*
                ) )?
                (?: \+ [0-9A-Za-z-]+ (?: \. [0-9A-Za-z-]+ )* )?
                /#
            guard let match = text.trimmingCharacters(in: .whitespaces).wholeMatch(of: pattern),
                  let major = Int(match.major), let minor = Int(match.minor), let patch = Int(match.patch)
            else { return nil }
            numbers = [major, minor, patch]
            prerelease = match.prerelease.map { $0.split(separator: ".") } ?? []
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.numbers != rhs.numbers { return lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
            switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
            case (true, _): return false
            case (false, true): return true
            case (false, false):
                for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
                    switch (Int(left), Int(right)) {
                    case let (left?, right?): return left < right
                    case (.some, nil): return true
                    case (nil, .some): return false
                    case (nil, nil): return left < right
                    }
                }
                return lhs.prerelease.count < rhs.prerelease.count
            }
        }
    }

    /// What is new in the release: the feed's top-level `releaseNotes`, which electron-builder writes from the app's
    /// release notes, in Markdown, as a plain, quoted or block scalar. The list it writes instead when told to keep
    /// every version's notes is not read.
    static func releaseNotes(fromFeed text: String) -> ReleaseNotes? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let key = "releaseNotes:"
        guard let start = lines.firstIndex(where: { $0.hasPrefix(key) }) else { return nil }
        let value = lines[start].dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        let notes: String
        switch value.first {
        case "|", ">":
            let block = lines[(start + 1)...].prefix { $0.isEmpty || $0.first?.isWhitespace == true }
            notes = scalar(of: block, keepingLineBreaks: value.first == "|")
        case "'":
            guard value.count >= 2, value.hasSuffix("'") else { return nil }
            notes = String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        case "\"":
            guard value.count >= 2, value.hasSuffix("\"") else { return nil }
            notes = unescaped(value.dropFirst().dropLast())
        case nil:
            return nil
        default:
            notes = value
        }
        return ReleaseNotes(notes, format: .markdown)
    }

    /// A block scalar's lines without their common indentation: kept as lines for `|`, and folded into paragraphs
    /// for `>`, where an empty line is a line break.
    private static func scalar(of block: ArraySlice<Substring>, keepingLineBreaks: Bool) -> String {
        func indentation(_ line: Substring) -> Int { line.prefix { $0 == " " }.count }
        let written = block.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let common = written.map(indentation).min() ?? 0
        let lines = block.map { String($0.dropFirst(min(common, indentation($0)))) }
        guard !keepingLineBreaks else { return lines.joined(separator: "\n") }
        return lines.reduce(into: "") { folded, line in
            if line.isEmpty {
                folded += "\n"
            } else {
                if !folded.isEmpty, folded.last != "\n" { folded += " " }
                folded += line
            }
        }
    }

    /// A double-quoted scalar's text, with YAML's escapes read: a line break, a tab, a quote, a backslash, a slash and
    /// a character by its code.
    private static func unescaped(_ quoted: Substring) -> String {
        var text = ""
        var characters = quoted.makeIterator()
        while let character = characters.next() {
            guard character == "\\", let escaped = characters.next() else {
                text.append(character)
                continue
            }
            switch escaped {
            case "n": text.append("\n")
            case "t": text.append("\t")
            case "u":
                let digits = String((0..<4).compactMap { _ in characters.next() })
                if let code = UInt32(digits, radix: 16), let scalar = Unicode.Scalar(code) {
                    text.unicodeScalars.append(scalar)
                }
            default: text.append(escaped)
            }
        }
        return text
    }

    private static func topLevelFields(in text: String) -> [String: String] {
        var fields: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) where line.first?.isWhitespace == false {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
            if !key.isEmpty, !value.isEmpty {
                fields[key] = value
            }
        }
        return fields
    }
}
