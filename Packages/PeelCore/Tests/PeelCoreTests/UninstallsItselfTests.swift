import Foundation
@testable import PeelCommandLine
@testable import PeelCore
import Testing

struct UninstallsItselfTests {
    @Test(.launchdHasEveryJob) func mullvadUninstallsItselfOnceItLeavesTheApplicationsFolder() async throws {
        let installed = try Installed()

        let uninstallsItself = await UninstallsItself.of(installed.app, environment: installed.environment)

        let script = installed.app.url.appending(path: "Contents/Resources/uninstall.sh").path(percentEncoded: false)
        #expect(uninstallsItself?.app == installed.app)
        #expect(uninstallsItself?.uninstaller == .logsOut(script: script))
        #expect(uninstallsItself?.letsItsProgramsRun == true)
    }

    /// The apps Peel lists come from a folder walk, whose URLs name a folder with a slash at the end.
    @Test(.launchdHasEveryJob) func knowsMullvadAsTheListOfAppsNamesIt() async throws {
        let installed = try Installed()
        let walked = URL(filePath: installed.app.url.path(percentEncoded: false), directoryHint: .isDirectory)
        #expect(walked.path(percentEncoded: false).hasSuffix("/"))
        let listed = InstalledApp(url: walked, bundleIdentifier: "net.mullvad.vpn", name: "Mullvad VPN")

        #expect(await UninstallsItself.of(listed, environment: installed.environment)?.app == listed)
    }

    @Test(.launchdHasEveryJob) func nothingHappensWhileTheAppSitsElsewhere() async throws {
        let installed = try Installed()
        let elsewhere = InstalledApp(
            url: installed.directory.url.appending(path: "home/Applications/Mullvad VPN.app"),
            bundleIdentifier: "net.mullvad.vpn", name: "Mullvad VPN"
        )
        let another = InstalledApp(url: installed.app.url, bundleIdentifier: "org.example.vpn", name: "Mullvad VPN")

        #expect(await UninstallsItself.of(elsewhere, environment: installed.environment) == nil)
        #expect(await UninstallsItself.of(another, environment: installed.environment) == nil)
    }

    private struct Installed: ~Copyable {
        let directory: TemporaryDirectory
        let app: InstalledApp
        let environment: SearchEnvironment
        let daemon: Process
        let job: URL

        init() throws {
            let directory = try TemporaryDirectory()
            let bundle = try directory.directory("root/Applications/Mullvad VPN.app")
            let daemon = try directory.runningProgram("root/Applications/Mullvad VPN.app/Contents/Resources/mullvad-daemon")
            let program = bundle.appending(path: "Contents/Resources/mullvad-daemon").path(percentEncoded: false)
            self.job = try directory.file(
                "root/Library/LaunchDaemons/net.mullvad.daemon.plist",
                contents: PropertyListSerialization.data(
                    fromPropertyList: ["Label": "net.mullvad.daemon", "Program": program], format: .xml, options: 0
                )
            )
            self.app = InstalledApp(url: bundle, bundleIdentifier: "net.mullvad.vpn", name: "Mullvad VPN")
            self.environment = SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            )
            self.daemon = daemon
            self.directory = directory
        }

        deinit {
            daemon.terminate()
        }

        func service() throws -> TrashService {
            let trash = try directory.directory("home/.Trash")
            return TrashService(environment: environment) { url in
                let destination = trash.appending(path: url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            }
        }
    }

    @Test(.launchdHasEveryJob) func leavesToTheUninstallerWhatItRemovesAndOffersTheRest() async throws {
        let installed = try Installed()
        let removedByIt = [
            installed.job,
            try installed.directory.directory("home/Library/Application Support/Mullvad VPN"),
            try installed.directory.directory("home/Library/Logs/Mullvad VPN"),
            try installed.directory.file("root/private/var/db/receipts/net.mullvad.vpn.bom"),
            try installed.directory.file("root/private/var/db/receipts/net.mullvad.vpn.plist"),
        ]
        let preferences = try installed.directory.file("home/Library/Preferences/net.mullvad.vpn.plist")

        let plan = await Uninstallation.prepare(
            installed.app,
            installedApps: [installed.app],
            receipts: ["net.mullvad.vpn"],
            environment: installed.environment
        )

        let heldBack = Dictionary(
            plan.scan.leftovers.map { (PathPattern.comparablePath(of: $0.url), $0.match.heldBack) },
            uniquingKeysWith: { first, _ in first }
        )
        for url in removedByIt {
            #expect(heldBack[PathPattern.comparablePath(of: url)] == .some(.leftToItsUninstaller), "\(url.path())")
        }
        #expect(heldBack[PathPattern.comparablePath(of: preferences)] == .some(nil))
        #expect(plan.uninstallsItself?.app == installed.app)
    }

