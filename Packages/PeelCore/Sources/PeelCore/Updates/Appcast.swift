import Foundation

struct AppcastItem: Equatable {
    var version: String?
    var shortVersion: String?
    var minimumSystemVersion: String?
    var maximumSystemVersion: String?
    var channel: String?
    /// `sparkle:os` on the enclosure. A feed shared with WinSparkle lists Windows builds beside the Mac's.
    var system: String?
    /// `sparkle:hardwareRequirements`, in lowercase. Sparkle knows one: `arm64`, a release for Apple silicon only.
    var hardwareRequirements: Set<String> = []
    var releaseNotes: URL?
    /// The page `sparkle:releaseNotesLink` names, which holds what is new. Unlike `releaseNotes`, never the product
    /// page an item's `link` names.
    var notesPage: URL?
    /// The item's `description` in the reader's language, and the format its `sparkle:format` names.
    var description: String?
    var descriptionFormat: ReleaseNotes.Format = .html

    /// What is new, as the item writes it in its `description`. Read once the feed has been, since reading HTML
    /// while `XMLParser` is still reading the feed stops it.
    var notes: ReleaseNotes? {
        description.flatMap { ReleaseNotes($0, format: descriptionFormat) }
    }

    var displayVersion: String? {
        shortVersion ?? version
    }
}

enum Appcast {
    enum Reading: Equatable {
        case latest(AppcastItem)
        /// The feed was read, but none of its items is a release for the running system: each is on a named
        /// channel, is for another operating system, needs a newer or older macOS or Apple silicon, or has no
        /// version. This counts as up to date, not as a failed check.
        case nothingForThisMac
        case unreadable
    }

    /// Finds the newest release that runs on `systemVersion`. Like Sparkle, it skips items on a named channel,
    /// items for another operating system, items that need a newer or older macOS, and, on an Intel Mac, items
    /// that need Apple silicon. Sparkle offers those under Rosetta, which only an Apple silicon Mac has.
    static func read(_ data: Data, systemVersion: String, isAppleSilicon: Bool) -> Reading {
        guard let releases = releases(in: data, systemVersion: systemVersion, isAppleSilicon: isAppleSilicon) else {
            return .unreadable
        }
        return releases.max(by: isOlder).map(Reading.latest) ?? .nothingForThisMac
    }

    /// Every release in the feed that runs on `systemVersion`, in feed order. Nil for a feed that cannot be read.
    static func releases(in data: Data, systemVersion: String, isAppleSilicon: Bool) -> [AppcastItem]? {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }

