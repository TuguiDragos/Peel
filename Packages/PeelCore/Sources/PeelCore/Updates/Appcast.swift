import Foundation

struct AppcastItem: Equatable {
    var version: String?
    var shortVersion: String?
    var minimumSystemVersion: String?
    var maximumSystemVersion: String?
    var channel: String?
    /// `sparkle:os` on the enclosure. A feed shared with WinSparkle lists Windows builds beside the Mac's.
    var system: String?
    var releaseNotes: URL?

    var displayVersion: String? {
        shortVersion ?? version
    }
}

enum Appcast {
    enum Reading: Equatable {
        case latest(AppcastItem)
        /// The feed was read, but none of its items is a release for the running system: each is on a named
        /// channel, is for another operating system, needs a newer or older macOS, or has no version. This counts
        /// as up to date, not as a failed check.
        case nothingForThisMac
        case unreadable
    }

    /// Finds the newest release that runs on `systemVersion`. Like Sparkle, it skips items on a named channel,
    /// items for another operating system, and items that need a newer or older macOS.
    static func read(_ data: Data, systemVersion: String) -> Reading {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return .unreadable }

        let releases = delegate.items.filter { item in
            guard item.channel == nil, item.displayVersion != nil, item.system == nil || item.system == "macos" else { return false }
            if let minimum = item.minimumSystemVersion, VersionComparison.isNewer(minimum, than: systemVersion) { return false }
            if let maximum = item.maximumSystemVersion, VersionComparison.isNewer(systemVersion, than: maximum) { return false }
            return true
        }
        return releases.max(by: isOlder).map(Reading.latest) ?? .nothingForThisMac
    }

    /// Picks the release notes link in the user's language, then a link with no language, then the first link.
    /// `Bundle.preferredLocalizations` returns a language even when none matches (the first one offered, or `en`
    /// when none is offered), so its pick is used only when the user reads that language and a link has it.
    static func preferred(_ links: [(language: String, url: URL)], languages: [String] = Locale.preferredLanguages) -> URL? {
        func base(_ tag: String) -> String { Locale(identifier: tag).language.languageCode?.identifier ?? tag }
        let tagged = links.map(\.language).filter { !$0.isEmpty }
        if let best = Bundle.preferredLocalizations(from: tagged, forPreferences: languages).first,
           Set(languages.map(base)).contains(base(best)), let url = links.first(where: { $0.language == best })?.url {
            return url
        }
        return links.first { $0.language.isEmpty }?.url ?? links.first?.url
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
        private var notes: [String: [(language: String, url: URL)]] = [:]
        private var noteLanguage = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            switch elementName {
            case "item":
                current = AppcastItem()
                (elementVersion, elementShortVersion, notes) = (nil, nil, [:])
            case "sparkle:releaseNotesLink", "releaseNotesLink", "sparkle:fullReleaseNotesLink", "link":
                noteLanguage = attributes["xml:lang"] ?? ""
            case "enclosure":
                guard var item = current, item.version == nil, item.shortVersion == nil, item.system == nil else { break }
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

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch elementName {
            case "item":
                if var item = current {
                    item.version = item.version ?? elementVersion
                    item.shortVersion = item.shortVersion ?? elementShortVersion
                    item.releaseNotes = ["sparkle:releaseNotesLink", "releaseNotesLink", "sparkle:fullReleaseNotesLink", "link"].lazy.compactMap { self.notes[$0].flatMap { Appcast.preferred($0) } }.first
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
            case "sparkle:releaseNotesLink", "releaseNotesLink", "sparkle:fullReleaseNotesLink", "link":
                if current != nil, let url = URL(string: value), url.scheme == "https",
                   notes[elementName]?.contains(where: { $0.language == noteLanguage }) != true {
                    notes[elementName, default: []].append((noteLanguage, url))
                }
            default:
                break
            }
            text = ""
        }
    }
}
