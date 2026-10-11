public import Foundation
import PeelPrivileged

/// Finds the app a launchd job belongs to. Every clue is tried before a job is called orphaned, because
/// one key that does not match is not enough reason to remove a job that an app may still need.
public struct BackgroundItemOwnership: Sendable {
    public struct Owner: Sendable, Hashable {
        public let bundleIdentifier: String?
        public let name: String?
        /// Where the app is, or nil when it is gone.
        public let url: URL?
        /// True when macOS registered the job for the app, or its program is signed by the app's team or sits
        /// inside the app. False when only a name points to the app: a label, or a bundle anyone can make.
        public var isConfirmed = true

        public var isInstalled: Bool { url != nil }
    }

    private let apps: [InstalledApp]
    private let byIdentifier: [String: InstalledApp]
    private let byTeam: [String: [InstalledApp]]
    private let teamOfProgram: @Sendable (String) -> String?
    private var liveLabels: Set<String> = []

    public init(installedApps: [InstalledApp]) {
        self.init(installedApps: installedApps) { CodeSignature.teamIdentifier(at: URL(filePath: $0)) }
    }

    /// For tests: `teamOfProgram` stands in for reading each program's code signature.
    init(installedApps: [InstalledApp], teamOfProgram: @escaping @Sendable (String) -> String?) {
        self.teamOfProgram = teamOfProgram
        apps = installedApps
        byIdentifier = Dictionary(
            installedApps.compactMap { app in app.bundleIdentifier.map { ($0.lowercased(), app) } },
            uniquingKeysWith: { first, _ in first }
        )
        byTeam = Dictionary(grouping: installedApps.compactMap { app in app.teamIdentifier.map { ($0, app) } }, by: \.0)
            .mapValues { $0.map(\.1) }
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
        if let identifier = Self.bundleIdentifier(inProgramPath: program) {
            var owner = owner(forIdentifier: identifier)
            owner.isConfirmed = byIdentifier[identifier.lowercased()].map { proves(program, $0, team: team) } ?? false
            return owner
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
                url: candidates[0].url
            )
        }
        // No installed app claims the job. An app the plist names that is gone is still returned, so the user
        // can see which app it was. That app is not installed, so it keeps nothing from being called orphaned.
        let gone = associated.first {
            byIdentifier[$0.lowercased()] == nil && AppInspector.applicationURL(forBundleIdentifier: $0) == nil
        }
        return gone.map { Owner(bundleIdentifier: $0, name: nil, url: nil, isConfirmed: false) }
    }

    /// Whether a job is orphaned: no installed app claims it, and its program is gone from disk or it names
    /// none of its own. Labels that start with `com.apple.` or `application.` are never orphaned.
    public func isOrphan(label: String, program: String?, owner: Owner?) -> Bool {
        guard !label.hasPrefix("com.apple."), !label.hasPrefix("application.") else { return false }
        if let owner, owner.isInstalled { return false }
        guard let program, !program.isEmpty else { return true }
        return !Self.exists(program)
    }

    /// Runs the same check on a job read from its property list. Orphaned Files uses this one.
    func isOrphan(_ job: JobDefinition) -> Bool {
        // A program still on disk keeps its job whoever owns it, so the owner, which reads signatures, is not needed.
        if let program = job.program, !program.isEmpty, Self.exists(program) { return false }
        let owner = owner(label: job.label, associated: job.associated, program: job.program)
        return isOrphan(label: job.label, program: job.program, owner: owner)
    }

    /// This ownership, also knowing the jobs defined in `folders` that are not orphans: a helper keeps its settings
    /// beside its job, named for the job's label, while the app behind it may have another identifier.
    func knowingJobs(in folders: [URL]) -> BackgroundItemOwnership {
        var knowing = self
        let files = folders.flatMap {
            (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? []
        }
        knowing.liveLabels = Set(
            files.filter { $0.pathExtension == "plist" }.compactMap(JobDefinition.init(contentsOf:))
                .filter { !isOrphan($0) }.map { $0.label.lowercased() }
        )
        return knowing
    }

    func ownsItem(named identifier: String) -> Bool {
        let name = identifier.lowercased()
        return liveLabels.contains { name == $0 || name.hasPrefix($0 + ".") }
    }

    /// The folders launchd searches when the first item of `ProgramArguments` is a relative path.
    /// `man launchd.plist` says such a path "is resolved using _PATH_STDPATH", which `paths.h` defines as these four.
    private static let standardPath = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]

    private static func exists(_ program: String) -> Bool {
        guard !program.contains("/") else { return FileManager.default.fileExists(atPath: program) }
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

    static func bundleIdentifier(inProgramPath path: String?) -> String? {
        guard let path, let range = path.range(of: ".app/") else { return nil }
        let bundle = URL(filePath: String(path[..<range.lowerBound]) + ".app", directoryHint: .isDirectory)
        return AppInspector.infoDictionary(in: bundle.appending(path: "Contents", directoryHint: .isDirectory))?["CFBundleIdentifier"] as? String
    }
}