        return delegate.items.filter { item in
            guard item.channel == nil, item.displayVersion != nil, item.system == nil || item.system == "macos" else {
                return false
            }
            if let minimum = item.minimumSystemVersion, VersionComparison.isNewer(minimum, than: systemVersion) {
                return false
            }
            // A maximum that is no version, such as a release's name, reads as zero and would hold back every Mac.
            if let maximum = item.maximumSystemVersion, VersionComparison.isAVersion(maximum),
               VersionComparison.isNewer(systemVersion, than: maximum) {
                return false
            }
            if !isAppleSilicon, item.hardwareRequirements.contains("arm64") { return false }
            return true
        }
    }

    /// Picks the release notes in the user's language, then notes with no language, then the first.
    /// `Bundle.preferredLocalizations` returns a language even when none matches (the first one offered, or `en`
    /// when none is offered), so its pick is used only when the user reads that language and notes have it.
    static func preferred<Value>(
        _ notes: [(language: String, value: Value)],
        languages: [String] = Locale.preferredLanguages
    ) -> Value? {
        func base(_ tag: String) -> String { Locale(identifier: tag).language.languageCode?.identifier ?? tag }
        let tagged = notes.map(\.language).filter { !$0.isEmpty }
        if let best = Bundle.preferredLocalizations(from: tagged, forPreferences: languages).first,
           Set(languages.map(base)).contains(base(best)),
           let value = notes.first(where: { $0.language == best })?.value {
            return value
        }
        return notes.first { $0.language.isEmpty }?.value ?? notes.first?.value
    }

    /// The format a `description` is read in, as Sparkle reads `sparkle:format`: HTML unless it says otherwise.
    static func format(named name: String?) -> ReleaseNotes.Format {
        switch name?.lowercased() {
        case "plain-text": .plainText
        case "markdown": .markdown
        default: .html
        }
    }

    private static func isOlder(_ lhs: AppcastItem, than rhs: AppcastItem) -> Bool {
        let left = lhs.version ?? lhs.shortVersion ?? ""
        let right = rhs.version ?? rhs.shortVersion ?? ""
        return VersionComparison.compare(left, right) == .orderedAscending
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        private(set) var items: [AppcastItem] = []
        private var current: AppcastItem?
        private var text = ""
        /// The item's `sparkle:version` and `sparkle:shortVersionString` elements, kept apart until the item ends.
        /// Like Sparkle, an enclosure attribute wins over an element, wherever each appears in the item.
        private var elementVersion: String?
        private var elementShortVersion: String?
        /// The item's release notes links by element, in feed order, each with its `xml:lang` language or "".
        /// An item's `<link>` is usually the product page, so it is the last choice for release notes.
        private var notes: [String: [(language: String, value: URL)]] = [:]
        private var noteLanguage = ""
        /// The item's `description` elements, each with its language and its `sparkle:format`.
        private var descriptions: [(language: String, value: (text: String, format: String?))] = []
        private var descriptionFormat: String?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String] = [:]
        ) {
            text = ""
            switch elementName {
            case "item":
                current = AppcastItem()
                (elementVersion, elementShortVersion, notes, descriptions) = (nil, nil, [:], [])
            case "sparkle:releaseNotesLink", "releaseNotesLink", "sparkle:fullReleaseNotesLink", "link":
                noteLanguage = attributes["xml:lang"] ?? ""
            case "description":
                noteLanguage = attributes["xml:lang"] ?? ""
                descriptionFormat = attributes["sparkle:format"]
            case "enclosure":
                guard var item = current, item.version == nil, item.shortVersion == nil, item.system == nil else {
                    break
                }
                item.version = attributes["sparkle:version"]
                item.shortVersion = attributes["sparkle:shortVersionString"]
                item.system = attributes["sparkle:os"]
                current = item
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            text += String(decoding: CDATABlock, as: UTF8.self)
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch elementName {
            case "item":
                if var item = current {
                    item.version = item.version ?? elementVersion
                    item.shortVersion = item.shortVersion ?? elementShortVersion
                    item.releaseNotes =
                        ["sparkle:releaseNotesLink", "releaseNotesLink", "sparkle:fullReleaseNotesLink", "link"]
                        .lazy.compactMap { self.notes[$0].flatMap { Appcast.preferred($0) } }.first
                    item.notesPage = ["sparkle:releaseNotesLink", "releaseNotesLink"]
                        .lazy.compactMap { self.notes[$0].flatMap { Appcast.preferred($0) } }.first
                    if let description = Appcast.preferred(descriptions) {
                        item.description = description.text
                        item.descriptionFormat = Appcast.format(named: description.format)
                    }
                    items.append(item)
                }
                current = nil
            case "sparkle:version" where !value.isEmpty:
                elementVersion = value
            case "sparkle:shortVersionString" where !value.isEmpty:
                elementShortVersion = value
            case "sparkle:minimumSystemVersion" where !value.isEmpty:
                current?.minimumSystemVersion = value
            case "sparkle:maximumSystemVersion" where !value.isEmpty:
                current?.maximumSystemVersion = value
            case "sparkle:channel" where !value.isEmpty:
                current?.channel = value
            case "sparkle:hardwareRequirements":
                let separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ","))
                current?.hardwareRequirements = Set(
                    value.lowercased().components(separatedBy: separators).filter { !$0.isEmpty }
                )
            case "sparkle:releaseNotesLink", "releaseNotesLink", "sparkle:fullReleaseNotesLink", "link":
                if current != nil, let url = URL(string: value), url.scheme == "https",
                   notes[elementName]?.contains(where: { $0.language == noteLanguage }) != true {
                    notes[elementName, default: []].append((noteLanguage, url))
                }
            case "description" where current != nil:
                descriptions.append((noteLanguage, (value, descriptionFormat)))
            default:
                break
            }
            text = ""
        }
    }
}
