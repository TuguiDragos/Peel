public import Foundation
import PeelPrivileged
import Synchronization

/// Finds the app a launchd job belongs to. Every clue is tried before a job is called orphaned, because
/// one key that does not match is not enough reason to remove a job that an app may still need.
public struct BackgroundItemOwnership: Sendable {
    public struct Owner: Sendable, Hashable {
        public let bundleIdentifier: String?
        public let name: String?
        /// Where the app is, or nil when it is gone.
        public let url: URL?
        /// True when macOS registered the job for the app, or its program is signed by the app's team or sits
        /// inside the app (outside the scanned folders, an app signed by the program's team). False when only a name
        /// points to the app: a label, or a bundle anyone can make.
        public var isConfirmed = true
        /// True when only the team that signed the program points to the app, the only one of that team installed.
        public var isOnlyItsMaker = false

        public var isInstalled: Bool { url != nil }
    }

    /// The team each program is signed by, read once while its file stays the same: a page scans every job's program
    /// each time Peel comes forward, and checking a signature takes milliseconds.
    final class ProgramTeams: Sendable {
        static let shared = ProgramTeams { CodeSignature.teamIdentifier(at: URL(filePath: $0)) }

        private let known = Mutex<[String: (file: FileIdentity, team: String?)]>([:])
        private let read: @Sendable (String) -> String?

        init(read: @escaping @Sendable (String) -> String?) {
            self.read = read
        }

        func team(of program: String) -> String? {
            guard let file = FileIdentity.of(URL(filePath: program)) else { return read(program) }
            let last = known.withLock { $0[program] }
            if let last, last.file == file { return last.team }
            let team = read(program)
            known.withLock { $0[program] = (file, team) }
            return team
        }
    }

    private let byIdentifier: [String: InstalledApp]
    private let byTeam: [String: [InstalledApp]]
    private let teamOfProgram: @Sendable (String) -> String?
    private var liveLabels: Set<String> = []
    /// The path of each program, with what is offered with it when its job came with an app that left.
    private var livePrograms: [(program: String, offeredAs: String?)] = []
    private let declared: DeclaredJobs
    private let remembered: [RememberedApp]

    public init(installedApps: [InstalledApp], remembered: [RememberedApp] = []) {
        self.init(installedApps: installedApps, remembered: remembered, teamOfProgram: ProgramTeams.shared.team(of:))
    }

    /// For tests: `teamOfProgram` stands in for reading each program's code signature.
    init(
        installedApps: [InstalledApp], remembered: [RememberedApp] = [],
        teamOfProgram: @escaping @Sendable (String) -> String?
    ) {
        self.teamOfProgram = teamOfProgram
        self.remembered = remembered
        byIdentifier = Dictionary(
            installedApps.compactMap { app in app.bundleIdentifier.map { ($0.lowercased(), app) } },
            uniquingKeysWith: { first, _ in first }
        )
        byTeam = Dictionary(grouping: installedApps.compactMap { app in app.teamIdentifier.map { ($0, app) } }, by: \.0)
            .mapValues { $0.map(\.1) }
        declared = DeclaredJobs(installedApps)
    }

    /// Returns the app that owns a job, trying each clue in turn, or nil when no clue names an app.
    ///
    /// `registeredBy` comes from macOS and is trusted. `associated` is the plist's `AssociatedBundleIdentifiers`,
    /// which anyone writing the plist can fill in: like macOS, this trusts an entry only when the program is
    /// signed by the same team as the app it names. Otherwise the next clue is tried.
    public func owner(
        label: String,
        registeredBy: String? = nil,
        associated: [String],
        program: String?
    ) -> Owner? {
        if let registeredBy, !registeredBy.isEmpty {
            return owner(forIdentifier: registeredBy)
        }
        let team = program.flatMap(teamOfProgram)
        if let team,
           let app = associated.lazy.compactMap({ byIdentifier[$0.lowercased()] })
               .first(where: { $0.teamIdentifier == team }) {
            return Owner(bundleIdentifier: app.bundleIdentifier, name: app.name, url: app.url)
        }
        if let bundle = Self.bundle(holding: program) {
            if let app = byIdentifier[bundle.identifier.lowercased()] {
                return Owner(
                    bundleIdentifier: app.bundleIdentifier,
                    name: app.name,
                    url: app.url,
                    isConfirmed: proves(program, app, team: team)
                )
            }
            let url = URL(filePath: bundle.path, directoryHint: .isDirectory)
            return Owner(
                bundleIdentifier: bundle.identifier,
                name: AppInspector.displayName(of: url, identifier: bundle.identifier),
                url: AppInspector.isInATrash(url) ? nil : url,
                isConfirmed: team != nil && teamOfProgram(bundle.path) == team
            )
        }
        if let app = appMatching(label: label) {
            return Owner(
                bundleIdentifier: app.bundleIdentifier,
                name: app.name,
                url: app.url,
                isConfirmed: proves(program, app, team: team)
            )
        }
        if let team, let candidates = byTeam[team], candidates.count == 1 {
            return Owner(
                bundleIdentifier: candidates[0].bundleIdentifier,
                name: candidates[0].name,
                url: candidates[0].url,
                isOnlyItsMaker: true
            )
        }
        // No installed app claims the job. An app the plist names that is gone is still returned, so the user
        // can see which app it was. That app is not installed, so it keeps nothing from being called orphaned.
        let gone = associated.first {
            byIdentifier[$0.lowercased()] == nil && AppInspector.applicationURL(forBundleIdentifier: $0) == nil
        }
        return gone.map { Owner(bundleIdentifier: $0, name: nil, url: nil, isConfirmed: false) }
    }

