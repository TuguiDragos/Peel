import Darwin
public import Foundation
import PeelPrivileged

public enum BackgroundItems {
    static let serviceManagement = "com.apple.xpc.ServiceManagement"
    private static let concurrentDetailQueries = 8

    /// What `launchctl` answered about in a form Peel cannot read, kind by kind, so some jobs may be missing.
    public struct Unanswered: Sendable, Hashable {
        /// The kinds whose loaded jobs couldn't be listed: the jobs apps added, known only from that list, may be
        /// missing.
        public var lists: Set<BackgroundItem.Kind> = []
        /// The kinds whose disabled jobs couldn't be read: the state of each job isn't known, and a disabled job that
        /// isn't loaded may be missing.
        public var overrides: Set<BackgroundItem.Kind> = []
        /// The kinds of the jobs an app added whose own answer couldn't be read, so their rows may be missing.
        public var jobs: Set<BackgroundItem.Kind> = []

        public init(
            lists: Set<BackgroundItem.Kind> = [], overrides: Set<BackgroundItem.Kind> = [],
            jobs: Set<BackgroundItem.Kind> = []
        ) {
            self.lists = lists
            self.overrides = overrides
            self.jobs = jobs
        }

        public var isEmpty: Bool { kinds.isEmpty }

        /// Every kind some of whose jobs may be missing, for whatever reason.
        public var kinds: Set<BackgroundItem.Kind> { lists.union(overrides).union(jobs) }
    }

    public struct Scan: Sendable {
        public let items: [BackgroundItem]
        public let unanswered: Unanswered
        /// The folders that kept Peel from listing a folder of job files, so a job whose file is there and which isn't
        /// loaded is missing.
        public let unreadableFolders: [URL]

        public init(
            items: [BackgroundItem] = [], unanswered: Unanswered = Unanswered(), unreadableFolders: [URL] = []
        ) {
            self.items = items
            self.unanswered = unanswered
            self.unreadableFolders = unreadableFolders
        }
    }

    /// A loaded job no file in the three folders declares, as `launchctl` described it.
    enum Undeclared: Equatable {
        case item(BackgroundItem)
        /// Nothing to list: one of macOS's own, an excluded file, or a job that is no longer loaded.
        case nothing
        /// `launchctl` answered in a form Peel cannot read, so the job may belong in the list.
        case unreadable(BackgroundItem.Kind)
    }

    @concurrent
    public static func scan(
        installedApps: [InstalledApp] = [],
        environment: SearchEnvironment = .current,
        exclusions: Exclusions = .none
    ) async -> Scan {
        let ownership = BackgroundItemOwnership(installedApps: installedApps)
        let userDomain = "gui/\(getuid())"
        async let userList = Launchctl.run(["list"])
        async let systemPrint = Launchctl.run(["print", "system"])
        async let userDisabledOutput = Launchctl.run(["print-disabled", userDomain])
        // `launchctl list` names the jobs of the user's own domain too, which launchd keeps apart from the GUI one.
        async let userDomainPrint = Launchctl.run(["print", "user/\(getuid())"])

        let systemOutput = await systemPrint.output
        let loaded = Loaded(
            user: Launchctl.parseList(await userList.output),
            system: Launchctl.parseSystemServices(systemOutput),
            userDisabled: Launchctl.parseDisabled(await userDisabledOutput.output),
            systemDisabled: Launchctl.parseDisabled(systemOutput),
            inTheUserDomain: Launchctl.parseSystemServices(await userDomainPrint.output).map { Set($0.keys) }
        )

        var items = await settlingSharedLabels(
            declared(in: environment, ownership: ownership, exclusions: exclusions, loaded: loaded)
        ) { item in
            Launchctl.parseDetails(await Launchctl.run(["print", BackgroundItemActions.target(of: item)]).output)?.path
        }

        let submitted = undeclared(in: loaded, declared: items, uid: getuid())

        let found = await withTaskGroup(of: Undeclared.self) { group in
            var pending = submitted.makeIterator()
            var results: [Undeclared] = []
            for _ in 0..<concurrentDetailQueries {
                guard let next = pending.next() else { break }
                group.addTask {
                    await appSubmittedItem(next, ownership: ownership, loaded: loaded, exclusions: exclusions)
                }
            }
            while let result = await group.next() {
                results.append(result)
                if !Task.isCancelled, let next = pending.next() {
                    group.addTask {
                        await appSubmittedItem(next, ownership: ownership, loaded: loaded, exclusions: exclusions)
                    }
                }
            }
            return results
        }
        let undeclared = merged(found, loaded: loaded)
        let unlisted = unlistedJobFolders(in: environment, exclusions: exclusions)
        items = placing(undeclared.items, into: items, unlisted: unlisted.map { ($0.folder, $0.source) })
        items += disabledJobs(in: loaded, listed: items, ownership: ownership)

        return Scan(
            items: rows(items, exclusions: exclusions),
            unanswered: undeclared.unanswered,
            unreadableFolders: unlisted.map(\.refused).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        )
    }

