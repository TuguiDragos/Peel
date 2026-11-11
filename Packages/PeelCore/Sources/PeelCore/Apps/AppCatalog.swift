public import Foundation
internal import PeelPrivileged
import Synchronization

/// One reading of the folders apps are kept in.
public struct AppScan: Sendable, Equatable {
    public let apps: [InstalledApp]
    /// What is there and could not be read: a folder of apps or an app, whose apps are missing from `apps`.
    public let unreadable: [URL]
    /// Whether Full Disk Access would open what could not be read.
    public let needsFullDiskAccess: Bool
    /// The folders the person chose that the reading looked in, beside the Applications folders, or nil when their
    /// list is there and could not be read.
    public let chosenFolders: [URL]?
    /// Why their list could not be read, when Peel knows.
    public let whyListOfFoldersUnreadable: FileProblem?
    /// The folders on that list it no longer reads, whose apps it doesn't list.
    public let foldersLeftOut: [AppFolders.LeftOut]

    init(
        apps: [InstalledApp], unreadable: [URL] = [], needsFullDiskAccess: Bool = false, chosenFolders: [URL]? = [],
        whyListOfFoldersUnreadable: FileProblem? = nil, foldersLeftOut: [AppFolders.LeftOut] = []
    ) {
        self.apps = apps
        self.unreadable = unreadable
        self.needsFullDiskAccess = needsFullDiskAccess
        self.chosenFolders = chosenFolders
        self.whyListOfFoldersUnreadable = whyListOfFoldersUnreadable
        self.foldersLeftOut = foldersLeftOut
    }

    /// Whether the list of folders the person chose could not be read, so the apps in those folders are missing from
    /// `apps` too. Settings > General > App Folders starts it over.
    public var listOfFoldersUnreadable: Bool { chosenFolders == nil }

    /// Whether every app could be read. Until then nothing can be called orphaned, since the files of an app Peel
    /// can't see would look so.
    public var readEverything: Bool { unreadable.isEmpty && !listOfFoldersUnreadable }
}

public enum AppCatalog {
    /// Where Peel looks for apps: the Applications folders and the folders the person chose (`AppFolders`).
    public static var defaultDirectories: [URL] {
        directories(in: .current)
    }

    /// Where Peel looks for apps in `environment`: its Applications folders and the folders chosen in its home.
    static func directories(in environment: SearchEnvironment) -> [URL] {
        let home = environment.homeDirectory
        let chosen = AppFolders(url: AppFolders.url(inHome: home), home: home).load() ?? []
        return standardDirectories(home: environment.homeDirectory, root: environment.rootDirectory) + chosen
    }

    static var standardDirectories: [URL] {
        standardDirectories(home: .homeDirectory)
    }

