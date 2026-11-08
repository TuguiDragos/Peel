import Foundation
internal import PeelPrivileged

/// An app whose own uninstaller runs once the app leaves its place, deleting what History can't put back.
public struct UninstallsItself: Sendable, Hashable {
    public enum Uninstaller: Sendable, Hashable {
        /// Logs the Mac out of the account and deletes the settings; the script can be run instead.
        case logsOut(script: String)
        /// Asks for an administrator, then deletes the app, even from the Trash, and its system files.
        case deletesTheApp
        /// Asks to remove the components it keeps in the system, then deletes them.
        case removesItsComponents
        /// Runs as an administrator and deletes the maker's other app, while it is still in place, and the data the
        /// two keep for every account.
        case deletesItsSuite
        /// Runs as an administrator without asking, deletes its system files and can delete the app from the Trash,
        /// then asks for an administrator to delete the accounts it made.
        case uninstallsWithoutAsking
        /// A launchd job watches the app's place and, once the app leaves it, runs a program kept outside the app.
        case watchedByAJob
    }

    public let app: InstalledApp
    public let uninstaller: Uninstaller
    private let removed: Set<String>
    /// What the job of `watchedByAJob` needs where it is: its file, its program, and the files its arguments name.
    private var needed: Set<String> = []

    /// True when the app's own uninstaller stops the programs the app runs from inside itself, so they keep running
    /// while it moves. A job known only by what it watches promises nothing of the kind.
    public var letsItsProgramsRun: Bool {
        if case .watchedByAJob = uninstaller { false } else { true }
    }

    /// Mullvad VPN's daemon watches `/Applications/Mullvad VPN.app`, and when its own program goes it logs the Mac out
    /// of the account and runs `uninstall_macos.sh`, which deletes the settings (`mullvad-daemon/src/macos.rs`).
    private static let mullvad = (identifier: "net.mullvad.vpn", path: "Applications/Mullvad VPN.app")

    private static let mullvadRemoves = (
        root: [
            "Library/LaunchDaemons/net.mullvad.daemon.plist",
            "usr/local/share/zsh/site-functions/_mullvad",
            "opt/homebrew/share/fish/vendor_completions.d/mullvad.fish",
            "usr/local/share/fish/vendor_completions.d/mullvad.fish",
            "usr/local/share/nushell/vendor/autoload/mullvad.nu",
            "usr/local/bin/mullvad",
            "usr/local/bin/mullvad-problem-report",
            "private/var/db/receipts/net.mullvad.vpn.bom",
            "private/var/db/receipts/net.mullvad.vpn.plist",
            "private/var/log/mullvad-vpn",
            "private/var/root/Library/Caches/mullvad-vpn",
            "Library/Caches/mullvad-vpn",
            "private/etc/mullvad-vpn",
        ],
        home: ["Library/Logs/Mullvad VPN", "Library/Application Support/Mullvad VPN"]
    )

    /// Citrix's agent `com.citrix.UninstallMonitor` watches the app's place and, once the app is gone, opens the
    /// uninstaller that deletes the app and its system files (Citrix's "Uninstall Citrix Workspace app for Mac").
    private static let citrix = (
        identifier: "com.citrix.receiver.nomas",
        monitor: "Library/LaunchAgents/com.citrix.UninstallMonitor.plist"
    )

    private static let citrixRemoves = (
        root: [
            "Library/LaunchAgents/com.citrix.AuthManager_Mac.plist",
            "Library/LaunchAgents/com.citrix.ReceiverHelper.plist",
            "Library/LaunchAgents/com.citrix.ServiceRecords.plist",
            "Library/LaunchAgents/com.citrix.safariadapter.plist",
            "Library/LaunchAgents/com.citrix.UninstallMonitor.plist",
            "Library/LaunchAgents/com.citrix.devicetrust.launchagent.plist",
            "Library/LaunchDaemons/com.citrix.CtxWorkspaceHelperDaemon.plist",
            "Library/LaunchDaemons/com.citrix.ReceiverUninstallHelper.plist",
            "Library/LaunchDaemons/com.citrix.ctxusbd.plist",
            "Library/LaunchDaemons/com.citrix.ctxworkspaceupdater.plist",
            "Library/Citrix Workspace",
            "Library/Application Support/Citrix Receiver",
            "Library/Application Support/deviceTRUST",
            "Library/Logs/Citrix Workspace",
            "private/var/db/receipts/com.citrix.ICAClient.bom",
            "private/var/db/receipts/com.citrix.ICAClient.plist",
        ],
        home: [
            "Library/Logs/Citrix Workspace",
            "Library/Application Support/Citrix Workspace",
            "Library/HTTPStorages/com.citrix.receiver.nomas",
            "Library/Preferences/com.citrix.receiver.nomas.plist",
        ]
    )