    /// The rows, each job launchd loaded from a file Peel can't read in the place of that file's row, with the file's
    /// folder as its source; then the other loaded jobs.
    /// The rows in the page's order. A job of an app the person excluded stays listed, marked so: the tab says what
    /// runs in the background, and Peel acts on none of it.
    static func rows(_ items: [BackgroundItem], exclusions: Exclusions) -> [BackgroundItem] {
        items
            .map { item in
                var item = item
                item.isExcluded = item.ownerBundleIdentifier.map(exclusions.excludes(bundleIdentifier:)) == true
                return item
            }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    private static func jobFolders(
        in environment: SearchEnvironment
    ) -> [(folder: URL, kind: BackgroundItem.Kind, source: BackgroundItem.Source)] {
        let userLibrary = environment.homeDirectory.appending(path: "Library", directoryHint: .isDirectory)
        let systemLibrary = environment.rootDirectory.appending(path: "Library", directoryHint: .isDirectory)
        return [
            (userLibrary.appending(path: "LaunchAgents", directoryHint: .isDirectory), .agent, .userLibrary),
            (systemLibrary.appending(path: "LaunchAgents", directoryHint: .isDirectory), .agent, .systemLibrary),
            (systemLibrary.appending(path: "LaunchDaemons", directoryHint: .isDirectory), .daemon, .systemLibrary),
        ]
    }

    /// The folders of the three that Peel can't list, each with where its jobs come from and the folder that kept Peel
    /// out, which can be one around it.
    static func unlistedJobFolders(
        in environment: SearchEnvironment, exclusions: Exclusions = .none
    ) -> [(folder: URL, source: BackgroundItem.Source, refused: URL)] {
        jobFolders(in: environment).compactMap { folder, _, source in
            guard !exclusions.excludes(folder),
                  (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) == nil,
                  let refused = FileAccess.refusedFolder(folder)
            else { return nil }
            return (folder, source, refused)
        }
    }

    /// The rows, each job launchd loaded from a file Peel can't read in the place of that file's row, with the file's
    /// folder as its source; then the other loaded jobs, one from a folder Peel can't list with that folder's source.
    static func placing(
        _ loadedJobs: [BackgroundItem],
        into rows: [BackgroundItem],
        unlisted: [(folder: URL, source: BackgroundItem.Source)] = []
    ) -> [BackgroundItem] {
        var rows = rows
        var others: [BackgroundItem] = []
        for job in loadedJobs {
            guard let plist = job.plistURL else {
                others.append(job)
                continue
            }
            let file = PathPattern.comparablePath(of: plist)
            let folder = PathPattern.comparablePath(of: plist.deletingLastPathComponent())
            var placed = job
            placed.isClosedToPeel = true
            if let index = rows.firstIndex(where: {
                $0.isClosedToPeel && $0.isNamedByItsFile && $0.plistURL.map(PathPattern.comparablePath(of:)) == file
            }) {
                placed.source = rows[index].source
                rows[index] = placed
            } else if let unlisted = unlisted.first(where: { PathPattern.comparablePath(of: $0.folder) == folder }) {
                placed.source = unlisted.source
                others.append(placed)
            } else {
                others.append(job)
            }
        }
        return rows + others
    }

    /// The items among what `launchctl` said of each undeclared job, and what was not answered: what `loaded` could
    /// not read, and the kind of each job whose answer could not be read.
    static func merged(_ found: [Undeclared], loaded: Loaded) -> (items: [BackgroundItem], unanswered: Unanswered) {
        var items: [BackgroundItem] = []
        var unanswered = loaded.unanswered
        for result in found {
            switch result {
            case .item(let item): items.append(item)
            case .nothing: break
            case .unreadable(let kind): unanswered.jobs.insert(kind)
            }
        }
        return (items, unanswered)
    }

    /// The loaded jobs no file in the three folders declares, which an app may have submitted and `appSubmittedItem`
    /// then asks about. Apple's own are left out.
    static func undeclared(
        in loaded: Loaded,
        declared items: [BackgroundItem],
        uid: uid_t
    ) -> [(label: String, kind: BackgroundItem.Kind, target: String)] {
        // By kind and label: an item's `id` also holds its file's path, which a loaded job does not report. A file
        // Peel can't read names no label, so whatever job launchd loaded from it is asked about too.
        let known = Set(items.filter { !$0.isClosedToPeel }.map { "\($0.kind.rawValue)/\($0.label)" })
        let candidates: [(label: String, kind: BackgroundItem.Kind, target: String)] =
            (loaded.user ?? [:]).keys.map { label in
                (label, .agent, "\(loaded.isInTheUserDomain(label) ? "user" : "gui")/\(uid)/\(label)")
            }
            + (loaded.system ?? [:]).keys.map { ($0, .daemon, "system/\($0)") }
        return candidates.filter { label, kind, _ in
            !label.hasPrefix("com.apple.") && !label.hasPrefix("application.") && !known.contains("\(kind.rawValue)/\(label)")
        }.sorted { $0.label < $1.label }
    }

    /// The jobs launchd keeps disabled that no row lists, because they are not loaded and no file here declares
    /// them, when they belong to an installed app. A job an app registered is seen only while it is loaded, so without
    /// this row, one disabled here would leave the list after a restart, with no way to Enable it again.
    static func disabledJobs(
        in loaded: Loaded,
        listed: [BackgroundItem],
        ownership: BackgroundItemOwnership
    ) -> [BackgroundItem] {
        let known = Set(listed.map { "\($0.kind.rawValue)/\($0.label)" })
        let overrides = (loaded.userDisabled ?? [:]).map { ($0.key, $0.value, BackgroundItem.Kind.agent) }
            + (loaded.systemDisabled ?? [:]).map { ($0.key, $0.value, BackgroundItem.Kind.daemon) }
        return overrides.compactMap { label, isDisabled, kind in
            guard isDisabled, !label.hasPrefix("com.apple."), !label.hasPrefix("application."),
                  !known.contains("\(kind.rawValue)/\(label)"), loaded.state(of: label, kind) == .notLoaded
            else { return nil }
            let byLabel = ownership.owner(label: label, associated: [], program: nil)
            guard let owner = byLabel?.isInstalled == true ? byLabel : ownership.owner(declaring: label, kind: kind),
                  let app = owner.url
            else {
                return nil
            }
            let declared = StartsAtLogin.declaration(of: label, kind: kind, in: app)
            return BackgroundItem(
                label: label,
                kind: kind,
                source: .app,
                plistURL: nil,
                program: nil,
                runsAtLoad: declared?.runsAtLoad,
                keepsAlive: declared?.keepsAlive ?? nil,
                ownerBundleIdentifier: owner.bundleIdentifier,
                ownerName: owner.name,
                ownerURL: owner.url,
                isOrphan: false,
                state: .notLoaded,
                isDisabled: true,
                isOwnerConfirmed: owner.isConfirmed
            )
        }
    }

    /// What `launchctl` reports right now. Each part is nil when `launchctl` answered in a form Peel cannot read.
    struct Loaded {
        var user: [String: Int32?]? = [:]
        var system: [String: Int32?]? = [:]
        var userDisabled: [String: Bool]? = [:]
        var systemDisabled: [String: Bool]? = [:]
        /// The agents launchd keeps in the user's own domain rather than the GUI one, which are asked about there.
        var inTheUserDomain: Set<String>? = []

        func isInTheUserDomain(_ label: String) -> Bool {
            inTheUserDomain?.contains(label) == true
        }

        /// The state of the job `label` of `kind`, known only when what `launchctl` said about both the jobs and
        /// the overrides of its domain could be read.
        func state(of label: String, _ kind: BackgroundItem.Kind) -> BackgroundItem.State {
            guard let jobs = kind == .agent ? user : system, overrides(kind) != nil else { return .unknown }
            return switch jobs[label] {
            case .none: .notLoaded
            case .some(.none): .loaded
            case .some(.some(let pid)): .running(pid: pid)
            }
        }

        /// Whether `launchctl` marks the job `label` of `kind` disabled, or nil when it says nothing of it.
        func override(of label: String, _ kind: BackgroundItem.Kind) -> Bool? {
            overrides(kind)?[label]
        }

        /// What could not be read of the loaded jobs and of the disabled ones, kind by kind.
        var unanswered: Unanswered {
            var unanswered = Unanswered()
            if user == nil || inTheUserDomain == nil { unanswered.lists.insert(.agent) }
            if system == nil { unanswered.lists.insert(.daemon) }
            if userDisabled == nil { unanswered.overrides.insert(.agent) }
            if systemDisabled == nil { unanswered.overrides.insert(.daemon) }
            return unanswered
        }

        private func overrides(_ kind: BackgroundItem.Kind) -> [String: Bool]? {
            kind == .agent ? userDisabled : systemDisabled
        }
    }

    /// Returns the jobs declared in `~/Library/LaunchAgents`, `/Library/LaunchAgents`, and `/Library/LaunchDaemons`.
    /// It takes the `launchctl` state as `loaded` instead of running `launchctl`, so a test can use folders it made.
    static func declared(
        in environment: SearchEnvironment,
        ownership: BackgroundItemOwnership,
        exclusions: Exclusions = .none,
        loaded: Loaded = Loaded()
    ) -> [BackgroundItem] {
        var items: [BackgroundItem] = []
        for (folder, kind, source) in jobFolders(in: environment) {
            for plist in plists(in: folder) where !exclusions.excludes(plist) {
                // A label of macOS's own is shown too, and marked (`usesALabelOfMacOS`): macOS keeps its jobs
                // elsewhere, so a file here that borrows one is somebody else's, and a common way to hide a job.
                guard let job = JobDefinition(contentsOf: plist) else {
                    items.append(
                        FileAccess.isClosedToReading(plist)
                            ? closed(plist, kind: kind, source: source, ownership: ownership, loaded: loaded)
                            : unreadable(plist, kind: kind, source: source, ownership: ownership)
                    )
                    continue
                }
                let owner = ownership.owner(label: job.label, associated: job.associated, program: job.program)
                var item = BackgroundItem(
                    label: job.label,
                    kind: kind,
                    source: source,
                    plistURL: plist,
                    program: job.program,
                    runsAtLoad: job.runsAtLoad,
                    keepsAlive: job.keepsAlive,
                    ownerBundleIdentifier: owner?.bundleIdentifier,
                    ownerName: owner?.name,
                    ownerURL: owner?.url,
                    isOrphan: ownership.isOrphan(label: job.label, program: job.program, owner: owner),
                    state: loaded.state(of: job.label, kind),
                    isDisabled: loaded.override(of: job.label, kind) ?? job.isDisabled,
                    isOwnerConfirmed: owner?.isConfirmed ?? false,
                    unusualCommand: UnusualCommand(arguments: job.arguments)
                )
                item.loadsInTheBackgroundSession = kind == .agent && job.loadsInTheBackground
                items.append(item)
            }
        }
        return items
    }

    /// Gives a job two files declare its state on the row of the file launchd loaded it from, which `loadedFrom` asks
    /// of launchd, and marks the other row as not loaded. When launchd doesn't say which, neither row is said to run.
    static func settlingSharedLabels(
        _ items: [BackgroundItem], loadedFrom: (BackgroundItem) async -> String?
    ) async -> [BackgroundItem] {
        let declared = items.indices.filter { items[$0].plistURL != nil && !items[$0].isNamedByItsFile }
        let shared = Dictionary(grouping: declared) { "\(items[$0].kind.rawValue)/\(items[$0].label)" }
            .values.filter { $0.count > 1 }
        var settled = items
        for rows in shared where ![.notLoaded, .unknown].contains(items[rows[0]].state) {
            let path = await loadedFrom(items[rows[0]]).map { PathPattern.comparablePath(of: URL(filePath: $0)) }
            for row in rows {
                guard let path else {
                    settled[row].state = .unknown
                    continue
                }
                if let plist = items[row].plistURL, PathPattern.comparablePath(of: plist) != path {
                    settled[row].state = .notLoaded
                    settled[row].anotherFileIsLoaded = true
                }
            }
        }
        return settled
    }

    /// A job file launchd can't load, named by its file since it declares no label that can be read.
    private static func unreadable(
        _ plist: URL, kind: BackgroundItem.Kind, source: BackgroundItem.Source, ownership: BackgroundItemOwnership
    ) -> BackgroundItem {
        let name = plist.deletingPathExtension().lastPathComponent
        let owner = ownership.owner(label: name, associated: [], program: nil)
        return BackgroundItem(
            label: name,
            kind: kind,
            source: source,
            plistURL: plist,
            program: nil,
            runsAtLoad: false,
            keepsAlive: false,
            ownerBundleIdentifier: owner?.bundleIdentifier,
            ownerName: owner?.name,
            ownerURL: owner?.url,
            isOrphan: ownership.isOrphan(label: name, program: nil, owner: owner),
            state: .notLoaded,
            isDisabled: false,
            isOwnerConfirmed: owner?.isConfirmed ?? false,
            isUnreadable: true,
            isNamedByItsFile: true
        )
    }

    /// A job file macOS lets only its owner read, named by its file until launchd says which job it loaded from it.
    /// What it runs is not known, so it is never called orphaned, and it is said not loaded only when no job runs
    /// under its name.
    private static func closed(
        _ plist: URL,
        kind: BackgroundItem.Kind,
        source: BackgroundItem.Source,
        ownership: BackgroundItemOwnership,
        loaded: Loaded
    ) -> BackgroundItem {
        let name = plist.deletingPathExtension().lastPathComponent
        let owner = ownership.owner(label: name, associated: [], program: nil)
        return BackgroundItem(
            label: name,
            kind: kind,
            source: source,
            plistURL: plist,
            program: nil,
            runsAtLoad: nil,
            keepsAlive: nil,
            ownerBundleIdentifier: owner?.bundleIdentifier,
            ownerName: owner?.name,
            ownerURL: owner?.url,
            isOrphan: false,
            state: loaded.state(of: name, kind) == .notLoaded ? .notLoaded : .unknown,
            isDisabled: loaded.override(of: name, kind) ?? false,
            isOwnerConfirmed: owner?.isConfirmed ?? false,
            isClosedToPeel: true,
            isNamedByItsFile: true
        )
    }

    private static func appSubmittedItem(
        _ candidate: (label: String, kind: BackgroundItem.Kind, target: String),
        ownership: BackgroundItemOwnership,
        loaded: Loaded,
        exclusions: Exclusions
    ) async -> Undeclared {
        let printed = await Launchctl.run(["print", candidate.target])
        let answer = Launchctl.answer(status: printed.status, output: printed.output)
        return undeclaredItem(candidate, answer: answer, ownership: ownership, loaded: loaded, exclusions: exclusions)
    }

    /// The item for a loaded job no file in the three folders declares, from what `launchctl print` said of it: one
    /// an app registered or submitted, named by its owner when Peel can tell it, or one something loaded from a file
    /// anywhere else, which launchd forgets at the next logout or restart. A job macOS loaded from its own folders is
    /// not an item, and neither is a file the user excluded.
    static func undeclaredItem(
        _ candidate: (label: String, kind: BackgroundItem.Kind, target: String),
        answer: Launchctl.Answer,
        ownership: BackgroundItemOwnership,
        loaded: Loaded,
        exclusions: Exclusions
    ) -> Undeclared {
        let details: Launchctl.JobDetails
        switch answer {
        case .details(let read): details = read
        case .gone: return .nothing
        case .unreadable: return .unreadable(candidate.kind)
        }
        let isSubmittedByApp = details.path?.hasPrefix("(submitted by") == true
            && details.program.map { !PathComponents.isPath($0, inside: "/System") } == true
        let isAnApps = details.managedBy == serviceManagement || isSubmittedByApp
        let path = details.path.flatMap { $0.hasPrefix("/") ? URL(filePath: $0) : nil }
        let isMacOSs = path.map { file in
            ["/System", "/Library/Apple"].contains { PathComponents.isPath(file.path(percentEncoded: false), inside: $0) }
        } ?? false
        guard isAnApps || (path != nil && !isMacOSs), path.map(exclusions.excludes) != true else { return .nothing }
        let job = path.flatMap(JobDefinition.init(contentsOf:))
        let program = details.program ?? job?.program
        let owner = ownership.owner(
            label: candidate.label,
            registeredBy: details.parentBundleIdentifier,
            associated: job?.associated ?? [],
            program: program
        )
        let state = loaded.state(of: candidate.label, candidate.kind)
        let registered = details.managedBy == serviceManagement
            ? owner?.url.flatMap { StartsAtLogin.declaration(of: candidate.label, kind: candidate.kind, in: $0) } : nil
        // launchctl names no program for an app's login item or agent: macOS finds it in the app as it starts it.
        let programIsUnnamed = isAnApps && program == nil
        let running = if case .running(let pid) = state { RunningProgram.path(of: pid) } else { String?.none }

        var item = BackgroundItem(
            label: candidate.label,
            kind: candidate.kind,
            source: isAnApps ? .app : .otherFile,
            plistURL: path,
            program: program,
            runsAtLoad: job?.runsAtLoad ?? registered?.runsAtLoad,
            keepsAlive: job?.keepsAlive ?? registered?.keepsAlive ?? nil,
            ownerBundleIdentifier: owner?.bundleIdentifier,
            ownerName: owner?.name,
            ownerURL: owner?.url,
            isOrphan: !programIsUnnamed && ownership.isOrphan(label: candidate.label, program: program, owner: owner),
            state: state,
            isDisabled: loaded.override(of: candidate.label, candidate.kind) ?? false,
            isOwnerConfirmed: owner?.isConfirmed ?? false,
            unusualCommand: UnusualCommand(arguments: job?.arguments ?? program.map { [$0] } ?? [])
        )
        item.runsFromTheTrash = programIsUnnamed && running.map { AppInspector.isInATrash(URL(filePath: $0)) } == true
        item.isSystemExtension = program.map { PathComponents.isPath($0, inside: "/Library/SystemExtensions") } == true
        item.isManagedByServiceManagement = details.managedBy == serviceManagement
        item.isSubmittedByItsApp = isSubmittedByApp && !item.isManagedByServiceManagement && !item.isSystemExtension
        item.isFileGone = !isAnApps && path?.isMissing == true
        item.loadsInTheBackgroundSession = candidate.kind == .agent && loaded.isInTheUserDomain(candidate.label)
        if isAnApps, item.canBeControlled, !item.isManagedByServiceManagement {
            item.staysListedWhenDisabled =
                ownership.owner(label: candidate.label, associated: [], program: nil)?.isInstalled == true
                    || ownership.owner(declaring: candidate.label, kind: candidate.kind) != nil
        }
        return .item(item)
    }

    private static func plists(in folder: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { $0.pathExtension == "plist" }
    }

}

struct JobDefinition {
    let label: String
    let program: String?
    /// The program and its arguments, as launchd runs them.
    let arguments: [String]
    let runsAtLoad: Bool
    let keepsAlive: Bool
    let isDisabled: Bool
    /// The plist's `AssociatedBundleIdentifiers`. Whoever wrote the plist chose them, so they are a claim, not proof.
    let associated: [String]
    /// True when `LimitLoadToSessionType`, a string or an array (`man launchd.plist`), names Background: launchd
    /// keeps such an agent in the user's own domain, whatever other sessions it names.
    let loadsInTheBackground: Bool
    let watchPaths: [String]

