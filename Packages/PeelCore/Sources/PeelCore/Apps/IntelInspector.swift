import Darwin
public import Foundation
internal import PeelPrivileged

/// Intel-only software, which needs Rosetta on Apple silicon. macOS 27 is the last release to offer Rosetta.
public struct IntelFinding: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case app
        case insideApp
        case plugin
        case driver
        case backgroundItem
        case commandLineTool
    }

    public let url: URL
    public let kind: Kind
    public let name: String
    /// What it belongs to: the app it sits inside, or the launchd property list that starts it.
    public let owner: String?
    /// Nil when the size is not known because measuring it timed out or was refused. Unknown is not zero.
    public let size: Int64?
    /// For a plug-in, its kind, which says where its Intel code can load (`Plugin.Category.intelHost`).
    public var pluginCategory: Plugin.Category?
    /// The labels of the launchd jobs that run a program at it or inside it.
    public var backgroundItems: [String] = []

    public var id: URL { url }
}

public struct IntelScan: Sendable {
    public let findings: [IntelFinding]
    /// What the scan couldn't read, each named once: folders it couldn't look into and programs it couldn't open.
    /// Something there may need Rosetta.
    public var unreadable: [URL] = []
    /// True when macOS's privacy protection kept Peel out of one of them, which Full Disk Access lifts.
    public var needsFullDiskAccess = false
    /// The kinds of launchd jobs `launchctl` didn't describe in a form Peel can read, whose programs it never saw.
    public var unansweredJobs: Set<BackgroundItem.Kind> = []

    public func findings(of kind: IntelFinding.Kind) -> [IntelFinding] {
        findings.filter { $0.kind == kind }
    }
}

public enum IntelInspector {
    /// Folders searched in both the user's Library and the system's, because printer drivers and audio plug-ins
    /// can be installed for one user or for everyone. The macOS 27 release notes point to these folders for
    /// Intel plug-ins that may not appear in System Settings: `~/Library/Audio/Plug-Ins/*`,
    /// `~/Library/Printers/`, and `~/Library/ColorPickers/`.
    static let driverFolders = [
        "Image Capture/Devices",
        "Image Capture/TWAIN Data Sources",
        printers,
        "Audio/Plug-Ins",
        "ColorPickers",
    ]

    /// A printer driver keeps programs of its own beside its bundles: the filters and the tools its PPD names, as
    /// CUPS's PPD specification shows with `/Library/Printers/vendor/Tools/lowinktool`.
    static let printers = "Printers"

    static func driverDirectories(_ environment: SearchEnvironment, folders: [String] = driverFolders) -> [String] {
        [environment.homeDirectory.appending(path: "Library", directoryHint: .isDirectory),
         environment.rootDirectory.appending(path: "Library", directoryHint: .isDirectory)]
            .flatMap { library in folders.map { library.appending(path: $0).path(percentEncoded: false) } }
    }

    static func toolDirectories(_ environment: SearchEnvironment) -> [String] {
        ["usr/local/bin", "usr/local/sbin", "usr/local/libexec"].map {
            environment.rootDirectory.appending(path: $0).path(percentEncoded: false)
        }
    }

    /// Folders inside an app whose contents run as processes of their own, so an Intel-only one really does
    /// need Rosetta.
    ///
    /// `Contents/Frameworks` is not one of them: a library there is loaded into the app's own process, so an
    /// Intel-only one matters only when the app itself runs as Intel code. The bundles beside the libraries are
    /// processes, and `frameworkProcesses` finds those.
    /// `Contents/MacOS` holds helper tools beside the main executable, whose own architectures decide whether the
    /// app is listed as a whole. A Quick Look generator, a Spotlight importer and a system extension run in a
    /// process of their own as well.
    static let embeddedDirectories = [
        "Contents/MacOS", "Contents/Library/LoginItems", "Contents/PlugIns", "Contents/Extensions",
        "Contents/XPCServices", "Contents/Helpers", "Contents/Library/LaunchServices",
        "Contents/Library/SystemExtensions", "Contents/Library/QuickLook", "Contents/Library/Spotlight",
    ]

    /// The extensions of bundles that run as a process of their own.
    static let processExtensions: Set<String> = ["app", "xpc"]

