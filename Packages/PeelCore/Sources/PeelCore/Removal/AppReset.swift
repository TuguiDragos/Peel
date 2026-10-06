public import Foundation
internal import PeelPrivileged

/// The files a reset can clear for an app, so the app starts fresh without being uninstalled. The app itself,
/// its launch agents and its helper tools are never part of a reset: removing them would break the app.
public struct AppReset: Sendable {
    public enum Group: String, Sendable, Hashable, CaseIterable {
        /// Settings, caches and window state. An app writes all of it again on the next launch.
        case settings
        /// Cookies and website data. Offered but never preselected, because clearing it signs the user out.
        case webData
        /// Data the app keeps for the user, such as its Application Support folder. Never preselected.
        case appData
    }

    public struct Item: Sendable, Hashable, Identifiable {
        public let url: URL
        public let kind: SearchLocation.Kind
        public let group: Group
        /// Always known: a folder that was not measured or not read is never offered, nor one holding a wallet or a
        /// repository, as the uninstall holds such a folder back.
        public let size: Int64

        public var id: URL { url }
    }

    /// These apps' data is the user's own mail, messages, notes and photos, so it is never offered.
    static let dataIsNeverOffered: Set<String> = [
        "com.apple.mail",
        "com.apple.MobileSMS",
        "com.apple.Notes",
        "com.apple.Photos",
    ]

    /// The only folders a reset clears inside a sandboxed app's container. The container also holds the user's
    /// documents, so it is never offered whole. Everything else in it stays: `Documents`, `Autosave Information`
    /// (unsaved work), `Application Support`, the app's own stores such as Stickies' notes, and the symbolic
    /// links that lead out to the home folder.
    static let containerFolders: [(path: String, group: Group, kind: SearchLocation.Kind)] = [
        ("Data/Library/Saved Application State", .settings, .savedApplicationState),
        ("Data/Library/Caches", .settings, .caches),
        ("Data/Library/Logs", .settings, .logs),
        ("Data/Library/HTTPStorages", .webData, .httpStorages),
        ("Data/Library/WebKit", .webData, .webKit),
        ("Data/Library/Cookies", .webData, .cookies),
    ]

    /// Holds the app's own plist next to symlinks to shared system preferences, so it is read file by file.
    /// `SyncedPreferences`, beside it, keeps the app's iCloud key-value store and is never touched.
    static let containerPreferenceFolder = "Data/Library/Preferences"

    public let app: InstalledApp
    public let items: [Item]
    /// True when the app's data is never offered, because it is the user's mail, messages, notes or photos.
    public let keepsAppData: Bool
    /// True when the app keeps settings in a container Peel can't read without Full Disk Access.
    public let needsFullDiskAccess: Bool

    public func items(in group: Group) -> [Item] {
        items.filter { $0.group == group }
    }

    /// The default selection: the settings group only, which the app rebuilds by itself.
    public var suggestedSelection: Set<URL> {
        Set(items(in: .settings).map(\.url))
    }

    public func groups(in selection: Set<URL>) -> Set<Group> {
        Set(items.filter { selection.contains($0.url) }.map(\.group))
    }

    public func size(of selection: Set<URL>) -> SizeTotal {
        SizeTotal(items.filter { selection.contains($0.url) }.map(\.size))
    }

    /// True when moving `urls` is followed by a `defaults delete` of at least one preference domain.
    public func clearsSettings(moving urls: [URL]) -> Bool {
        !PreferenceCleanup.domains(for: urls, ownedBy: app.bundleIdentifier).isEmpty
    }

    /// Returns the selected items in the order the sheet lists them. Preference domains are forgotten only after
    /// every file has moved, so the order of the files does not matter.
    public func selected(_ selection: Set<URL>) -> [URL] {
        items.map(\.url).filter(selection.contains)
    }

    static func group(for kind: SearchLocation.Kind) -> Group? {
        switch kind {
        case .preferences, .preferencesByHost, .savedApplicationState, .caches, .logs, .recentDocuments,
            .temporaryItems:
            .settings
        case .cookies, .httpStorages, .webKit, .safariWebApps:
            .webData
        case .applicationSupport, .containers, .groupContainers, .applicationScripts:
            .appData
        // A reset leaves these alone. What every account on the Mac shares is not one user's to reset, and a
        // plug-in or a framework is code that macOS loads, not a setting.
        case .launchAgents, .launchDaemons, .privilegedHelperTools, .startupItems, .plugIns, .frameworks, .receipts,
             .library,
             .sharedFolder, .hiddenHomeFiles, .homeFolder, .commandLineTools, .shellCompletions, .nativeMessagingHosts,
             .elsewhere:
            nil
        }
    }

    /// Finds what a reset of `app` can clear. Only files that are certainly this app's are offered, because a
    /// reset must never touch another app's settings. Anything that needs administrator rights is left out
    /// too, since a reset is a user-level change.
    @concurrent
    public static func prepare(
        _ app: InstalledApp,
        installedApps: [InstalledApp],
        exclusions: Exclusions = .none,
        environment: SearchEnvironment = .current
    ) async -> AppReset {
        await prepare(
            app,
            installedApps: installedApps,
            exclusions: exclusions,
            environment: environment,
            measure: LeftoverScanner.walk
        )
    }