    init?(contentsOf url: URL) {
        guard
            let plist = BoundedRead.propertyList(at: url)
        else { return nil }
        self.init(plist)
    }

    init?(_ plist: [String: Any]) {
        guard let label = plist["Label"] as? String, !label.isEmpty else { return nil }
        self.label = label
        // Reads each argument alone: a cast to `[String]` fails when any argument is not a string.
        let listed = (plist["ProgramArguments"] as? [Any])?.compactMap { $0 as? String } ?? []
        program = plist["Program"] as? String ?? (plist["ProgramArguments"] as? [Any])?.first as? String
        arguments = (plist["Program"] as? String).map { [$0] + listed.dropFirst() } ?? listed
        keepsAlive = (plist["KeepAlive"] as? Bool) ?? (plist["KeepAlive"] is [String: Any])
        // `man launchd.plist`, KeepAlive: "The use of this key implicitly implies RunAtLoad".
        runsAtLoad = (plist["RunAtLoad"] as? Bool ?? false) || keepsAlive
        isDisabled = plist["Disabled"] as? Bool ?? false
        let named = plist["AssociatedBundleIdentifiers"]
        associated = (named as? String).map { [$0] } ?? (named as? [Any])?.compactMap { $0 as? String } ?? []
        let sessions = plist["LimitLoadToSessionType"]
        let types = (sessions as? String).map { [$0] } ?? (sessions as? [Any])?.compactMap { $0 as? String } ?? []
        loadsInTheBackground = types.contains("Background")
        watchPaths = (plist["WatchPaths"] as? [Any])?.compactMap { $0 as? String } ?? []
    }
}