    /// Folders of an app made for resources, where some apps still keep a process of their own, an updater above all.
    static let resourceDirectories = ["Contents/Resources", "Contents/SharedSupport"]

    @concurrent
    public static func scan(
        installedApps: [InstalledApp],
        backgroundItems: BackgroundItems.Scan = BackgroundItems.Scan(),
        exclusions: Exclusions = .none,
        environment: SearchEnvironment = .current
    ) async -> IntelScan {
        await scan(
            installedApps: installedApps,
            backgroundItems: backgroundItems,
            exclusions: exclusions,
            environment: environment,
            measure: FileSize.measure
        )
    }

    @concurrent
    static func scan(
        installedApps: [InstalledApp],
        backgroundItems: BackgroundItems.Scan = BackgroundItems.Scan(),
        exclusions: Exclusions,
        environment: SearchEnvironment = .current,
        measure: FileSize.Measure
    ) async -> IntelScan {
        // A path can be found twice: `/Library/Audio/Plug-Ins/HAL` is a plug-in folder and sits inside a driver
        // folder, and two launchd jobs often run the same program. The first kind to find a path keeps it.
        var findings: [IntelFinding] = []
        var seen: Set<String> = []
        func isNew(_ url: URL) -> Bool { seen.insert(PathPattern.comparablePath(of: url)).inserted }
        var unreadable: [URL] = []

        for app in installedApps where !exclusions.excludes(app) {
            guard !Task.isCancelled else { break }
            // An app whose own program Peel couldn't read may be Intel only, so what it carries can't be told apart.
            let refusedBefore = unreadable.count
            let intelOnly = app.isIntelOnly
                || app.architectures.isEmpty && isIntelOnly(bundle: app.url, unreadable: &unreadable)
            guard unreadable.count == refusedBefore else { continue }
            if intelOnly, isNew(app.url) {
                findings.append(IntelFinding(
                    url: app.url,
                    kind: .app,
                    name: app.name,
                    owner: nil,
                    size: await measure(app.url),
                ))
                continue
            }
            for url in intelOnlyBundles(inside: app.url, unreadable: &unreadable)
            where !Task.isCancelled && !exclusions.excludes(url) && isNew(url) {
                findings.append(IntelFinding(
                    url: url,
                    kind: .insideApp,
                    name: url.lastPathComponent,
                    owner: app.name,
                    size: await measure(url),
                ))
            }
        }

        // Read here rather than taken from the Plug-ins page, whose list is as old as its last scan. Apple's own are
        // left out, as that page leaves them out.
        for plugin in Plugins.installed(in: environment, unreadable: &unreadable)
        where !Task.isCancelled && !exclusions.excludes(plugin.url) {
            guard isIntelOnly(bundle: plugin.url, unreadable: &unreadable), !AppleCode.isApples(plugin.url),
                  isNew(plugin.url)
            else { continue }
            let info = AppInspector.infoDictionary(in: plugin.url.appending(path: "Contents", directoryHint: .isDirectory))
            findings.append(IntelFinding(
                url: plugin.url,
                kind: .plugin,
                name: Plugins.name(of: plugin.url, info: info),
                owner: nil,
                size: await measure(plugin.url),
                pluginCategory: plugin.category,
            ))
        }

        for url in bundles(in: driverDirectories(environment), unreadable: &unreadable)
        where !Task.isCancelled && !exclusions.excludes(url) {
            guard isIntelOnly(bundle: url, unreadable: &unreadable), isNew(url) else { continue }
            findings.append(IntelFinding(
                url: url,
                kind: .driver,
                name: url.lastPathComponent,
                owner: nil,
                size: await measure(url),
            ))
        }

        let printerDirectories = driverDirectories(environment, folders: [printers])
        for url in programs(in: printerDirectories, unreadable: &unreadable)
        where !Task.isCancelled && !exclusions.excludes(url) {
            guard isIntelOnly(executable: url, unreadable: &unreadable), isNew(url) else { continue }
            findings.append(IntelFinding(
                url: url,
                kind: .driver,
                name: url.lastPathComponent,
                owner: nil,
                size: await measure(url),
            ))
        }

        // A job or a command that runs what is listed already, or something inside it, is that code's, and a job is
        // named on its row.
        var listed = findings.map { PathPattern.comparablePath(of: $0.url) }
        for item in backgroundItems.items where !Task.isCancelled {
            guard let program = item.program.map({ URL(filePath: $0) }), !exclusions.excludes(program) else { continue }
            let path = PathPattern.comparablePath(of: program)
            if let index = listed.firstIndex(where: { PathComponents.isPath(path, atOrInside: $0) }) {
                findings[index].backgroundItems.append(item.label)
                continue
            }
            guard isIntelOnly(executable: program, unreadable: &unreadable), isNew(program) else { continue }
            findings.append(IntelFinding(
                url: program,
                kind: .backgroundItem,
                name: item.label,
                owner: item.plistURL?.lastPathComponent,
                size: await measure(program),
            ))
            listed.append(path)
        }

        for tool in tools(in: toolDirectories(environment), unreadable: &unreadable)
        where !Task.isCancelled && !exclusions.excludes(tool.url) {
            let path = PathPattern.comparablePath(of: tool.url)
            guard !listed.contains(where: { PathComponents.isPath(path, atOrInside: $0) }) else { continue }
            guard isIntelOnly(executable: tool.url, unreadable: &unreadable), isNew(tool.url) else { continue }
            findings.append(IntelFinding(
                url: tool.url,
                kind: .commandLineTool,
                name: tool.name,
                owner: nil,
                size: await measure(tool.url),
            ))
        }

        var named: Set<String> = []
        let unread = unreadable.filter {
            !exclusions.excludes($0) && named.insert(PathPattern.comparablePath(of: $0)).inserted
        }
        return IntelScan(
            findings: findings.sorted {
                $0.size != $1.size ? SizeTotal([$0.size]) > SizeTotal([$1.size]) : $0.name < $1.name
            },
            unreadable: unread,
            needsFullDiskAccess: unread.contains { FullDiskAccess.canList($0) == .missing },
            unansweredJobs: backgroundItems.unanswered
        )
    }