    /// TeamViewer's daemon `com.teamviewer.UninstallerWatcher` opens TeamViewer 15's uninstaller once TeamViewer or
    /// TeamViewer Host is in the Trash, which asks to remove what TeamViewer's package put in the system.
    private static let teamViewer = (
        identifiers: ["com.teamviewer.TeamViewer", "com.teamviewer.TeamViewerHost"],
        watcher: "Library/LaunchDaemons/com.teamviewer.UninstallerWatcher.plist"
    )

    private static let teamViewerRemoves = (
        root: [
            "Library/LaunchDaemons/com.teamviewer.Helper.plist",
            "Library/LaunchDaemons/com.teamviewer.ScriptExecutionHelper.plist",
            "Library/LaunchDaemons/com.teamviewer.UninstallerHelper.plist",
            "Library/LaunchDaemons/com.teamviewer.UninstallerWatcher.plist",
            "Library/LaunchDaemons/com.teamviewer.teamviewer_service.plist",
            "Library/LaunchAgents/com.teamviewer.teamviewer.plist",
            "Library/LaunchAgents/com.teamviewer.teamviewer_desktop.plist",
            "Library/PrivilegedHelperTools/com.teamviewer.Helper",
            "Library/PrivilegedHelperTools/com.teamviewer.UninstallerHelper",
            "Library/Application Support/TeamViewer",
            "Library/Security/SecurityAgentPlugins/TeamViewerAuthPlugin.bundle",
            "Library/Audio/Plug-Ins/HAL/TVRemoteAudio.driver",
            "Library/Caches/com.teamviewer.TeamViewer.RemotePrinting",
            "Library/Printers/Icons/TeamViewer.icns",
            "usr/libexec/cups/filter/pdftoteamviewer",
        ],
        home: [String]()
    )

    /// BlueStacks' daemon `com.now.gg.BlueStacks.cleanup` runs its cleanup as root once either of its apps leaves
    /// `/Applications`, which deletes the other one and what is below (the package's `uninstaller.sh`).
    private static let blueStacks = (
        identifiers: ["com.now.gg.BlueStacks", "com.now.gg.BlueStacksAirMIM"],
        cleanup: "Library/LaunchDaemons/com.now.gg.BlueStacks.cleanup.plist"
    )

    private static let blueStacksRemoves = (
        root: [
            "Library/LaunchDaemons/com.now.gg.BlueStacks.cleanup.plist",
            "Library/Application Support/BlueStacks/BlueStacksCleanup",
            "Users/Shared/Library/Application Support/BlueStacks",
            "private/var/db/receipts/com.now.gg.BlueStacks.bom",
            "private/var/db/receipts/com.now.gg.BlueStacks.plist",
        ],
        home: [String]()
    )

    /// Once the app is gone, NoMachine's daemon `com.nomachine.uninstall` runs `nxuninstall.sh` as root, which,
    /// with the NoMachine Uninstall it opens, deletes what is below (NoMachine's "How to uninstall NoMachine on Mac").
    private static let noMachine = (
        identifier: "com.nomachine.nxdock",
        uninstall: "Library/LaunchDaemons/com.nomachine.uninstall.plist"
    )

    private static let noMachineRemoves = (
        root: [
            "Library/LaunchDaemons/com.nomachine.uninstall.plist",
            "Library/LaunchDaemons/com.nomachine.server.plist",
            "Library/LaunchDaemons/com.nomachine.nxd.plist",
            "Library/LaunchDaemons/com.nomachine.nxhtd.plist",
            "Library/LaunchAgents/com.nomachine.localnxserver.plist",
            "Library/LaunchAgents/com.nomachine.uninstallAgent.plist",
            "Library/Application Support/NoMachine",
            "Library/Audio/Plug-Ins/HAL/NMAudio.driver",
            "Library/Audio/Plug-Ins/HAL/NMAudioMic.driver",
            "private/etc/NX",
            "private/var/db/receipts/com.nomachine.nxnode.bom",
            "private/var/db/receipts/com.nomachine.nxnode.plist",
            "private/var/db/receipts/com.nomachine.nxplayer.bom",
            "private/var/db/receipts/com.nomachine.nxplayer.plist",
            "private/var/db/receipts/com.nomachine.nxrunner.bom",
            "private/var/db/receipts/com.nomachine.nxrunner.plist",
            "private/var/db/receipts/com.nomachine.nxserver.bom",
            "private/var/db/receipts/com.nomachine.nxserver.plist",
            "usr/libexec/cups/backend/nx",
            "usr/libexec/cups/backend/nxprint",
        ],
        home: [String]()
    )

