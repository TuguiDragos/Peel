public import Foundation
internal import PeelPrivileged

/// The paths a Homebrew cask says its app leaves behind. Peel treats them as evidence only: each path still
/// goes through the usual checks, and one that is not `isInLibrary` is shown but never selected for the user.
public struct CaskEvidence: Sendable, Hashable {
    public struct Item: Sendable, Hashable {
        public let url: URL
        /// True for a path in `~/Library`, `/Library`, or `/private/var/folders`, where Peel looks for leftovers
        /// anyway. Any other path is only shown, never selected for the user.
        public let isInLibrary: Bool
    }

    public let items: [Item]

    public static func evidence(
        for app: InstalledApp,
        casks: [HomebrewPackage],
        home: URL = .homeDirectory
    ) -> CaskEvidence? {
        guard let cask = cask(for: app, in: casks) else { return nil }
        var seen: Set<ItemKey> = []
        let named = cask.leftoverPatterns.flatMap { expand($0, home: home) }
        let emptied = cask.emptyFolderPatterns.flatMap { expand($0, home: home) }.filter(holdsNothing)
        let items = (named + emptied).compactMap { url -> Item? in
            // A folder listed twice, with and without a slash at the end or in another case, becomes one item.
            guard seen.insert(ItemKey(url)).inserted else { return nil }
            return Item(url: url, isInLibrary: isInLibrary(url, home: home))
        }
        guard !items.isEmpty else { return nil }
        return CaskEvidence(items: items)
    }

    /// Returns the cask Homebrew installed this app from, if any. A cask Homebrew only has a definition for
    /// says which files belong to the app, not that this copy came from Homebrew. A second copy of the app,
    /// in a place Homebrew did not put it, is not the one `brew upgrade` changes, so it has no installed cask.
    public static func installedCask(for app: InstalledApp, in casks: [HomebrewPackage]) -> HomebrewPackage? {
        let path = PathPattern.comparablePath(of: app.url)
        return casks.first { cask in
            guard cask.installedVersion != nil else { return false }
            let isAmong = { (apps: [String]) in apps.contains { $0.caseInsensitiveCompare(path) == .orderedSame } }
            if isAmong(cask.packagedApps) { return true }
            return proves(cask, isThe: app) && (cask.appTargets.isEmpty || isAmong(cask.appTargets))
        }
    }

    /// Returns the cask whose definition describes this app. Several casks can describe one app (`firefox`,
    /// `firefox@beta`, and `firefox@esr` all install `Firefox.app`), so the installed one is preferred, and otherwise
    /// the line the copy is on: the one at the copy's very version, else the one whose version starts with the copy's
    /// first number, the plain token first, else the closest one below it, and none when no line is. A copy whose
    /// version can't be read gets the plain one.
    static func cask(for app: InstalledApp, in casks: [HomebrewPackage]) -> HomebrewPackage? {
        let proving = casks.filter { proves($0, isThe: app) }
        if let installed = proving.first(where: { $0.installedVersion != nil }) { return installed }
        guard proving.count > 1 else { return proving.first }
        let isPlain = { (cask: HomebrewPackage) in !cask.name.contains("@") }
        let major = { (version: String?) in version.flatMap { Int($0.prefix { $0.isASCII && $0.isNumber }) } }
        guard let copy = major(app.version) else { return proving.first(where: isPlain) ?? proving.first }
        let atIt = proving.filter { $0.latestVersion.map(UpdateStatus.shownVersion(of:)) == app.version }
        if let line = atIt.first(where: isPlain) ?? atIt.first { return line }
        let lines = proving.compactMap { cask in major(cask.latestVersion).map { (cask: cask, major: $0) } }
        let onIt = lines.filter { $0.major == copy }
        if let line = onIt.first(where: { isPlain($0.cask) }) ?? onIt.first { return line.cask }
        return lines.filter { $0.major < copy }.max { $0.major < $1.major }?.cask
    }