    @concurrent
    static func prepare(
        _ app: InstalledApp,
        installedApps: [InstalledApp],
        exclusions: Exclusions,
        environment: SearchEnvironment,
        measure: LeftoverScanner.Measure
    ) async -> AppReset {
        guard !exclusions.excludes(app) else {
            return AppReset(app: app, items: [], keepsAppData: false, needsFullDiskAccess: false)
        }
        let scan = await LeftoverScanner(environment: environment, exclusions: exclusions).scan(
            app,
            installedApps: installedApps
        )
        let keepsAppData = dataIsNeverOffered.contains(app.bundleIdentifier)
        // A container held back because of the documents or a wallet's keys inside it is still looked into: a reset
        // never touches `Documents`, never offers a folder that holds keys, and the settings beside them are what a
        // reset is for.
        let usable = scan.leftovers.filter { leftover in
            // Only `certain`, never `likely`: a reset ends in `defaults delete`, and a display name or an unlisted
            // prefix may also belong to something else (an app called Yarn, and the Yarn command-line tool). Another
            // copy of the app shares its settings, and a reset waits for every copy to quit.
            let isCertainlyTheApps = leftover.match.confidence == .certain && leftover.match.sharedWith.isEmpty
            let isOffered = leftover.match.heldBack == nil
                || (leftover.kind == .containers && [.holdsDocuments, .holdsKeys].contains(leftover.match.heldBack))
            return isCertainlyTheApps && isOffered && !leftover.requiresPrivileges
        }

        var items = usable.compactMap { leftover -> Item? in
            guard leftover.kind != .containers, let group = group(for: leftover.kind) else { return nil }
            guard !(keepsAppData && group == .appData) else { return nil }
            return Item(url: leftover.url, kind: leftover.kind, group: group, size: leftover.size)
        }

        var needsFullDiskAccess = false
        for container in usable.filter({ $0.kind == .containers }) {
            let library = container.url.appending(path: "Data/Library", directoryHint: .isDirectory)
            // A container without `Data/Library` is a stub, not one macOS hides from Peel. Only a refusal
            // (`missing`) means Full Disk Access would help.
            let access = FullDiskAccess.canList(library)
            guard access == .granted else {
                needsFullDiskAccess = needsFullDiskAccess || access == .missing
                continue
            }
            items += await itemsInside(
                container.url,
                of: app,
                exclusions: exclusions,
                home: environment.homeDirectory,
                measure: measure
            )
        }

        return AppReset(
            app: app,
            items: items.sorted { $0.size > $1.size },
            keepsAppData: keepsAppData,
            needsFullDiskAccess: needsFullDiskAccess
        )
    }

    static func itemsInside(
        _ container: URL,
        of app: InstalledApp,
        exclusions: Exclusions,
        home: URL,
        measure: LeftoverScanner.Measure
    ) async -> [Item] {
        var items: [Item] = []
        for folder in containerFolders {
            let url = container.appending(path: folder.path, directoryHint: .isDirectory)
            guard url.isRealFolder, !exclusions.excludes(url), !exclusions.holds(url), !holdsKeys(url, home: home)
            else { continue }
            // What the uninstall would hold back is never offered: a wallet or a repository inside, or a folder that
            // was not measured or not read.
            let seen = await measure(url)
            guard let seen, HoldBack.seen(in: seen) == nil else { continue }
            items.append(Item(url: url, kind: folder.kind, group: folder.group, size: seen.size))
        }
        let preferences = container.appending(path: containerPreferenceFolder, directoryHint: .isDirectory)
        guard preferences.isRealFolder else { return items }
        // Only the file named after the app, or after the container when it is a helper's: that is the file
        // `defaults` reads. A name that merely starts the same (`com.foo.AppOther`) belongs to another app.
        let names = Set([app.bundleIdentifier, container.lastPathComponent].map { $0.lowercased() + ".plist" })
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: preferences,
            includingPropertiesForKeys: [.isSymbolicLinkKey]
        )) ?? []
        for file in contents where names.contains(file.lastPathComponent.lowercased()) {
            guard (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                  !exclusions.excludes(file)
            else { continue }
            let seen = await measure(file)
            guard let seen, HoldBack.seen(in: seen) == nil else { continue }
            items.append(Item(url: file, kind: .preferences, group: .settings, size: seen.size))
        }
        return items
    }

    /// True for a folder that holds a wallet's or a key's file `ProtectedData` names, or a browser profile with a
    /// wallet in it, which `RemovalGuard` would refuse to move.
    private static func holdsKeys(_ url: URL, home: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        let home = home.path(percentEncoded: false)
        return ProtectedData.refuses(path, home: home) || ProtectedData.holds(path, home: home)
            || ProtectedData.holdsABrowserWallet(path)
    }
}
