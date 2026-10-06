import Darwin
import Foundation
import PeelPrivileged

public enum BackgroundItems {
    private static let serviceManagement = "com.apple.xpc.ServiceManagement"
    private static let concurrentDetailQueries = 8

    public struct Scan: Sendable {
        public let items: [BackgroundItem]
        /// The kinds that may be missing jobs, because `launchctl` answered about them in a form Peel cannot read.
        public let unanswered: Set<BackgroundItem.Kind>
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

        let systemOutput = await systemPrint.output
        let loaded = Loaded(
            user: Launchctl.parseList(await userList.output),
            system: Launchctl.parseSystemServices(systemOutput),
            userDisabled: Launchctl.parseDisabled(await userDisabledOutput.output),
            systemDisabled: Launchctl.parseDisabled(systemOutput)
        )

        var items = declared(in: environment, ownership: ownership, exclusions: exclusions, loaded: loaded)

        let submitted = undeclared(in: loaded, declared: items, userDomain: userDomain)

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
        items += undeclared.items
        items += disabledJobs(in: loaded, listed: items, ownership: ownership)

        return Scan(
            items: items
                .filter { $0.ownerBundleIdentifier.map(exclusions.excludes(bundleIdentifier:)) != true }
                .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending },
            unanswered: undeclared.unanswered
        )
    }

    /// The items among what `launchctl` said of each undeclared job, and the kinds some of whose jobs may be missing:
    /// those `loaded` could not read, and those of a job whose answer could not be read.
    static func merged(
        _ found: [Undeclared], loaded: Loaded
    ) -> (items: [BackgroundItem], unanswered: Set<BackgroundItem.Kind>) {
        var items: [BackgroundItem] = []
        var unanswered = loaded.unanswered
        for result in found {
            switch result {
            case .item(let item): items.append(item)
            case .nothing: break
            case .unreadable(let kind): unanswered.insert(kind)
            }
        }
        return (items, unanswered)
    }

    /// The loaded jobs no file in the three folders declares, which an app may have submitted and `appSubmittedItem`
    /// then asks about. Apple's own are left out.
    static func undeclared(
        in loaded: Loaded,
        declared items: [BackgroundItem],
        userDomain: String
    ) -> [(label: String, kind: BackgroundItem.Kind, target: String)] {
        // By kind and label: an item's `id` also holds its file's path, which a loaded job does not report.
        let known = Set(items.map { "\($0.kind.rawValue)/\($0.label)" })
        let candidates: [(label: String, kind: BackgroundItem.Kind, target: String)] =
            (loaded.user ?? [:]).keys.map { ($0, .agent, "\(userDomain)/\($0)") }
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
                  !known.contains("\(kind.rawValue)/\(label)"), loaded.state(of: label, kind) == .notLoaded,
                  let owner = ownership.owner(label: label, associated: [], program: nil), owner.isInstalled
            else { return nil }
            return BackgroundItem(
                label: label,
                kind: kind,
                source: .app,
                plistURL: nil,
                program: nil,
                runsAtLoad: false,
                keepsAlive: false,
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

        /// The kinds whose loaded jobs or overrides could not be read, so that jobs an app registered, which are
        /// known only from them, may be missing.
        var unanswered: Set<BackgroundItem.Kind> {
            var kinds: Set<BackgroundItem.Kind> = []
            if user == nil || userDisabled == nil { kinds.insert(.agent) }
            if system == nil || systemDisabled == nil { kinds.insert(.daemon) }
            return kinds
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
        let userLibrary = environment.homeDirectory.appending(path: "Library", directoryHint: .isDirectory)
        let systemLibrary = environment.rootDirectory.appending(path: "Library", directoryHint: .isDirectory)
        let folders: [(URL, BackgroundItem.Kind, BackgroundItem.Source)] = [
            (userLibrary.appending(path: "LaunchAgents", directoryHint: .isDirectory), .agent, .userLibrary),
            (systemLibrary.appending(path: "LaunchAgents", directoryHint: .isDirectory), .agent, .systemLibrary),
            (systemLibrary.appending(path: "LaunchDaemons", directoryHint: .isDirectory), .daemon, .systemLibrary),
        ]

        var items: [BackgroundItem] = []
        for (folder, kind, source) in folders {
            for plist in plists(in: folder) where !exclusions.excludes(plist) {
                // A label of macOS's own is shown too, and marked (`usesALabelOfMacOS`): macOS keeps its jobs
                // elsewhere, so a file here that borrows one is somebody else's, and a common way to hide a job.
                guard let job = JobDefinition(contentsOf: plist) else {
                    items.append(unreadable(plist, kind: kind, source: source, ownership: ownership))
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
                item.loadsInTheBackgroundSession = kind == .agent && job.loadsOnlyInTheBackground
                items.append(item)
            }
        }
        return items
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
            isUnreadable: true
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

        return .item(BackgroundItem(
            label: candidate.label,
            kind: candidate.kind,
            source: isAnApps ? .app : .otherFile,
            plistURL: path,
            program: program,
            runsAtLoad: job?.runsAtLoad ?? false,
            keepsAlive: job?.keepsAlive ?? false,
            ownerBundleIdentifier: owner?.bundleIdentifier,
            ownerName: owner?.name,
            ownerURL: owner?.url,
            isOrphan: ownership.isOrphan(label: candidate.label, program: program, owner: owner),
            state: loaded.state(of: candidate.label, candidate.kind),
            isDisabled: loaded.override(of: candidate.label, candidate.kind) ?? false,
            isOwnerConfirmed: owner?.isConfirmed ?? false,
            unusualCommand: UnusualCommand(arguments: job?.arguments ?? program.map { [$0] } ?? [])
        ))
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
    /// True when `LimitLoadToSessionType`, a string or an array (`man launchd.plist`), names only Background.
    let loadsOnlyInTheBackground: Bool

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
        loadsOnlyInTheBackground = types == ["Background"]
    }
}