    /// Returns the names a cask for this app could go by. Homebrew's token doesn't always follow the app's
    /// name: AltTab is `alt-tab`, Hidden Bar is `hiddenbar`, and HandBrake is `handbrake-app`. Each one is only
    /// a guess, which `proves(_:isThe:)` then checks.
    static func tokens(for app: InstalledApp) -> [String] {
        var tokens: [String] = []
        for name in app.names {
            let plain = tokenize(name)
            let candidates = [
                plain, tokenize(separatingWords(in: name)), plain.replacingOccurrences(of: "-", with: ""),
                plain + "-app",
            ]
            for candidate in candidates where candidate.count >= 2 && !tokens.contains(candidate) {
                tokens.append(candidate)
            }
        }
        return tokens
    }

    private static func tokenize(_ name: String) -> String {
        var token = ""
        var lastWasSeparator = false
        for character in name.lowercased() {
            if character.isLetter || character.isNumber {
                token.append(character)
                lastWasSeparator = false
            } else if !token.isEmpty, !lastWasSeparator {
                token.append("-")
                lastWasSeparator = true
            }
        }
        while token.hasSuffix("-") { token.removeLast() }
        return token
    }

    /// Splits words written together ("AltTab" becomes "Alt Tab"), so the token matches Homebrew's `alt-tab`.
    private static func separatingWords(in name: String) -> String {
        var separated = ""
        var previous: Character?
        for character in name {
            if let previous, previous.isLowercase || previous.isNumber, character.isUppercase {
                separated.append(" ")
            }
            separated.append(character)
            previous = character
        }
        return separated
    }

    /// Returns whether `cask` really is this app's cask. A wrong match would hand one app's files to another,
    /// so a guessed name is never enough. The cask has to name the app's bundle, quit the app by its bundle
    /// identifier, or list the app's installer receipt while it is on the Mac (`HomebrewPackage.noting(receipts:)`).
    static func proves(_ cask: HomebrewPackage, isThe app: InstalledApp) -> Bool {
        guard cask.kind == .cask else { return false }
        let identifier = app.bundleIdentifier?.lowercased()
        let quits = cask.quitIdentifiers.map { $0.lowercased() }

        // A bundle's file name is whatever its maker called it, and two real casks install a `Caffeine.app`.
        // So the name counts unless the identifiers the cask goes by, those it quits or else those its paths are
        // named for, are all some other maker's.
        let bundleName = app.url.lastPathComponent
        if cask.appNames.contains(where: { $0.caseInsensitiveCompare(bundleName) == .orderedSame }) {
            let maker = identifier.flatMap(Identifier.vendor(of:))
            let isTheAppsOrItsMakers = { (named: String) in
                identifier.map { named == $0 || named.hasPrefix($0 + ".") } == true
                    || maker != nil && Identifier.vendor(of: named) == maker
            }
            let goesBy = quits.isEmpty ? identifiers(namingThePathsOf: cask) : quits
            if goesBy.isEmpty || goesBy.contains(where: isTheAppsOrItsMakers) {
                return true
            }
        }

        guard let identifier else { return false }
        if quits.contains(identifier) { return true }

        return cask.receiptsOnThisMac.contains { PackageReceipts.proves($0, isThe: identifier) }
    }

    /// The identifiers the last names of `cask`'s paths read as, lowercased, Apple's left out: what a path removes is
    /// named for whoever made it, while a folder above it can be Apple's or a framework's.
    static func identifiers(namingThePathsOf cask: HomebrewPackage) -> [String] {
        (cask.leftoverPatterns + cask.emptyFolderPatterns).compactMap { pattern in
            var name = String((pattern.split(separator: "/").last ?? "").prefix { !"*?[{".contains($0) })
            while let last = name.last, ".-_".contains(last) { name.removeLast() }
            if name.hasPrefix("group.") { name.removeFirst("group.".count) }
            let lowered = name.lowercased()
            return Identifier.isReverseDNS(name) && !ProtectedData.isApplesName(lowered) ? lowered : nil
        }
    }

