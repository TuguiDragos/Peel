public import Foundation

/// A large installer or backup that is easy to forget: an app's disk image, package, or archive, a macOS
/// installer, device firmware, or a backup of an iPhone or iPad.
public struct InstallerItem: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case appInstaller
        case macOSInstaller
        case firmware
        case deviceBackup
    }

    public let url: URL
    public let kind: Kind
    public let name: String
    /// Nil when measuring ran out of time or was refused. Unknown is not the same as empty.
    public let size: Int64?
    public let date: Date?
    /// The name of the installed app that this installer is for, when there is one.
    public let installedApp: String?
    /// True for a device backup: Peel shows it, but the app that made it is the one that should remove it.
    public let isReadOnly: Bool
    public let notes: [Note]
    /// True when moving the item needs administrator access, so the move goes through the helper. A macOS
    /// installer that Software Update downloaded is one: it belongs to root.
    public var requiresPrivileges = false
    /// Why the item is left for the person to choose, from what measuring it saw: it was not measured or not read,
    /// or a wallet or a repository is inside.
    public var heldBack: HoldBack?

    public var id: URL { url }

    /// A fact shown beside the item's name. The app puts it into words.
    public enum Note: Sendable, Hashable {
        /// A macOS installer's version, as its bundle gives it.
        case version(String)
        /// A name a backup gives for its device or system, such as "iPhone" or "iOS 17.2", shown as is.
        case name(String)
        case encrypted
    }
}

public struct InstallerScan: Sendable {
    public let items: [InstallerItem]
    /// The folders Peel looks in that macOS would not let it read, the device backups' among them, so what is in
    /// them is not known.
    public let unreadableLocations: [URL]

    public var needsFullDiskAccess: Bool { !unreadableLocations.isEmpty }

    public func items(in kind: InstallerItem.Kind) -> [InstallerItem] {
        items.filter { $0.kind == kind }
    }
}

public enum Installers {
    /// Anything smaller than this isn't worth a row in a list about big downloads.
    public static let minimumSize: Int64 = 20 * 1_000_000

    /// `xip` is Apple's own archive format, which Xcode ships in. `zip` is not listed, since a zip file can hold
    /// anything: `appInside(zip:)` decides about each one.
    static let installerExtensions: Set<String> = ["dmg", "iso", "pkg", "mpkg", "xip"]
    static let firmwareExtensions: Set<String> = ["ipsw"]

    @concurrent
    public static func scan(
        installedApps: [InstalledApp],
        home: URL = .homeDirectory,
        root: URL = URL(filePath: "/", directoryHint: .isDirectory),
        exclusions: Exclusions = .none,
        minimumSize: Int64 = Installers.minimumSize
    ) async -> InstallerScan {
        await scan(installedApps: installedApps, home: home, root: root, exclusions: exclusions, minimumSize: minimumSize, measure: LeftoverScanner.walk)
    }

    @concurrent
    static func scan(
        installedApps: [InstalledApp],
        home: URL,
        root: URL,
        exclusions: Exclusions,
        minimumSize: Int64,
        measure: LeftoverScanner.Measure,
        canList: (URL) -> AccessState = FullDiskAccess.canList,
        isInTheCloud: (URL) -> Bool = { $0.isInTheCloud }
    ) async -> InstallerScan {
        var items: [InstallerItem] = []
        var unreadable: [URL] = []
        let downloads = ["Downloads", "Desktop", "Documents"].map { home.appending(path: $0, directoryHint: .isDirectory) }

        for folder in downloads {
            if canList(folder) == .missing { unreadable.append(folder) }
            for url in files(in: folder) {
                // The extension is checked before measuring, since measuring a folder walks all of it.
                let suffix = url.pathExtension.lowercased()
                let isInstaller = installerExtensions.contains(suffix)
                let isArchive = suffix == "zip"
                guard isInstaller || isArchive || firmwareExtensions.contains(suffix), !exclusions.excludes(url), !Task.isCancelled else { continue }
                let (size, seen) = await measured(url, by: measure)
                guard isWorthARow(size, minimumSize) else { continue }
                let heldBack = isInTheCloud(url) ? .inTheCloud : seen
                if isArchive {
                    guard let app = appInside(zip: url) else { continue }
                    items.append(appInstaller(at: url, size: size, heldBack: heldBack, installedApps: installedApps, named: app))
                } else {
                    items.append(
                        isInstaller
                            ? appInstaller(at: url, size: size, heldBack: heldBack, installedApps: installedApps)
                            : firmware(at: url, size: size, heldBack: heldBack)
                    )
                }
            }
        }

        items += await macOSInstallers(
            in: [root.appending(path: "Applications", directoryHint: .isDirectory)] + downloads,
            exclusions: exclusions,
            minimumSize: minimumSize,
            measure: measure,
            isInTheCloud: isInTheCloud
        )
        items += await firmwareFiles(home: home, exclusions: exclusions, minimumSize: minimumSize, measure: measure)

        let backupFolder = home.appending(path: "Library/Application Support/MobileSync/Backup", directoryHint: .isDirectory)
        let readable = canList(backupFolder)
        if readable == .granted {
            items += await backups(in: backupFolder, measure: measure)
        }

        if readable == .missing { unreadable.append(backupFolder) }
        return InstallerScan(
            // An unknown size sorts first: an item that ran out of time is most likely one of the biggest.
            items: items.sorted { ($0.size ?? .max) > ($1.size ?? .max) },
            unreadableLocations: unreadable
        )
    }