    /// The installed app whose own bundle declares the job `label`: a label launchd still keeps after a restart, when
    /// the job is no longer loaded and nothing else points to its app.
    func owner(declaring label: String, kind: BackgroundItem.Kind) -> Owner? {
        declared.app(declaring: label, kind: kind)
            .map { Owner(bundleIdentifier: $0.bundleIdentifier, name: $0.name, url: $0.url) }
    }

    /// Whether a job is orphaned: no installed app claims it, and its program is gone from disk or it names
    /// none of its own. Labels that start with `com.apple.` or `application.` are never orphaned.
    public func isOrphan(label: String, program: String?, owner: Owner?) -> Bool {
        guard !label.hasPrefix("com.apple."), !label.hasPrefix("application.") else { return false }
        if let owner, owner.isInstalled { return false }
        guard let program, !program.isEmpty else { return true }
        // A NUL ends the path where the kernel reads it, so what launchd would run is not known.
        guard !program.utf8.contains(0) else { return false }
        return !Self.exists(program)
    }

    /// The app Peel saw go whose team signed the program of `job`: a program on disk outside every installed app and
    /// every Trash, while no installed app has that team or claims the job by its label. Of several such apps, the one
    /// the job names, by its label or its plist, or else the one that left last. A program its maker ships with no
    /// app, such as Nix's, has none.
    func appThatLeft(running job: JobDefinition) -> RememberedApp? {
        guard !remembered.isEmpty, !job.label.hasPrefix("com.apple."), !job.label.hasPrefix("application."),
              let program = job.program, program.hasPrefix("/"), !program.utf8.contains(0),
              appMatching(label: job.label) == nil
        else { return nil }
        if let bundle = PathComponents.outermostApp(of: program) {
            guard !AppInspector.isInATrash(URL(filePath: bundle, directoryHint: .isDirectory)),
                  Self.bundle(holding: program).map({ byIdentifier[$0.identifier.lowercased()] == nil }) ?? true
            else { return nil }
        }
        var info = stat()
        guard stat(program, &info) == 0, let team = teamOfProgram(program), byTeam[team] == nil else { return nil }
        let gone = remembered.filter {
            $0.teamIdentifier == team && byIdentifier[$0.bundleIdentifier.lowercased()] == nil
        }
        let mounted = MountedDisks.now()
        guard !gone.isEmpty, gone.allSatisfy({ $0.stillInstalled(on: mounted) == nil }) else { return nil }
        if let named = AppMemory.app(for: job.label, in: gone) { return named }
        let associated = Set(job.associated.map { $0.lowercased() })
        if let named = gone.first(where: { associated.contains($0.bundleIdentifier.lowercased()) }) { return named }
        return gone.max { one, other in
            let (left, otherLeft) = (one.goneSince ?? one.lastSeen, other.goneSince ?? other.lastSeen)
            return left == otherLeft ? one.bundleIdentifier > other.bundleIdentifier : left < otherLeft
        }
    }

    /// Runs the same check on a job read from its property list. Orphaned Files uses this one.
    func isOrphan(_ job: JobDefinition) -> Bool {
        // A program still on disk keeps its job whoever owns it, so the owner, which reads signatures, is not needed.
        if let program = job.program, !program.isEmpty, Self.exists(program) { return false }
        let owner = owner(label: job.label, associated: job.associated, program: job.program)
        return isOrphan(label: job.label, program: job.program, owner: owner)
    }

    struct JobOfAnAppThatLeft: Sendable {
        let plist: URL
        let folder: SearchLocation
        /// The program, or the app bundle it is in.
        let runs: URL
        let app: RememberedApp
    }

    /// The jobs `knowingJobs(in:)` read that came with an app that left.
    private(set) var ofAppsThatLeft: [JobOfAnAppThatLeft] = []

