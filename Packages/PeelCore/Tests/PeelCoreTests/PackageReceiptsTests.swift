import Foundation
@testable import PeelCore
import PeelPrivileged
import Synchronization
import Testing

struct PackageReceiptsTests {
    @Test func everyFolderPeelSearchesInTheLibraryIsShared() {
        for folder in LibraryFolder.local + LibraryFolder.plugIns {
            #expect(PackageReceipts.sharedDirectories.contains("/Library/" + folder.rawValue), "\(folder)")
        }
        let plugIns = "Library/Application Support/Avid/Audio/Plug-Ins"
        let files = ["Library", "Library/Application Support", "Library/Application Support/Avid",
                     "Library/Application Support/Avid/Audio", plugIns, "\(plugIns)/SonoBus.aaxplugin",
                     "\(plugIns)/SonoBus.aaxplugin/Contents"]

        let found = PackageReceipts.topLevel(
            files: files, installLocation: "/", namesInside: { _ in [] }, exists: { _ in true }
        )

        #expect(found.offered == ["/\(plugIns)/SonoBus.aaxplugin"])
    }

    @Test func aPackageInstalledIntoAnAppOffersTheApp() {
        let files = ["Contents", "Contents/Info.plist", "Contents/MacOS", "Contents/MacOS/Example"]

        let found = PackageReceipts.topLevel(
            files: files, installLocation: "/Applications/Example.app", namesInside: { _ in nil }, exists: { _ in true }
        )
        let gone = PackageReceipts.topLevel(
            files: files, installLocation: "/Applications/Example.app", namesInside: { _ in nil }, exists: { _ in false }
        )

        #expect(found.offered == ["/Applications/Example.app"])
        #expect(gone.onDisk.isEmpty)
    }