    /// Helpers, plug-ins, and plain binaries inside an app that only have Intel code.
    static func intelOnlyBundles(inside bundle: URL, unreadable: inout [URL]) -> [URL] {
        var candidates = frameworkProcesses(inside: bundle, unreadable: &unreadable)
        for directory in resourceDirectories {
            let folder = bundle.appending(path: directory, directoryHint: .isDirectory)
            candidates += processes(in: folder, unreadable: &unreadable)
        }
        var found = candidates.filter { isIntelOnlyProcess($0, unreadable: &unreadable) }
        for directory in embeddedDirectories {
            let folder = bundle.appending(path: directory, directoryHint: .isDirectory)
            for url in entries(of: folder, unreadable: &unreadable) {
                var info = stat()
                guard lstat(url.path(percentEncoded: false), &info) == 0 else { continue }
                if info.st_mode & S_IFMT == S_IFDIR {
                    if !url.pathExtension.isEmpty, isIntelOnly(bundle: url, unreadable: &unreadable) {
                        found.append(url)
                    }
                } else if isRunnable(info), isIntelOnly(executable: url, unreadable: &unreadable),
                          MachOHeader.isProgram(at: url) == true {
                    // A library or a bundle kept beside the programs runs in the process that loads it.
                    found.append(url)
                }
            }
        }
        return found
    }

    /// Returns the processes under `Contents/Frameworks`: apps and XPC services kept there directly, as every
    /// Electron app keeps its helpers, and those in each framework's `XPCServices` and `Helpers` folders, at the top
    /// of each version, as Sparkle keeps its updater, and in its `Resources`, as Squirrel does. `Versions/Current` is
    /// skipped: it is a link to one of the versions beside it, so following it would report the same bundle twice.
    static func frameworkProcesses(inside bundle: URL, unreadable: inout [URL]) -> [URL] {
        let frameworks = bundle.appending(path: "Contents/Frameworks", directoryHint: .isDirectory)
        var found: [URL] = []
        for url in entries(of: frameworks, unreadable: &unreadable) {
            if processExtensions.contains(url.pathExtension.lowercased()) {
                found.append(url)
                continue
            }
            guard url.pathExtension.lowercased() == "framework" else { continue }
            let versions = entries(of: url.appending(path: "Versions", directoryHint: .isDirectory), unreadable: &unreadable)
                .filter { $0.lastPathComponent != "Current" }
            for version in versions + [url] {
                for name in ["XPCServices", "Helpers"] {
                    // At the top of a versioned framework these are links into `Versions/Current`, already read.
                    let folder = version.appending(path: name, directoryHint: .isDirectory)
                    guard version != url || folder.isRealFolder else { continue }
                    found += entries(of: folder, unreadable: &unreadable)
                        .filter { processExtensions.contains($0.pathExtension.lowercased()) }
                }
                found += processes(in: version, unreadable: &unreadable)
                let resources = version.appending(path: "Resources", directoryHint: .isDirectory)
                if version != url || resources.isRealFolder {
                    found += processes(in: resources, unreadable: &unreadable)
                }
            }
        }
        return found
    }

