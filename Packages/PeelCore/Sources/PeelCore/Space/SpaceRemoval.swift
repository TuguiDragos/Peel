import AppKit
public import Foundation

/// Plans the emptying of one of Space's folders. The folder itself is never removed (the guard refuses it, and
/// macOS expects to find it), so its children are listed instead. Each child passes through the same guard and
/// exclusions as anything else, and one named for an open app is left where it is, since the app may still be
/// writing to it.
public enum SpaceRemoval {
    public struct Plan: Sendable {
        /// Children that will be moved to the Trash.
        public let removable: [URL]
        /// Children left alone because the app that owns them is open, each with the name of that app.
        public let inUse: [(url: URL, name: String)]
        /// Children left to Developer, which lists something inside each.
        public let leftToDeveloper: [URL]
        /// The size of each removable child, which is what emptying frees. A child whose size is not known is
        /// missing here but stays in `removable`.
        public let sizes: [URL: Int64]
        /// Why a removable child is left for the person to choose, from what measuring it saw. A child missing here
        /// holds nothing that keeps it from being selected.
        public var heldBack: [URL: HoldBack] = [:]

        /// The open apps whose folders are left alone, each named once and sorted, by the names the user knows, not
        /// the folder names. One app can write to several folders, by its name and by its identifier.
        public var appsToQuit: [String] {
            Set(inUse.map(\.name)).sorted()
        }

        /// What Peel selects of this plan for the person: every child it could measure that nothing holds back.
        public var suggested: Set<URL> {
            Set(sizes.keys).subtracting(heldBack.keys)
        }
    }

    @concurrent
    public static func plan(
        for item: SpaceItem,
        environment: SearchEnvironment = .current,
        exclusions: Exclusions = .none,
        running: [String: String] = [:]
    ) async -> Plan {
        await plan(for: item, environment: environment, exclusions: exclusions, running: running, measure: LeftoverScanner.walk)
    }

    @concurrent
    static func plan(
        for item: SpaceItem,
        environment: SearchEnvironment,
        exclusions: Exclusions,
        running: [String: String],
        measure: LeftoverScanner.Measure
    ) async -> Plan {
        let children = children(of: item, environment: environment, exclusions: exclusions, running: running)
        var sizes: [URL: Int64] = [:]
        var heldBack: [URL: HoldBack] = [:]
        for child in children.removable where !Task.isCancelled {
            let contents = await measure(child)
            sizes[child] = contents.flatMap { $0.couldNotBeRead ? nil : $0.size }
            heldBack[child] = HoldBack.seen(in: contents)
        }
        return Plan(
            removable: children.removable, inUse: children.inUse, leftToDeveloper: children.leftToDeveloper, sizes: sizes,
            heldBack: heldBack
        )
    }

    /// What of `item` can move now, measuring nothing: the check a move makes just before it moves, since an app
    /// opened since the plan may be writing to some of these folders.
    @concurrent
    public static func removable(
        in item: SpaceItem,
        environment: SearchEnvironment = .current,
        exclusions: Exclusions = .none,
        running: [String: String] = [:]
    ) async -> [URL] {
        children(of: item, environment: environment, exclusions: exclusions, running: running).removable
    }

    private static func children(
        of item: SpaceItem,
        environment: SearchEnvironment,
        exclusions: Exclusions,
        running: [String: String]
    ) -> (removable: [URL], inUse: [(url: URL, name: String)], leftToDeveloper: [URL]) {
        let removalGuard = RemovalGuard(environment: environment, exclusions: exclusions)
        let children = item.urls.flatMap { url in
            (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        }

        let developerNames = item.urls.flatMap { DeveloperCaches.namesListed(inside: $0, home: environment.homeDirectory) }
        var removable: [URL] = []
        var inUse: [(url: URL, name: String)] = []
        var leftToDeveloper: [URL] = []
        for child in children where removalGuard.allowsRemoval(of: child) {
            if let name = running[Naming.normalized(child.lastPathComponent)] {
                inUse.append((child, name))
            } else if developerNames.contains(where: { fnmatch($0, child.lastPathComponent, FNM_CASEFOLD) == 0 }) {
                leftToDeveloper.append(child)
            } else {
                removable.append(child)
            }
        }
        return (removable, inUse, leftToDeveloper)
    }

    /// Maps each name an open app answers to, normalized, to the app's display name. The names are the bundle
    /// identifier, its last part, and the bundle's file name, since many cache and log folders carry the app's
    /// name rather than its identifier (`Firefox`, `Zed`).
    public static func namesOfRunningApps(_ running: [RunningCopies.Process]) -> [String: String] {
        var names: [String: String] = [:]
        for process in running {
            let bundle = process.bundleURL?.deletingPathExtension().lastPathComponent
            // Folders on disk carry the bundle's file name. The user sees the app's name as Finder shows it.
            let displayed = process.bundleURL.map(AppInspector.displayName) ?? process.bundleIdentifier
            let spellings = [
                process.bundleIdentifier,
                process.bundleIdentifier.split(separator: ".").last.map(String.init),
                bundle,
            ].compactMap(\.self)
            for spelling in spellings where Naming.isSignificant(spelling) {
                names[Naming.normalized(spelling)] = displayed
            }
        }
        return names
    }

    @MainActor
    public static func namesOfRunningApps() -> [String: String] {
        namesOfRunningApps(RunningCopies.current)
    }
}
