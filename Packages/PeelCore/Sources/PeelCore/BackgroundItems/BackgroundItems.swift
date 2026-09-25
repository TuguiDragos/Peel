import Darwin
import Foundation
import PeelPrivileged

public enum BackgroundItems {
    private static let serviceManagement = "com.apple.xpc.ServiceManagement"
    private static let concurrentDetailQueries = 8

    @concurrent
    public static func scan(
        installedApps: [InstalledApp] = [],
        environment: SearchEnvironment = .current,
        exclusions: Exclusions = .none
    ) async -> [BackgroundItem] {
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

        items += await withTaskGroup(of: BackgroundItem?.self) { group in
            var pending = submitted.makeIterator()
            var results: [BackgroundItem] = []
            for _ in 0..<concurrentDetailQueries {
                guard let next = pending.next() else { break }
                group.addTask { await appSubmittedItem(next, ownership: ownership, loaded: loaded) }
            }
            while let result = await group.next() {
                if let result { results.append(result) }
                if !Task.isCancelled, let next = pending.next() {
                    group.addTask { await appSubmittedItem(next, ownership: ownership, loaded: loaded) }
                }
            }
            return results
        }

        return items
            .filter { $0.ownerBundleIdentifier.map(exclusions.excludes(bundleIdentifier:)) != true }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
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

    /// What `launchctl` reports right now: the loaded jobs, with the process ID of each one running, and the
    /// jobs marked disabled or enabled. Each is nil when `launchctl` answered in a form Peel cannot read.
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
                // Skips a job with the label of one of macOS's own daemons. Any other `com.apple.` label is kept
                // and shown, because a made-up Apple label is a common way to disguise a job.
                guard let job = JobDefinition(contentsOf: plist), !SystemDaemons.shipped.contains(job.label), !SystemAgents.shipped.contains(job.label) else { continue }
                let owner = ownership.owner(label: job.label, associated: job.associated, program: job.program)
                items.append(BackgroundItem(
                    label: job.label,
                    kind: kind,
                    source: source,
                    plistURL: plist,
                    program: job.program,
                    runsAtLoad: job.runsAtLoad,
                    keepsAlive: job.keepsAlive,
                    ownerBundleIdentifier: owner?.bundleIdentifier,
                    ownerName: owner?.name,
                    isOwnerInstalled: owner?.isInstalled ?? false,
                    isOrphan: ownership.isOrphan(label: job.label, program: job.program, owner: owner),
                    state: loaded.state(of: job.label, kind),
                    isDisabled: loaded.override(of: job.label, kind) ?? job.isDisabled
                ))
            }
        }
        return items
    }

    private static func appSubmittedItem(
        _ candidate: (label: String, kind: BackgroundItem.Kind, target: String),
        ownership: BackgroundItemOwnership,
        loaded: Loaded
    ) async -> BackgroundItem? {
        let details = Launchctl.parseDetails(await Launchctl.run(["print", candidate.target]).output)
        let isSubmittedByApp = details.path?.hasPrefix("(submitted by") == true
            && details.program.map { !PathComponents.isPath($0, inside: "/System") } == true
        guard details.managedBy == serviceManagement || isSubmittedByApp else { return nil }
        let path = details.path.flatMap { $0.hasPrefix("/") ? URL(filePath: $0) : nil }
        let job = path.flatMap(JobDefinition.init(contentsOf:))
        let program = details.program ?? job?.program
        guard let owner = ownership.owner(
            label: candidate.label,
            registeredBy: details.parentBundleIdentifier,
            associated: job?.associated ?? [],
            program: program
        ) else { return nil }

        return BackgroundItem(
            label: candidate.label,
            kind: candidate.kind,
            source: .app,
            plistURL: path,
            program: program,
            runsAtLoad: job?.runsAtLoad ?? false,
            keepsAlive: job?.keepsAlive ?? false,
            ownerBundleIdentifier: owner.bundleIdentifier,
            ownerName: owner.name,
            isOwnerInstalled: owner.isInstalled,
            isOrphan: ownership.isOrphan(label: candidate.label, program: program, owner: owner),
            state: loaded.state(of: candidate.label, candidate.kind),
            isDisabled: loaded.override(of: candidate.label, candidate.kind) ?? false
        )
    }

    private static func plists(in folder: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { $0.pathExtension == "plist" }
    }

}

struct JobDefinition {
    let label: String
    let program: String?
    let runsAtLoad: Bool
    let keepsAlive: Bool
    let isDisabled: Bool
    /// The plist's `AssociatedBundleIdentifiers`. Whoever wrote the plist chose them, so they are a claim, not proof.
    let associated: [String]

    init?(contentsOf url: URL) {
        guard
            let plist = BoundedRead.propertyList(at: url)
        else { return nil }
        self.init(plist)
    }

    init?(_ plist: [String: Any]) {
        guard let label = plist["Label"] as? String, !label.isEmpty else { return nil }
        self.label = label
        // Reads only the first argument: a cast to `[String]` fails when any argument is not a string.
        program = plist["Program"] as? String ?? (plist["ProgramArguments"] as? [Any])?.first as? String
        keepsAlive = (plist["KeepAlive"] as? Bool) ?? (plist["KeepAlive"] is [String: Any])
        // `man launchd.plist`, KeepAlive: "The use of this key implicitly implies RunAtLoad".
        runsAtLoad = (plist["RunAtLoad"] as? Bool ?? false) || keepsAlive
        isDisabled = plist["Disabled"] as? Bool ?? false
        let named = plist["AssociatedBundleIdentifiers"]
        associated = (named as? String).map { [$0] } ?? (named as? [Any])?.compactMap { $0 as? String } ?? []
    }
}