    static func standardDirectories(home: URL, root: URL = URL(filePath: "/", directoryHint: .isDirectory)) -> [URL] {
        [
            root.appending(path: "Applications", directoryHint: .isDirectory),
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

    public static func installedApps(in directories: [URL] = defaultDirectories) async -> [InstalledApp] {
        await scan(in: directories).apps
    }

    /// Reads the apps in the Applications folders and in the folders the person chose, and says which of those it
    /// looked in (`chosenFolders`, nil when their list cannot be read).
    @concurrent
    public static func scan(choices: AppFolders = AppFolders()) async -> AppScan {
        let chosen = choices.load()
        let found = await scan(in: chosen.map(directories(adding:)) ?? standardDirectories)
        return AppScan(
            apps: found.apps,
            unreadable: found.unreadable,
            needsFullDiskAccess: found.needsFullDiskAccess,
            chosenFolders: chosen,
            whyListOfFoldersUnreadable: chosen == nil ? choices.whyUnreadable() : nil,
            foldersLeftOut: choices.leftOut()
        )
    }

    @concurrent
    public static func scan(in directories: [URL]) async -> AppScan {
        await scan(in: directories, within: FileSize.budget, walking: { appBundles(in: $0, unless: $1) })
    }

    /// Walks one folder for `scan(in:)`, until `isGivenUp` says nobody waits anymore. A parameter so a test can stand
    /// in for a folder that never answers.
    typealias Walk = @Sendable (_ folder: URL, _ isGivenUp: @escaping @Sendable () -> Bool) -> (
        bundles: [URL], unreadable: [URL]
    )

    /// Each folder is walked on a thread of its own and waited for within `budget`: a folder on a disk that sleeps, or
    /// one a file provider holds, can keep a directory read in the kernel for minutes. One that doesn't answer is
    /// among what could not be read, and the others are listed meanwhile.
    @concurrent
    static func scan(
        in directories: [URL], within budget: TimeInterval, walking walk: @escaping Walk,
        reading readApp: @escaping @Sendable (URL) -> InstalledApp? = { Reading.of($0) }
    ) async -> AppScan {
        let walks = await withTaskGroup(of: (index: Int, walk: (bundles: [URL], unreadable: [URL])?).self) { group in
            for (index, directory) in directories.enumerated() {
                group.addTask { (index, await SlowRead.answer(within: budget) { walk(directory, $0) }) }
            }
            return await group.reduce(into: Array(repeating: nil, count: directories.count)) { $0[$1.index] = $1.walk }
        }
        let answered = zip(directories, walks).compactMap { directory, walk in walk.map { (directory, $0) } }
        let unanswered = zip(directories, walks).filter { $0.1 == nil }.map(\.0)
        let bundles = Set(answered.flatMap(\.1.bundles))

        // A folder the person chose can be on a disk that lists from memory and then doesn't answer, so its apps are
        // read on threads of their own, and once one doesn't answer in time the rest of that folder isn't asked. The
        // Applications folders are on this Mac.
        let usual = Set(standardDirectories.map(PathPattern.comparablePath))
        let waited = directories.filter { !usual.contains(PathPattern.comparablePath(of: $0)) }
        func folder(of bundle: URL) -> URL? {
            let path = PathPattern.comparablePath(of: bundle)
            return waited.first { PathComponents.isPath(path, inside: PathPattern.comparablePath(of: $0)) }
        }
        var stalled: Set<URL> = []
        var unasked: [URL] = []
        let read = await withTaskGroup(of: (bundle: URL, app: InstalledApp?, answered: Bool).self) { group in
            var pending = bundles.makeIterator()
            func askNext() {
                while let bundle = pending.next() {
                    let waitedFor = folder(of: bundle)
                    if let waitedFor, stalled.contains(waitedFor) {
                        unasked.append(bundle)
                        continue
                    }
                    group.addTask {
                        guard !Task.isCancelled else { return (bundle, nil, true) }
                        guard waitedFor != nil else { return (bundle, readApp(bundle), true) }
                        let answer = await SlowRead.answer(within: budget) { _ in readApp(bundle) }
                        return answer.map { (bundle, $0, true) } ?? (bundle, nil, false)
                    }
                    return
                }
            }
            for _ in 0..<max(ProcessInfo.processInfo.activeProcessorCount, 2) {
                askNext()
            }
            var read: [(bundle: URL, app: InstalledApp?, answered: Bool)] = []
            while let result = await group.next() {
                if !result.answered, let waitedFor = folder(of: result.bundle) { stalled.insert(waitedFor) }
                read.append(result)
                askNext()
            }
            return read
        }
        guard !Task.isCancelled else { return AppScan(apps: [], unreadable: [], needsFullDiskAccess: false) }

        Reading.forget(inside: answered.map { followingALink($0.0) }, except: bundles)
        let closedApps = read.filter { $0.answered && $0.app == nil && AppInspector.isClosed($0.bundle) }.map(\.bundle)
        let silent = read.filter { !$0.answered }.map(\.bundle) + unasked
        let refused = answered.flatMap(\.1.unreadable) + closedApps
        return AppScan(
            apps: sorted(read.compactMap(\.app)),
            unreadable: (refused + unanswered + silent)
                .sorted { $0.path(percentEncoded: false) < $1.path(percentEncoded: false) },
            needsFullDiskAccess: refused.contains { FullDiskAccess.canList($0) == .missing }
        )
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
            let contents = AppBundleLayout(of: bundle).infoFolder
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

    /// Which of `urls` are surely gone, read on a thread of its own within `FileSize.budget`, since an app shown from
    /// outside the folders can be on a disk that stopped answering: none, when it doesn't answer in time.
    public static func gone(
        _ urls: [URL],
        isMissing: @escaping @Sendable (URL) -> Bool = { $0.isMissing }
    ) async -> Set<URL> {
        guard !urls.isEmpty else { return [] }
        return await SlowRead.answer(within: FileSize.budget) { _ in Set(urls.filter(isMissing)) } ?? []
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

    /// How many levels below each folder apps are looked for.
    static let depth = 3

    /// Whether `appBundles` looks inside `folder` when it meets it: it passes over hidden folders and packages.
    static func looksInside(_ folder: URL) -> Bool {
        let values = try? folder.resourceValues(forKeys: [.isHiddenKey, .isPackageKey])
        return values?.isHidden != true && values?.isPackage != true
    }

    /// What is read for `directory`: the enumerator doesn't follow a link it starts from, answering "Not a directory".
    private static func followingALink(_ directory: URL) -> URL {
        directory.isSymbolicLink ? PathPattern.canonical(directory) : directory
    }

    /// The apps in `directory`, `depth` levels deep, and the folders in it that are there and could not be read. A
    /// folder that is not there, such as an Applications folder nobody made, holds no app.
    static func appBundles(
        in directory: URL, unless isStopped: () -> Bool = { false }
    ) -> (bundles: [URL], unreadable: [URL]) {
        var unreadable: [URL] = []
        guard !directory.isALinkThatLeadsNowhere else { return ([], []) }
        guard let enumerator = FileManager.default.enumerator(
            at: followingALink(directory),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, error in
                if (error as? CocoaError)?.code != .fileReadNoSuchFile { unreadable.append(url) }
                return true
            }
        ) else { return ([], directory.isMissing ? [] : [directory]) }

        var bundles: [URL] = []
        for case let url as URL in enumerator {
            guard !isStopped() else { break }
            if url.isNamedAsAnApp {
                if AppInspector.isABundle(url) { bundles.append(url.standardizedFileURL) }
            } else if enumerator.level >= depth {
                enumerator.skipDescendants()
            }
        }
        return (bundles, unreadable)
    }

    /// The apps in `folder`, one that arrived in a Trash, found as the list finds them in a folder of apps, on a thread
    /// of its own within `FileSize.budget`. A link, a package, or a hidden folder holds none: a link leads to apps that
    /// are still where they were.
    @concurrent
    public static func apps(inAFolderThrownAway folder: URL) async -> [URL] {
        // `lstat` follows a link whose name ends in a slash, as a folder's URL is written.
        var info = stat()
        guard lstat(PathPattern.comparablePath(of: folder), &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              looksInside(folder)
        else { return [] }
        return await SlowRead.answer(within: FileSize.budget) { appBundles(in: folder, unless: $0).bundles } ?? []
    }

    private static func byName(_ lhs: InstalledApp, _ rhs: InstalledApp) -> Bool {
        let order = lhs.name.localizedStandardCompare(rhs.name)
        if order != .orderedSame { return order == .orderedAscending }
        return lhs.url.path(percentEncoded: false) < rhs.url.path(percentEncoded: false)
    }
}