    @Test(.launchdHasEveryJob) func itsBundleMovesWhileItsOwnProgramRunsFromIt() async throws {
        let installed = try Installed()
        let preferences = try installed.directory.file("home/Library/Preferences/net.mullvad.vpn.plist")
        let plan = await Uninstallation.prepare(
            installed.app, installedApps: [installed.app], environment: installed.environment
        )

        let result = await plan.move([installed.app.url, preferences], using: try installed.service())

        #expect(result.failures.isEmpty, "\(result.failures.map(\.reason))")
        #expect(Set(result.trashed.map(\.originalURL)) == [installed.app.url, preferences])
    }

    @Test func itsBundleMovesAloneWhileItsOwnProgramRunsFromItOnlyWhenAskedTo() async throws {
        let installed = try Installed()

        let kept = try await installed.service().trash([installed.app.url], usingHelperFor: [])
        let moved = try await installed.service().trash(
            [installed.app.url], usingHelperFor: [], lettingTheirProgramsRun: [installed.app.url]
        )

        #expect(kept.trashed.isEmpty)
        #expect(moved.trashed.map(\.originalURL) == [installed.app.url], "\(moved.failures.map(\.reason))")
    }

    @Test func itsBundleGoesThroughTheHelperWhileItsOwnProgramRunsFromIt() async throws {
        let installed = try Installed()
        let trash = try installed.directory.directory("home/.Trash")
        let service = TrashService(
            environment: installed.environment,
            moveThroughHelper: { urls in
                var result = TrashResult()
                for url in urls {
                    let destination = trash.appending(path: url.lastPathComponent)
                    try? FileManager.default.moveItem(at: url, to: destination)
                    result.trashed.append(TrashedItem(originalURL: url, trashedURL: destination, date: .now))
                }
                return result
            },
            moveToTrash: { _ in throw CocoaError(.fileWriteNoPermission) }
        )
        let app = installed.app.url

        let held = await service.trash(
            apps: [app], thenFiles: { _ in [] }, usingHelperFor: [app], lettingTheirProgramsRun: []
        )
        let moved = await service.trash(
            apps: [app], thenFiles: { _ in [] }, usingHelperFor: [app], lettingTheirProgramsRun: [app]
        )

        #expect(held.failures.map(\.reason) == [.heldOpen(by: ["mullvad-daemon"])])
        #expect(moved.trashed.map(\.originalURL) == [app])
    }

    @Test(.launchdHasEveryJob) func itsBundleMovesAmongSeveralAppsWhileItsOwnProgramRunsFromIt() async throws {
        let installed = try Installed()
        let several = await BulkUninstallation.prepare(
            [installed.app], installedApps: [installed.app], environment: installed.environment
        )

        let result = await several.move([installed.app.url], using: try installed.service())

        #expect(result.failures.isEmpty, "\(result.failures.map(\.reason))")
        #expect(result.trashed.map(\.originalURL) == [installed.app.url])
    }

    @Test(.launchdHasEveryJob) func peelUninstallMovesItsBundleWhileItsOwnProgramRunsFromIt() async throws {
        let installed = try Installed()
        let plan = UninstallPlan.make(
            await Uninstallation.prepare(
                installed.app, installedApps: [installed.app], environment: installed.environment
            ),
            keepLeftovers: true,
            refusal: { _ in nil }
        )

        let result = await plan.move(using: try installed.service())

        #expect(result.failures.isEmpty, "\(result.failures.map(\.reason))")
        #expect(result.trashed.map(\.originalURL) == [installed.app.url])
    }

    @Test(.launchdHasEveryJob) func peelUninstallLeavesOutOfReviewWhatItsUninstallerRemoves() async throws {
        let installed = try Installed()
        try installed.directory.directory("home/Library/Logs/Mullvad VPN")

        let plan = UninstallPlan.make(
            await Uninstallation.prepare(
                installed.app, installedApps: [installed.app], environment: installed.environment
            ),
            keepLeftovers: false,
            refusal: { _ in nil }
        )

        #expect(plan.needsReview == 0)
    }

    @Test(.launchdHasEveryJob) func itsPrivacyIsResetThoughItsOwnProgramRunsFromIt() async throws {
        let installed = try Installed()

        #expect(await PrivacyReset.goingNow([installed.app], with: try installed.service()) == [installed.app])
    }

    private struct Citrix: ~Copyable {
        let directory: TemporaryDirectory
        let app: InstalledApp
        let environment: SearchEnvironment

