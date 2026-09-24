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

    public static func evidence(for app: InstalledApp, casks: [HomebrewPackage], home: URL = .homeDirectory) -> CaskEvidence? {
        guard let cask = cask(for: app, in: casks) else { return nil }
        var seen: Set<String> = []
        let named = cask.leftoverPatterns.flatMap { expand($0, home: home) }
        let emptied = cask.emptyFolderPatterns.flatMap { expand($0, home: home) }.filter(holdsNothing)
        let items = (named + emptied).compactMap { url -> Item? in
            // A folder listed twice, such as with and without a trailing slash, becomes one item.
            guard seen.insert(PathPattern.comparablePath(of: url)).inserted else { return nil }
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
            guard cask.installedVersion != nil, proves(cask, isThe: app) else { return false }
            return cask.appTargets.isEmpty || cask.appTargets.contains { $0.caseInsensitiveCompare(path) == .orderedSame }
        }
    }

    /// Returns the cask whose definition describes this app. Several casks can describe one app (`firefox`,
    /// `firefox@beta`, and `firefox@esr` all install `Firefox.app`), so the installed one is preferred.
    static func cask(for app: InstalledApp, in casks: [HomebrewPackage]) -> HomebrewPackage? {
        let proving = casks.filter { proves($0, isThe: app) }
        return proving.first { $0.installedVersion != nil } ?? proving.first
    }

    /// Returns the names a cask for this app could go by. Homebrew's token doesn't always follow the app's
    /// name: AltTab is `alt-tab`, Hidden Bar is `hiddenbar`, and HandBrake is `handbrake-app`. Each one is only
    /// a guess, which `proves(_:isThe:)` then checks.
    static func tokens(for app: InstalledApp) -> [String] {
        var tokens: [String] = []
        for name in app.names {
            let plain = tokenize(name)
            let candidates = [plain, tokenize(separatingWords(in: name)), plain.replacingOccurrences(of: "-", with: ""), plain + "-app"]
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
        let identifier = app.bundleIdentifier.lowercased()
        let quits = cask.quitIdentifiers.map { $0.lowercased() }

        // A bundle's file name is whatever its maker called it, and two real casks install a `Caffeine.app`.
        // So the name counts unless the cask quits identifiers and every one of them is some other maker's.
        let bundleName = app.url.lastPathComponent
        if cask.appNames.contains(where: { $0.caseInsensitiveCompare(bundleName) == .orderedSame }) {
            let maker = Identifier.vendor(of: identifier)
            if quits.isEmpty || quits.contains(where: { maker != nil && Identifier.vendor(of: $0) == maker }) { return true }
        }

        guard !identifier.isEmpty else { return false }
        if quits.contains(identifier) { return true }

        return cask.receiptsOnThisMac.contains { PackageReceipts.proves($0, isThe: identifier) }
    }

    /// Returns the casks that describe `apps`, including apps Homebrew did not install. A cask lists what its
    /// app leaves behind, even a folder named nothing like the app, which name matching cannot find. Only
    /// Homebrew's local copy of its definitions is read, so nothing goes over the network, and no cask is
    /// asked about when Homebrew or that copy is missing.
    @concurrent
    public static func knownCasks(for apps: [InstalledApp], receipts: Set<String> = []) async -> [HomebrewPackage] {
        guard !apps.isEmpty, await Homebrew.hasLocalDefinitions() else { return [] }
        let known = await Homebrew.caskTokens()
        guard !known.isEmpty else { return [] }

        var wanted: [String] = []
        var seen: Set<String> = []
        for app in apps {
            for token in tokens(for: app) where known.contains(token) && seen.insert(token).inserted {
                wanted.append(token)
            }
        }

        let found = await Homebrew.casks(named: wanted).map { $0.noting(receipts: receipts) }
        return found.filter { cask in apps.contains { proves(cask, isThe: $0) } }
    }

    /// Merges installed packages with the casks Homebrew only knows of, keeping the installed one when both
    /// share an ID. `receipts`, the installer receipts on the Mac, are noted on each installed package, since
    /// a receipt is what proves a cask that installs its app from a `.pkg`.
    public static func combined(installed: [HomebrewPackage], known: [HomebrewPackage], receipts: Set<String>) -> [HomebrewPackage] {
        var byID = Dictionary(installed.map { ($0.id, $0.noting(receipts: receipts)) }, uniquingKeysWith: { first, _ in first })
        for cask in known where byID[cask.id] == nil {
            byID[cask.id] = cask
        }
        return byID.values.sorted { $0.id < $1.id }
    }

    /// Homebrew's rule for `rmdir`: a real folder with nothing in it but folders and `.DS_Store`, all the way down.
    static func holdsNothing(_ folder: URL) -> Bool {
        var pending = [folder]
        var visited = 0
        while let next = pending.popLast() {
            visited += 1
            guard visited <= PathPattern.maximumMatches, next.isRealFolder,
                  let children = try? FileManager.default.contentsOfDirectory(at: next, includingPropertiesForKeys: nil)
            else { return false }
            pending += children.filter { $0.lastPathComponent != ".DS_Store" }
        }
        return true
    }

    /// A cask only ever names absolute paths; anything else is ignored.
    static func expand(_ pattern: String, home: URL) -> [URL] {
        guard pattern.hasPrefix("/") || pattern.hasPrefix("~") else { return [] }
        return PathPattern.expand(pattern, home: home)
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