    /// What measuring `url` gave: its size, and why what it saw leaves the item for the person to choose.
    private static func measured(_ url: URL, by measure: LeftoverScanner.Measure) async -> (size: Int64?, heldBack: HoldBack?) {
        let contents = await measure(url)
        return (contents.flatMap { $0.couldNotBeRead ? nil : $0.size }, HoldBack.seen(in: contents))
    }

    /// True when `size` reaches `minimumSize`. An unknown size could be any size, so it is kept.
    private static func isWorthARow(_ size: Int64?, _ minimumSize: Int64) -> Bool {
        size.map { $0 >= minimumSize } ?? true
    }

    /// Makes the item for an app installer. For an archive, `name` is the app inside it, which is matched
    /// instead of the file name: a download can be called anything, such as `download (3).zip`.
    static func appInstaller(at url: URL, size: Int64?, heldBack: HoldBack?, installedApps: [InstalledApp], named name: String? = nil) -> InstallerItem {
        let match = installedApp(named: name ?? url.deletingPathExtension().lastPathComponent, in: installedApps)
        return InstallerItem(
            url: url,
            kind: .appInstaller,
            name: url.lastPathComponent,
            size: size,
            date: creationDate(of: url),
            installedApp: match?.name,
            isReadOnly: false,
            notes: [],
            requiresPrivileges: FileAccess.requiresPrivilegesToRemove(url),
            heldBack: heldBack
        )
    }

    /// Words that can follow the app's name in an installer's file name, as `words(in:)` gives them joined: an
    /// architecture, a platform, or a word such as "setup" or "final".
    private static let afterTheName: Set<String> = ["arm64", "x64", "x8664", "amd64", "intel", "universal", "mac", "macos", "osx", "darwin", "installer", "setup", "full", "final"]

    /// Returns the installed app that the installer at `url` is for. The app's name must be the whole name in
    /// the file name, because the user may delete their only copy of an installer marked "already installed":
    /// `Xcodes-1.4.dmg` is not Xcode's, and `Archiver-4.dmg` is not Arc's.
    static func installedApp(for url: URL, in installedApps: [InstalledApp]) -> InstalledApp? {
        installedApp(named: url.deletingPathExtension().lastPathComponent, in: installedApps)
    }

    private static func installedApp(named stem: String, in installedApps: [InstalledApp]) -> InstalledApp? {
        let normalized = Naming.normalized(stem)
        guard normalized.count >= 3 else { return nil }
        let matches = installedApps.compactMap { app -> (app: InstalledApp, length: Int)? in
            let lengths = app.names
                .filter { Naming.isSignificant($0) && Naming.normalized($0).count >= 3 && names(stem, and: $0) }
                .map { Naming.normalized($0).count }
            return lengths.max().map { (app, $0) }
        }
        return matches.max { $0.length < $1.length }?.app
    }

    /// Returns the name of the app a zip archive holds, when the app is all it holds: every entry sits inside
    /// one `<Name>.app` at the top, apart from the metadata `ditto` writes (`__MACOSX`, `._` files). An archive
    /// of documents, or an app with anything beside it, is not an installer.
    static func appInside(zip url: URL) -> String? {
        guard let names = ZipDirectory.names(at: url) else { return nil }
        var app: String?
        for name in names {
            let first = String(name.prefix { $0 != "/" })
            if first == "__MACOSX" || first.hasPrefix("._") { continue }
            guard first.count > 4, first.lowercased().hasSuffix(".app"), name.count > first.count, app == nil || app == first else { return nil }
            app = first
        }
        return app.map { String($0.dropLast(4)) }
    }

    /// True when the file name `stem` is the app's `name`, alone or followed by a version, an architecture, or a
    /// word installers add. Any other word after the name makes it another product: `Notion Calendar` is not
    /// Notion, and `Signal RGB` is not Signal.
    static func names(_ stem: String, and name: String) -> Bool {
        let app = Naming.normalized(name)
        guard Naming.normalized(stem) != app else { return true }
        let words = words(in: stem)
        // The app's name covers the first words whole, however they are spelled.
        guard !words.isEmpty, let count = (1...words.count).first(where: { words.prefix($0).joined() == app }) else {
            return false
        }
        let rest = words.dropFirst(count)
        guard let first = rest.first else { return true }
        if first.first?.isNumber == true { return true }
        if first == "v", rest.dropFirst().first?.first?.isNumber == true { return true }
        return (1...rest.count).contains { afterTheName.contains(rest.prefix($0).joined()) }
    }

