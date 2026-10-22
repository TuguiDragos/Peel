import Foundation
@testable import PeelCore
import Testing

struct HomebrewReceiptTests {
    private let json = """
        {"formulae": [], "casks": [
          {"token": "example", "installed": "1.0", "version": "1.0",
           "artifacts": [{"app": ["Example.app"], "target": "/Applications/Example.app"}]},
          {"token": "other", "version": "2.0"}
        ]}
        """

    @Test func anInstalledCaskKnowsItsFolderInTheCaskroom() throws {
        let caskroom = URL(filePath: "/opt/homebrew/Caskroom", directoryHint: .isDirectory)

        let casks = try #require(Homebrew.parseInstalled(Data(json.utf8), caskroom: caskroom))

        let folder = casks.first { $0.name == "example" }?.caskroomFolder
        #expect(folder?.path(percentEncoded: false) == "/opt/homebrew/Caskroom/example/")
        #expect(casks.first { $0.name == "other" }?.caskroomFolder == nil)
    }

    @Test func readsTheCaskroomHomebrewNames() {
        #expect(Homebrew.folder(answering: "/opt/homebrew/Caskroom\n")?.path(percentEncoded: false)
            == "/opt/homebrew/Caskroom/")
        #expect(Homebrew.folder(answering: "") == nil)
        #expect(Homebrew.folder(answering: "Caskroom\n") == nil)
        #expect(Homebrew.folder(answering: "/opt/homebrew/Caskroom\n/usr/local/Caskroom\n") == nil)
    }

    @Test func everyCaskInstalledOnThisMacIsReadAsItIsOnTheDisk() async throws {
        guard Homebrew.executableURL != nil, await Homebrew.hasLocalDefinitions() else { return }

        for cask in try await Homebrew.installedPackages() where cask.kind == .cask {
            let folder = try #require(cask.caskroomFolder, "\(cask.name)")
            var isFolder: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: folder.path(percentEncoded: false), isDirectory: &isFolder))
            #expect(isFolder.boolValue, "\(folder.path())")
            let receipts = URL(filePath: "/private/var/db/receipts", directoryHint: .isDirectory)
            let gone = cask.appTargets.isEmpty
                ? !cask.packageIdentifiers.isEmpty && cask.packageIdentifiers.allSatisfy { identifier in
                    identifier.range(of: "^[A-Za-z0-9_-][A-Za-z0-9._-]*$", options: .regularExpression) != nil
                        && receipts.appending(path: "\(identifier).plist").isMissing
                }
                : cask.appTargets.allSatisfy { URL(filePath: $0).isMissing }
            #expect(cask.isMissingWhatItInstalled == gone, "\(cask.name)")
        }
    }

    @Test func aCaskIsMissingItsAppsOnlyWhenEveryOneIsGone() throws {
        let installed = try Installed()
        let app = try installed.app("Example", identifier: "org.example.app")
        let gone = installed.directory.url.appending(path: "root/Applications/Gone.app", directoryHint: .isDirectory)
        let other = InstalledApp(url: gone, bundleIdentifier: "org.example.gone", name: "Gone")

        #expect(installed.cask(installing: [other]).checkingWhatItInstalled().isMissingWhatItInstalled)
        #expect(!installed.cask(installing: [app]).checkingWhatItInstalled().isMissingWhatItInstalled)
        #expect(!installed.cask(installing: [app, other]).checkingWhatItInstalled().isMissingWhatItInstalled)
        #expect(!installed.cask(installing: []).checkingWhatItInstalled().isMissingWhatItInstalled)
        let known = HomebrewPackage(name: "example", kind: .cask, appTargets: [PathPattern.comparablePath(of: gone)])
        #expect(!known.checkingWhatItInstalled().isMissingWhatItInstalled)
    }

    @Test func aCaskOfPackagesAloneIsGoneOnceEveryReceiptIs() throws {
        let installed = try Installed()
        let receipts = try installed.directory.directory("root/private/var/db/receipts")
        try installed.directory.file("root/private/var/db/receipts/org.example.kept.plist")
        let cask = { (packages: [String]) in
            HomebrewPackage(name: "example", kind: .cask, installedVersion: "1.0", packageIdentifiers: packages)
                .kept(inCaskroom: installed.caskroom)
        }
        let gone = { (cask: HomebrewPackage) in
            cask.checkingWhatItInstalled(receipts: receipts).isMissingWhatItInstalled
        }

        #expect(gone(cask(["org.example.driver", "org.example.app"])))
        #expect(!gone(cask(["org.example.driver", "org.example.kept"])))
        #expect(!gone(cask(["org.example.driver.*"])))
        #expect(!gone(cask([])))
        #expect(!gone(HomebrewPackage(name: "example", kind: .cask, packageIdentifiers: ["org.example.driver"])))
    }

    @Test func anAppOnADiskThatIsNotConnectedIsNotGone() throws {
        let installed = try Installed()
        let disk = "/Volumes/Peel Not Connected \(UUID().uuidString)"
        let cask = HomebrewPackage(
            name: "example", kind: .cask, installedVersion: "1.0", appTargets: ["\(disk)/Applications/Example.app"]
        ).kept(inCaskroom: installed.caskroom)

        #expect(!cask.checkingWhatItInstalled().isMissingWhatItInstalled)
    }

    @Test func aCaskMissingItsAppsWaitsForNoUpgrade() throws {
        let installed = try Installed()
        let gone = installed.directory.url.appending(path: "root/Applications/Gone.app", directoryHint: .isDirectory)
        let cask = HomebrewPackage(
            name: "example",
            kind: .cask,
            installedVersion: "1.0",
            latestVersion: "2.0",
            isOutdated: true,
            appTargets: [PathPattern.comparablePath(of: gone)]
        ).kept(inCaskroom: installed.caskroom)

        #expect(cask.waitsForAnUpgrade)
        #expect(cask.joinsUpgradeAll)
        #expect(!cask.checkingWhatItInstalled().waitsForAnUpgrade)
        #expect(!cask.checkingWhatItInstalled().joinsUpgradeAll)
    }

    @Test func forgettingACaskTakesItsReceiptAndTheLinksIntoItAndIntoItsApps() async throws {
        let installed = try Installed()
        let gone = installed.directory.url.appending(path: "root/Applications/Gone.app", directoryHint: .isDirectory)
        let cask = HomebrewPackage(
            name: "example", kind: .cask, installedVersion: "1.0", appTargets: [PathPattern.comparablePath(of: gone)]
        ).kept(inCaskroom: installed.caskroom).checkingWhatItInstalled()
        let wrapper = try installed.directory.file("root/opt/homebrew/Caskroom/example/1.0/.homebrew-command-wrappers/example")
        let bin = try installed.directory.directory("root/opt/homebrew/bin")
        let completions = try installed.directory.directory("root/opt/homebrew/share/zsh/site-functions")
        try FileManager.default.createSymbolicLink(at: bin.appending(path: "example"), withDestinationURL: wrapper)
        try FileManager.default.createSymbolicLink(
            at: bin.appending(path: "gone"), withDestinationURL: gone.appending(path: "Contents/MacOS/gone")
        )
        try FileManager.default.createSymbolicLink(
            at: completions.appending(path: "_gone"), withDestinationURL: gone.appending(path: "Contents/Resources/_gone")
        )
        try FileManager.default.createSymbolicLink(
            at: bin.appending(path: "tool"),
            withDestinationURL: try installed.directory.file("root/opt/homebrew/Cellar/tool/1.0/bin/tool")
        )

        let items = HomebrewReceipt.items(of: cask, environment: installed.environment)
        let result = await HomebrewReceipt.forget(
            [cask], through: try installed.service(), environment: installed.environment
        )

        #expect(Set(items.map(\.lastPathComponent)) == ["example", "gone", "_gone"])
        #expect(items.first.map { PathPattern.comparablePath(of: $0) }
            == PathPattern.comparablePath(of: installed.caskroom.appending(path: "example")))
        #expect(result.failures.isEmpty, "\(result.failures.map(\.reason))")
        #expect(result.trashed.count == 4)
        #expect(installed.caskroom.appending(path: "example").isMissing)
        #expect(bin.appending(path: "tool").isThere)
    }

    @Test func aCaskWhoseAppIsBackIsNotForgotten() async throws {
        let installed = try Installed()
        let app = try installed.app("Example", identifier: "org.example.app")
        let cask = installed.cask(installing: [app])

        let result = await HomebrewReceipt.forget(
            [cask], through: try installed.service(), environment: installed.environment
        )

        #expect(HomebrewReceipt.items(of: cask, environment: installed.environment).isEmpty)
        #expect(result.trashed.isEmpty)
        #expect(installed.caskroom.appending(path: "example").isThere)
    }

    private struct Installed: ~Copyable {
        let directory: TemporaryDirectory
        let environment: SearchEnvironment
        let caskroom: URL

        init() throws {
            let directory = try TemporaryDirectory()
            try directory.file("root/opt/homebrew/Caskroom/example/.metadata/1.0/20261007000000.000/Casks/example.json")
            environment = SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            )
            caskroom = directory.url.appending(path: "root/opt/homebrew/Caskroom", directoryHint: .isDirectory)
            self.directory = directory
        }

        func app(_ name: String, identifier: String) throws -> InstalledApp {
            InstalledApp(
                url: try directory.directory("root/Applications/\(name).app"),
                bundleIdentifier: identifier,
                name: name
            )
        }

        func service() throws -> TrashService {
            let trash = try directory.directory("home/.Trash")
            return TrashService(environment: environment) { url in
                let destination = trash.appending(path: UUID().uuidString + " " + url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            }
        }

        func cask(installing apps: [InstalledApp]) -> HomebrewPackage {
            HomebrewPackage(
                name: "example",
                kind: .cask,
                installedVersion: "1.0",
                appNames: apps.map(\.url.lastPathComponent),
                appTargets: apps.map { PathPattern.comparablePath(of: $0.url) }
            ).kept(inCaskroom: caskroom)
        }
    }

    @Test func theAppTakesItsHomebrewReceiptAlong() async throws {
        let installed = try Installed()
        let app = try installed.app("Example", identifier: "org.example.app")

        let plan = await Uninstallation.prepare(
            app, installedApps: [app], casks: [installed.cask(installing: [app])], environment: installed.environment
        )

        let row = try #require(plan.scan.leftovers.first { $0.kind == .homebrewReceipt })
        #expect(PathPattern.comparablePath(of: row.url)
            == PathPattern.comparablePath(of: installed.caskroom.appending(path: "example")))
        #expect(row.match.reason == .homebrewReceipt)
        #expect(row.match.isRecommended)
        #expect(plan.suggestedSelection(canUseHelper: false).contains(row.url))
        #expect(plan.removalOrder(of: [row.url, app.url]) == [app.url, row.url])
    }

    @Test func aCaskWhoseOtherAppStaysKeepsItsReceipt() async throws {
        let installed = try Installed()
        let app = try installed.app("Example", identifier: "org.example.app")
        let other = try installed.app("Example Helper", identifier: "org.example.helper")

        let plan = await Uninstallation.prepare(
            app,
            installedApps: [app, other],
            casks: [installed.cask(installing: [app, other])],
            environment: installed.environment
        )

        let row = try #require(plan.scan.leftovers.first { $0.kind == .homebrewReceipt })
        #expect(row.match.sharedWith == ["org.example.helper"])
        #expect(!plan.suggestedSelection(canUseHelper: false).contains(row.url))
    }

    @Test func anAppACasksPackagesWroteTakesItsHomebrewRecordAlong() async throws {
        let installed = try Installed()
        let app = try installed.app("Example", identifier: "org.example.app")
        let other = try installed.app("Example Effects", identifier: "org.example.effects")
        let location = String(PathPattern.comparablePath(of: app.url.deletingLastPathComponent()).dropFirst())
        let pkgutil: PackageReceipts.Pkgutil = { arguments in
            switch arguments {
            case ["--pkgs=org.example.suite.*"]:
                "org.example.suite.pkg\n"
            case ["--pkg-info-plist", "org.example.suite.pkg"]:
                PkgutilAnswer.packageInfo("org.example.suite.pkg", location: location)
            case ["--files", "org.example.suite.pkg", "--only-dirs"]:
                "Example.app\nExample.app/Contents\nExample Effects.app\n"
            default:
                nil
            }
        }
        let patterns = ["org.example.suite.*"]
        let cask = HomebrewPackage(name: "example", kind: .cask, installedVersion: "1.0", packageIdentifiers: patterns)
            .kept(inCaskroom: installed.caskroom)
            .noting(packagedApps: await PackageReceipts.apps(installedByPackagesMatching: patterns, pkgutil: pkgutil))

        #expect(cask.packagedApps == [app.url, other.url].map(PathPattern.comparablePath(of:)).sorted())
        let alone = await Uninstallation.prepare(
            app, installedApps: [app], casks: [cask], environment: installed.environment
        )
        let shared = await Uninstallation.prepare(
            app, installedApps: [app, other], casks: [cask], environment: installed.environment
        )

        #expect(alone.scan.leftovers.first { $0.kind == .homebrewReceipt }?.match.isRecommended == true)
        #expect(shared.scan.leftovers.first { $0.kind == .homebrewReceipt }?.match.sharedWith == ["org.example.effects"])
    }

    /// An installer's script can move the apps its package wrote, so the cask's other apps are found by its proof.
    @Test func anotherAppACaskProvesByItsReceiptKeepsItsHomebrewRecord() async throws {
        let installed = try Installed()
        let app = try installed.app("Synth", identifier: "org.example.synth")
        let other = try installed.app("Synth Effects", identifier: "org.example.effects")
        let cask = HomebrewPackage(
            name: "example",
            kind: .cask,
            installedVersion: "1.0",
            packageIdentifiers: ["org.example.synth.app.pkg", "org.example.effects.app.pkg"]
        ).kept(inCaskroom: installed.caskroom).noting(receipts: ["org.example.synth.app.pkg", "org.example.effects.app.pkg"])

        let plan = await Uninstallation.prepare(
            app, installedApps: [app, other], casks: [cask], environment: installed.environment
        )

        let row = try #require(plan.scan.leftovers.first { $0.kind == .homebrewReceipt })
        #expect(row.match.sharedWith == ["org.example.effects"])
        #expect(!plan.suggestedSelection(canUseHelper: false).contains(row.url))
    }

    @Test func theReceiptGoesToTheTrashAfterTheApp() async throws {
        let installed = try Installed()
        let app = try installed.app("Example", identifier: "org.example.app")
        let plan = await Uninstallation.prepare(
            app, installedApps: [app], casks: [installed.cask(installing: [app])], environment: installed.environment
        )

        let result = await plan.move(plan.suggestedSelection(canUseHelper: false), using: try installed.service())

        #expect(result.failures.isEmpty, "\(result.failures.map(\.reason))")
        #expect(result.trashed.map(\.originalURL.lastPathComponent) == ["Example.app", "example"])
    }

    @Test func aCaskTakesItsReceiptAlongOnlyWithAllItsApps() async throws {
        let installed = try Installed()
        let app = try installed.app("Example", identifier: "org.example.app")
        let other = try installed.app("Example Helper", identifier: "org.example.helper")
        let cask = installed.cask(installing: [app, other])

        let both = await BulkUninstallation.prepare(
            [app, other], installedApps: [app, other], casks: [cask], environment: installed.environment
        )
        let one = await BulkUninstallation.prepare(
            [app], installedApps: [app, other], casks: [cask], environment: installed.environment
        )

        #expect(both.items.first { $0.kind == .homebrewReceipt }?.isRecommended == true)
        #expect(one.items.first { $0.kind == .homebrewReceipt }?.isRecommended == false)
        let result = await both.move(Set(both.items.filter(\.isRecommended).map(\.url)), using: try installed.service())
        #expect(result.failures.isEmpty, "\(result.failures.map(\.reason))")
        #expect(result.trashed.last?.originalURL.lastPathComponent == "example")
    }

    @Test func aLinkIntoTheReceiptGoesWithIt() async throws {
        let installed = try Installed()
        let app = try installed.app("Example", identifier: "org.example.app")
        let wrapper = try installed.directory.file("root/opt/homebrew/Caskroom/example/1.0/.homebrew-command-wrappers/example")
        let bin = try installed.directory.directory("root/opt/homebrew/bin")
        let command = bin.appending(path: "example")
        let elsewhere = bin.appending(path: "tool")
        try FileManager.default.createSymbolicLink(at: command, withDestinationURL: wrapper)
        try FileManager.default.createSymbolicLink(
            at: elsewhere, withDestinationURL: try installed.directory.file("root/opt/homebrew/Cellar/tool/1.0/bin/tool")
        )

        let plan = await Uninstallation.prepare(
            app, installedApps: [app], casks: [installed.cask(installing: [app])], environment: installed.environment
        )

        let link = try #require(plan.scan.leftovers.first {
            $0.url.lastPathComponent == "example" && $0.kind == .commandLineTools
        })
        #expect(link.match.reason == .leadsIntoItsHomebrewReceipt)
        #expect(link.match.isRecommended)
        #expect(!plan.scan.leftovers.contains { $0.url.lastPathComponent == "tool" })
        let result = await plan.move(plan.suggestedSelection(canUseHelper: false), using: try installed.service())
        #expect(result.failures.isEmpty, "\(result.failures.map(\.reason))")
        #expect(result.trashed.first?.originalURL == app.url)
        #expect(Set(result.trashed.map(\.originalURL.lastPathComponent)).isSuperset(of: ["example", "Example.app"]))
    }

    @Test func aLinkIntoASharedReceiptStaysWithIt() async throws {
        let installed = try Installed()
        let app = try installed.app("Example", identifier: "org.example.app")
        let other = try installed.app("Example Helper", identifier: "org.example.helper")
        let wrapper = try installed.directory.file("root/opt/homebrew/Caskroom/example/1.0/.homebrew-command-wrappers/example")
        let command = try installed.directory.directory("root/opt/homebrew/bin").appending(path: "example")
        try FileManager.default.createSymbolicLink(at: command, withDestinationURL: wrapper)

        let plan = await Uninstallation.prepare(
            app,
            installedApps: [app, other],
            casks: [installed.cask(installing: [app, other])],
            environment: installed.environment
        )

        let link = try #require(plan.scan.leftovers.first { $0.match.reason == .leadsIntoItsHomebrewReceipt })
        #expect(link.match.sharedWith == ["org.example.helper"])
        #expect(!plan.suggestedSelection(canUseHelper: false).contains(link.url))
    }
}
