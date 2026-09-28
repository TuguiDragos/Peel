import ArgumentParser
import Foundation
import PeelCore

struct OrphansCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "orphans",
        abstract: "List files left by apps that are no longer installed, and move a group to the Trash.",
        discussion: "Nothing here is ever suggested, so --remove takes the identifier of one group. What Peel refuses to move, what it leaves for you to choose in the app, and what needs administrator access, stays."
    )

    @Argument(help: "The group to move, as `peel orphans` names it in its first column.")
    var group: String?

    @Flag(help: "Move the named group to the Trash, leaving out what Peel holds back.")
    var remove = false

    @OptionGroup var removal: RemovalOptions

    @OptionGroup var output: OutputOptions

    /// What `--json` writes.
    struct Report: Encodable {
        let groups: [Group]
        let unreadableLocations: [String]

        struct Group: Encodable {
            let identifier: String
            let size: MeasuredSize
            let confidence: String
            let why: String
            let files: [File]
        }

        struct File: Encodable {
            let path: String
            let size: MeasuredSize
            /// Why `--remove` leaves the file where it is, or `null` when it would move it.
            let heldBack: String?

            private enum CodingKeys: String, CodingKey {
                case path
                case size
                case heldBack
            }

            /// Encodes a missing `heldBack` as `null`, for the reason `AppRecord` gives.
            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(path, forKey: .path)
                try container.encode(size, forKey: .size)
                try container.encode(heldBack, forKey: .heldBack)
            }
        }
    }

    func validate() throws {
        try removal.validate(removing: remove, with: output)
        guard remove == (group != nil) else {
            throw ValidationError(remove
                ? "Name the group to move. See `peel orphans`."
                : "A group on its own does nothing. Add --remove to move it.")
        }
    }

    func run() async throws {
        let apps = await AppCatalog.installedApps()
        // The same signals the app uses (the apps Peel remembers and the apps running), so both judge these
        // files alike. The memory of apps is only read here, never written.
        let remembered = await AppMemory().load()
        let running = Set(await RunningCopies.current.map(\.bundleIdentifier))
        let exclusions = await UnreadableExclusions.load()
        let scanner = OrphanScanner(exclusions: exclusions)
        let scan = await scanner.scan(
            installedApps: apps, remembered: remembered, running: running, owners: OrphanOwners().load()
        )
        if let group {
            return try await clean(group, in: scan, apps: apps, scanner: scanner, using: TrashService(exclusions: exclusions))
        }

        if output.json {
            try Output.json(Self.report(for: scan))
        } else if scan.groups.isEmpty {
            Output.line("No orphaned files found.")
        } else {
            for group in scan.groups {
                Output.line(Self.heading(for: group))
                Output.table(Self.rows(for: group), indent: "  ")
            }
        }
        if !scan.unreadableLocations.isEmpty {
            let folders = scan.unreadableLocations.map(\.url)
            Output.note(Output.unreadableNote(for: folders, needsFullDiskAccess: scan.needsFullDiskAccess))
        }
    }

    static func report(for scan: OrphanScan) -> Report {
        Report(
            groups: scan.groups.map { group in
                Report.Group(
                    identifier: group.identifier,
                    size: MeasuredSize(group.total),
                    confidence: group.confidence.levelName,
                    why: group.confidence.summary,
                    files: group.items.map { item in
                        let size = MeasuredSize(item.size)
                        return Report.File(path: Output.path(item.url), size: size, heldBack: item.heldBack?.rawValue)
                    }
                )
            },
            unreadableLocations: scan.unreadableLocations.map { Output.path($0.url) }
        )
    }

    static func heading(for group: OrphanGroup) -> String {
        "\(group.identifier)  \(Output.size(group.total))  \(group.confidence.levelName): \(group.confidence.summary)"
    }

    static func rows(for group: OrphanGroup) -> [[String]] {
        group.items.map { item in
            [Output.size(item.size), Output.path(item.url)] + (item.heldBack.map { ["stays: \($0.summary)"] } ?? [])
        }
    }

    func clean(
        _ identifier: String,
        in scan: OrphanScan,
        apps: [InstalledApp],
        scanner: OrphanScanner,
        using service: TrashService,
        recordingIn log: RemovalLog = RemovalLog(),
        refusals: RefusalLog = RefusalLog()
    ) async throws {
        let wanted = scan.groups.filter { $0.identifier.caseInsensitiveCompare(identifier) == .orderedSame }
        guard let group = wanted.first else {
            throw CommandFailure("Nothing orphaned is called \(Output.quoted(identifier)). See `peel orphans`.")
        }
        let items = group.items.filter { $0.heldBack == nil }
        // Nobody asked for a held back file on its own, so it is said here and never recorded as refused.
        let staying = group.items.compactMap { item in item.heldBack.map { "\(Output.plain(Output.path(item.url))) stays: \($0.summary)" } }
        guard !items.isEmpty else {
            Output.line("Every file of \(group.identifier) is one Peel leaves alone. See `peel orphans`.")
            staying.forEach(Output.note)
            return
        }
        let cleanup = Cleanup.of(
            items.map { (url: $0.url, size: $0.size) },
            source: group.title,
            tool: "orphans",
            needingAdministrator: Set(items.filter(\.requiresPrivileges).map(\.url)),
            service: service
        )
        try await cleanup.run(
            question: "Move \(Output.count(cleanup.moving.count, "item", "items")) of \(group.title) to the Trash?",
            notes: staying,
            dryRun: removal.dryRun,
            yes: removal.yes,
            using: service,
            recordingIn: log,
            refusals: refusals
        ) { service, urls in
            let wanted = Set(urls)
            return await OrphanRemoval.trash(
                items.filter { wanted.contains($0.url) },
                installedApps: apps,
                scanner: scanner,
                using: service
            )
        }
    }
}