    /// Returns the casks that describe `apps`, including apps Homebrew did not install. A cask lists what its
    /// app leaves behind, even a folder named nothing like the app, which name matching cannot find. Only
    /// Homebrew's local copy of its definitions is read, so nothing goes over the network, and no cask is
    /// asked about when Homebrew or that copy is missing. Each carries Homebrew's last check for new versions, which
    /// the version it lists is no more recent than.
    @concurrent
    public static func knownCasks(for apps: [InstalledApp], receipts: Set<String> = []) async -> [HomebrewPackage] {
        let answers = Homebrew.Answers()
        guard !apps.isEmpty, await Homebrew.hasLocalDefinitions(asking: answers) else { return [] }
        // Read first, so a check made while the casks are read leaves them dated older than they are, never newer.
        let checked = await Homebrew.lastUpdateCheck(asking: answers)
        let known = await Homebrew.caskTokens()
        guard !known.isEmpty else { return [] }

        let found = await Homebrew.casks(named: tokens(for: apps, among: known)).map {
            $0.noting(receipts: receipts).noting(lastUpdateCheck: checked)
        }
        return found.filter { cask in apps.contains { proves(cask, isThe: $0) } }
    }

    /// The tokens to ask Homebrew about for `apps`: the names a cask for each could go by, among those `known` has,
    /// each with every line Homebrew keeps of it (`firefox@esr` beside `firefox`).
    static func tokens(for apps: [InstalledApp], among known: Set<String>) -> [String] {
        let lines = Dictionary(grouping: known.filter { $0.contains("@") }) { String($0.prefix { $0 != "@" }) }
        var wanted: [String] = []
        var seen: Set<String> = []
        for app in apps {
            for token in tokens(for: app) where known.contains(token) {
                for named in [token] + (lines[token] ?? []).sorted() where seen.insert(named).inserted {
                    wanted.append(named)
                }
            }
        }
        return wanted
    }

    /// Merges installed packages with the casks Homebrew only knows of, keeping the installed one when both
    /// share an ID.
    public static func combined(installed: [HomebrewPackage], known: [HomebrewPackage]) -> [HomebrewPackage] {
        var byID = Dictionary(installed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for cask in known where byID[cask.id] == nil {
            byID[cask.id] = cask
        }
        return byID.values.sorted { $0.id < $1.id }
    }

    /// Past this many folders, `holdsNothing` answers no rather than walk on.
    private static let foldersLookedInto = 200

    /// Homebrew's rule for `rmdir`: a real folder with nothing in it but folders and `.DS_Store`, all the way down.
    static func holdsNothing(_ folder: URL) -> Bool {
        var pending = [folder]
        var visited = 0
        while let next = pending.popLast() {
            visited += 1
            guard visited <= foldersLookedInto, next.isRealFolder,
                  let children = try? FileManager.default.contentsOfDirectory(at: next, includingPropertiesForKeys: nil)
            else { return false }
            pending += children.filter { $0.lastPathComponent != ".DS_Store" }
        }
        return true
    }

    /// A cask's path read as Homebrew reads one (`each_resolved_path` in its `abstract_uninstall.rb`): `~` is the home
    /// folder only before a slash, and a relative path or one with a `.` or `..` in it is skipped.
    static func expand(_ pattern: String, home: URL) -> [URL] {
        guard pattern.hasPrefix("/") || pattern == "~" || pattern.hasPrefix("~/"),
              !PathComponents.of(pattern).contains(where: { $0 == "." || $0 == ".." })
        else { return [] }
        return PathPattern.expand(pattern, home: home, from: .cask)
    }

    static func isInLibrary(_ url: URL, home: URL) -> Bool {
        let path = PathPattern.comparablePath(of: url)
        let homePath = PathPattern.comparablePath(of: home)
        if PathComponents.isPath(path, inside: homePath) {
            return PathComponents.isPath(path, inside: homePath + "/Library")
        }
        return PathComponents.isPath(path, inside: "/Library") || PathComponents.isPath(path, inside: "/private/var/folders")
    }
}