    public static func of(_ app: InstalledApp, environment: SearchEnvironment = .current) async -> UninstallsItself? {
        if let known = mullvad(app, environment: environment) ?? citrix(app, environment: environment)
            ?? teamViewer(app, environment: environment) ?? blueStacks(app, environment: environment)
            ?? noMachine(app, environment: environment) {
            return known
        }
        return await watched(app, environment: environment)
    }

    private static func mullvad(_ app: InstalledApp, environment: SearchEnvironment) -> UninstallsItself? {
        let place = environment.rootDirectory.appending(path: mullvad.path)
        guard
            app.bundleIdentifier == mullvad.identifier,
            PathPattern.comparablePath(of: app.url) == PathPattern.comparablePath(of: place)
        else { return nil }
        let script = place.appending(path: "Contents/Resources/uninstall.sh").path(percentEncoded: false)
        return UninstallsItself(
            app: app,
            uninstaller: .logsOut(script: script),
            removed: paths(mullvadRemoves, in: environment)
        )
    }

    private static func citrix(_ app: InstalledApp, environment: SearchEnvironment) -> UninstallsItself? {
        guard
            app.bundleIdentifier == citrix.identifier,
            program(ofTheJobIn: citrix.monitor, watching: app, in: environment) != nil
        else { return nil }
        return UninstallsItself(app: app, uninstaller: .deletesTheApp, removed: paths(citrixRemoves, in: environment))
    }

    private static func teamViewer(_ app: InstalledApp, environment: SearchEnvironment) -> UninstallsItself? {
        let place = PathPattern.comparablePath(of: app.url)
        guard
            let identifier = app.bundleIdentifier, teamViewer.identifiers.contains(identifier),
            let watcher = JobDefinition(contentsOf: environment.rootDirectory.appending(path: teamViewer.watcher)),
            !watcher.isDisabled,
            watcher.watchPaths.contains(where: {
                PathComponents.isPath(PathPattern.comparablePath(of: URL(filePath: $0)), atOrInside: place)
            }),
            let program = watcher.program,
            FileManager.default.isExecutableFile(atPath: program)
        else { return nil }
        return UninstallsItself(
            app: app,
            uninstaller: .removesItsComponents,
            removed: paths(teamViewerRemoves, in: environment)
        )
    }

    private static func blueStacks(_ app: InstalledApp, environment: SearchEnvironment) -> UninstallsItself? {
        guard
            let identifier = app.bundleIdentifier, blueStacks.identifiers.contains(identifier),
            let program = program(ofTheJobIn: blueStacks.cleanup, watching: app, in: environment)
        else { return nil }
        return UninstallsItself(
            app: app,
            uninstaller: .deletesItsSuite,
            removed: paths(blueStacksRemoves, in: environment),
            needed: [program]
        )
    }

    private static func noMachine(_ app: InstalledApp, environment: SearchEnvironment) -> UninstallsItself? {
        guard
            app.bundleIdentifier == noMachine.identifier,
            let program = program(ofTheJobIn: noMachine.uninstall, watching: app, in: environment)
        else { return nil }
        return UninstallsItself(
            app: app,
            uninstaller: .uninstallsWithoutAsking,
            removed: paths(noMachineRemoves, in: environment),
            needed: [program]
        )
    }

    /// The program of the job in `file`, as Peel compares paths, when the job isn't disabled, its `WatchPaths` names
    /// the app's place itself, and the program can run.
    private static func program(
        ofTheJobIn file: String,
        watching app: InstalledApp,
        in environment: SearchEnvironment
    ) -> String? {
        let place = PathPattern.comparablePath(of: app.url)
        guard
            let job = JobDefinition(contentsOf: environment.rootDirectory.appending(path: file)), !job.isDisabled,
            job.watchPaths.contains(where: { PathPattern.comparablePath(of: URL(filePath: $0)) == place }),
            let program = job.program, FileManager.default.isExecutableFile(atPath: program)
        else { return nil }
        return PathPattern.comparablePath(of: URL(filePath: program))
    }