struct CachesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "caches",
        abstract: "List caches of developer tools, and move them to the Trash.",
        discussion: "With --remove, only what Peel would suggest goes: never a toolchain, an account, a token, or something it couldn't measure. Name tools to narrow it down."
    )

    @Argument(help: "Tools to look at, as `peel caches` names them. All of them when none is given.")
    var tools: [String] = []

    @Flag(help: RemovalOptions.movesWhatPeelSuggests)
    var remove = false

    @OptionGroup var removal: RemovalOptions

    @OptionGroup var output: OutputOptions

    struct Record: Encodable {
        let tool: String
        let size: MeasuredSize
        let locations: [Location]

        struct Location: Encodable {
            let path: String
            let size: MeasuredSize
            let kind: String
            let source: String
            /// Whether `--remove` would move it.
            let suggested: Bool
        }
    }

    func validate() throws {
        try removal.validate(removing: remove, with: output)
    }

    func run() async throws {
        let all = await DeveloperCaches.scan(exclusions: UnreadableExclusions.load())
        let environments = try Self.chosen(from: all, named: tools)
        guard !remove else {
            return try await clean(environments, using: TrashService(exclusions: await ExclusionStore().load()))
        }

        if output.json {
            try Output.json(Self.records(for: environments))
        } else if environments.isEmpty {
            Output.line("No developer caches found.")
        } else {
            for environment in environments {
                Output.line("\(environment.name)  \(Output.size(environment.total))")
                Output.table(Self.rows(for: environment), indent: "  ")
            }
        }
    }

    static func rows(for environment: DeveloperEnvironment) -> [[String]] {
        environment.locations.map { [Output.size($0.size), Output.path($0.url), $0.kind.summary] }
    }

    static func records(for environments: [DeveloperEnvironment]) -> [Record] {
        environments.map { environment in
            Record(tool: environment.name, size: MeasuredSize(environment.total), locations: environment.locations.map {
                Record.Location(
                    path: Output.path($0.url),
                    size: MeasuredSize($0.size),
                    kind: $0.kind.rawValue,
                    source: $0.source,
                    suggested: $0.isRecommended
                )
            })
        }
    }

    /// Returns the environments named in `tools`, by the name the listing shows or by its identifier, ignoring
    /// case. All of them when `tools` is empty.
    static func chosen(from environments: [DeveloperEnvironment], named tools: [String]) throws -> [DeveloperEnvironment] {
        guard !tools.isEmpty else { return environments }
        let chosen = environments.filter { environment in
            tools.contains { $0.caseInsensitiveCompare(environment.name) == .orderedSame || $0.caseInsensitiveCompare(environment.id) == .orderedSame }
        }
        guard !chosen.isEmpty else {
            throw CommandFailure("No developer caches of \(tools.map(Output.quoted).joined(separator: ", ")) were found. See `peel caches`.")
        }
        return chosen
    }

    func clean(
        _ environments: [DeveloperEnvironment],
        using service: TrashService,
        recordingIn log: RemovalLog = RemovalLog(),
        refusals: RefusalLog = RefusalLog()
    ) async throws {
        // Nothing of a tool moves while its app runs, since the app writes in those folders.
        let open = environments.filter { $0.runningApp != nil && $0.locations.contains(where: \.isRecommended) }
        for environment in open {
            Output.note(Self.quitFirst(environment))
        }
        let closed = environments.filter { environment in !open.contains { $0.id == environment.id } }
        let locations = closed.flatMap { environment in environment.locations.filter(\.isRecommended) }
        guard !locations.isEmpty else {
            if let first = open.first {
                throw CommandFailure(Self.quitFirst(first))
            }
            Output.line("Nothing here is safe to suggest. See `peel caches`.")
            return
        }
        let cleanup = Cleanup.of(
            locations.map { (url: $0.url, size: $0.size) },
            source: closed.count == 1 ? closed[0].name : "Developer caches",
            sourceKey: closed.count == 1 ? nil : "tool",
            tool: "developer",
            service: service
        )
        try await cleanup.run(
            question: "Move \(Output.count(cleanup.moving.count, "item", "items")) to the Trash?",
            dryRun: removal.dryRun,
            yes: removal.yes,
            using: service,
            recordingIn: log,
            refusals: refusals,
            checkingAgain: {
                // The question takes time, and an app may have been opened meanwhile.
                if let reopened = closed.first(where: { $0.runningApp != nil }) {
                    throw CommandFailure(Self.quitFirst(reopened))
                }
            }
        )
    }

    private static func quitFirst(_ environment: DeveloperEnvironment) -> String {
        "Quit \(Output.plain(environment.runningApp ?? environment.name)) first: \(environment.name)'s caches stay while it runs."
    }
}

