import Foundation
@testable import PeelCore
import Synchronization
import Testing

struct PackageReceiptsTests {
    @Test func keepsOnlyOutermostPackageItems() {
        let files = [
            "Adguard.app", "Adguard.app/Contents", "Adguard.app/Contents/Info.plist",
            "Library", "Library/Application Support", "Library/Application Support/AdGuard Software",
            "Library/Application Support/AdGuard Software/helper",
            "Library/LaunchDaemons", "Library/LaunchDaemons/com.adguard.helper.plist",
            "./usr/local/bin/adguard-cli",
        ]
        let items = PackageReceipts.topLevel(files: files, installLocation: "/", namesInside: { _ in nil }, exists: { _ in true }).offered
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

    @Test func resolvesPathsAgainstTheInstallLocationAndSkipsMissingFiles() {
        let files = ["Example.app", "Example.app/Contents", "Gone.app"]
        let items = PackageReceipts.topLevel(files: files, installLocation: "/Applications", exists: { $0 != "/Applications/Gone.app" }).offered
        #expect(items == ["/Applications/Example.app"])
    }

    @Test func neverReturnsSharedDirectories() {
        let files = ["Applications", "Library", "Library/Fonts", "usr", "usr/local", "usr/local/lib"]
        #expect(PackageReceipts.topLevel(files: files, installLocation: "/", exists: { _ in true }).offered.isEmpty)
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
        #expect(!receipt.total.isComplete, "an unknown file list read as a size of zero")
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
        let environment = SearchEnvironment(homeDirectory: directory.url.appending(path: "home"), rootDirectory: directory.url.appending(path: "root"))

        let receipt = try #require(await PackageReceipts.list(exclusions: .none, pkgutil: pkgutil, environment: environment).receipts.first)

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
        let environment = SearchEnvironment(homeDirectory: directory.url.appending(path: "home"), rootDirectory: directory.url.appending(path: "root"))

        let excluded = try #require(await PackageReceipts.list(exclusions: Exclusions(paths: [app]), pkgutil: pkgutil, environment: environment).receipts.first)
        #expect(excluded.items.isEmpty)
        #expect(!excluded.nothingLeftOnDisk)

        try FileManager.default.removeItem(at: app)
        let gone = try #require(await PackageReceipts.list(exclusions: .none, pkgutil: pkgutil, environment: environment).receipts.first)
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
        let environment = SearchEnvironment(homeDirectory: directory.url.appending(path: "home"), rootDirectory: directory.url.appending(path: "root"))

        let receipt = try #require(await PackageReceipts.list(exclusions: .none, pkgutil: pkgutil, environment: environment).receipts.first)

        #expect(!receipt.isFileListKnown)
        #expect(!receipt.nothingLeftOnDisk)
        #expect(receipt.items.isEmpty)
    }

    /// A receipt can name a path `RemovalGuard` refuses, such as a file in `/usr/local/bin` or a Mail bundle.
    /// Such an item is listed and left alone, rather than offered and then refused at the move.
    @Test func leavesAloneWhatTheGuardWouldRefuse() async throws {
        let directory = try TemporaryDirectory()
        let volume = PathPattern.canonical(directory.url).path(percentEncoded: false)
        let app = PathPattern.canonical(try directory.directory("Applications/Example.app"))
        let rules = PathPattern.canonical(try directory.directory("home/Library/Mail/Bundles/Example.mailbundle"))
        let info = try #require(String(
            data: PropertyListSerialization.data(fromPropertyList: ["volume": volume, "install-location": ""], format: .xml, options: 0),
            encoding: .utf8
        ))
        let pkgutil: PackageReceipts.Pkgutil = { arguments in
            switch arguments.first {
            case "--pkgs-plist": PkgutilAnswer.packages("com.example.pkg")
            case "--pkg-info-plist": info
            case "--files": "Applications/Example.app\nhome/Library/Mail/Bundles/Example.mailbundle\n"
            default: ""
            }
        }
        let environment = SearchEnvironment(homeDirectory: directory.url.appending(path: "home"), rootDirectory: directory.url.appending(path: "root"))

        let receipt = try #require(await PackageReceipts.list(exclusions: .none, pkgutil: pkgutil, environment: environment).receipts.first)

        #expect(receipt.items.first { $0.url == app }?.isLeftAlone == false)
        #expect(receipt.items.first { $0.url == rules }?.isLeftAlone == true)
    }

    /// An item that needs an administrator is left alone when the helper would refuse it. The helper refuses
    /// items outside the folders it serves, and anything in `/Applications` that is not an app.
    @Test func leavesAloneWhatTheHelperWouldRefuse() async throws {
        let directory = try TemporaryDirectory()
        let volume = PathPattern.canonical(directory.url).path(percentEncoded: false)
        let served = PathPattern.canonical(try directory.directory("root/Library/Application Support/Example"))
        let vendor = PathPattern.canonical(try directory.directory("root/Library/Example"))
        let tools = PathPattern.canonical(try directory.directory("root/Applications/Example Tools"))
        for folder in [served, vendor, tools] {
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path(percentEncoded: false))
        }
        defer {
            for folder in [served, vendor, tools] {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path(percentEncoded: false))
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
            case "--files": "root/Library/Application Support/Example\nroot/Library/Example\nroot/Applications/Example Tools\n"
            default: ""
            }
        }
        let environment = SearchEnvironment(homeDirectory: directory.url.appending(path: "home"), rootDirectory: directory.url.appending(path: "root"))

        let receipt = try #require(await PackageReceipts.list(exclusions: .none, pkgutil: pkgutil, environment: environment).receipts.first)
        func item(_ url: URL) throws -> PackageReceipt.Item {
            try #require(receipt.items.first { $0.url == url })
        }

        #expect(try item(served).requiresPrivileges)
        #expect(try item(served).isLeftAlone == false)
        #expect(try item(vendor).isLeftAlone == true)
        #expect(try item(tools).isLeftAlone == true)
    }
}
