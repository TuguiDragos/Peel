public import Foundation
internal import PeelPrivileged
import Synchronization

public enum AppCatalog {
    /// Where Peel looks for apps: the Applications folders and the folders the person chose (`AppFolders`).
    public static var defaultDirectories: [URL] {
        directories(adding: AppFolders().load())
    }

    static var standardDirectories: [URL] {
        standardDirectories(home: .homeDirectory)
    }

    static func standardDirectories(home: URL) -> [URL] {
        [
            URL(filePath: "/Applications", directoryHint: .isDirectory),
            home.appending(path: "Applications", directoryHint: .isDirectory),
        ]
    }

    public static func directories(adding folders: [URL]) -> [URL] {
        standardDirectories + folders
    }

    static var systemDirectories: [URL] {
        [
            "/System/Applications",
            "/System/Cryptexes/App/System/Applications",
            "/System/Library/CoreServices",
        ].map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    /// The apps that ship with macOS. They are not in the list of installed apps, but every scan needs them as
    /// rivals when it decides which app a file belongs to. The system volume is sealed, so they are read once.
    static let systemApps = Task { await installedApps(in: systemDirectories) }

    /// Returns the app in `apps` that `url` leads to, even when `url` is written in another case or goes
    /// through a link. The result is always the listed bundle, never the link.
    public static func app(at url: URL, among apps: [InstalledApp]) -> InstalledApp? {
        let real = PathPattern.comparablePath(of: PathPattern.canonical(url))
        return apps.first { PathPattern.comparablePath(of: PathPattern.canonical($0.url)) == real }
    }

    /// The app `url` is, or the one it sits inside, such as the app that holds a plug-in. When apps sit inside
    /// each other, the innermost one.
    public static func app(holding url: URL, among apps: [InstalledApp]) -> InstalledApp? {
        let path = PathPattern.comparablePath(of: url)
        return apps
            .map { (app: $0, path: PathPattern.comparablePath(of: $0.url)) }
            .filter { PathComponents.isPath(path, atOrInside: $0.path) }
            .max { $0.path.count < $1.path.count }?.app
    }

    @concurrent
    public static func installedApps(in directories: [URL] = defaultDirectories) async -> [InstalledApp] {
        let bundles = Set(directories.flatMap { appBundles(in: $0) })

        let apps = await withTaskGroup(of: InstalledApp?.self) { group in
            for bundle in bundles {
                group.addTask { Reading.of(bundle) }
            }
            return await group.reduce(into: [InstalledApp]()) { apps, app in
                if let app { apps.append(app) }
            }
        }

        Reading.forget(inside: directories, except: bundles)
        return sorted(apps)
    }

    /// Whether what was read about `bundle` is kept, so the next reading of its folder does not read it again.
    static func remembers(_ bundle: URL) -> Bool {
        Reading.remembers(bundle)
    }

    /// A cache of what was read about each bundle. Reading a bundle costs its `Info.plist`, its signature, its
    /// Mach-O header, and a Spotlight query, and the catalog is read again when Peel comes forward and on every
    /// change in the app folders. Three `stat` calls tell whether a bundle changed. When it did not, only the
    /// date it was last opened is read again, since that can change while the bundle stays the same.
    private enum Reading {
        private struct Identity: Hashable {
            let bundle: Date?
            let contents: Date?
            let info: Date?
            let size: Int64
        }

        private static let known = Mutex<[String: (identity: Identity, app: InstalledApp)]>([:])

        static func of(_ bundle: URL) -> InstalledApp? {
            let path = PathPattern.comparablePath(of: bundle)
            let identity = identity(of: bundle)
            if let remembered = known.withLock({ $0[path] }), remembered.identity == identity {
                let use = AppInspector.use(of: bundle)
                return remembered.app.withUse(lastUsedDate: use.lastUsedDate, isUseRecorded: use.isRecorded)
            }
            guard let app = AppInspector.inspect(bundle) else { return nil }
            known.withLock { $0[path] = (identity, app) }
            return app
        }

        /// Forgets every bundle in `directories` that is not in `bundles`, such as an app that was removed or moved.
        /// What other folders hold stays: the system apps are read on their own.
        static func forget(inside directories: [URL], except bundles: Set<URL>) {
            let paths = Set(bundles.map(PathPattern.comparablePath))
            let folders = directories.map(PathPattern.comparablePath)
            known.withLock { known in
                known = known.filter { path, _ in
                    paths.contains(path) || !folders.contains { PathComponents.isPath(path, atOrInside: $0) }
                }
            }
        }

        static func remembers(_ bundle: URL) -> Bool {
            known.withLock { $0[PathPattern.comparablePath(of: bundle)] != nil }
        }

        private static func identity(of bundle: URL) -> Identity {
            let contents = bundle.appending(path: "Contents", directoryHint: .isDirectory)
            let info = contents.appending(path: "Info.plist")
            let values = try? info.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return Identity(
                bundle: written(at: bundle),
                contents: written(at: contents),
                info: values?.contentModificationDate,
                size: Int64(values?.fileSize ?? 0)
            )
        }

        private static func written(at url: URL) -> Date? {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
    }

    /// Sorts `apps` by name, then by path. This is the order the list is kept in, for any code that adds to it.
    public static func sorted(_ apps: [InstalledApp]) -> [InstalledApp] {
        apps.sorted(by: byName)
    }

    /// Whether `reading` lists the same apps as `listed`, each the same build in the same place, whatever each says
    /// about when it was last opened: that changes every time an app is opened, and says nothing about what is
    /// installed. Both are in the order `sorted` keeps.
    public static func listsTheSameApps(_ reading: [InstalledApp], as listed: [InstalledApp]) -> Bool {
        reading.count == listed.count
            && zip(reading, listed).allSatisfy { read, known in
                read.withUse(lastUsedDate: nil, isUseRecorded: true)
                    == known.withUse(lastUsedDate: nil, isUseRecorded: true)
            }
    }

    static func appBundles(in directory: URL, maximumDepth: Int = 3) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var bundles: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "app" {
                bundles.append(url.standardizedFileURL)
            } else if enumerator.level >= maximumDepth {
                enumerator.skipDescendants()
            }
        }
        return bundles
    }

    private static func byName(_ lhs: InstalledApp, _ rhs: InstalledApp) -> Bool {
        let order = lhs.name.localizedStandardCompare(rhs.name)
        if order != .orderedSame { return order == .orderedAscending }
        return lhs.url.path(percentEncoded: false) < rhs.url.path(percentEncoded: false)
    }
}