struct ProjectsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "projects",
        abstract: "List what builds left behind in your projects, and move it to the Trash.",
        discussion: "A folder only counts when the file that makes it sits beside it, or its tool tagged it as a cache. Projects changed in the last 7 days, and folders under a name that could mean anything, are listed but never suggested, and --remove moves only what is suggested."
    )

    @Argument(help: "Folders your projects live in.", completion: .directory)
    var folders: [String]

    @Flag(help: RemovalOptions.movesWhatPeelSuggests)
    var remove = false

    @OptionGroup var removal: RemovalOptions

    @OptionGroup var output: OutputOptions

    struct Record: Encodable {
        let path: String
        let project: String
        /// `null` for a folder known only by the cache directory tag its tool wrote.
        let tool: String?
        let size: MeasuredSize
        let suggested: Bool
        let recentlyActive: Bool
        /// Why measuring the folder left it to be chosen by hand, or `null` when nothing did.
        let heldBack: String?

        private enum CodingKeys: String, CodingKey {
            case path
            case project
            case tool
            case size
            case suggested
            case recentlyActive
            case heldBack
        }

        /// Encodes a missing `heldBack` as `null`, for the reason `AppRecord` gives.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(path, forKey: .path)
            try container.encode(project, forKey: .project)
            try container.encode(tool, forKey: .tool)
            try container.encode(size, forKey: .size)
            try container.encode(suggested, forKey: .suggested)
            try container.encode(recentlyActive, forKey: .recentlyActive)
            try container.encode(heldBack, forKey: .heldBack)
        }
    }

    /// Fails when none of the folders can be searched, giving the reason for each, rather than report that
    /// nothing built was found.
    func validate() throws {
        try removal.validate(removing: remove, with: output)
        let refused = folders.map(URL.init(argument:)).compactMap { root in
            ProjectArtifacts.refusal(for: root).map { "\(Output.plain(Output.path(root))): \($0.summary)" }
        }
        guard refused.count < folders.count else {
            throw ValidationError((refused.isEmpty ? ["No folders to look in."] : refused).joined(separator: "\n"))
        }
    }

    func run() async throws {
        let roots = folders.map(URL.init(argument:))
        // Each folder that can't be searched gets a note, so it isn't mistaken for one with nothing built in it.
        for root in roots {
            if let refusal = ProjectArtifacts.refusal(for: root) {
                Output.note("\(Output.plain(Output.path(root))): \(refusal.summary)")
            }
        }
        let scan = await ProjectArtifacts.scan(roots: roots, exclusions: UnreadableExclusions.load())
        let artifacts = scan.artifacts
        if remove {
            Self.notes(for: scan).forEach(Output.note)
            return try await clean(artifacts, using: TrashService(exclusions: await ExclusionStore().load()))
        }

        if output.json {
            try Output.json(Self.report(for: scan))
        } else if artifacts.isEmpty {
            Output.line("Nothing built was found in those folders.")
        } else {
            Output.table(Self.rows(for: artifacts))
        }
        Self.notes(for: scan).forEach(Output.note)
    }

    /// What `--json` writes.
    struct Report: Encodable {
        let artifacts: [Record]
        let unreadableLocations: [String]
    }

    /// What the scan couldn't look at, said on standard error whatever the output, so that an empty answer is not
    /// read as nothing being there.
    static func notes(for scan: ProjectArtifacts.Scan) -> [String] {
        var notes: [String] = []
        if !scan.unreadableLocations.isEmpty {
            notes.append(Output.fullDiskAccessNote)
        }
        if scan.wasCutShort {
            notes.append("There were more folders than Peel looks at in one go, so this list isn't all of them.")
        }
        return notes
    }

    static func report(for scan: ProjectArtifacts.Scan) -> Report {
        Report(
            artifacts: scan.artifacts.map {
                Record(
                    path: Output.path($0.url),
                    project: Output.path($0.project),
                    tool: $0.tool,
                    size: MeasuredSize($0.size),
                    suggested: $0.isRecommended,
                    recentlyActive: $0.isRecentlyActive,
                    heldBack: $0.heldBack?.rawValue
                )
            },
            unreadableLocations: scan.unreadableLocations.map(Output.path)
        )
    }

    func clean(
        _ artifacts: [ProjectArtifact],
        using service: TrashService,
        recordingIn log: RemovalLog = RemovalLog(),
        refusals: RefusalLog = RefusalLog()
    ) async throws {
        let suggested = artifacts.filter(\.isRecommended)
        guard !suggested.isEmpty else {
            Output.line("Nothing here is safe to suggest. See `peel projects`.")
            return
        }
        let projects = Set(suggested.map(\.project.lastPathComponent)).sorted()
        let cleanup = Cleanup.of(
            suggested.map { (url: $0.url, size: $0.size) },
            source: projects.count == 1 ? projects[0] : "Build artifacts",
            sourceKey: projects.count == 1 ? nil : "tool",
            tool: "projects",
            service: service
        )
        try await cleanup.run(
            question: "Move \(Output.count(cleanup.moving.count, "folder", "folders")) to the Trash?",
            dryRun: removal.dryRun,
            yes: removal.yes,
            using: service,
            recordingIn: log,
            refusals: refusals
        )
    }

    static func rows(for artifacts: [ProjectArtifact]) -> [[String]] {
        artifacts.map { [Output.size($0.size), Output.path($0.url), $0.tool ?? "tagged as a cache", note(for: $0)] }
    }

    /// Returns why `artifact` is kept, or "suggested". It checks the same conditions as `isRecommended`, and
    /// the two must never disagree.
    static func note(for artifact: ProjectArtifact) -> String {
        if let heldBack = artifact.heldBack { return "\(heldBack.summary), kept" }
        if artifact.isRecentlyActive { return "changed in the last 7 days, kept" }
        if !artifact.lastActivityIsCertain { return "too large to tell when it last changed, kept" }
        if artifact.isEnvironment { return "installed packages, kept" }
        if artifact.hasGenericName { return "name could mean anything, kept" }
        return "suggested"
    }
}