        init(watching watched: String? = nil, disabled: Bool = false, uninstallerInPlace: Bool = true) throws {
            let directory = try TemporaryDirectory()
            let bundle = try directory.directory("root/Applications/Citrix Workspace.app")
            let uninstaller = "root/Library/Citrix Workspace/Uninstaller/Uninstall Citrix Workspace.app/Contents/MacOS/Uninstall Citrix Workspace"
            if uninstallerInPlace {
                try directory.file(uninstaller)
                try directory.setPermissions(0o755, of: uninstaller)
            }
            try directory.file(
                "root/Library/LaunchAgents/com.citrix.UninstallMonitor.plist",
                contents: PropertyListSerialization.data(
                    fromPropertyList: [
                        "Label": "com.citrix.UninstallMonitor",
                        "Disabled": disabled,
                        "ProgramArguments": [
                            directory.url.appending(path: uninstaller).path(percentEncoded: false),
                            "--monitor",
                            "Citrix Workspace",
                        ],
                        "RunAtLoad": false,
                        "WatchPaths": [watched ?? bundle.path(percentEncoded: false)],
                    ],
                    format: .xml,
                    options: 0
                )
            )
            self.app = InstalledApp(url: bundle, bundleIdentifier: "com.citrix.receiver.nomas", name: "Citrix Workspace")
            self.environment = SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            )
            self.directory = directory
        }