    /// This ownership, also knowing the jobs defined in `folders` that are not orphans: a helper keeps its settings
    /// beside its job, named for the job's label, while the app behind it may have another identifier.
    func knowingJobs(in folders: [SearchLocation]) -> BackgroundItemOwnership {
        var knowing = self
        for folder in folders {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder.url, includingPropertiesForKeys: nil))
            for plist in files ?? [] where plist.pathExtension == "plist" {
                guard let job = JobDefinition(contentsOf: plist), !isOrphan(job) else { continue }
                knowing.liveLabels.insert(job.label.lowercased())
                guard let program = job.program, program.hasPrefix("/"), Self.exists(program) else { continue }
                let path = PathPattern.comparablePath(of: URL(filePath: program))
                guard let app = appThatLeft(running: job) else {
                    knowing.livePrograms.append((path, offeredAs: nil))
                    continue
                }
                let runs = PathComponents.outermostApp(of: program).map {
                    URL(filePath: $0, directoryHint: .isDirectory)
                } ?? URL(filePath: program)
                knowing.livePrograms.append((path, offeredAs: PathPattern.comparablePath(of: runs)))
                knowing.ofAppsThatLeft.append(JobOfAnAppThatLeft(plist: plist, folder: folder, runs: runs, app: app))
            }
        }
        return knowing
    }

    func ownsItem(named identifier: String) -> Bool {
        let name = identifier.lowercased()
        return liveLabels.contains { name == $0 || name.hasPrefix($0 + ".") }
    }

    /// Whether `url` is, or holds, the program of a job `knowingJobs(in:)` found that still has one. What a job of an
    /// app that left runs is offered with that job, so it counts only for a folder around it.
    func needs(_ url: URL) -> Bool {
        let path = PathPattern.comparablePath(of: url)
        return livePrograms.contains { program, offeredAs in
            offeredAs != path && PathComponents.isPath(program, atOrInside: path)
        }
    }

    /// The folders launchd searches when the first item of `ProgramArguments` is a relative path.
    /// `man launchd.plist` says such a path "is resolved using _PATH_STDPATH", which `paths.h` defines as these four.
    private static let standardPath = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]

    private static func exists(_ program: String) -> Bool {
        guard !program.contains("/") else {
            // Gone only when nothing is there, on a disk that is connected: launchd runs a daemon as root, which
            // reaches a folder this account can't search, and a program on a disk that is away comes back with it.
            var info = stat()
            return stat(program, &info) == 0 || ![ENOENT, ENOTDIR, ELOOP].contains(errno)
                || URL(filePath: program).isOnADiskNotConnected
        }
        return standardPath.contains { FileManager.default.isExecutableFile(atPath: $0 + "/" + program) }
    }

    /// Returns the owner with this bundle identifier. An app can live outside the folders Peel scans, so macOS
    /// is asked where it is before the owner is called not installed.
    private func owner(forIdentifier identifier: String) -> Owner {
        if let app = byIdentifier[identifier.lowercased()] {
            return Owner(bundleIdentifier: app.bundleIdentifier, name: app.name, url: app.url)
        }
        let elsewhere = AppInspector.applicationURL(forBundleIdentifier: identifier)
        return Owner(
            bundleIdentifier: identifier,
            name: elsewhere?.deletingPathExtension().lastPathComponent,
            url: elsewhere
        )
    }

    /// Whether `program` is `app`'s own: signed by its team, or inside its bundle.
    private func proves(_ program: String?, _ app: InstalledApp, team: String?) -> Bool {
        if let team, team == app.teamIdentifier { return true }
        guard let program else { return false }
        return PathComponents.isPath(
            PathPattern.comparablePath(of: URL(filePath: program)),
            inside: PathPattern.comparablePath(of: app.url)
        )
    }

    /// Returns the installed app whose bundle identifier is the label, or else the longest one the label
    /// starts with. Labels usually begin with the app's bundle identifier, as in `com.example.app.updater`.
    private func appMatching(label: String) -> InstalledApp? {
        let lowercased = label.lowercased()
        if let exact = byIdentifier[lowercased] { return exact }
        return byIdentifier
            .filter { lowercased.hasPrefix($0.key + ".") }
            .max { $0.key.count < $1.key.count }?.value
    }

    /// The outermost app bundle `program` sits in, with the identifier its Info.plist declares.
    static func bundle(holding program: String?) -> (path: String, identifier: String)? {
        guard let program, let path = PathComponents.outermostApp(of: program) else { return nil }
        let contents = URL(filePath: path, directoryHint: .isDirectory)
            .appending(path: "Contents", directoryHint: .isDirectory)
        guard let identifier = AppInspector.infoDictionary(in: contents)?["CFBundleIdentifier"] as? String else {
            return nil
        }
        return (path, identifier)
    }
}

/// The jobs the installed apps' bundles declare, read once when first asked about: a scan asks about many labels.
private final class DeclaredJobs: Sendable {
    private let apps: [InstalledApp]
    private let byJob = Mutex<[String: InstalledApp]?>(nil)

    init(_ apps: [InstalledApp]) {
        self.apps = apps
    }

    func app(declaring label: String, kind: BackgroundItem.Kind) -> InstalledApp? {
        byJob.withLock { byJob in
            if byJob == nil {
                var read: [String: InstalledApp] = [:]
                for app in apps {
                    for job in StartsAtLogin.declarations(in: app.url) where read["\(job.kind)/\(job.label)"] == nil {
                        read["\(job.kind)/\(job.label)"] = app
                    }
                }
                byJob = read
            }
            return byJob?["\(kind)/\(label)"]
        }
    }
}