struct DuplicatesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "duplicates",
        abstract: "Find folders and files with identical contents.",
        discussion: "Without folders, Peel scans Desktop, Documents, Downloads, Pictures, Movies, and Music. The first copy of each group is the one Peel suggests keeping. A folder is a copy of another only when every file under it matches, so what a folder already speaks for isn't listed again on its own."
    )

    @Argument(help: "Folders to scan.", completion: .directory)
    var folders: [String] = []

    @Option(help: "Only files of this kind.")
    var kind: KindArgument?

    @Option(name: .customLong("min-size"), help: "Only files at least this large, and folders holding at least this much, like 500KB or 1.5GB.")
    var minimumSize: ByteSize?

    @Flag(help: RemovalOptions.movesWhatPeelSuggests)
    var remove = false

    @OptionGroup var removal: RemovalOptions

    @OptionGroup var output: OutputOptions

    struct Record: Encodable {
        let size: Int64
        let reclaimableSize: Int64
        let files: [String]
    }

    struct FolderRecord: Encodable {
        let size: Int64
        let reclaimableSize: Int64
        let fileCount: Int
        let folders: [String]
    }

    struct Found: Encodable {
        let folders: [FolderRecord]
        let files: [Record]
        let unreadableLocations: [String]
        /// Chosen folders the scan didn't look in.
        let skippedLocations: [String]
    }

    /// Checks the folders here rather than in `run()`: only while it parses does ArgumentParser know which
    /// subcommand's usage to print. The finder needs no exclusions, since they don't decide what can be scanned.
    func validate() throws {
        try removal.validate(removing: remove, with: output)
        // One finder for every folder: each new finder resolves the home folder's links again.
        let finder = DuplicateFinder()
        let urls = folders.map(URL.init(argument:))
        let missing = urls.filter { !isAFolder($0) }
        guard missing.isEmpty else {
            throw ValidationError("\(missing.map(Output.path).joined(separator: ", ")): no such folder.")
        }
        let rejected = urls.filter { !finder.canScan($0) }
        guard rejected.isEmpty else {
            throw ValidationError("Peel can't scan \(rejected.map(Output.path).joined(separator: ", ")). Choose folders in your home folder, /Users/Shared, or a disk Peel can write to. iCloud Drive, app data, the Music and TV apps' media folders, apps and other packages, and system folders aren't scanned.")
        }
    }

    func run() async throws {
        let finder = await DuplicateFinder(exclusions: UnreadableExclusions.load(), digestMemory: DigestMemory())
        let urls = folders.isEmpty ? finder.defaultFolders : folders.map(URL.init(argument:))
        var options = DuplicateScanOptions(folders: urls)
        options.kind = kind?.fileKind ?? .any
        options.minimumSize = minimumSize?.bytes ?? 1
        let scan = try await finder.scan(options)
        if remove {
            Self.notes(for: scan).forEach(Output.note)
            return try await clean(scan, using: TrashService(exclusions: await ExclusionStore().load()))
        }

        if output.json {
            try Output.json(Self.found(in: scan))
        } else if scan.groups.isEmpty, scan.folderGroups.isEmpty {
            Output.line("No duplicates found.")
        } else {
            for group in scan.folderGroups {
                Output.line(Self.heading(for: group))
                Output.table(Self.rows(for: group.folders.map(\.url)), indent: "  ")
            }
            for group in scan.groups {
                Output.line(Self.heading(for: group))
                Output.table(Self.rows(for: group.files.map(\.url)), indent: "  ")
            }
            let total = scan.groups.reduce(0) { $0 + $1.reclaimableSize } + scan.folderGroups.reduce(0) { $0 + $1.reclaimableSize }
            Output.line("Total to free: \(Output.size(total))")
        }
        Self.notes(for: scan).forEach(Output.note)
    }

    /// What the scan didn't look at, said on standard error whatever the output, so that an empty answer is not
    /// read as nothing being there.
    static func notes(for scan: DuplicateScan) -> [String] {
        var notes: [String] = []
        if !scan.unreadableLocations.isEmpty {
            notes.append(
                Output.unreadableNote(for: scan.unreadableLocations, needsFullDiskAccess: scan.needsFullDiskAccess)
            )
        }
        if !scan.skippedLocations.isEmpty {
            let folders = scan.skippedLocations.map(Output.path).joined(separator: ", ")
            notes.append("Peel didn't look in \(folders), so there may be duplicates there. It leaves repositories alone, and doesn't scan iCloud Drive, app data, or system folders.")
        }
        return notes
    }

    static func found(in scan: DuplicateScan) -> Found {
        Found(
            folders: scan.folderGroups.map { group in
                FolderRecord(
                    size: group.size,
                    reclaimableSize: group.reclaimableSize,
                    fileCount: group.fileCount,
                    folders: group.folders.map { Output.path($0.url) }
                )
            },
            files: scan.groups.map { Record(size: $0.size, reclaimableSize: $0.reclaimableSize, files: $0.files.map { Output.path($0.url) }) },
            unreadableLocations: scan.unreadableLocations.map(Output.path),
            skippedLocations: scan.skippedLocations.map(Output.path)
        )
    }

    static func heading(for group: DuplicateFolderGroup) -> String {
        "\(Output.count(group.folders.count, "copy", "copies")) of a folder of \(Output.count(group.fileCount, "file", "files")), \(Output.size(group.size)), \(Output.size(group.reclaimableSize)) to free"
    }

    static func heading(for group: DuplicateGroup) -> String {
        "\(Output.count(group.files.count, "copy", "copies")) of \(Output.size(group.size)), \(Output.size(group.reclaimableSize)) to free"
    }

    /// One row per copy. Only the first, the copy Peel suggests keeping, is marked "keep".
    static func rows(for copies: [URL]) -> [[String]] {
        copies.enumerated().map { index, url in [index == 0 ? "keep" : "", Output.path(url)] }
    }

    func clean(
        _ scan: DuplicateScan,
        using service: TrashService,
        recordingIn log: RemovalLog = RemovalLog(),
        refusals: RefusalLog = RefusalLog()
    ) async throws {
        let folders = scan.folderGroups.flatMap { $0.folders.dropFirst() }
        let files = scan.groups.flatMap { $0.files.dropFirst() }
        guard !folders.isEmpty || !files.isEmpty else {
            Output.line("No duplicates found.")
            return
        }
        // Where each group's kept copy is comes first: it is what the decision rests on.
        let kept = scan.folderGroups.compactMap { $0.folders.first?.url }
            + scan.groups.compactMap { $0.files.first?.url }
        Output.table(kept.map { ["keep", Output.path($0)] })
        let cleanup = Cleanup.of(
            folders.map { (url: $0.url, size: $0.reclaimableSize) } + files.map { (url: $0.url, size: $0.reclaimableSize) },
            source: "Duplicates",
            sourceKey: "tool",
            tool: "duplicates",
            service: service
        )
        try await cleanup.run(
            question: "Move \(Output.count(cleanup.moving.count, "copy", "copies")) to the Trash? One of each is always kept.",
            dryRun: removal.dryRun,
            yes: removal.yes,
            using: service,
            recordingIn: log,
            refusals: refusals
        ) { service, urls in
            let wanted = Set(urls)
            return await DuplicateRemoval.trash(
                Set(files.map(\.url)).intersection(wanted),
                folders: Set(folders.map(\.url)).intersection(wanted),
                from: scan,
                using: service
            )
        }
    }
}

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "search", abstract: "Search the Spotlight index for files.")

    @Option(help: "Part of the file name.")
    var name: String?

    @Option(help: "The kind of file.")
    var kind: KindArgument?

    @Option(name: .customLong("min-size"), help: "Only files at least this large, like 500KB or 1.5GB.")
    var minimumSize: ByteSize?

    @Option(name: .customLong("older-than"), help: "Only files not modified in this many days.")
    var olderThan: Int?

    @Flag(help: "Search every volume mounted on this Mac, not only your home folder.")
    var everywhere = false

    @OptionGroup var output: OutputOptions

    private struct Record: Encodable {
        let path: String
        let size: Int64
        let modificationDate: Date
    }

    var criteria: FileSearchCriteria {
        var criteria = FileSearchCriteria()
        criteria.name = name ?? ""
        criteria.kind = kind?.fileKind ?? .any
        criteria.minimumSize = minimumSize?.bytes ?? 0
        criteria.unmodifiedDays = olderThan ?? 0
        criteria.scope = everywhere ? .computer : .home
        return criteria
    }

    func validate() throws {
        guard criteria.isSearchable else {
            throw ValidationError("Add --name, --kind, or --min-size to narrow the search.")
        }
        if let olderThan, olderThan < 0 {
            throw ValidationError("--older-than can't be negative.")
        }
    }

    func run() async throws {
        let results = await FileSearch.run(criteria, exclusions: UnreadableExclusions.load())
        guard results.didRun else {
            throw CommandFailure("Spotlight didn't answer, so Peel can't say what is on this Mac. Check that Spotlight indexing is on.")
        }

        if output.json {
            try Output.json(results.files.map { Record(path: Output.path($0.url), size: $0.size, modificationDate: $0.modificationDate) })
        } else if results.files.isEmpty {
            Output.line("No files found.")
        } else {
            Output.table(results.files.map { [Output.size($0.size), Output.day($0.modificationDate), Output.path($0.url)] })
        }
        if results.isTruncated {
            Output.note("Only the first \(Output.number(FileSearch.maximumResults)) files are shown. Narrow the search to see the rest.")
        }
    }
}