        func job(_ path: String, running program: String) throws -> URL {
            let job = [
                "Label": URL(filePath: path).deletingPathExtension().lastPathComponent,
                "Program": app.url.appending(path: program).path(percentEncoded: false),
            ]
            return try directory.file(
                path,
                contents: PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0)
            )
        }
    }

    @Test(.launchdHasEveryJob) func citrixUninstallsItselfThroughTheAgentThatWatchesItsPlace() async throws {
        let citrix = try Citrix()

        #expect(await UninstallsItself.of(citrix.app, environment: citrix.environment)?.uninstaller == .deletesTheApp)
    }

    @Test(.launchdHasEveryJob) func citrixIsAnOrdinaryAppWhenNoAgentWouldOpenItsUninstaller() async throws {
        let elsewhere = try Citrix(watching: "/Applications/Another.app")
        let disabled = try Citrix(disabled: true)
        let noUninstaller = try Citrix(uninstallerInPlace: false)
        let noAgent = try Citrix()
        try FileManager.default.removeItem(
            at: noAgent.environment.rootDirectory.appending(path: "Library/LaunchAgents/com.citrix.UninstallMonitor.plist")
        )

        #expect(await UninstallsItself.of(elsewhere.app, environment: elsewhere.environment) == nil)
        #expect(await UninstallsItself.of(disabled.app, environment: disabled.environment) == nil)
        #expect(await UninstallsItself.of(noUninstaller.app, environment: noUninstaller.environment) == nil)
        #expect(await UninstallsItself.of(noAgent.app, environment: noAgent.environment) == nil)
    }

    @Test(.launchdHasEveryJob) func leavesToCitrixsUninstallerWhatItDeletesAndOffersTheRest() async throws {
        let citrix = try Citrix()
        let helpers = "Contents/CitrixWorkspaceApps"
        let deletedByIt = [
            try citrix.job(
                "root/Library/LaunchAgents/com.citrix.safariadapter.plist",
                running: "\(helpers)/SafariAdapter.app/Contents/MacOS/SafariAdapter"
            ),
            try citrix.job("root/Library/LaunchDaemons/com.citrix.ctxusbd.plist", running: "\(helpers)/ctxusbd"),
            citrix.environment.rootDirectory.appending(path: "Library/LaunchAgents/com.citrix.UninstallMonitor.plist"),
            citrix.environment.rootDirectory.appending(path: "Library/Citrix Workspace"),
            try citrix.directory.directory("root/Library/Logs/Citrix Workspace"),
            try citrix.directory.directory("home/Library/Logs/Citrix Workspace"),
            try citrix.directory.directory("home/Library/Application Support/Citrix Workspace"),
            try citrix.directory.directory("home/Library/HTTPStorages/com.citrix.receiver.nomas"),
            try citrix.directory.file("home/Library/Preferences/com.citrix.receiver.nomas.plist"),
        ]
        let leftByIt = [
            try citrix.job(
                "root/Library/LaunchAgents/com.citrix.PluginBroker.plist",
                running: "\(helpers)/Citrix Plugin Broker.app/Contents/MacOS/Citrix Plugin Broker"
            ),
            try citrix.directory.directory("home/Library/Caches/com.citrix.receiver.nomas"),
            try citrix.directory.directory("home/Library/WebKit/com.citrix.receiver.nomas"),
        ]

        let plan = await Uninstallation.prepare(
            citrix.app, installedApps: [citrix.app], environment: citrix.environment
        )

        let heldBack = Dictionary(
            plan.scan.leftovers.map { (PathPattern.comparablePath(of: $0.url), $0.match.heldBack) },
            uniquingKeysWith: { first, _ in first }
        )
        for url in deletedByIt {
            #expect(heldBack[PathPattern.comparablePath(of: url)] == .some(.leftToItsUninstaller), "\(url.path())")
        }
        for url in leftByIt {
            #expect(heldBack[PathPattern.comparablePath(of: url)] == .some(nil), "\(url.path())")
        }
    }

    private struct TeamViewer: ~Copyable {
        let directory: TemporaryDirectory
        let app: InstalledApp
        let environment: SearchEnvironment

        init(
            watching watched: String? = nil, disabled: Bool = false, starterInPlace: Bool = true, host: Bool = false
        ) throws {
            let directory = try TemporaryDirectory()
            let bundle = try directory.directory("root/Applications/\(host ? "TeamViewerHost" : "TeamViewer").app")
            let starter = "root/Library/Application Support/TeamViewer/TeamViewerUninstaller.app/Contents/Helpers/com.teamviewer.UninstallerStarter"
            if starterInPlace {
                try directory.file(starter)
                try directory.setPermissions(0o755, of: starter)
            }
            try directory.file(
                "root/Library/LaunchDaemons/com.teamviewer.UninstallerWatcher.plist",
                contents: PropertyListSerialization.data(
                    fromPropertyList: [
                        "Label": "com.teamviewer.UninstallerWatcher",
                        "Disabled": disabled,
                        "Program": directory.url.appending(path: starter).path(percentEncoded: false),
                        "WatchPaths": [watched ?? bundle.path(percentEncoded: false)],
                    ],
                    format: .xml,
                    options: 0
                )
            )
            self.app = host
                ? InstalledApp(url: bundle, bundleIdentifier: "com.teamviewer.TeamViewerHost", name: "TeamViewer Host")
                : InstalledApp(url: bundle, bundleIdentifier: "com.teamviewer.TeamViewer", name: "TeamViewer")
            self.environment = SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            )
            self.directory = directory
        }

        func job(_ path: String, running program: String) throws -> URL {
            let job = [
                "Label": URL(filePath: path).deletingPathExtension().lastPathComponent,
                "Program": app.url.appending(path: program).path(percentEncoded: false),
            ]
            return try directory.file(
                path,
                contents: PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0)
            )
        }
    }

    @Test(.launchdHasEveryJob) func teamViewerUninstallsItselfThroughTheDaemonThatWatchesIt() async throws {
        let teamViewer = try TeamViewer()

        let uninstaller = await UninstallsItself.of(teamViewer.app, environment: teamViewer.environment)?.uninstaller
        #expect(uninstaller == .removesItsComponents)
    }

    @Test(.launchdHasEveryJob) func teamViewerHostUninstallsItselfThroughTheSameDaemon() async throws {
        let host = try TeamViewer(host: true)

        let uninstaller = await UninstallsItself.of(host.app, environment: host.environment)?.uninstaller
        #expect(uninstaller == .removesItsComponents)
    }

    @Test(.launchdHasEveryJob) func teamViewerIsAnOrdinaryAppWhenNoDaemonWouldOpenItsUninstaller() async throws {
        let elsewhere = try TeamViewer(watching: "/Applications/Another.app")
        let disabled = try TeamViewer(disabled: true)
        let noStarter = try TeamViewer(starterInPlace: false)
        let noDaemon = try TeamViewer()
        try FileManager.default.removeItem(
            at: noDaemon.environment.rootDirectory.appending(path: "Library/LaunchDaemons/com.teamviewer.UninstallerWatcher.plist")
        )

        #expect(await UninstallsItself.of(elsewhere.app, environment: elsewhere.environment) == nil)
        #expect(await UninstallsItself.of(disabled.app, environment: disabled.environment) == nil)
        #expect(await UninstallsItself.of(noStarter.app, environment: noStarter.environment) == nil)
        #expect(await UninstallsItself.of(noDaemon.app, environment: noDaemon.environment) == nil)
    }

    @Test(.launchdHasEveryJob) func leavesToTeamViewersUninstallerWhatItRemovesAndOffersTheRest() async throws {
        let teamViewer = try TeamViewer()
        let root = teamViewer.environment.rootDirectory
        let removedByIt = [
            try teamViewer.job(
                "root/Library/LaunchDaemons/com.teamviewer.teamviewer_service.plist",
                running: "Contents/MacOS/TeamViewer_Service"
            ),
            try teamViewer.job(
                "root/Library/LaunchAgents/com.teamviewer.teamviewer_desktop.plist",
                running: "Contents/Helpers/TeamViewer_Desktop"
            ),
            root.appending(path: "Library/LaunchDaemons/com.teamviewer.UninstallerWatcher.plist"),
            root.appending(path: "Library/Application Support/TeamViewer"),
            try teamViewer.directory.file(
                "root/Library/Security/SecurityAgentPlugins/TeamViewerAuthPlugin.bundle/Contents/Info.plist",
                contents: Data(#"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.teamviewer.AuthorizationPlugin</string></dict></plist>"#.utf8)
            ).deletingLastPathComponent().deletingLastPathComponent(),
        ]
        let leftByIt = [try teamViewer.directory.directory("home/Library/Caches/com.teamviewer.TeamViewer")]

        let plan = await Uninstallation.prepare(
            teamViewer.app, installedApps: [teamViewer.app], environment: teamViewer.environment
        )

        let heldBack = Dictionary(
            plan.scan.leftovers.map { (PathPattern.comparablePath(of: $0.url), $0.match.heldBack) },
            uniquingKeysWith: { first, _ in first }
        )
        for url in removedByIt {
            #expect(heldBack[PathPattern.comparablePath(of: url)] == .some(.leftToItsUninstaller), "\(url.path())")
        }
        for url in leftByIt {
            #expect(heldBack[PathPattern.comparablePath(of: url)] == .some(nil), "\(url.path())")
        }
    }

    @Test(.launchdHasEveryJob) func citrixsBundleMovesWhileItsHelperRunsFromIt() async throws {
        let citrix = try Citrix()
        let helper = try citrix.directory.runningProgram(
            "root/Applications/Citrix Workspace.app/Contents/CitrixWorkspaceApps/CtxWorkspaceHelperDaemon.app/Contents/MacOS/CtxWorkspaceHelperDaemon"
        )
        defer { helper.terminate() }
        let trash = try citrix.directory.directory("home/.Trash")
        let service = TrashService(environment: citrix.environment) { url in
            let destination = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
        let plan = await Uninstallation.prepare(
            citrix.app, installedApps: [citrix.app], environment: citrix.environment
        )

        let result = await plan.move([citrix.app.url], using: service)

        #expect(result.failures.isEmpty, "\(result.failures.map(\.reason))")
        #expect(result.trashed.map(\.originalURL) == [citrix.app.url])
    }

    @Test(.launchdHasEveryJob) func peelUninstallWarnsThatCitrixsUninstallerDeletesTheApp() async throws {
        let citrix = try Citrix()
        let uninstallsItself = await UninstallsItself.of(citrix.app, environment: citrix.environment)

        let warnings = UninstallCommand.warnings(
            moving: [citrix.app.url], of: citrix.app,
            uninstallsItself: uninstallsItself, leftInTheSystem: nil, commandToRunFirst: nil, resettingPrivacy: false
        )

        #expect(warnings.count == 1)
        #expect(warnings.first?.contains("deletes the app, even from the Trash") == true)
    }

    private struct BlueStacks: ~Copyable {
        let directory: TemporaryDirectory
        let app: InstalledApp
        let manager: URL
        let environment: SearchEnvironment
        let job: URL

        init() throws {
            let directory = try TemporaryDirectory()
            let bundle = try directory.directory("root/Applications/BlueStacks.app")
            let manager = try directory.directory("root/Applications/BlueStacks Air multi-instance manager.app")
            let cleanup = "root/Library/Application Support/BlueStacks/BlueStacksCleanup"
            try directory.file(cleanup)
            try directory.setPermissions(0o755, of: cleanup)
            self.job = try directory.file(
                "root/Library/LaunchDaemons/com.now.gg.BlueStacks.cleanup.plist",
                contents: PropertyListSerialization.data(
                    fromPropertyList: [
                        "Label": "com.now.gg.BlueStacks.cleanup",
                        "ProgramArguments": [directory.url.appending(path: cleanup).path(percentEncoded: false)],
                        "WatchPaths": [bundle.path(percentEncoded: false), manager.path(percentEncoded: false)],
                    ],
                    format: .xml,
                    options: 0
                )
            )
            self.app = InstalledApp(url: bundle, bundleIdentifier: "com.now.gg.BlueStacks", name: "BlueStacks")
            self.manager = manager
            self.environment = SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            )
            self.directory = directory
        }
    }

    @Test(.launchdHasEveryJob) func blueStacksUninstallsItselfThroughTheCleanupThatWatchesBothItsApps() async throws {
        let blueStacks = try BlueStacks()
        let shared = try blueStacks.directory.directory("root/Users/Shared/Library/Application Support/BlueStacks/Engine")
            .deletingLastPathComponent()

        let plan = await Uninstallation.prepare(
            blueStacks.app, installedApps: [blueStacks.app], environment: blueStacks.environment
        )

        let heldBack = Dictionary(
            plan.scan.leftovers.map { (PathPattern.comparablePath(of: $0.url), $0.match.heldBack) },
            uniquingKeysWith: { first, _ in first }
        )
        #expect(plan.uninstallsItself?.uninstaller == .deletesItsSuite)
        #expect(heldBack[PathPattern.comparablePath(of: blueStacks.job)] == .some(.leftToItsUninstaller))
        #expect(heldBack[PathPattern.comparablePath(of: shared)] == .some(.leftToItsUninstaller))
        let program = blueStacks.directory.url.appending(path: "root/Library/Application Support/BlueStacks")
        #expect(heldBack[PathPattern.comparablePath(of: program)] == .some(.neededWhenTheAppLeaves))
        let warnings = UninstallCommand.warnings(
            moving: [blueStacks.app.url], of: blueStacks.app,
            uninstallsItself: plan.uninstallsItself,
            leftInTheSystem: nil, commandToRunFirst: nil, resettingPrivacy: false
        )
        #expect(warnings.first?.contains("deletes the other BlueStacks app") == true)
        let other = InstalledApp(
            url: blueStacks.manager, bundleIdentifier: "com.now.gg.BlueStacksAirMIM",
            name: "BlueStacks Air multi-instance manager"
        )
        #expect(await UninstallsItself.of(other, environment: blueStacks.environment)?.uninstaller == .deletesItsSuite)
    }

    private struct NoMachine: ~Copyable {
        let directory: TemporaryDirectory
        let app: InstalledApp
        let environment: SearchEnvironment
        let job: URL

        init() throws {
            let directory = try TemporaryDirectory()
            let bundle = try directory.directory("root/Applications/NoMachine.app")
            let script = "root/Library/Application Support/NoMachine/nxuninstall.sh"
            try directory.file(script)
            try directory.setPermissions(0o755, of: script)
            self.job = try directory.file(
                "root/Library/LaunchDaemons/com.nomachine.uninstall.plist",
                contents: PropertyListSerialization.data(
                    fromPropertyList: [
                        "Label": "com.nomachine.uninstall",
                        "ProgramArguments": [directory.url.appending(path: script).path(percentEncoded: false)],
                        "WatchPaths": [bundle.path(percentEncoded: false)],
                    ],
                    format: .xml,
                    options: 0
                )
            )
            self.app = InstalledApp(url: bundle, bundleIdentifier: "com.nomachine.nxdock", name: "NoMachine")
            self.environment = SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            )
            self.directory = directory
        }

        func driver(_ name: String) throws -> URL {
            let driver = try directory.directory("root/Library/Audio/Plug-Ins/HAL/\(name).driver")
            try directory.file(
                "root/Library/Audio/Plug-Ins/HAL/\(name).driver/Contents/Info.plist",
                contents: PropertyListSerialization.data(
                    fromPropertyList: ["CFBundleIdentifier": "com.nomachine.\(name)"], format: .xml, options: 0
                )
            )
            return driver
        }
    }

    @Test(.launchdHasEveryJob) func leavesToNoMachinesUninstallWhatItDeletesAndOffersTheRest() async throws {
        let noMachine = try NoMachine()
        let deletedByIt = [
            noMachine.job,
            try noMachine.directory.file("root/Library/LaunchAgents/com.nomachine.uninstallAgent.plist"),
            noMachine.environment.rootDirectory.appending(path: "Library/Application Support/NoMachine"),
            try noMachine.driver("NMAudio"),
            try noMachine.driver("NMAudioMic"),
        ]
        let settings = try noMachine.directory.file("home/Library/Preferences/com.nomachine.nxdock.plist")

        let plan = await Uninstallation.prepare(
            noMachine.app, installedApps: [noMachine.app], environment: noMachine.environment
        )

        #expect(plan.uninstallsItself?.uninstaller == .uninstallsWithoutAsking)
        let heldBack = Dictionary(
            plan.scan.leftovers.map { (PathPattern.comparablePath(of: $0.url), $0.match.heldBack) },
            uniquingKeysWith: { first, _ in first }
        )
        for url in deletedByIt {
            #expect(heldBack[PathPattern.comparablePath(of: url)] == .some(.leftToItsUninstaller), "\(url.path())")
        }
        #expect(heldBack[PathPattern.comparablePath(of: settings)] == .some(nil))
    }

    @Test(.launchdHasEveryJob) func noMachinesBundleMovesWhileItsServerRunsFromIt() async throws {
        let noMachine = try NoMachine()
        let server = try noMachine.directory.runningProgram(
            "root/Applications/NoMachine.app/Contents/Frameworks/bin/nxserver.bin"
        )
        defer { server.terminate() }
        let trash = try noMachine.directory.directory("home/.Trash")
        let service = TrashService(environment: noMachine.environment) { url in
            let destination = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
        let plan = await Uninstallation.prepare(
            noMachine.app, installedApps: [noMachine.app], environment: noMachine.environment
        )

        let result = await plan.move([noMachine.app.url], using: service)

        #expect(result.failures.isEmpty, "\(result.failures.map(\.reason))")
        #expect(result.trashed.map(\.originalURL) == [noMachine.app.url])
    }

    @Test(.launchdHasEveryJob) func peelUninstallWarnsThatNoMachineDeletesItselfWithoutAsking() async throws {
        let noMachine = try NoMachine()
        let uninstallsItself = await UninstallsItself.of(noMachine.app, environment: noMachine.environment)

        let warnings = UninstallCommand.warnings(
            moving: [noMachine.app.url], of: noMachine.app,
            uninstallsItself: uninstallsItself, leftInTheSystem: nil, commandToRunFirst: nil, resettingPrivacy: false
        )

        #expect(warnings.count == 1)
        #expect(warnings.first?.contains("as an administrator, without asking") == true)
        #expect(warnings.first?.contains("can delete the app from the Trash too") == true)
        #expect(warnings.first?.contains("NoMachine Uninstall opens") == true)
    }

    @Test(.launchdHasNoJob) func noAppUninstallsItselfWhileLaunchdLacksTheJobThatWouldDoIt() async throws {
        let mullvad = try Installed()
        let citrix = try Citrix()
        let teamViewer = try TeamViewer()
        let blueStacks = try BlueStacks()
        let noMachine = try NoMachine()

        #expect(await UninstallsItself.of(mullvad.app, environment: mullvad.environment) == nil)
        #expect(await UninstallsItself.of(citrix.app, environment: citrix.environment) == nil)
        #expect(await UninstallsItself.of(teamViewer.app, environment: teamViewer.environment) == nil)
        #expect(await UninstallsItself.of(blueStacks.app, environment: blueStacks.environment) == nil)
        #expect(await UninstallsItself.of(noMachine.app, environment: noMachine.environment) == nil)
        let plan = await Uninstallation.prepare(
            teamViewer.app, installedApps: [teamViewer.app], environment: teamViewer.environment
        )
        #expect(plan.uninstallsItself == nil)
        #expect(!plan.scan.leftovers.contains { $0.match.heldBack == .leftToItsUninstaller })
    }

    private struct Watched: ~Copyable {
        enum Runs {
            case helper
            case helperInsideTheApp
            case script
        }

        let directory: TemporaryDirectory
        let app: InstalledApp
        let environment: SearchEnvironment
        let job: URL
        let support: URL

        init(
            watching watched: String? = nil,
            runs: Runs = .helper,
            runnable: Bool = true,
            disabled: Bool = false
        ) throws {
            let directory = try TemporaryDirectory()
            let bundle = try directory.directory("root/Applications/Watched.app")
            let executable = try directory.file("root/Applications/Watched.app/Contents/MacOS/Watched")
            let support = try directory.directory("home/Library/Application Support/Watched")
            let helper = switch runs {
            case .helper, .script: "home/Library/Application Support/Watched/Uninstall Helper.app/Contents/MacOS/Helper"
            case .helperInsideTheApp: "root/Applications/Watched.app/Contents/Helpers/Uninstall Helper"
            }
            try directory.file(helper)
            if runnable {
                try directory.setPermissions(0o755, of: helper)
            }
            let script = try directory.file("home/Library/Application Support/Watched/uninstall.sh")
            let arguments = switch runs {
            case .helper, .helperInsideTheApp: [directory.url.appending(path: helper).path(percentEncoded: false)]
            case .script: ["sh", script.path(percentEncoded: false)]
            }
            let trashed = directory.url.appending(path: "home/.Trash/Watched.app/Contents/MacOS/Watched")
            self.job = try directory.file(
                "home/Library/LaunchAgents/org.example.watched.UninstallHelper.plist",
                contents: PropertyListSerialization.data(
                    fromPropertyList: [
                        "Label": "org.example.watched.UninstallHelper",
                        "Disabled": disabled,
                        "ProgramArguments": arguments,
                        "WatchPaths": [
                            watched ?? executable.path(percentEncoded: false), trashed.path(percentEncoded: false),
                        ],
                    ],
                    format: .xml,
                    options: 0
                )
            )
            self.app = InstalledApp(url: bundle, bundleIdentifier: "org.example.watched", name: "Watched")
            self.environment = SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            )
            self.support = support
            self.directory = directory
        }

        func uninstallsItself(whileLaunchdHasTheJob loaded: Bool = true) async -> UninstallsItself? {
            let (app, environment) = (app, environment)
            return await UninstallsItself.$launchdStandIn.withValue({ _ in loaded }) {
                await UninstallsItself.of(app, environment: environment)
            }
        }

        func prepared() async -> Uninstallation {
            let (app, environment) = (app, environment)
            return await UninstallsItself.$launchdStandIn.withValue({ _ in true }) {
                await Uninstallation.prepare(app, installedApps: [app], environment: environment)
            }
        }

        func service() throws -> TrashService {
            let trash = try directory.directory("home/.Trash")
            return TrashService(environment: environment) { url in
                let destination = trash.appending(path: url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            }
        }
    }

    @Test func anAppUninstallsItselfThroughAJobThatWatchesItsPlace() async throws {
        let watched = try Watched()

        let uninstallsItself = await watched.uninstallsItself()

        #expect(uninstallsItself?.uninstaller == .watchedByAJob)
        #expect(uninstallsItself?.letsItsProgramsRun == false)
    }

    @Test func anAppIsOrdinaryWhenNoLoadedJobWouldRunAProgramOutsideIt() async throws {
        let elsewhere = try Watched(watching: "/Applications/Another.app")
        let insideTheApp = try Watched(runs: .helperInsideTheApp)
        let notRunnable = try Watched(runnable: false)
        let disabled = try Watched(disabled: true)
        let notLoaded = try Watched()

        #expect(await elsewhere.uninstallsItself() == nil)
        #expect(await insideTheApp.uninstallsItself() == nil)
        #expect(await notRunnable.uninstallsItself() == nil)
        #expect(await disabled.uninstallsItself() == nil)
        #expect(await notLoaded.uninstallsItself(whileLaunchdHasTheJob: false) == nil)
    }

    @Test func leavesWhatTheWatchingJobNeedsWhereItIsAndOffersTheRest() async throws {
        let watched = try Watched()
        let caches = try watched.directory.directory("home/Library/Caches/org.example.watched")

        let plan = await watched.prepared()

        let heldBack = Dictionary(
            plan.scan.leftovers.map { (PathPattern.comparablePath(of: $0.url), $0.match.heldBack) },
            uniquingKeysWith: { first, _ in first }
        )
        #expect(heldBack[PathPattern.comparablePath(of: watched.job)] == .some(.neededWhenTheAppLeaves))
        #expect(heldBack[PathPattern.comparablePath(of: watched.support)] == .some(.neededWhenTheAppLeaves))
        #expect(heldBack[PathPattern.comparablePath(of: caches)] == .some(nil))
    }

    @Test func aScriptTheWatchingJobRunsKeepsItsFolderInPlace() async throws {
        let watched = try Watched(runs: .script)

        let plan = await watched.prepared()

        let support = plan.scan.leftovers.first {
            PathPattern.comparablePath(of: $0.url) == PathPattern.comparablePath(of: watched.support)
        }
        #expect(await watched.uninstallsItself()?.uninstaller == .watchedByAJob)
        #expect(support?.match.heldBack == .neededWhenTheAppLeaves)
    }

    @Test func movingAWatchedAppLeavesItsJobAndProgramInPlace() async throws {
        let watched = try Watched()
        let caches = try watched.directory.directory("home/Library/Caches/org.example.watched")
        let plan = await watched.prepared()

        let result = await plan.move(plan.suggestedSelection(canUseHelper: false), using: try watched.service())

        #expect(result.failures.isEmpty, "\(result.failures.map(\.reason))")
        #expect(
            Set(result.trashed.map { PathPattern.comparablePath(of: $0.originalURL) })
                == Set([watched.app.url, caches].map(PathPattern.comparablePath))
        )
        #expect(!watched.job.isMissing)
        #expect(!watched.support.isMissing)
    }

    @Test func aWatchedAppsOwnProgramStillKeepsItInPlace() async throws {
        let watched = try Watched()
        try FileManager.default.removeItem(at: watched.app.url.appending(path: "Contents/MacOS/Watched"))
        let program = try watched.directory.runningProgram("root/Applications/Watched.app/Contents/MacOS/Watched")
        defer { program.terminate() }
        let plan = await watched.prepared()

        let result = await plan.move([watched.app.url], using: try watched.service())

        #expect(result.trashed.isEmpty)
        #expect(result.failures.map(\.reason) == [.heldOpen(by: ["Watched"])])
    }

    @Test func peelUninstallWarnsThatAWatchedAppStartsAProgramAsItLeaves() async throws {
        let watched = try Watched()
        let uninstallsItself = await watched.uninstallsItself()

        let warnings = UninstallCommand.warnings(
            moving: [watched.app.url], of: watched.app,
            uninstallsItself: uninstallsItself, leftInTheSystem: nil, commandToRunFirst: nil, resettingPrivacy: false
        )

        #expect(warnings == [
            "Moving Watched to the Trash starts a program that waits for it to leave. Peel leaves that program and the file that starts it in place so it can finish, and the Trash can't bring back anything it removes.",
        ])
    }
}

/// Says for the test it marks whether launchd has the jobs Peel asks about, since no test loads a job into launchd.
struct LaunchdJobs: TestTrait, TestScoping {
    let areLoaded: Bool

    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
        let areLoaded = areLoaded
        try await UninstallsItself.$launchdStandIn.withValue({ _ in areLoaded }) { try await function() }
    }
}

extension Trait where Self == LaunchdJobs {
    static var launchdHasEveryJob: Self { Self(areLoaded: true) }
    static var launchdHasNoJob: Self { Self(areLoaded: false) }
}