    @Test func keepsOnlyOutermostPackageItems() {
        let files = [
            "Adguard.app", "Adguard.app/Contents", "Adguard.app/Contents/Info.plist",
            "Library", "Library/Application Support", "Library/Application Support/AdGuard Software",
            "Library/Application Support/AdGuard Software/helper",
            "Library/LaunchDaemons", "Library/LaunchDaemons/com.adguard.helper.plist",
            "./usr/local/bin/adguard-cli",
        ]
        let items = PackageReceipts.topLevel(
            files: files,
            installLocation: "/",
            namesInside: { _ in nil },
            exists: { _ in true }
        ).offered
        #expect(items == [
            "/Adguard.app",
            "/Library/Application Support/AdGuard Software",
            "/Library/LaunchDaemons/com.adguard.helper.plist",
            "/usr/local/bin/adguard-cli",
        ])
    }

    /// Two products of one vendor can install into one folder. Only what this package wrote there is offered,
    /// so removing it leaves the other product's files in place.
    @Test func offersOnlyWhatThisPackageWroteInAFolderItShares() {
        let files = [
            "Library/Application Support/Vendor", "Library/Application Support/Vendor/Updater",
            "Library/Application Support/Vendor/Updater/updater", "Library/Application Support/Vendor/shared.db",
        ]
        let inside = [
            "/Library/Application Support/Vendor": ["Updater", "shared.db", "Editor"],
            "/Library/Application Support/Vendor/Updater": ["updater"],
        ]

        let items = PackageReceipts.topLevel(
            files: files,
            installLocation: "/",
            namesInside: { inside[$0] },
            exists: { _ in true }
        ).offered

        #expect(items == ["/Library/Application Support/Vendor/Updater", "/Library/Application Support/Vendor/shared.db"].sorted())
    }

    /// An app that updated itself does not match its receipt file by file, but it is still offered whole, never
    /// as its parts.
    @Test func keepsABundleWholeHoweverItsContentsChanged() {
        let files = ["Applications/Example.app", "Applications/Example.app/Contents"]
        let inside = ["/Applications/Example.app": ["Contents", "Updated"]]

        let items = PackageReceipts.topLevel(
            files: files,
            installLocation: "/",
            namesInside: { inside[$0] },
            exists: { _ in true }
        ).offered

        #expect(items == ["/Applications/Example.app"])
    }

    @Test func offersAFolderWholeOnlyWhenNothingInsideItAtAnyDepthIsAnotherOnes() {
        let support = "/Library/Application Support"
        let tree: [String: [String]] = [
            "\(support)/ZeroTier": ["One"],
            "\(support)/ZeroTier/One": ["zerotier-one", "uninstall.sh", "identity.secret"],
            "\(support)/org.pqrs": ["Karabiner-DriverKit-VirtualHIDDevice", "config", "tmp"],
            "\(support)/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice": ["scripts"],
            "\(support)/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/scripts": ["uninstall.sh"],
            "\(support)/Logitech.localized": ["LogiOptionsPlus", "LogiRightSightForWebcams"],
            "\(support)/Logitech.localized/LogiRightSightForWebcams": ["agent"],
            "\(support)/Vendor": ["Product"],
            "\(support)/Vendor/Product": ["Resources"],
            "\(support)/Vendor/Product/Resources": ["data.bin"],
        ]
        let files = [
            "ZeroTier", "ZeroTier/One", "ZeroTier/One/zerotier-one", "ZeroTier/One/uninstall.sh",
            "org.pqrs", "org.pqrs/Karabiner-DriverKit-VirtualHIDDevice",
            "org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/scripts",
            "org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/scripts/uninstall.sh",
            "Logitech.localized", "Logitech.localized/LogiRightSightForWebcams",
            "Logitech.localized/LogiRightSightForWebcams/agent",
            "Vendor", "Vendor/Product", "Vendor/Product/Resources", "Vendor/Product/Resources/data.bin",
        ]

        let found = PackageReceipts.topLevel(
            files: files,
            installLocation: support,
            namesInside: { tree[$0] },
            exists: { path in tree[path] != nil || files.contains { "\(support)/\($0)" == path } }
        )

        #expect(found.offered == [
            "\(support)/Logitech.localized/LogiRightSightForWebcams", "\(support)/Vendor",
            "\(support)/ZeroTier/One/uninstall.sh", "\(support)/ZeroTier/One/zerotier-one",
            "\(support)/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice",
        ])
        #expect(found.othersFilled.isEmpty)
    }

    @Test func offersALinkThePackageInstalledAsOneItemWithoutLookingThrough() throws {
        let directory = try TemporaryDirectory()
        let root = directory.url.path(percentEncoded: false)
        try directory.file("Library/Application Support/Vendor/Versions/2/tool", bytes: 16)
        try directory.file("Library/Application Support/Vendor/Versions/2/settings.json", bytes: 16)
        try FileManager.default.createSymbolicLink(
            atPath: "\(root)/Library/Application Support/Vendor/Current", withDestinationPath: "Versions/2"
        )
        let files = [
            "Library/Application Support/Vendor", "Library/Application Support/Vendor/Current",
            "Library/Application Support/Vendor/Versions", "Library/Application Support/Vendor/Versions/2",
            "Library/Application Support/Vendor/Versions/2/tool",
            "Library/Application Support/Vendor/Versions/2/settings.json",
        ]

        let found = PackageReceipts.topLevel(files: files, installLocation: root)

        #expect(found.offered.map { ($0 as NSString).lastPathComponent } == ["Vendor"])
        #expect(found.othersFilled.isEmpty)
    }

    @Test func resolvesPathsAgainstTheInstallLocationAndSkipsMissingFiles() {
        let files = ["Example.app", "Example.app/Contents", "Gone.app"]
        let items = PackageReceipts.topLevel(files: files, installLocation: "/Applications", exists: { $0 != "/Applications/Gone.app" }).offered
        #expect(items == ["/Applications/Example.app"])
    }

    @Test func neverReturnsSharedDirectories() {
        let files = ["Applications", "Library", "Library/Fonts", "usr", "usr/local", "usr/local/lib"]
        #expect(PackageReceipts.topLevel(files: files, installLocation: "/", exists: { _ in true }).offered.isEmpty)
    }

    /// What may exist nowhere else is left for the person to choose, with its reason: a folder the package made
    /// that now holds a repository, a wallet, or what something else put there, and anything in `/Users/Shared`.
    @Test func leavesToThePersonWhatAReceiptsFolderHolds() async throws {
        let directory = try TemporaryDirectory()
        let volume = PathPattern.canonical(directory.url)
        try directory.file("Library/Application Support/Vendor Repo/.git/HEAD", bytes: 16)
        try directory.file("Library/Application Support/Vendor Coin/wallet.dat", bytes: 16)
        try directory.file("Library/Application Support/Vendor Plain/data.db", bytes: 16)
        try directory.file("Library/Application Support/Vendor Shared/Other.component/plugin", bytes: 16)
        try directory.file("Users/Shared/StudioSync/project.txt", bytes: 16)
        let locations = ["com.example.vendor": "Library/Application Support", "com.example.studio": "Users/Shared"]
        let files = [
            "com.example.vendor": "Vendor Repo\nVendor Coin\nVendor Plain\nVendor Plain/data.db\nVendor Shared\n",
            "com.example.studio": "StudioSync\n",
        ]
        let pkgutil: PackageReceipts.Pkgutil = { arguments in
            switch arguments.first {
            case "--pkgs-plist":
                return PkgutilAnswer.packages("com.example.studio", "com.example.vendor")
            case "--pkg-info-plist":
                let info = ["volume": volume.path(percentEncoded: false), "install-location": locations[arguments[1]] ?? ""]
                let data = try? PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                return data.flatMap { String(data: $0, encoding: .utf8) }
            case "--files":
                return files[arguments[1]]
            default:
                return nil
            }
        }
        let environment = SearchEnvironment(homeDirectory: volume.appending(path: "home"), rootDirectory: volume)

        let scan = await PackageReceipts.list(exclusions: .none, pkgutil: pkgutil, environment: environment)

        let reasons = scan.receipts.flatMap(\.items).map { "\($0.url.lastPathComponent): \($0.heldBack.map(\.rawValue) ?? "none")" }
        #expect(reasons.sorted() == [
            "StudioSync: sharedWithEveryone", "Vendor Coin: holdsAWallet", "Vendor Plain: none", "Vendor Repo: holdsRepository",
            "Vendor Shared: holdsWhatOthersPut",
        ])
    }

    @Test func offersOnlyWhatThePackageWroteInFoldersOthersWroteInToo() async throws {
        let directory = try TemporaryDirectory()
        let volume = PathPattern.canonical(directory.url)
        try directory.file("Library/Application Support/Vendor Node/One/vendor-node", bytes: 16)
        try directory.file("Library/Application Support/Vendor Node/One/identity.secret", bytes: 16)
        try directory.file("Library/Application Support/org.example/Driver/driver.sh", bytes: 16)
        try directory.file("Library/Application Support/org.example/config/profile.json", bytes: 16)
        try directory.file("Library/Application Support/Example.plugin/Contents/Info.plist", bytes: 16)
        try directory.file("Library/Application Support/Example.plugin/Contents/Updated", bytes: 16)
        let listing = [
            "Vendor Node", "Vendor Node/One", "Vendor Node/One/vendor-node",
            "org.example", "org.example/Driver", "org.example/Driver/driver.sh",
            "Example.plugin", "Example.plugin/Contents", "Example.plugin/Contents/Info.plist",
        ].joined(separator: "\n")
        let pkgutil: PackageReceipts.Pkgutil = { arguments in
            switch arguments.first {
            case "--pkgs-plist":
                return PkgutilAnswer.packages("com.example.node")
            case "--pkg-info-plist":
                let info = ["volume": volume.path(percentEncoded: false), "install-location": "Library/Application Support"]
                let data = try? PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                return data.flatMap { String(data: $0, encoding: .utf8) }
            case "--files":
                return listing
            default:
                return nil
            }
        }
        let environment = SearchEnvironment(homeDirectory: volume.appending(path: "home"), rootDirectory: volume)

        let scan = await PackageReceipts.list(exclusions: .none, pkgutil: pkgutil, environment: environment)

        let items = scan.receipts.flatMap(\.items).map {
            $0.url.path(percentEncoded: false).components(separatedBy: "Library/Application Support/").last ?? ""
        }
        #expect(items.sorted() == ["Example.plugin", "Vendor Node/One/vendor-node", "org.example/Driver"])
    }

    @Test func aStoppedListStops() async throws {
        let directory = try TemporaryDirectory()
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home"), rootDirectory: directory.url
        )
        let unanswered = Unanswered()
        let packages = PkgutilAnswer.packages(
            "org.example.one", "org.example.two", "org.example.three", "org.example.four", "org.example.five",
            "org.example.six", "org.example.seven", "org.example.eight", "org.example.nine", "org.example.ten"
        )
        let pkgutil: PackageReceipts.Pkgutil = { arguments in
            if arguments.first == "--pkgs-plist" { return packages }
            return await unanswered.pkgutil(arguments)
        }

        let stop = try await unanswered.stop {
            _ = await PackageReceipts.list(exclusions: .none, pkgutil: pkgutil, environment: environment)
        }

        #expect(stop.took < .seconds(1))
        #expect(stop.askedBefore < 10)
        #expect(stop.askedAfter == 0)
    }

    @Test func aPackageWhoseScriptsPlaceItsFilesIsNeverReceiptOnly() async throws {
        let directory = try TemporaryDirectory()
        let volume = PathPattern.canonical(directory.url)
        try directory.file("Applications/Mixer.app/Contents/Info.plist", bytes: 16)
        let locations = ["org.example.mixer": "tmp/MXR", "org.example.mixer.scripts": "", "org.example.gone": "Applications"]
        let listings = [
            "org.example.mixer": "Mixer.app\nMixer.app/Contents\nMixer.app/Contents/Info.plist",
            "org.example.mixer.scripts": "",
            "org.example.gone": "Gone.app\nGone.app/Contents",
        ]
        let pkgutil: PackageReceipts.Pkgutil = { arguments in
            switch arguments.first {
            case "--pkgs-plist":
                return PkgutilAnswer.packages("org.example.gone", "org.example.mixer", "org.example.mixer.scripts")
            case "--pkg-info-plist":
                let info = ["volume": volume.path(percentEncoded: false), "install-location": locations[arguments[1]] ?? ""]
                let data = try? PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                return data.flatMap { String(data: $0, encoding: .utf8) }
            case "--files":
                return listings[arguments[1]]
            default:
                return nil
            }
        }
        let environment = SearchEnvironment(homeDirectory: volume.appending(path: "home"), rootDirectory: volume)

        let scan = await PackageReceipts.list(exclusions: .none, pkgutil: pkgutil, environment: environment)
        let receipts = scan.receipts

        let byScripts = receipts.filter { $0.identifier.hasPrefix("org.example.mixer") }
        #expect(byScripts.count == 2)
        #expect(byScripts.allSatisfy { $0.installedThroughItsScripts && !$0.nothingLeftOnDisk })
        let gone = try #require(receipts.first { $0.identifier == "org.example.gone" })
        #expect(gone.nothingLeftOnDisk && !gone.installedThroughItsScripts)
    }

    @Test func aPackageWhoseAppIsStillThereNamesIt() async throws {
        let directory = try TemporaryDirectory()
        let volume = PathPattern.canonical(directory.url)
        let info = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "org.example.mixer", "CFBundleName": "Mixer"], format: .xml, options: 0
        )
        try directory.file("Applications/Mixer.app/Contents/Info.plist", contents: info)
        let pkgutil: PackageReceipts.Pkgutil = { arguments in
            switch arguments.first {
            case "--pkgs-plist":
                return PkgutilAnswer.packages("org.example.gone.pkg", "org.example.mixer.pkg")
            case "--pkg-info-plist":
                let info = ["volume": volume.path(percentEncoded: false), "install-location": "Applications"]
                let data = try? PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                return data.flatMap { String(data: $0, encoding: .utf8) }
            case "--files":
                return arguments[1] == "org.example.mixer.pkg"
                    ? "Mixer.app\nMixer.app/Contents\nMixer.app/Contents/Info.plist" : "Gone.app"
            default:
                return nil
            }
        }
        let environment = SearchEnvironment(homeDirectory: volume.appending(path: "home"), rootDirectory: volume)

        let scan = await PackageReceipts.list(exclusions: .none, pkgutil: pkgutil, environment: environment)

        #expect(scan.receipts.first { $0.identifier == "org.example.mixer.pkg" }?.installedApps == ["Mixer"])
        #expect(scan.receipts.first { $0.identifier == "org.example.gone.pkg" }?.installedApps == [])

        let excluding = Exclusions(bundleIdentifiers: ["org.example.mixer"])
        let kept = await PackageReceipts.list(exclusions: excluding, pkgutil: pkgutil, environment: environment)
        let mixer = try #require(kept.receipts.first { $0.identifier == "org.example.mixer.pkg" })
        #expect(mixer.apps.contains(where: excluding.excludes))
        try directory.file("private/var/db/receipts/org.example.mixer.pkg.bom", bytes: 16)
        try directory.file("private/var/db/receipts/org.example.mixer.pkg.plist", bytes: 16)
        let forgotten = await PackageActions.forget(mixer, exclusions: excluding)
        #expect(forgotten.trashed.isEmpty)
        #expect(forgotten.failures.map(\.reason) == [.guarded(.excluded), .guarded(.excluded)])

        // Read before the app was excluded, and forgotten after: the question can outlive the scan it came from.
        let readBefore = try #require(scan.receipts.first { $0.identifier == "org.example.mixer.pkg" })
        let moved = Mutex<[URL]>([])
        let service = TrashService(
            environment: environment, exclusions: excluding,
            moveThroughHelper: { urls in
                moved.withLock { $0 += urls }
                return TrashResult(trashed: urls.map { TrashedItem(originalURL: $0, trashedURL: $0, date: .now) })
            },
            moveToTrash: { _ in throw CocoaError(.fileWriteNoPermission) }
        )
        let late = await PackageActions.forget([readBefore], through: service)
        #expect(moved.withLock { $0 }.isEmpty)
        #expect(late.failures.map(\.reason) == [.guarded(.excluded), .guarded(.excluded)])
    }

    @Test func namesAPackageAsMacOSsInstallHistoryDoes() throws {
        let directory = try TemporaryDirectory()
        let history: [[String: Any]] = [
            ["displayName": "Mixer 1", "date": Date(timeIntervalSince1970: 1_000), "packageIdentifiers": ["org.example.mixer.pkg"]],
            ["displayName": "Mixer", "date": Date(timeIntervalSince1970: 2_000), "packageIdentifiers": ["org.example.mixer.pkg"]],
            ["displayName": "macOS 26.7.1", "date": Date(timeIntervalSince1970: 3_000)],
            ["displayName": "", "date": Date(timeIntervalSince1970: 4_000), "packageIdentifiers": ["org.example.blank.pkg"]],
        ]
        try directory.file(
            "Library/Receipts/InstallHistory.plist",
            contents: PropertyListSerialization.data(fromPropertyList: history, format: .xml, options: 0)
        )

        #expect(InstallHistory.names(onVolume: directory.url) == ["org.example.mixer.pkg": "Mixer"])
        #expect(InstallHistory.names(onVolume: directory.url.appending(path: "nowhere")).isEmpty)

        var receipt = PackageReceipt(
            identifier: "org.example.mixer.pkg", version: nil, installDate: nil, volume: directory.url,
            items: [PackageReceipt.Item(url: URL(filePath: "/Library/Application Support/Soundworks/Mixer"), size: 1, requiresPrivileges: false)],
            nothingLeftOnDisk: false
        )
        receipt.name = "Tunewell"
        #expect(receipt.matches("mixer.pkg"))
        #expect(receipt.matches("Tunewell"), "the name macOS gave it")
        #expect(receipt.matches("Soundworks"), "where its files are")
        #expect(!receipt.matches("Logitech"))
    }

    @Test func leavesAnAppToFinderWhenMacOSInstalledItsSystemExtension() async throws {
        let directory = try TemporaryDirectory()
        let volume = PathPattern.canonical(directory.url)
        func info(_ identifier: String, _ name: String) throws -> Data {
            try PropertyListSerialization.data(
                fromPropertyList: ["CFBundleIdentifier": identifier, "CFBundleName": name], format: .xml, options: 0
            )
        }
        try directory.file("Applications/Guard.app/Contents/Info.plist", contents: info("org.example.guard", "Guard"))
        try directory.file(
            "Applications/Guard.app/Contents/Library/SystemExtensions/org.example.guard.filter.systemextension/Contents/Info.plist",
            contents: info("org.example.guard.filter", "Guard Filter")
        )
        try directory.file("Applications/Plain.app/Contents/Info.plist", contents: info("org.example.plain", "Plain"))
        let pkgutil: PackageReceipts.Pkgutil = { arguments in
            switch arguments.first {
            case "--pkgs-plist":
                return PkgutilAnswer.packages("org.example.guard.pkg")
            case "--pkg-info-plist":
                let info = ["volume": volume.path(percentEncoded: false), "install-location": "Applications"]
                let data = try? PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                return data.flatMap { String(data: $0, encoding: .utf8) }
            case "--files":
                return "Guard.app\nPlain.app\n"
            default:
                return nil
            }
        }
        let filter = AppExtension(
            identifier: "org.example.guard.filter", name: "Guard Filter", kind: .systemExtension, point: nil, owner: nil,
            url: nil, election: .on, teamIdentifier: nil, reportedState: nil
        )
        let environment = SearchEnvironment(homeDirectory: volume.appending(path: "home"), rootDirectory: volume)

        let scan = await PackageReceipts.list(
            exclusions: .none, pkgutil: pkgutil, environment: environment, systemExtensions: { [filter] }
        )

        let items = Dictionary(
            uniqueKeysWithValues: scan.receipts.flatMap(\.items).map { ($0.url.lastPathComponent, $0) }
        )
        #expect(items["Guard.app"]?.removedElsewhere == .byFinder(systemExtensions: CarriedSystemExtensions(names: ["Guard Filter"])))
        #expect(items["Guard.app"]?.isLeftAlone == true)
        #expect(items["Plain.app"]?.removedElsewhere == nil)
        #expect(items["Plain.app"]?.isLeftAlone == false)
    }

    @Test func leavesTheRestOfAPackageToWhatRemovesItsApp() async throws {
        let directory = try TemporaryDirectory()
        let volume = PathPattern.canonical(directory.url)
        let plist = { (object: [String: Any]) in
            try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
        }
        try directory.file(
            "Applications/Guard.app/Contents/Info.plist",
            contents: plist(["CFBundleIdentifier": "org.example.guard", "CFBundleName": "Guard"])
        )
        try directory.file(
            "Applications/Guard.app/Contents/Library/SystemExtensions/org.example.guard.filter.systemextension/Contents/Info.plist",
            contents: plist(["CFBundleIdentifier": "org.example.guard.filter", "CFBundleName": "Guard Filter"])
        )
        try directory.file("Library/Application Support/Guard/rules.json", bytes: 16)
        let workspace = "Applications/Citrix Workspace.app"
        try directory.file(
            "\(workspace)/Contents/Info.plist",
            contents: plist(["CFBundleIdentifier": "com.citrix.receiver.nomas", "CFBundleName": "Citrix Workspace"])
        )
        let uninstaller = "Library/Citrix Workspace/Uninstaller/Uninstall Citrix Workspace"
        try directory.file(uninstaller)
        try directory.setPermissions(0o755, of: uninstaller)
        try directory.file("Library/LaunchAgents/com.citrix.UninstallMonitor.plist", contents: plist([
            "Label": "com.citrix.UninstallMonitor",
            "ProgramArguments": [volume.appending(path: uninstaller).path(percentEncoded: false)],
            "WatchPaths": [volume.appending(path: workspace).path(percentEncoded: false)],
        ]))
        try directory.file("Library/Application Support/Citrix Receiver/config.xml", bytes: 16)
        try directory.file("Library/Application Support/Citrix Extra/notes.txt", bytes: 16)
        try directory.file("Library/Application Support/ZeroTier/One/zerotier-one", bytes: 16)
        try directory.file("Library/Application Support/ZeroTier/One/identity.secret", bytes: 16)
        let files = [
            "org.example.guard.pkg": [
                "Applications/Guard.app", "Library/Application Support/Guard",
                "Library/Application Support/Guard/rules.json",
            ],
            "com.citrix.ICAClient": [
                workspace, "Library/Application Support/Citrix Receiver",
                "Library/Application Support/Citrix Receiver/config.xml", "Library/Application Support/Citrix Extra",
                "Library/Application Support/Citrix Extra/notes.txt",
            ],
            "com.zerotier.pkg.ZeroTierOne": [
                "Library/Application Support/ZeroTier", "Library/Application Support/ZeroTier/One",
                "Library/Application Support/ZeroTier/One/zerotier-one",
            ],
        ]
        let pkgutil: PackageReceipts.Pkgutil = { arguments in
            switch arguments.first {
            case "--pkgs-plist":
                return PkgutilAnswer.packages("com.citrix.ICAClient", "com.zerotier.pkg.ZeroTierOne", "org.example.guard.pkg")
            case "--pkg-info-plist":
                let info = ["volume": volume.path(percentEncoded: false), "install-location": "/"]
                let data = try? PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                return data.flatMap { String(data: $0, encoding: .utf8) }
            case "--files":
                return files[arguments[1]]?.joined(separator: "\n")
            default:
                return nil
            }
        }
        let filter = AppExtension(
            identifier: "org.example.guard.filter", name: "Guard Filter", kind: .systemExtension, point: nil, owner: nil,
            url: nil, election: .on, teamIdentifier: nil, reportedState: nil
        )
        let environment = SearchEnvironment(homeDirectory: volume.appending(path: "home"), rootDirectory: volume)

        let scan = await PackageReceipts.list(
            exclusions: .none, pkgutil: pkgutil, environment: environment, systemExtensions: { [filter] }
        )

        let items = Dictionary(
            uniqueKeysWithValues: scan.receipts.flatMap(\.items).map { ($0.url.lastPathComponent, $0) }
        )
        let finder = RemovedElsewhere.byFinder(systemExtensions: CarriedSystemExtensions(names: ["Guard Filter"]))
        #expect(items["Guard"]?.removedElsewhere == finder)
        #expect(items["Guard"]?.isLeftAlone == true)
        #expect(items["Citrix Receiver"]?.heldBack == .leftToItsUninstaller)
        #expect(items["Citrix Extra"]?.heldBack == nil)
        #expect(items["Citrix Workspace.app"]?.uninstallsItself?.uninstaller == .deletesTheApp)
        #expect(items["Citrix Extra"]?.uninstallsItself == nil)
        #expect(items["zerotier-one"]?.heldBack == .holdsVPNConnections)
    }

    /// A receipt's file list leaves out the install prefix, such as `Applications`, so the path is asked about again
    /// without its leading folders, and the answer is believed only if the receipt really installed that path.
    @Test func findsThePackageThatInstalledAnAppUnderAnInstallPrefix() async throws {
        let directory = try TemporaryDirectory()
        let volume = PathPattern.canonical(directory.url).path(percentEncoded: false)
        let app = PathPattern.canonical(try directory.directory("Applications/Example.app"))
        let info = try #require(String(
            data: PropertyListSerialization.data(fromPropertyList: ["volume": volume, "install-location": "Applications"], format: .xml, options: 0),
            encoding: .utf8
        ))
        let asked = Mutex<[String]>([])
        let pkgutil: PackageReceipts.Pkgutil = { arguments in
            if arguments.first == "--file-info-plist" {
                asked.withLock { $0.append(arguments[1]) }
                // Answers only for the path as the receipt lists it: the app without the install prefix.
                return arguments[1] == "/Example.app"
                    ? PkgutilAnswer.fileInfo(arguments[1], packages: "com.example.pkg")
                    : PkgutilAnswer.fileInfo(arguments[1])
            }
            return switch arguments.first {
            case "--pkg-info-plist": info
            case "--files": "Example.app\nExample.app/Contents\n"
            default: ""
            }
        }

        let found = await PackageReceipts.receipts(installing: app, exclusions: .none, pkgutil: pkgutil)

        #expect(found.map(\.identifier) == ["com.example.pkg"])
        #expect(asked.withLock { $0 }.first == PathPattern.comparablePath(of: app), "the real path is asked about first")
    }

    @Test func findsAPackageInstalledIntoTheAppItself() async throws {
        let directory = try TemporaryDirectory()
        let volume = PathPattern.canonical(directory.url).path(percentEncoded: false)
        let app = PathPattern.canonical(try directory.directory("Applications/Example.app"))
        try directory.file("Applications/Example.app/Contents/Info.plist", bytes: 16)
        // As `pkgutil` matches a path: literally, against the file list relative to the install location.
        let pkgutil: PackageReceipts.Pkgutil = { arguments in
            switch arguments.first {
            case "--file-info-plist": arguments[1] == "/Contents/Info.plist"
                ? PkgutilAnswer.fileInfo(arguments[1], packages: "org.example.inside", "org.example.other")
                : PkgutilAnswer.fileInfo(arguments[1])
            case "--pkg-info-plist": PkgutilAnswer.packageInfo(
                arguments[1], volume: volume,
                location: arguments[1] == "org.example.other" ? "Applications/Other.app" : "Applications/Example.app"
            )
            case "--files": "Contents\nContents/Info.plist\n"
            default: nil
            }
        }

        let found = await PackageReceipts.receipts(installing: app, exclusions: .none, pkgutil: pkgutil)
        let wroteOnlyTheApp = await PackageReceipts.receipts(writingOnly: app, pkgutil: pkgutil)

        #expect(found.map(\.identifier) == ["org.example.inside"])
        let items = found.first?.items.map { PathPattern.comparablePath(of: $0.url) }
        #expect(items == [PathPattern.comparablePath(of: app)])
        #expect(wroteOnlyTheApp == ["org.example.inside"])
    }

    /// A link the package installed is on the disk even when what it leads to is gone, so the package is not
    /// "Receipt only": `fileExists` follows the link and would call it missing.
    @Test func aDanglingLinkThePackageInstalledIsStillThere() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("usr/local/bin")
        try FileManager.default.createSymbolicLink(
            atPath: directory.url.appending(path: "usr/local/bin/tool").path(percentEncoded: false),
            withDestinationPath: "/nonexistent/peel-test/tool"
        )

        let found = PackageReceipts.topLevel(files: ["usr/local/bin/tool"], installLocation: directory.url.path(percentEncoded: false))

        #expect(found.onDisk.map { ($0 as NSString).lastPathComponent } == ["tool"], "a link whose target is gone was read as removed")
    }

    /// When `pkgutil` does not say what a package installed, nothing is known about what is left, so the list must
    /// not say that nothing of it can be moved. And a package whose details `pkgutil` does not give stays listed,
    /// with its file list unknown, rather than vanishing from the page.
    @Test func aPackageKnownOnlyByNameStaysListedAndUnknown() async throws {
        let pkgutil: PackageReceipts.Pkgutil = { arguments in
            switch arguments.first {
            case "--pkgs-plist": PkgutilAnswer.packages("com.example.quiet")
            default: nil
            }
        }

        let receipt = try #require(await PackageReceipts.list(exclusions: .none, pkgutil: pkgutil).receipts.first, "the package vanished")

        #expect(receipt.identifier == "com.example.quiet")
        #expect(!receipt.isFileListKnown)
        #expect(!receipt.holdsNothingToRemove, "an unknown file list read as \"Nothing Peel moves\"")
        #expect(!receipt.movable(canUseHelper: true).isComplete, "an unknown file list read as a size of zero")
    }

    /// A `pkgid` found that way says only that some package lists a path ending like this one.
    @Test func believesNoPackageThatDidNotInstallThatPath() async throws {
        let directory = try TemporaryDirectory()
        let volume = PathPattern.canonical(directory.url).path(percentEncoded: false)
        let app = PathPattern.canonical(try directory.directory("Applications/Example.app"))
        try directory.directory("Example.app")
        let info = try #require(String(
            data: PropertyListSerialization.data(fromPropertyList: ["volume": volume, "install-location": ""], format: .xml, options: 0),
            encoding: .utf8
        ))
        let pkgutil: PackageReceipts.Pkgutil = { arguments in
            switch arguments.first {
            // The package installed an app of the same name elsewhere, not the one asked about.
            case "--file-info-plist": arguments[1] == "/Example.app"
                ? PkgutilAnswer.fileInfo(arguments[1], packages: "com.example.pkg")
                : PkgutilAnswer.fileInfo(arguments[1])
            case "--pkg-info-plist": info
            case "--files": "Example.app\n"
            default: ""
            }
        }

        #expect(await PackageReceipts.receipts(installing: app, exclusions: .none, pkgutil: pkgutil).isEmpty)
    }

    /// A receipt says the package installed a link. What the link leads to is somebody else's file.
    @Test func offersTheLinkThePackageInstalledAndNotWhatItLeadsTo() async throws {
        let directory = try TemporaryDirectory()
        let volume = PathPattern.canonical(directory.url).path(percentEncoded: false)
        let real = try directory.file("Library/Frameworks/Example.framework/tool")
        try directory.directory("usr/local/bin")
        for name in ["tool", "tool3"] {
            try FileManager.default.createSymbolicLink(
                at: directory.url.appending(path: "usr/local/bin/" + name),
                withDestinationURL: real
            )
        }
        let info = try #require(String(
            data: PropertyListSerialization.data(fromPropertyList: ["volume": volume, "install-location": ""], format: .xml, options: 0),
            encoding: .utf8
        ))
        let pkgutil: PackageReceipts.Pkgutil = { arguments in
            switch arguments.first {
            case "--pkgs-plist": PkgutilAnswer.packages("com.example.pkg")
            case "--pkg-info-plist": info
            case "--files": "usr/local/bin/tool\nusr/local/bin/tool3\n"
            default: ""
            }
        }
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home"),
            rootDirectory: directory.url.appending(path: "root")
        )

        let receipt = try #require(
            await PackageReceipts.list(exclusions: .none, pkgutil: pkgutil, environment: environment).receipts.first
        )

        #expect(receipt.items.map(\.url.lastPathComponent) == ["tool", "tool3"])
        #expect(Set(receipt.items.map(\.id)).count == 2)
        #expect(!receipt.items.contains { $0.url.path(percentEncoded: false).contains("Frameworks") })
    }

    /// When `pkgutil` fails, nothing is known about what is installed, so "No Installer Packages" would be wrong.
    @Test func tellsNothingInstalledFromNoAnswerAtAll() async {
        let silent = await PackageReceipts.list(exclusions: .none, pkgutil: { _ in nil })
        #expect(silent.couldNotAsk)
        #expect(silent.receipts.isEmpty)

        let empty = await PackageReceipts.list(exclusions: .none, pkgutil: { _ in PkgutilAnswer.packages() })
        #expect(!empty.couldNotAsk)
        #expect(empty.receipts.isEmpty)
    }

    /// An answer that is not the property list `pkgutil` prints says nothing about what is installed.
    @Test func anAnswerInAnotherFormIsNoAnswer() async {
        let error: PackageReceipts.Pkgutil = { _ in "Error: the receipts could not be read.\n" }
        let scan = await PackageReceipts.list(exclusions: .none, pkgutil: error)

        #expect(scan.couldNotAsk)
        #expect(scan.receipts.isEmpty)
        #expect(PackageReceipts.packageList(in: "com.example.pkg\n") == nil)
        #expect(PackageReceipts.packageList(in: PkgutilAnswer.packages("com.example.pkg")) == ["com.example.pkg"])
    }

    /// "Receipt only" is a fact about the disk. Hiding an item behind an exclusion does not make it true.
    @Test func doesNotCallAPackageForgottenBecauseItsItemsWereFilteredOut() async throws {
        let directory = try TemporaryDirectory()
        let volume = PathPattern.canonical(directory.url).path(percentEncoded: false)
        let app = PathPattern.canonical(try directory.directory("Applications/Example.app"))
        let info = try #require(String(
            data: PropertyListSerialization.data(fromPropertyList: ["volume": volume, "install-location": ""], format: .xml, options: 0),
            encoding: .utf8
        ))
        let pkgutil: PackageReceipts.Pkgutil = { arguments in
            switch arguments.first {
            case "--pkgs-plist": PkgutilAnswer.packages("com.example.pkg")
            case "--pkg-info-plist": info
            case "--files": "Applications/Example.app\n"
            default: ""
            }
        }
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home"),
            rootDirectory: directory.url.appending(path: "root")
        )

        let excluded = try #require(
            await PackageReceipts.list(exclusions: Exclusions(paths: [app]), pkgutil: pkgutil, environment: environment)
                .receipts.first
        )
        #expect(excluded.items.isEmpty)
        #expect(!excluded.nothingLeftOnDisk)

        try FileManager.default.removeItem(at: app)
        let gone = try #require(
            await PackageReceipts.list(exclusions: .none, pkgutil: pkgutil, environment: environment).receipts.first
        )
        #expect(gone.nothingLeftOnDisk)
    }

    /// When `pkgutil --files` fails or runs out of time, the file list is unknown. That is not a package with
    /// nothing left on disk, so it must not get the "Receipt only" badge.
    @Test func aFileListThatDidNotComeIsNotAPackageWithNothingLeft() async throws {
        let directory = try TemporaryDirectory()
        let volume = PathPattern.canonical(directory.url).path(percentEncoded: false)
        let info = try #require(String(
            data: PropertyListSerialization.data(fromPropertyList: ["volume": volume, "install-location": ""], format: .xml, options: 0),
            encoding: .utf8
        ))
        let pkgutil: PackageReceipts.Pkgutil = { arguments in
            switch arguments.first {
            case "--pkgs-plist": PkgutilAnswer.packages("com.example.pkg")
            case "--pkg-info-plist": info
            default: nil
            }
        }
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home"),
            rootDirectory: directory.url.appending(path: "root")
        )

        let receipt = try #require(
            await PackageReceipts.list(exclusions: .none, pkgutil: pkgutil, environment: environment).receipts.first
        )

        #expect(!receipt.isFileListKnown)
        #expect(!receipt.nothingLeftOnDisk)
        #expect(receipt.items.isEmpty)
    }

    /// A receipt can name a path `RemovalGuard` refuses, such as a file in `/usr/local/bin` or one inside Mail.
    /// Such an item is listed and left alone, rather than offered and then refused at the move.
    @Test func leavesAloneWhatTheGuardWouldRefuse() async throws {
        let directory = try TemporaryDirectory()
        let volume = PathPattern.canonical(directory.url).path(percentEncoded: false)
        let app = PathPattern.canonical(try directory.directory("Applications/Example.app"))
        let rules = PathPattern.canonical(try directory.directory("home/Library/Mail/V10/MailData/Example"))
        let info = try #require(String(
            data: PropertyListSerialization.data(fromPropertyList: ["volume": volume, "install-location": ""], format: .xml, options: 0),
            encoding: .utf8
        ))
        let pkgutil: PackageReceipts.Pkgutil = { arguments in
            switch arguments.first {
            case "--pkgs-plist": PkgutilAnswer.packages("com.example.pkg")
            case "--pkg-info-plist": info
            case "--files": "Applications/Example.app\nhome/Library/Mail/V10/MailData/Example\n"
            default: ""
            }
        }
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home"),
            rootDirectory: directory.url.appending(path: "root")
        )

        let receipt = try #require(
            await PackageReceipts.list(exclusions: .none, pkgutil: pkgutil, environment: environment).receipts.first
        )

        #expect(receipt.items.first { $0.url == app }?.isLeftAlone == false)
        #expect(receipt.items.first { $0.url == rules }?.isLeftAlone == true)
        #expect(receipt.items.first { $0.url == rules }?.refusal == .protectedLocation)
    }

    /// An item that needs an administrator is left alone when the helper would refuse it. The helper refuses
    /// items outside the folders it serves, anything in `/Applications` that is not an app, and, in a folder
    /// command-line tools are linked into, anything but a link that leads nowhere.
    @Test func leavesAloneASignInPlugIn() async throws {
        let directory = try TemporaryDirectory()
        let volume = PathPattern.canonical(directory.url)
        let plugIn = PathPattern.canonical(try directory.directory("Library/Security/SecurityAgentPlugins/Example.bundle"))
        let settings = PathPattern.canonical(try directory.directory("Library/Application Support/Example"))
        let info = try #require(String(
            data: PropertyListSerialization.data(
                fromPropertyList: ["volume": volume.path(percentEncoded: false), "install-location": ""],
                format: .xml, options: 0
            ),
            encoding: .utf8
        ))
        let pkgutil: PackageReceipts.Pkgutil = { arguments in
            switch arguments.first {
            case "--pkgs-plist": PkgutilAnswer.packages("com.example.pkg")
            case "--pkg-info-plist": info
            case "--files": "Library/Security/SecurityAgentPlugins/Example.bundle\nLibrary/Application Support/Example\n"
            default: ""
            }
        }
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home"),
            rootDirectory: directory.url.appending(path: "root")
        )

        let receipt = try #require(
            await PackageReceipts.list(exclusions: .none, pkgutil: pkgutil, environment: environment).receipts.first
        )

        #expect(receipt.items.first { $0.url == plugIn }?.heldBack == .signInPlugIn)
        #expect(receipt.items.first { $0.url == settings }?.heldBack == nil)
    }

    @Test(.permissionsHold) func leavesAloneWhatTheHelperWouldRefuse() async throws {
        let directory = try TemporaryDirectory()
        let volume = PathPattern.canonical(directory.url).path(percentEncoded: false)
        let served = PathPattern.canonical(try directory.directory("root/Library/Application Support/Example"))
        let vendor = PathPattern.canonical(try directory.directory("root/Library/Example"))
        let tools = PathPattern.canonical(try directory.directory("root/Applications/Example Tools"))
        let bin = PathPattern.canonical(try directory.directory("root/usr/local/bin"))
        try directory.file("root/usr/local/bin/tool")
        try FileManager.default.createSymbolicLink(
            atPath: bin.appending(path: "linked").path(percentEncoded: false),
            withDestinationPath: "tool"
        )
        try FileManager.default.createSymbolicLink(
            atPath: bin.appending(path: "gone").path(percentEncoded: false),
            withDestinationPath: "/Applications/Gone.app/Contents/MacOS/gone"
        )
        for folder in [served, vendor, tools, bin] {
            try directory.setPermissions(0o555, of: folder)
        }
        defer {
            for folder in [served, vendor, tools, bin] {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: folder.path(percentEncoded: false)
                )
            }
        }
        let info = try #require(String(
            data: PropertyListSerialization.data(fromPropertyList: ["volume": volume, "install-location": ""], format: .xml, options: 0),
            encoding: .utf8
        ))
        let pkgutil: PackageReceipts.Pkgutil = { arguments in
            switch arguments.first {
            case "--pkgs-plist": PkgutilAnswer.packages("com.example.pkg")
            case "--pkg-info-plist": info
            case "--files": "root/Library/Application Support/Example\nroot/Library/Example\nroot/Applications/Example Tools\nroot/usr/local/bin/tool\nroot/usr/local/bin/linked\nroot/usr/local/bin/gone\n"
            default: ""
            }
        }
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home"),
            rootDirectory: directory.url.appending(path: "root")
        )

        let receipt = try #require(
            await PackageReceipts.list(exclusions: .none, pkgutil: pkgutil, environment: environment).receipts.first
        )
        func item(_ url: URL) throws -> PackageReceipt.Item {
            try #require(receipt.items.first { $0.url == url })
        }

        #expect(try item(served).requiresPrivileges)
        #expect(try item(served).isLeftAlone == false)
        #expect(try item(vendor).isLeftAlone == true)
        #expect(try item(tools).isLeftAlone == true)
        #expect(try [item(vendor), item(tools)].map(\.heldBack) == [.beyondTheHelper, .beyondTheHelper])
        func tool(_ name: String) throws -> PackageReceipt.Item {
            try #require(
                receipt.items.first {
                    $0.url.deletingLastPathComponent().lastPathComponent == "bin" && $0.url.lastPathComponent == name
                }
            )
        }
        #expect(try tool("tool").isLeftAlone == true, "a file in a folder only links leave was offered")
        #expect(try tool("linked").isLeftAlone == true, "a link that leads somewhere was offered")
        #expect(try tool("gone").isLeftAlone == false)
    }

    @Test func knowsWhatApplesPackagesInstalledOnThisMac() async throws {
        let directory = try TemporaryDirectory()
        let applicationSupport = URL(filePath: "/Library/Application Support", directoryHint: .isDirectory)

        #expect(await PackageReceipts.isInstalledByApple(applicationSupport))
        #expect(await PackageReceipts.isInstalledByApple(directory.url) == false)
    }

    @Test func countsOnlyApplesPackagesThatInstallAtTheRoot() async {
        func answering(location: String, package: String = "com.apple.pkg.Example") -> PackageReceipts.Pkgutil {
            { arguments in
                switch arguments.first {
                case "--file-info-plist": PkgutilAnswer.fileInfo(arguments[1], packages: package)
                case "--pkg-info-plist": PkgutilAnswer.packageInfo(package, location: location)
                default: nil
                }
            }
        }
        let url = URL(filePath: "/Library/Example Kit/Example", directoryHint: .isDirectory)

        #expect(await PackageReceipts.isInstalledByApple(url, pkgutil: answering(location: "/")))
        #expect(await PackageReceipts.isInstalledByApple(url, pkgutil: answering(location: "")))
        #expect(await PackageReceipts.isInstalledByApple(url, pkgutil: answering(location: "Library/Apple/")) == false)
        #expect(
            await PackageReceipts.isInstalledByApple(url, pkgutil: answering(location: "/", package: "org.example.pkg"))
                == false
        )
    }
}