    /// Watched when a job launchd has loaded from a folder it reads by itself names the app's place, or something
    /// inside it, in `WatchPaths`, and runs a program outside the app, which can still run once the app has moved.
    private static func watched(_ app: InstalledApp, environment: SearchEnvironment) async -> UninstallsItself? {
        let place = PathPattern.comparablePath(of: app.url)
        var needed: Set<String> = []
        for (job, paths) in jobs(watching: place, in: environment) where await isLoaded(job) {
            needed.insert(PathPattern.comparablePath(of: job.plist))
            needed.formUnion(paths)
        }
        guard !needed.isEmpty else { return nil }
        return UninstallsItself(app: app, uninstaller: .watchedByAJob, removed: [], needed: needed)
    }

    /// Each job whose `WatchPaths` names `place` or something inside it, with the paths it needs to run: its program
    /// and each file its arguments name outside the app.
    private static func jobs(
        watching place: String,
        in environment: SearchEnvironment
    ) -> [(job: LaunchdCleanup.Job, paths: Set<String>)] {
        let folders = environment.locations.filter { $0.kind == .launchAgents || $0.kind == .launchDaemons }
        return folders.flatMap { folder in
            plists(in: folder.url).compactMap { plist -> (job: LaunchdCleanup.Job, paths: Set<String>)? in
                guard
                    let definition = JobDefinition(contentsOf: plist), !definition.isDisabled,
                    LaunchdCleanup.isAppsOwn(definition.label),
                    definition.watchPaths.contains(where: {
                        PathComponents.isPath(PathPattern.comparablePath(of: URL(filePath: $0)), atOrInside: place)
                    }),
                    let program = definition.program.flatMap(runnable),
                    !PathComponents.isPath(program, atOrInside: place)
                else { return nil }
                let named = definition.arguments.dropFirst().filter { $0.hasPrefix("/") }
                    .map { PathPattern.comparablePath(of: URL(filePath: $0)) }
                    .filter { !PathComponents.isPath($0, atOrInside: place) }
                let job = LaunchdCleanup.Job(
                    label: definition.label, isDaemon: folder.kind == .launchDaemons, plist: plist,
                    loadsInTheBackgroundSession: definition.loadsInTheBackground
                )
                return (job, Set([program] + named))
            }
        }
    }

    private static func plists(in folder: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { $0.pathExtension == "plist" }
    }

    /// The program launchd runs for `program` when it can be run: an absolute path, or a name looked up in the
    /// standard path (`man launchd.plist`, ProgramArguments).
    private static func runnable(_ program: String) -> String? {
        let candidates = program.hasPrefix("/")
            ? [program] : _PATH_STDPATH.split(separator: ":").map { "\($0)/\(program)" }
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:))
            .map { PathPattern.comparablePath(of: URL(filePath: $0)) }
    }

    /// Whether launchd has `job` loaded from its file now, so it starts once the app leaves. An answer Peel can't read
    /// counts as yes: leaving the job's files in place costs nothing, and moving them could stop it halfway.
    private static func isLoaded(_ job: LaunchdCleanup.Job) async -> Bool {
        if let launchdStandIn { return launchdStandIn(job) }
        let reply = await Launchctl.run(["print", "\(job.domain)/\(job.label)"])
        return switch Launchctl.answer(status: reply.status, output: reply.output) {
        case .details(let details): LaunchdCleanup.isLoaded(from: details.path, job)
        case .gone: false
        case .unreadable: true
        }
    }

    /// For a test: no test loads a job into launchd.
    @TaskLocal static var launchdStandIn: (@Sendable (LaunchdCleanup.Job) -> Bool)?

    private static func paths(
        _ removes: (root: [String], home: [String]),
        in environment: SearchEnvironment
    ) -> Set<String> {
        let urls = removes.root.map { environment.rootDirectory.appending(path: $0) }
            + removes.home.map { environment.homeDirectory.appending(path: $0) }
        return Set(urls.map(PathPattern.comparablePath))
    }

    func holdBack(for url: URL) -> HoldBack? {
        let path = PathPattern.comparablePath(of: url)
        if removed.contains(where: { PathComponents.isPath(path, atOrInside: $0) }) { return .leftToItsUninstaller }
        return needed.contains { PathComponents.isPath($0, atOrInside: path) } ? .neededWhenTheAppLeaves : nil
    }
}
