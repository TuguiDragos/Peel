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
            "/Applications/Mullvad VPN.app/Contents/Resources/uninstall.sh",
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
}
