import AppKit
import Foundation
import Testing

/// Every language the project declares is complete and sound in all four catalogs. The build checks almost
/// none of this: a reordered placeholder without numbers, a plural with no `other`, an empty value and a
/// broken `inflect` all compile, and show a wrong number, `(null)`, a crash or raw markup at run time.
@Suite struct StringCatalogTests {
    static let catalogs = [
        Catalog(path: "Localization/Peel/Localizable.xcstrings", table: .localizable),
        Catalog(path: "Localization/PeelFinder/Localizable.xcstrings", table: .localizable),
        Catalog(path: "Localization/Peel/InfoPlist.xcstrings", table: .infoPlist),
        Catalog(path: "Localization/Peel/AppShortcuts.xcstrings", table: .appShortcuts),
    ]

    @Test(arguments: catalogs) func everyDeclaredLanguageIsCompleteAndSound(catalog: Catalog) throws {
        var checker = CatalogChecker(root: Self.repository, required: try Self.declaredLanguages())
        checker.check(catalog)
        for warning in checker.warnings { Issue.record("\(warning)", severity: .warning) }
        #expect(checker.problems.isEmpty, "\(checker.problems.prefix(40).map(\.description).joined(separator: "\n"))")
    }

    /// Every text of Info.plist that macOS shows, its permission prompts and its copyright, is in the InfoPlist
    /// catalog, or macOS shows it in English in every language.
    @Test func infoPlistTextIsInItsCatalog() throws {
        let data = try Data(contentsOf: Self.repository.appending(path: "Support/Peel-Info.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let shown = Set(plist.keys.filter { $0.hasSuffix("UsageDescription") || $0 == "NSHumanReadableCopyright" })
        let checker = CatalogChecker(root: Self.repository, required: [])
        let file = checker.load("Localization/Peel/InfoPlist.xcstrings")
        let catalog = try #require(file?["strings"] as? [String: [String: Any]])
        let translated = Set(catalog.filter { $0.value["shouldTranslate"] as? Bool != false }.keys)
        #expect(shown == translated)
    }

    /// Items Peel puts in menus SwiftUI builds use SwiftUI's own words in each language, or the menu reads as if
    /// two apps wrote it: German puts a no-break space before its ellipsis, and Traditional Chinese writes ⋯. The
    /// same goes for the one name SwiftUI looks up in Peel's own strings.
    @Test func menuWordsAreApples() throws {
        var checker = CatalogChecker(root: Self.repository, required: try Self.declaredLanguages())
        checker.checkMenuWords()
        #expect(checker.problems.isEmpty, "\(checker.problems.map(\.description).joined(separator: "\n"))")
    }

    /// The places and commands Peel names most read as macOS names them in each language, from the system's own
    /// tables on this Mac.
    @Test func placesAndCommandsAreMacOSsWords() throws {
        var checker = CatalogChecker(root: Self.repository, required: try Self.declaredLanguages())
        checker.checkSystemWords()
        #expect(checker.problems.isEmpty, "\(checker.problems.map(\.description).joined(separator: "\n"))")
    }

    /// The app quotes the Finder extension's menu item by name, so both catalogs have to agree on it.
    @Test func theFinderItemIsQuotedAsTranslated() throws {
        var checker = CatalogChecker(root: Self.repository, required: try Self.declaredLanguages())
        checker.checkFinderItem()
        #expect(checker.problems.isEmpty, "\(checker.problems.map(\.description).joined(separator: "\n"))")
    }

    /// Each sidebar name fits in the font the sidebar draws with, at both weights for Bold Text. The sidebar grows
    /// to 320 points for its longest name and cuts a longer one: 37 of those points are the row's insets, and 26
    /// are the symbol and its gap.
    @Test func namesFitTheirPlaces() throws {
        let catalog = try Self.localizable()
        let room = Self.sidebarMaximum - Self.sidebarRowInsets - Self.sidebarSymbol
        var problems: [String] = []
        for language in try Self.declaredLanguages() {
            for key in Self.sidebarNames {
                guard let text = Self.value(of: key, in: language, catalog), Self.width(text, in: language) > room else { continue }
                problems.append("\(language): \(text.debugDescription) is \(Int(Self.width(text, in: language))) points, and a sidebar row has \(Int(room))")
            }
        }
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    /// On macOS 26, a page's tabs are one segmented control in the title bar, with equal segments: the widest
    /// title plus 23.5 points each, or 27 at either end. The toolbar keeps the control only while its column is
    /// 24 points wider, and otherwise moves it into its overflow menu. Without the sidebar, the column must be 160
    /// points wider, since the window buttons and the sidebar button come first. When the window is too narrow for
    /// both, the sidebar steps aside for Tweaks' tabs (`TweakPage.tabBarWidth`). The Settings window lays its tabs
    /// out as toolbar items and is not checked here.
    @MainActor @Test func tabBarsFitTheirWindows() throws {
        let catalog = try Self.localizable()
        let settings = ["General", "Exclusions", "Privacy", "Helper"]
        let tweaks = ["Dock", "Screenshots", "Finder", "Typing", "Windows", "Privacy"]
        var problems: [String] = []
        for language in try Self.declaredLanguages() {
            let font = Self.font(NSFont.systemFont(ofSize: NSFont.systemFontSize), in: language)
            func bar(_ keys: [String]) -> CGFloat {
                let titles = keys.map { Self.value(of: $0, in: language, catalog) ?? $0 }
                let widest = titles.indices.map { index in
                    let end = index == 0 || index == titles.count - 1
                    return ceil((titles[index] as NSString).size(withAttributes: [.font: font]).width + (end ? 27 : 23.5))
                }.max() ?? 0
                return CGFloat(titles.count) * widest
            }
            let widestName = Self.sidebarNames.map { Self.width(Self.value(of: $0, in: language, catalog) ?? $0, in: language) }.max() ?? 0
            // Plus a scroll bar's width, which `ToolSidebar` adds where scroll bars show beside the content.
            let scroller = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
            let sidebar = max(min(ceil(widestName + Self.sidebarSymbol) + Self.sidebarRowInsets, Self.sidebarMaximum) + scroller, 220)
            let checks: [(needs: CGFloat, room: CGFloat, what: String)] = [
                (sidebar + bar(settings) + 24, 960, "Settings' tabs beside the sidebar at the narrowest window"),
                (sidebar + bar(tweaks) + 24, 1120, "Tweaks' tabs beside the sidebar at the default window"),
                (bar(tweaks) + 160, 960, "Tweaks' tabs alone at the narrowest window"),
            ]
            for check in checks where check.needs > check.room {
                problems.append("\(language): \(check.what) need \(Int(check.needs)) points of \(Int(check.room))")
            }
        }
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    static let sidebarNames = [
        "Home", "Tweaks", "Terminal", "History", "Settings", "Applications", "Orphaned Files", "Intel Software",
        "Package Receipts", "Space", "Developer", "Build Artifacts", "Installers and Backups", "Duplicates",
        "iCloud Drive", "File Search", "Background Items", "Extensions", "Plug-ins",
    ]
    static let sidebarMaximum: CGFloat = 320
    static let sidebarRowInsets: CGFloat = 37
    static let sidebarSymbol: CGFloat = 26

    static func localizable() throws -> [String: [String: Any]] {
        let checker = CatalogChecker(root: repository, required: [])
        return try #require(checker.load("Localization/Peel/Localizable.xcstrings")?["strings"] as? [String: [String: Any]])
    }

    static func value(of key: String, in language: String, _ catalog: [String: [String: Any]]) -> String? {
        let node = (catalog[key]?["localizations"] as? [String: Any])?[language] as? [String: Any]
        return (node?["stringUnit"] as? [String: Any])?["value"] as? String
    }

    /// The width of `text` in the regular or the bold system font, whichever is wider, since Bold Text may be on.
    static func width(_ text: String, in language: String) -> CGFloat {
        [NSFont.systemFont(ofSize: NSFont.systemFontSize), NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
            .map { (text as NSString).size(withAttributes: [.font: font($0, in: language)]).width }.max() ?? 0
    }

    /// `font` as an app running in `language` draws it, with the fallback fonts that language picks for the
    /// characters the font lacks. In an English process, Japanese kana would come from a Chinese font and draw wider.
    static func font(_ font: NSFont, in language: String) -> NSFont {
        let cascade = CTFontCopyDefaultCascadeListForLanguages(font, [language] as CFArray) as? [CTFontDescriptor] ?? []
        return NSFont(descriptor: font.fontDescriptor.addingAttributes([.cascadeList: cascade]), size: font.pointSize) ?? font
    }

    /// With no language declared, the checks above would have nothing to look at, so this runs them on a
    /// catalog with one of each defect.
    @Test func theRulesCatchWhatTheyAreFor() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "StringCatalogTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appending(path: "Localization/Peel"), withIntermediateDirectories: true)
        func unit(_ value: String, _ state: String = "translated") -> [String: Any] {
            ["stringUnit": ["state": state, "value": value]]
        }
        func plural(_ forms: [String: String]) -> [String: Any] {
            ["variations": ["plural": forms.mapValues { unit($0) }]]
        }
        let strings: [String: Any] = [
            "Kept": ["localizations": [:]],
            "Empty": ["localizations": ["ro": unit("")]],
            "Waiting": ["localizations": ["ro": unit("În așteptare", "needs_review")]],
            "Gone": ["extractionState": "stale", "localizations": ["ro": unit("Dispărut")]],
            "Peel": ["shouldTranslate": false, "localizations": ["ro": unit("Coajă")]],
            "%@ free of %@": ["localizations": ["ro": unit("%@ din %lld")]],
            "%1$@ in %2$@": ["localizations": ["ro": unit("%2$@ în %@")]],
            "^[%lld file](inflect: true)": ["localizations": ["ro": unit("^[%lld fișier](inflect: true)")]],
            "%lld files": ["localizations": ["ro": plural(["one": "%lld fișier", "other": "%lld de fișiere"])]],
            "%lld kept": ["localizations": ["ro": unit("%lld păstrate")]],
            "Step %lld of %lld": ["localizations": ["ro": unit("Pasul %lld din %lld")]],
            "%lld apps": ["localizations": ["ro": plural(["one": "Aplicație", "few": "Aplicații", "other": "Aplicații"])]],
            "%lld folders": ["localizations": ["fr": plural(["one": "Un dossier", "many": "%lld de dossiers", "other": "%lld dossiers"])]],
            "^[%lld file](inflect: true) in ^[%lld folder](inflect: true)": ["localizations": ["ro": [
                "stringUnit": ["state": "translated", "value": "%#@files@ în %#@folders@"],
                "substitutions": [
                    "files": ["argNum": 1, "formatSpecifier": "lld", "variations": ["plural": ["one": unit("%arg fișier"), "few": unit("%arg fișiere"), "other": unit("%arg de fișiere")]]],
                    "folders": ["argNum": 2, "formatSpecifier": "lld", "variations": ["plural": ["one": unit("%arg dosar"), "few": unit("%arg dosare")]]],
                ],
            ]]],
            "Move to Trash": ["localizations": ["ro": unit("Mutați — acum")]],
            "Choose…": ["localizations": ["ro": unit("Alegeți...")]],
            "Run `brew unpin`": ["localizations": ["ro": unit("Rulați brew unpin")]],
            "Uses [a tool](peel-license:tool)": ["localizations": ["ro": unit("Folosește [un instrument](peel-license:instrument)")]],
            "OrbStack": ["localizations": ["ro": unit("OrbStack"), "fr": unit("OrbStack")]],
            "Don't": ["localizations": ["ro": unit("Nu"), "fr": unit("Non")]],
            "Can’t open %@": ["localizations": ["ro": unit("Nu se poate deschide %@"), "fr": unit("Impossible d'ouvrir %@")]],
            "Open in Photos": ["localizations": ["ro": unit("Deschide în Poze"), "fr": unit("Ouvrir dans Photos"), "nl": unit("Open in Foto's")]],
            "%@: links": ["localizations": ["ro": unit("Linkuri %@:"), "fr": unit("liens %@")]],
            "%@ used": ["localizations": ["ro": unit("%@ folosiți"), "fr": unit("%@ utilisés")]],
        ]
        let catalog: [String: Any] = ["sourceLanguage": "en", "strings": strings, "version": "1.0"]
        try JSONSerialization.data(withJSONObject: catalog).write(to: folder.appending(path: "Localization/Peel/Localizable.xcstrings"))

        var checker = CatalogChecker(root: folder, required: ["ro", "fr"])
        checker.check(Catalog(path: "Localization/Peel/Localizable.xcstrings", table: .localizable))
        let caught = Dictionary(grouping: checker.problems, by: \.rule).mapValues { Set($0.map(\.key)) }

        #expect(caught["missing"]?.contains("Kept") == true)
        #expect(caught["empty"]?.contains("Empty") == true)
        #expect(caught["state"]?.contains("Waiting") == true)
        #expect(caught["stale"]?.contains("Gone") == true)
        #expect(caught["shouldTranslate"]?.contains("Peel") == true)
        #expect(caught["placeholder"]?.contains("%@ free of %@") == true, "a type changed")
        #expect(caught["placeholder"]?.contains("%1$@ in %2$@") == true, "numbered and unnumbered mixed")
        #expect(caught["inflect"]?.contains("^[%lld file](inflect: true)") == true, "Romanian cannot inflect")
        #expect(caught["plural"]?.contains("%lld files") == true, "Romanian has one, few, other")
        #expect(caught["plural"]?.contains("%lld kept") == true, "a count with one form")
        #expect(caught["plural"]?.contains("Step %lld of %lld") != true, "a position needs no form of its own")
        #expect(caught["plural"]?.contains("%lld apps") == true, "no form shows the number")
        #expect(caught["plural"]?.contains("%lld folders") == true, "French `one` is 0 as well as 1")
        let substituted = "^[%lld file](inflect: true) in ^[%lld folder](inflect: true)"
        #expect(caught["placeholder"]?.contains(substituted) != true, "a count written as a substitution fills its slot")
        #expect(caught["plural"]?.contains(substituted) == true, "a substitution is missing Romanian's other")
        #expect(caught["dash"]?.contains("Move to Trash") == true)
        #expect(caught["ellipsis"]?.contains("Choose…") == true)
        #expect(caught["markdown"]?.contains("Run `brew unpin`") == true)
        #expect(caught["markdown"]?.contains("Uses [a tool](peel-license:tool)") == true, "a link's address changed")
        #expect(caught["sameEverywhere"]?.contains("OrbStack") == true, "a name or a command, never to translate")
        #expect(caught["apostrophe"]?.contains("Don't") == true, "the English writes the curly apostrophe")
        #expect(caught["apostrophe"]?.contains("Can’t open %@") == true, "French writes its own apostrophe")
        #expect(caught["apostrophe"]?.contains("Open in Photos") != true, "Dutch writes the straight one, as its macOS does")
        #expect(caught["case"]?.contains("%@: links") == true, "a word that starts the line takes a capital")
        #expect(caught["case"]?.contains("%@ used") != true, "the line starts with the figure")
    }

    /// Text the user reads always goes through the catalogs. `Text(verbatim:)` is only for what is not words, or
    /// for a name.
    @Test func noVerbatimTextIsAnInterfaceSentence() throws {
        let allowed: Set<String> = [
            "Peel", "PEEL", "brew", "Țugui Dragoș-Constantin", "github.com/TuguiDragos/Peel", "© 2026", "·",
        ]
        let literal = try NSRegularExpression(pattern: #"Text\(verbatim: "((?:[^"\\]|\\.)*)"\)"#)
        var found: [String] = []
        for folder in ["Peel", "PeelFinder"] {
            let enumerator = FileManager.default.enumerator(at: Self.repository.appending(path: folder), includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "swift", let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
                for match in literal.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                    let text = String(source[Range(match.range(at: 1), in: source)!])
                    guard !allowed.contains(text), text.contains(where: \.isLetter), !text.contains("\\(") else { continue }
                    found.append("\(url.lastPathComponent): \(text)")
                }
            }
        }
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }

    static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    /// The languages the project declares, which are the ones the build ships. English and Base, the source,
    /// are left out.
    static func declaredLanguages() throws -> [String] {
        let project = try String(contentsOf: repository.appending(path: "Peel.xcodeproj/project.pbxproj"), encoding: .utf8)
        guard let range = project.range(of: #"knownRegions = \(([^)]*)\);"#, options: .regularExpression) else { return [] }
        return project[range]
            .dropFirst("knownRegions = (".count).dropLast(2)
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \n\t\"")) }
            .filter { !$0.isEmpty && $0 != "en" && $0 != "Base" }
    }
}

struct Catalog: CustomTestStringConvertible, Sendable {
    enum Table: Sendable { case localizable, infoPlist, appShortcuts }
    let path: String
    let table: Table
    var testDescription: String { path }
}

struct CatalogProblem: CustomStringConvertible {
    let catalog: String
    let key: String
    let language: String
    let rule: String
    let detail: String
    var description: String { "\(rule) [\(catalog) \(language)] \(key.debugDescription): \(detail)" }
}

struct CatalogChecker {
    /// The CLDR 48 cardinal plural categories of each language (cldr-json 48.2.2, `plurals.json`). Portuguese
    /// ships as `pt` with Brazilian text.
    static let plurals: [String: Set<String>] = [
        "en": ["one", "other"], "de": ["one", "other"], "nl": ["one", "other"], "sv": ["one", "other"], "tr": ["one", "other"],
        "ro": ["one", "few", "other"],
        "fr": ["one", "many", "other"], "es": ["one", "many", "other"], "it": ["one", "many", "other"], "pt": ["one", "many", "other"],
        "ja": ["other"], "ko": ["other"], "zh-Hans": ["other"], "zh-Hant": ["other"],
        "ru": ["one", "few", "many", "other"], "uk": ["one", "few", "many", "other"], "pl": ["one", "few", "many", "other"],
        "cs": ["one", "few", "many", "other"],
    ]
    static let dashes: Set<Character> = ["\u{2012}", "\u{2013}", "\u{2014}", "\u{2015}", "\u{2E3A}", "\u{2E3B}", "\u{FE31}", "\u{FE32}", "\u{FE58}"]
    /// The languages whose macOS writes the straight apostrophe, inside words and as its quotes: Apple's Dutch writes
    /// `Foto's` and `de map 'Apps'`. Every other language, English included, writes its own typographic marks.
    static let straightApostrophe: Set<String> = ["nl"]
    /// Keys whose numbers are positions, with no word that changes with them, so they need no plural variation.
    static let countsWithoutAgreement: Set<String> = ["Step %lld of %lld"]
    /// Languages where `one` covers more than 1, so a `one` form without the number would also show for other
    /// counts. In French and Portuguese 0 takes `one`, and in Russian and Ukrainian 21 and 101 do.
    static let oneIsMoreThanOne: Set<String> = ["fr", "pt", "ru", "uk"]
    static let integer = try! NSRegularExpression(pattern: #"%(\d+\$)?(ll|l)?d"#)
    /// The language codes Apple's tables use where they differ from Peel's.
    static let appleLanguages = ["zh-Hans": "zh_CN", "zh-Hant": "zh_TW", "pt": "pt_BR"]
    /// What Peel calls by macOS's own names, each with the system table and key that hold that name.
    static let systemWords: [(key: String, table: String, apple: String)] = [
        ("Full Disk Access", "/System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex/Contents/Resources/Localizable.loctable", "ALL_FILES"),
        ("App Management", "/System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex/Contents/Resources/Localizable.loctable", "APPLICATION_BUNDLES"),
        ("Show in Finder", "/System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex/Contents/Resources/Localizable.loctable", "REVEAL_IN_FINDER"),
        ("Login Items & Extensions", "/System/Library/ExtensionKit/Extensions/LoginItems.appex/Contents/Resources/Localizable.loctable", "Login Items & Extensions"),
    ]
    /// The items Peel puts in menus SwiftUI builds, each with SwiftUI's key. Their words are SwiftUI's, whatever
    /// the English says: in Polish, About Peel reads "Peel…".
    static let menuWords = ["About Peel": "About %@", "Quit Peel": "Quit %@", "Settings…": "Settings…", "Find": "Find", "Undo": "Undo", "Redo": "Redo", "Copy": "Copy", "Select All": "Select All"]
    /// Names SwiftUI looks up in the app's own strings, so an app without the key shows them in English: here, the
    /// name of the tab bar a `TabView` puts in the toolbar, which VoiceOver reads and the overflow menu shows.
    static let swiftUIWords = ["Navigation Tab Bar": "Navigation Tab Bar"]
    /// A named count comes first in the pattern: read as a specifier, `%#@selected@` would be a `%@` with a `#` flag.
    static let specifier = try! NSRegularExpression(
        pattern: #"%#@[A-Za-z0-9_]+@|\$\{[A-Za-z]+\}|%(?:(\d+)\$)?[-+ #0']*\d*(?:\.\d+)?(hh|h|ll|l|q|L|z|t|j)?([@dDiuUxXoOfFeEgGcCsSpaA])|%%"#
    )

    let root: URL
    let required: [String]
    var problems: [CatalogProblem] = []
    var warnings: [CatalogProblem] = []

    /// Whether a translation may keep the `inflect` markup, which needs Foundation to inflect the language.
    /// Korean is left out: its particles inflect, but every English key marks a count, and Korean counts have
    /// one form.
    static func keepsInflection(_ language: String) -> Bool {
        language != "ko" && InflectionRule.canInflect(language: language)
    }

    struct Slot: Hashable, Comparable {
        let position: Int
        let kind: String
        static func < (a: Slot, b: Slot) -> Bool { (a.position, a.kind) < (b.position, b.kind) }
    }

    /// The arguments a string reads, by position, and whether it numbered them.
    static func slots(_ text: String) -> (slots: [Slot], numbered: Int, unnumbered: Int, named: [String]) {
        var slots: [Slot] = []
        var numbered = 0, unnumbered = 0, next = 1
        var named: [String] = []
        for match in specifier.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let whole = String(text[Range(match.range, in: text)!])
            if whole == "%%" { continue }
            if whole.hasPrefix("${") || whole.hasPrefix("%#@") { named.append(whole); continue }
            let length = match.range(at: 2).location == NSNotFound ? "" : String(text[Range(match.range(at: 2), in: text)!])
            let conversion = String(text[Range(match.range(at: 3), in: text)!])
            let kind = conversion == "@" ? "@" : length + conversion
            if match.range(at: 1).location != NSNotFound {
                numbered += 1
                slots.append(Slot(position: Int(text[Range(match.range(at: 1), in: text)!])!, kind: kind))
            } else {
                unnumbered += 1
                slots.append(Slot(position: next, kind: kind))
                next += 1
            }
        }
        return (slots.sorted(), numbered, unnumbered, named.sorted())
    }

    /// The addresses of a string's Markdown links, which a translation keeps as they are.
    static func linkTargets(_ text: String) -> [String] {
        let link = try! NSRegularExpression(pattern: #"\]\(([^)]*)\)"#)
        return link.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .map { String(text[Range($0.range(at: 1), in: text)!]) }
            .filter { !$0.hasPrefix("inflect:") }
            .sorted()
    }

    /// Nil when the markup is sound: every `^[` became one inflected run and nothing of the syntax is left.
    static func brokenInflection(_ text: String) -> String? {
        let opened = text.components(separatedBy: "^[").count - 1
        guard opened > 0 || text.contains("(inflect") else { return nil }
        do {
            let parsed = try AttributedString(markdown: text, including: \.foundation, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            let runs = parsed.runs.filter { $0.inflect != nil }.count
            let left = String(parsed.characters)
            if runs != opened { return "\(opened) ^[ but \(runs) inflected runs" }
            if left.contains("^[") || left.contains("](") { return "markup left in the text" }
            return nil
        } catch {
            return "Foundation cannot parse it"
        }
    }

    mutating func fail(_ catalog: String, _ key: String, _ language: String, _ rule: String, _ detail: String) {
        problems.append(CatalogProblem(catalog: catalog, key: key, language: language, rule: rule, detail: detail))
    }

    mutating func warn(_ catalog: String, _ key: String, _ language: String, _ rule: String, _ detail: String) {
        warnings.append(CatalogProblem(catalog: catalog, key: key, language: language, rule: rule, detail: detail))
    }

    func load(_ path: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: root.appending(path: path)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    struct Leaf {
        var category: String?
        var state: String?
        var text: String
        /// One form of a count inside a sentence with several, where `%arg` stands for the count.
        var isSubstitution = false
    }

    /// Every leaf a language holds for one key: its plural category, if any, its state and its text.
    func leaves(_ node: [String: Any], category: String? = nil, isSubstitution: Bool = false) -> [Leaf] {
        var found: [Leaf] = []
        if let unit = node["stringUnit"] as? [String: Any] {
            found.append(Leaf(category: category, state: unit["state"] as? String, text: unit["value"] as? String ?? "", isSubstitution: isSubstitution))
        }
        if let set = node["stringSet"] as? [String: Any] {
            found += (set["values"] as? [String] ?? [""]).map { Leaf(category: category, state: set["state"] as? String, text: $0) }
        }
        for (_, kinds) in node["variations"] as? [String: Any] ?? [:] {
            for (name, child) in kinds as? [String: Any] ?? [:] {
                found += leaves(child as? [String: Any] ?? [:], category: name, isSubstitution: isSubstitution)
            }
        }
        for (_, substitution) in node["substitutions"] as? [String: Any] ?? [:] {
            found += leaves(substitution as? [String: Any] ?? [:], isSubstitution: true)
        }
        return found
    }

    /// The arguments a sentence with several counts reads through `%#@name@`, by name.
    static func substitutions(_ node: [String: Any]) -> [String: Slot] {
        var found: [String: Slot] = [:]
        for (name, value) in node["substitutions"] as? [String: Any] ?? [:] {
            guard let substitution = value as? [String: Any], let position = substitution["argNum"] as? Int else { continue }
            let specifier = substitution["formatSpecifier"] as? String ?? "@"
            found["%#@\(name)@"] = Slot(position: position, kind: specifier)
        }
        return found
    }

    mutating func check(_ catalog: Catalog) {
        let path = catalog.path
        guard let file = load(path) else {
            fail(path, "", "", "missing", "cannot read the catalog")
            return
        }
        let strings = file["strings"] as? [String: [String: Any]] ?? [:]
        var present: Set<String> = []
        for (key, entry) in strings.sorted(by: { $0.key < $1.key }) {
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            let translated = localizations.keys.filter { $0 != "en" }
            present.formUnion(translated)
            if entry["extractionState"] as? String == "stale" { fail(path, key, "", "stale", "the code no longer has it, and it still ships") }
            if entry["shouldTranslate"] as? Bool == false {
                if !translated.isEmpty { fail(path, key, "", "shouldTranslate", "marked never to translate, and translated") }
                continue
            }
            // A key with a value of its own (`Unknown (extension state)`) is translated from that value.
            let source = englishValue(localizations) ?? key
            if source.contains("'") { fail(path, key, "en", "apostrophe", "the straight apostrophe: write ’, as macOS does") }
            // The same words in every language are a name or a command, which no translator should be asked for.
            let values = required.map { ((localizations[$0] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String }
            if !required.isEmpty, source.contains(where: \.isLetter), values.allSatisfy({ $0 == source }) {
                fail(path, key, "", "sameEverywhere", "the English in every language: mark it never to translate")
            }
            let sourceSlots = Self.slots(source)
            for language in Set(required).union(translated).sorted() {
                guard let node = localizations[language] as? [String: Any] else {
                    if required.contains(language) { fail(path, key, language, "missing", "no translation") }
                    continue
                }
                let found = leaves(node)
                if found.isEmpty { fail(path, key, language, "shape", "no stringUnit, stringSet or variation") }
                let substitutions = Self.substitutions(node)
                if (Self.plurals[language]?.count ?? 1) > 1, !Self.countsWithoutAgreement.contains(key),
                   Self.integer.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) != nil,
                   found.allSatisfy({ $0.category == nil }) {
                    fail(path, key, language, "plural", "it counts something, and this language needs a plural variation for it")
                }
                let categories = Set(found.filter { !$0.isSubstitution }.compactMap(\.category))
                let forms = found.filter { $0.category != nil && !$0.isSubstitution }
                if !forms.isEmpty, !forms.contains(where: { Self.integer.firstMatch(in: $0.text, range: NSRange($0.text.startIndex..., in: $0.text)) != nil }) {
                    fail(path, key, language, "plural", "no form shows the number, which Xcode refuses to build: write a key for one and one for more")
                }
                if Self.oneIsMoreThanOne.contains(language) {
                    let ones = found.filter { $0.category == "one" }
                    if ones.contains(where: { $0.isSubstitution ? !$0.text.contains("%arg") : Self.integer.firstMatch(in: $0.text, range: NSRange($0.text.startIndex..., in: $0.text)) == nil }) {
                        fail(path, key, language, "plural", "`one` is not only 1 in this language, so its form shows the number")
                    }
                }
                if !categories.isEmpty, let cldr = Self.plurals[language] {
                    let missing = cldr.subtracting(categories)
                    let extra = categories.subtracting(cldr).subtracting(["zero"])
                    if !missing.isEmpty { fail(path, key, language, "plural", "missing \(missing.sorted())") }
                    if !extra.isEmpty { fail(path, key, language, "plural", "\(extra.sorted()) is no category of this language") }
                }
                for leaf in found {
                    check(leaf, key: key, source: source, sourceSlots: sourceSlots, substitutions: substitutions, language: language, catalog: catalog)
                }
                for (name, forms) in Self.substitutionCategories(node) {
                    guard let cldr = Self.plurals[language], !forms.isEmpty else { continue }
                    if !cldr.subtracting(forms).isEmpty { fail(path, key, language, "plural", "\(name) is missing \(cldr.subtracting(forms).sorted())") }
                }
            }
        }
        for language in present.subtracting(required).sorted() {
            warn(path, "", language, "undeclared", "translations exist and the language is not in knownRegions, so it ships half done")
        }
    }

    private mutating func check(
        _ leaf: Leaf, key: String, source: String, sourceSlots: (slots: [Slot], numbered: Int, unnumbered: Int, named: [String]),
        substitutions: [String: Slot], language: String, catalog: Catalog
    ) {
        let path = catalog.path
        let text = leaf.text
        guard !text.isEmpty else {
            fail(path, key, language, "empty", "an empty value ships empty, and crashes AttributedString(localized:) with an argument")
            return
        }
        if required.contains(language), leaf.state != "translated" { fail(path, key, language, "state", leaf.state ?? "no state") }
        if let dash = text.first(where: { Self.dashes.contains($0) }) {
            fail(path, key, language, "dash", "U+\(String(dash.unicodeScalars.first!.value, radix: 16, uppercase: true))")
        }
        if text.contains("'"), !Self.straightApostrophe.contains(language) {
            fail(path, key, language, "apostrophe", "the straight apostrophe: write this language's own, as its macOS does")
        }
        // A key that starts with a placeholder starts its line, so a translation that starts with a word instead
        // capitalizes it. A substitution sits inside its sentence.
        if !leaf.isSubstitution, source.first == "%", let first = text.first, first.isLetter, first.isLowercase {
            fail(path, key, language, "case", "the line starts with this word here, so it takes a capital")
        }
        if text.contains("...") { fail(path, key, language, "ellipsis", "three full stops") }
        let ellipsis: Character = language == "zh-Hant" ? "\u{22EF}" : "…"
        if Self.menuWords[key] == nil, text.filter({ $0 == ellipsis }).count != source.filter({ $0 == "…" }).count {
            fail(path, key, language, "ellipsis", "the English has \(source.filter { $0 == "…" }.count), written \(ellipsis) in this language")
        }
        for mark in ["`", "*", "_"] where text.components(separatedBy: mark).count != source.components(separatedBy: mark).count {
            fail(path, key, language, "markdown", "\(mark) is formatting: as many as the English has")
        }
        if Self.linkTargets(text) != Self.linkTargets(source) { fail(path, key, language, "markdown", "a link's address has to stay as the English has it") }
        if let broken = Self.brokenInflection(text) { fail(path, key, language, "inflect", broken) }
        if text.contains("^["), !source.contains("^[") { fail(path, key, language, "inflect", "markup only where the English has it") }
        if text.contains("^["), !Self.keepsInflection(language) { fail(path, key, language, "inflect", "this language cannot inflect: use a plural variation") }
        if catalog.table == .appShortcuts {
            if text.components(separatedBy: "${applicationName}").count != 2 { fail(path, key, language, "phrase", "needs ${applicationName} exactly once") }
            if Self.slots(text).named.filter({ $0 != "${applicationName}" }).count > 1 { fail(path, key, language, "phrase", "one parameter at most") }
            return
        }
        guard !leaf.isSubstitution else { return }
        var slots = Self.slots(text)
        for name in slots.named where substitutions[name] != nil {
            slots.slots.append(substitutions[name]!)
        }
        slots.slots.sort()
        slots.named.removeAll { substitutions[$0] != nil }
        if slots.numbered > 0, slots.unnumbered > 0 { fail(path, key, language, "placeholder", "numbered and unnumbered mixed") }
        if slots.named != sourceSlots.named { fail(path, key, language, "placeholder", "\(slots.named) against \(sourceSlots.named)") }
        if slots.slots != sourceSlots.slots {
            let dropped = Set(sourceSlots.slots).subtracting(slots.slots)
            let added = Set(slots.slots).subtracting(sourceSlots.slots)
            // A plural form may leave its count out ("one file"), but never a name, and only when what is
            // left is numbered: an unnumbered %@ would then read the count.
            let safeDrop = leaf.category != nil && added.isEmpty && dropped.allSatisfy { $0.kind != "@" } && slots.unnumbered == 0
            if !safeDrop {
                fail(path, key, language, "placeholder", "\(slots.slots.map { "\($0.position):\($0.kind)" }) against \(sourceSlots.slots.map { "\($0.position):\($0.kind)" })")
            }
        }
        if source.contains("Peel"), !text.contains("Peel") { warn(path, key, language, "name", "Peel is missing") }
    }

    /// The plural forms of each count in a sentence with several counts.
    static func substitutionCategories(_ node: [String: Any]) -> [String: Set<String>] {
        var found: [String: Set<String>] = [:]
        for (name, value) in node["substitutions"] as? [String: Any] ?? [:] {
            let plural = ((value as? [String: Any])?["variations"] as? [String: Any])?["plural"] as? [String: Any] ?? [:]
            found[name] = Set(plural.keys)
        }
        return found
    }

    func englishValue(_ localizations: [String: Any]) -> String? {
        ((localizations["en"] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
    }

    mutating func checkMenuWords() {
        check(Self.menuWords, against: "MainMenu", rule: "menu")
        check(Self.swiftUIWords, against: "Localizable", rule: "swiftui")
    }

    /// Compares each of `words` in Peel's catalog with one of SwiftUI's own tables. A key the catalog lacks
    /// fails too, since SwiftUI then shows its English.
    private mutating func check(_ words: [String: String], against table: String, rule: String) {
        let url = URL(filePath: "/System/Library/Frameworks/SwiftUI.framework/Versions/Current/Resources/\(table).loctable")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let catalog = load("Localization/Peel/Localizable.xcstrings")?["strings"] as? [String: [String: Any]] else { return }
        for (key, apple) in words.sorted(by: { $0.key < $1.key }) {
            guard let localizations = catalog[key]?["localizations"] as? [String: Any] else {
                fail("Localization/Peel/Localizable.xcstrings", key, "en", rule, "missing, so SwiftUI shows its English")
                continue
            }
            for (language, node) in localizations where language != "en" {
                let swiftUILanguage = Self.appleLanguages[language] ?? language
                guard let expected = (plist[swiftUILanguage] as? [String: String])?[apple]?.replacingOccurrences(of: "%@", with: "Peel"),
                      let value = leaves(node as? [String: Any] ?? [:]).first?.text else { continue }
                if value != expected { fail("Localization/Peel/Localizable.xcstrings", key, language, rule, "SwiftUI says \(expected.debugDescription)") }
            }
        }
    }

    /// Compares each of `systemWords` in Peel's catalog with the name macOS gives it in that language. A no-break
    /// space counts as a space: some languages keep a short word on the line of the next one.
    mutating func checkSystemWords() {
        guard let catalog = load("Localization/Peel/Localizable.xcstrings")?["strings"] as? [String: [String: Any]] else { return }
        func spaced(_ text: String) -> String {
            text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
        }
        for word in Self.systemWords {
            guard let data = try? Data(contentsOf: URL(filePath: word.table)),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                fail("Localization/Peel/Localizable.xcstrings", word.key, "en", "system", "\(word.table) is not on this Mac")
                continue
            }
            let localizations = catalog[word.key]?["localizations"] as? [String: Any] ?? [:]
            for language in required {
                guard let expected = (plist[Self.appleLanguages[language] ?? language] as? [String: Any])?[word.apple] as? String else {
                    fail("Localization/Peel/Localizable.xcstrings", word.key, language, "system", "macOS has no \(word.apple) in this language")
                    continue
                }
                let value = leaves(localizations[language] as? [String: Any] ?? [:]).first?.text
                if value.map(spaced) != spaced(expected) {
                    fail("Localization/Peel/Localizable.xcstrings", word.key, language, "system", "macOS says \(expected.debugDescription)")
                }
            }
        }
    }

    mutating func checkFinderItem() {
        guard let finder = load("Localization/PeelFinder/Localizable.xcstrings")?["strings"] as? [String: [String: Any]],
              let app = load("Localization/Peel/Localizable.xcstrings")?["strings"] as? [String: [String: Any]],
              let item = finder["Uninstall with Peel…"]?["localizations"] as? [String: Any] else { return }
        for (language, node) in item where language != "en" {
            guard let name = leaves(node as? [String: Any] ?? [:]).first?.text else { continue }
            // The app names the item in running text, where it has no ellipsis.
            let quoted = name.trimmingCharacters(in: CharacterSet(charactersIn: "…\u{22EF} \u{00A0}"))
            for (key, entry) in app where key.contains("Uninstall with Peel") {
                guard let local = (entry["localizations"] as? [String: Any])?[language] as? [String: Any],
                      let text = leaves(local).first?.text else { continue }
                if !text.contains(quoted) { fail("Localization/Peel/Localizable.xcstrings", key, language, "finder", "does not quote \(quoted.debugDescription)") }
            }
        }
    }
}
