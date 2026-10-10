import Foundation
@testable import PeelCommandLine
@testable import PeelCore
import Testing

struct UninstallsItselfTests {
    private let mullvad = InstalledApp(
        url: URL(filePath: "/Applications/Mullvad VPN.app"), bundleIdentifier: "net.mullvad.vpn", name: "Mullvad VPN"
    )

    @Test func mullvadUninstallsItselfOnceItLeavesTheApplicationsFolder() {
        #expect(UninstallsItself.when(moving: [mullvad.url], among: [mullvad]).map(\.app) == [mullvad])
        #expect(UninstallsItself.when(moving: [mullvad.url], among: [mullvad]).map(\.uninstaller) == [
            .logsOut(script: "/Applications/Mullvad VPN.app/Contents/Resources/uninstall.sh"),
        ])
    }

    /// The apps Peel lists come from a folder walk, whose URLs name a folder with a slash at the end.
    @Test func knowsMullvadAsTheListOfAppsNamesIt() throws {
        let walked = URL(filePath: "/Applications/Mullvad VPN.app", directoryHint: .isDirectory)
        #expect(walked.path(percentEncoded: false).hasSuffix("/"))
        let listed = InstalledApp(url: walked, bundleIdentifier: "net.mullvad.vpn", name: "Mullvad VPN")

        #expect(UninstallsItself.when(moving: [walked], among: [listed]).map(\.app) == [listed])
    }

    @Test func nothingHappensWhileTheAppStaysOrSitsElsewhere() {
        let elsewhere = InstalledApp(
            url: URL(filePath: "/Users/me/Applications/Mullvad VPN.app"), bundleIdentifier: "net.mullvad.vpn",
            name: "Mullvad VPN"
        )
        let another = InstalledApp(
            url: URL(filePath: "/Applications/Mullvad VPN.app"), bundleIdentifier: "org.example.vpn", name: "Mullvad VPN"
        )

        #expect(UninstallsItself.when(moving: [], among: [mullvad]).isEmpty)
        #expect(UninstallsItself.when(moving: [elsewhere.url], among: [elsewhere]).isEmpty)
        #expect(UninstallsItself.when(moving: [another.url], among: [another]).isEmpty)
    }

    private struct Installed: ~Copyable {
        let directory: TemporaryDirectory
        let app: InstalledApp
        let environment: SearchEnvironment
        let daemon: Process

        init() throws {
            let directory = try TemporaryDirectory()
            let bundle = try directory.directory("root/Applications/Mullvad VPN.app")
            let daemon = try directory.runningProgram("root/Applications/Mullvad VPN.app/Contents/Resources/mullvad-daemon")
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

    @Test func leavesToTheUninstallerWhatItRemovesAndOffersTheRest() async throws {
        let installed = try Installed()
        let program = installed.app.url.appending(path: "Contents/Resources/mullvad-daemon").path(percentEncoded: false)
        let job = try installed.directory.file(
            "root/Library/LaunchDaemons/net.mullvad.daemon.plist",
            contents: PropertyListSerialization.data(
                fromPropertyList: ["Label": "net.mullvad.daemon", "Program": program], format: .xml, options: 0
            )
        )
        let removedByIt = [
            job,
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

    @Test func itsBundleMovesWhileItsOwnProgramRunsFromIt() async throws {
        let installed = try Installed()
        let preferences = try installed.directory.file("home/Library/Preferences/net.mullvad.vpn.plist")
        let plan = await Uninstallation.prepare(
            installed.app, installedApps: [installed.app], environment: installed.environment
        )

        let result = await plan.move([installed.app.url, preferences], using: try installed.service())

        #expect(result.failures.isEmpty, "\(result.failures.map(\.reason))")
        #expect(Set(result.trashed.map(\.originalURL)) == [installed.app.url, preferences])
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

    @Test func itsBundleMovesAmongSeveralAppsWhileItsOwnProgramRunsFromIt() async throws {
        let installed = try Installed()
        let several = await BulkUninstallation.prepare(
            [installed.app], installedApps: [installed.app], environment: installed.environment
        )

        let result = await several.move([installed.app.url], using: try installed.service())

        #expect(result.failures.isEmpty, "\(result.failures.map(\.reason))")
        #expect(result.trashed.map(\.originalURL) == [installed.app.url])
    }

    @Test func peelUninstallMovesItsBundleWhileItsOwnProgramRunsFromIt() async throws {
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

    @Test func peelUninstallLeavesOutOfReviewWhatItsUninstallerRemoves() async throws {
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

    @Test func itsPrivacyIsResetThoughItsOwnProgramRunsFromIt() throws {
        let installed = try Installed()

        #expect(PrivacyReset.goingNow([installed.app], with: try installed.service()) == [installed.app])
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

    @Test func citrixUninstallsItselfThroughTheAgentThatWatchesItsPlace() throws {
        let citrix = try Citrix()

        #expect(UninstallsItself.of(citrix.app, environment: citrix.environment)?.uninstaller == .deletesTheApp)
    }

    @Test func citrixIsAnOrdinaryAppWhenNoAgentWouldOpenItsUninstaller() throws {
        let elsewhere = try Citrix(watching: "/Applications/Another.app")
        let disabled = try Citrix(disabled: true)
        let noUninstaller = try Citrix(uninstallerInPlace: false)
        let noAgent = try Citrix()
        try FileManager.default.removeItem(
            at: noAgent.environment.rootDirectory.appending(path: "Library/LaunchAgents/com.citrix.UninstallMonitor.plist")
        )

        #expect(UninstallsItself.of(elsewhere.app, environment: elsewhere.environment) == nil)
        #expect(UninstallsItself.of(disabled.app, environment: disabled.environment) == nil)
        #expect(UninstallsItself.of(noUninstaller.app, environment: noUninstaller.environment) == nil)
        #expect(UninstallsItself.of(noAgent.app, environment: noAgent.environment) == nil)
    }

    @Test func leavesToCitrixsUninstallerWhatItDeletesAndOffersTheRest() async throws {
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

    @Test func citrixsBundleMovesWhileItsHelperRunsFromIt() async throws {
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

    @Test func peelUninstallWarnsThatCitrixsUninstallerDeletesTheApp() throws {
        let citrix = try Citrix()

        let warnings = UninstallCommand.warnings(
            moving: [citrix.app.url], of: citrix.app, resettingPrivacy: false, environment: citrix.environment
        )

        #expect(warnings.count == 1)
        #expect(warnings.first?.contains("deletes the app, even from the Trash") == true)
    }
}