    /// What in `folder` can run as a process of its own: a bundle that runs as one, or a file that can be run. Links
    /// are passed over, since at the top of a framework they lead into a version read on its own.
    private static func processes(in folder: URL, unreadable: inout [URL]) -> [URL] {
        entries(of: folder, unreadable: &unreadable).filter { url in
            var info = stat()
            guard lstat(url.path(percentEncoded: false), &info) == 0 else { return false }
            switch info.st_mode & S_IFMT {
            case S_IFDIR: return processExtensions.contains(url.pathExtension.lowercased())
            case S_IFREG: return info.st_mode & 0o111 != 0
            default: return false
            }
        }
    }

    /// Whether `url`, a bundle that runs as a process or a file that can be run, has only Intel code, and a file is a
    /// program rather than a library another program loads.
    private static func isIntelOnlyProcess(_ url: URL, unreadable: inout [URL]) -> Bool {
        url.hasDirectoryPath || url.isRealFolder
            ? isIntelOnly(bundle: url, unreadable: &unreadable)
            : isIntelOnly(executable: url, unreadable: &unreadable) && MachOHeader.isProgram(at: url) == true
    }

    /// The entries of `directory`. One Peel can't list adds the folder that kept it out to `unreadable`.
    private static func entries(of directory: URL, unreadable: inout [URL]) -> [URL] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        else {
            if let folder = refusedFolder(directory) { unreadable.append(folder) }
            return []
        }
        return names.map { directory.appending(path: $0) }
    }

    /// The folder that kept Peel out of `folder`: `folder` itself when Peel can see it but not list it, or the folder
    /// around it Peel can't look into. Nil when nothing is there, or a file is, which hides nothing.
    static func refusedFolder(_ folder: URL) -> URL? {
        var info = stat()
        if stat(folder.path(percentEncoded: false), &info) == 0 {
            return info.st_mode & S_IFMT == S_IFDIR ? folder : nil
        }
        guard ![ENOENT, ENOTDIR, ELOOP].contains(errno) else { return nil }
        let around = folder.deletingLastPathComponent()
        return around.path(percentEncoded: false) == folder.path(percentEncoded: false) ? nil : refusedFolder(around)
    }

    /// Notes `program`, which macOS wouldn't let Peel read, or the folder around it Peel can't look into.
    private static func noteRefused(_ program: URL, in unreadable: inout [URL]) {
        unreadable.append(program.isThere ? program : refusedFolder(program.deletingLastPathComponent()) ?? program)
    }

    /// Whether a file can be run by anyone: one that only root may run still runs, though Peel can't read it.
    private static func isRunnable(_ info: stat) -> Bool {
        info.st_mode & S_IFMT == S_IFREG && info.st_mode & 0o111 != 0
    }

    static func isIntelOnly(bundle url: URL, unreadable: inout [URL]) -> Bool {
        guard let executable = executable(of: url, unreadable: &unreadable) else { return false }
        return isIntelOnly(executable: executable, unreadable: &unreadable)
    }

    static func isIntelOnly(executable url: URL, unreadable: inout [URL]) -> Bool {
        guard let architectures = MachOHeader.architectures(ofExecutableAt: url) else {
            noteRefused(url, in: &unreadable)
            return false
        }
        return architectures == [.x86_64]
    }

    /// The binary a bundle runs, from its Info.plist or, failing that, the name of the bundle.
    static func executable(of bundle: URL, unreadable: inout [URL]) -> URL? {
        let contents = bundle.appending(path: "Contents", directoryHint: .isDirectory)
        let info = BoundedRead.propertyList(at: contents.appending(path: "Info.plist"))
        let name = (info?["CFBundleExecutable"] as? String) ?? bundle.deletingPathExtension().lastPathComponent
        // The second place is for a flat bundle, which keeps its binary at its top level.
        for candidate in [contents.appending(path: "MacOS/\(name)"), bundle.appending(path: name)] {
            var status = stat()
            if stat(candidate.path(percentEncoded: false), &status) == 0 {
                if isRunnable(status) { return candidate }
            } else if ![ENOENT, ENOTDIR, ELOOP].contains(errno) {
                if let folder = refusedFolder(candidate.deletingLastPathComponent()) { unreadable.append(folder) }
                return nil
            }
        }
        return nil
    }

    /// `ds` is a TWAIN data source, which Apple's Technical Note TN2088 puts in `Image Capture/TWAIN Data Sources`.
    static let driverExtensions: Set<String> = ["app", "plugin", "bundle", "driver", "qlgenerator", "mdimporter", "ds"]

    static func bundles(in directories: [String], unreadable: inout [URL]) -> [URL] {
        var bundles: [URL] = []
        for directory in directories {
            let url = URL(filePath: directory, directoryHint: .isDirectory)
            var refused: [URL] = []
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { folder, _ in
                    refused.append(folder)
                    return true
                }
            ) else {
                if let folder = refusedFolder(url) { unreadable.append(folder) }
                continue
            }
            for case let item as URL in enumerator {
                guard !Task.isCancelled else { break }
                if driverExtensions.contains(item.pathExtension) { bundles.append(item) }
            }
            unreadable += refused.compactMap(refusedFolder)
        }
        return bundles
    }

    /// The programs in `directories` that sit outside every bundle: one inside a bundle is the bundle's.
    static func programs(in directories: [String], unreadable: inout [URL]) -> [URL] {
        var programs: [URL] = []
        for directory in directories {
            let url = URL(filePath: directory, directoryHint: .isDirectory)
            var refused: [URL] = []
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { folder, _ in
                    refused.append(folder)
                    return true
                }
            ) else {
                if let folder = refusedFolder(url) { unreadable.append(folder) }
                continue
            }
            for case let item as URL in enumerator {
                guard !Task.isCancelled else { break }
                if driverExtensions.contains(item.pathExtension) {
                    // `skipDescendants()` after a file would skip the next folder.
                    if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                var info = stat()
                guard lstat(item.path(percentEncoded: false), &info) == 0, isRunnable(info) else { continue }
                switch MachOHeader.isProgram(at: item) {
                case true?: programs.append(item)
                case nil: noteRefused(item, in: &unreadable)
                case false?: break
                }
            }
            unreadable += refused.compactMap(refusedFolder)
        }
        return programs
    }

    /// The programs the commands in `directories` run, each under the command's name. A command is often a link,
    /// as every one a Homebrew in `/usr/local` makes into its `Cellar`, and the program it leads to is what runs.
    static func tools(in directories: [String], unreadable: inout [URL]) -> [(name: String, url: URL)] {
        var tools: [(name: String, url: URL)] = []
        for directory in directories {
            let folder = URL(filePath: directory, directoryHint: .isDirectory)
            for command in entries(of: folder, unreadable: &unreadable) {
                let program = command.resolvingSymlinksInPath()
                var info = stat()
                if stat(program.path(percentEncoded: false), &info) == 0 {
                    if isRunnable(info) { tools.append((command.lastPathComponent, program)) }
                } else if ![ENOENT, ENOTDIR, ELOOP].contains(errno),
                          let place = refusedFolder(program.deletingLastPathComponent()) {
                    unreadable.append(place)
                }
            }
        }
        return tools
    }
}

extension IntelFinding {
    /// Whether `query` matches what the row shows, the name or what the finding belongs to, or a job that runs it.
    public func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return SearchText.matches(name, query) || owner.map { SearchText.matches($0, query) } == true
            || backgroundItems.contains { SearchText.matches($0, query) }
    }
}