    /// The words of a file name, lowercased: split at each character that is neither a letter nor a digit, where a
    /// lowercase letter meets an uppercase one, and where letters meet digits.
    static func words(in name: String) -> [String] {
        var words: [String] = []
        var word = ""
        var previous: Character?
        for character in name {
            guard character.isLetter || character.isNumber else {
                if !word.isEmpty { words.append(word.lowercased()) }
                word = ""
                previous = nil
                continue
            }
            if let previous, previous.isLowercase && character.isUppercase || previous.isNumber != character.isNumber {
                words.append(word.lowercased())
                word = ""
            }
            word.append(character)
            previous = character
        }
        if !word.isEmpty { words.append(word.lowercased()) }
        return words
    }

    static func macOSInstallers(
        in folders: [URL],
        exclusions: Exclusions,
        minimumSize: Int64,
        measure: LeftoverScanner.Measure,
        isInTheCloud: (URL) -> Bool
    ) async -> [InstallerItem] {
        var items: [InstallerItem] = []
        for folder in folders {
            for url in files(in: folder) where url.pathExtension.lowercased() == "app" && url.lastPathComponent.hasPrefix("Install macOS") {
                guard !Task.isCancelled else { return items }
                guard !exclusions.excludes(url) else { continue }
                let (size, seen) = await measured(url, by: measure)
                guard isWorthARow(size, minimumSize) else { continue }
                let version = AppInspector.infoDictionary(in: url.appending(path: "Contents", directoryHint: .isDirectory))?["CFBundleShortVersionString"] as? String
                items.append(InstallerItem(
                    url: url,
                    kind: .macOSInstaller,
                    name: url.deletingPathExtension().lastPathComponent,
                    size: size,
                    date: creationDate(of: url),
                    installedApp: nil,
                    isReadOnly: false,
                    notes: version.map { [.version($0)] } ?? [],
                    requiresPrivileges: FileAccess.requiresPrivilegesToRemove(url),
                    heldBack: isInTheCloud(url) ? .inTheCloud : seen
                ))
            }
        }
        return items
    }

    static func firmwareFiles(home: URL, exclusions: Exclusions, minimumSize: Int64, measure: LeftoverScanner.Measure) async -> [InstallerItem] {
        let folders = ["iPhone", "iPad", "iPod", "Apple TV", "HomePod", "Watch"].map {
            home.appending(path: "Library/iTunes/\($0) Software Updates", directoryHint: .isDirectory)
        }
        var items: [InstallerItem] = []
        for folder in folders {
            for url in files(in: folder) where firmwareExtensions.contains(url.pathExtension.lowercased()) {
                guard !Task.isCancelled else { return items }
                guard !exclusions.excludes(url) else { continue }
                let (size, heldBack) = await measured(url, by: measure)
                guard isWorthARow(size, minimumSize) else { continue }
                items.append(firmware(at: url, size: size, heldBack: heldBack))
            }
        }
        return items
    }

    static func firmware(at url: URL, size: Int64?, heldBack: HoldBack?) -> InstallerItem {
        InstallerItem(
            url: url,
            kind: .firmware,
            name: url.lastPathComponent,
            size: size,
            date: creationDate(of: url),
            installedApp: nil,
            isReadOnly: false,
            notes: [],
            heldBack: heldBack
        )
    }

    /// Lists the device backups in `folder`, with what each says about itself: the device, its system, the
    /// date of the last backup, and whether it is encrypted.
    static func backups(in folder: URL, measure: LeftoverScanner.Measure) async -> [InstallerItem] {
        var items: [InstallerItem] = []
        for url in files(in: folder) {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true, !Task.isCancelled else { continue }
            let info = plist(at: url.appending(path: "Info.plist"))
            let manifest = plist(at: url.appending(path: "Manifest.plist"))
            var notes: [InstallerItem.Note] = []
            if let product = info?["Product Name"] as? String ?? info?["Product Type"] as? String {
                notes.append(.name(product))
            }
            if let version = info?["Product Version"] as? String {
                // The product type is a model code, such as `iPad13,4`, which tells iPadOS apart from iOS.
                let system = (info?["Product Type"] as? String)?.hasPrefix("iPad") == true ? "iPadOS" : "iOS"
                notes.append(.name("\(system) \(version)"))
            }
            if manifest?["IsEncrypted"] as? Bool == true {
                notes.append(.encrypted)
            }
            items.append(InstallerItem(
                url: url,
                kind: .deviceBackup,
                name: info?["Device Name"] as? String ?? url.lastPathComponent,
                size: await measured(url, by: measure).size,
                date: info?["Last Backup Date"] as? Date ?? creationDate(of: url),
                installedApp: nil,
                isReadOnly: true,
                notes: notes
            ))
        }
        return items
    }

    private static func files(in folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private static func plist(at url: URL) -> [String: Any]? {
        guard let data = BoundedRead.data(at: url) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    private static func creationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
    }
}
