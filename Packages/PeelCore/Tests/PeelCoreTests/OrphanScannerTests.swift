import Foundation
import Synchronization
@testable import PeelCore
import Testing

struct OrphanScannerTests {
    @Test func aStoppedScanStops() async throws {
        let directory = try TemporaryDirectory()
        for index in 1...30 {
            try directory.directory("home/Library/Application Support/com.gone.app\(index)")
        }
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory),
            userCacheDirectory: directory.url.appending(path: "var/C", directoryHint: .isDirectory),
            userTemporaryDirectory: directory.url.appending(path: "var/T", directoryHint: .isDirectory)
        )
        let unanswered = Unanswered()
        let scanner = OrphanScanner(environment: environment, isRegisteredApp: { _ in false }, systemApps: [], walk: unanswered.walk)

        let stop = try await unanswered.stop {
            _ = await scanner.scan(installedApps: [])
        }

        #expect(stop.took < .seconds(1))
        #expect(stop.askedBefore < 30)
        #expect(stop.askedAfter == 0)
    }


    /// Launch Services is asked about apps outside the scanned folders. It knows an app by its bundle identifier,
    /// never by a group container's name, which has a team or `group.` in front.
    @Test func asksMacOSAboutTheAppBehindAGroupContainer() {
        let asked = Mutex<[String]>([])
        let ownership = AppOwnership(installedApps: []) { identifier in
            asked.withLock { $0.append(identifier) }
            return identifier == "com.example.app"
        }

        #expect(ownership.isClaimed(fileName: "ABCDE12345.com.example.app", kind: .groupContainers, identifier: "ABCDE12345.com.example.app"))
        #expect(ownership.isClaimed(fileName: "group.com.example.app.shared", kind: .groupContainers, identifier: "group.com.example.app.shared"))
        #expect(!ownership.isClaimed(fileName: "ABCDE12345.org.other.thing", kind: .groupContainers, identifier: "ABCDE12345.org.other.thing"))
        #expect(!asked.withLock { $0 }.contains { $0.hasPrefix("ABCDE12345") || $0.hasPrefix("group.") })
    }
    private let installed = [
        InstalledApp(url: URL(filePath: "/Applications/Installed.app"), bundleIdentifier: "com.installed.app", name: "Installed"),
        InstalledApp(url: URL(filePath: "/Applications/Word.app"), bundleIdentifier: "com.microsoft.Word", name: "Microsoft Word", teamIdentifier: "UBF8T346G9"),
    ]

    private func scanner(
        in directory: borrowing TemporaryDirectory,
        registered: Set<String> = [],
        systemApps: [InstalledApp] = []
    ) -> OrphanScanner {
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        return OrphanScanner(environment: environment, isRegisteredApp: { registered.contains($0) }, systemApps: systemApps)
    }

    /// What an app left behind can be the biggest folder in the Library. A folder that did not answer in time
    /// is listed first with an unknown size, and the group's total says it is incomplete.
    @Test func anItemThatDidNotAnswerInTimeIsNotReadAsEmpty() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Application Support/com.gone.app/library.db", bytes: 400_000)
        try directory.file("home/Library/Caches/com.gone.app/blob", bytes: 50_000)
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        let scanner = OrphanScanner(environment: environment, isRegisteredApp: { _ in false }) { url in
            url.path(percentEncoded: false).contains("Application Support") ? nil : await FileSize.contents(of: url)
        }

        let group = try #require(await scanner.scan(installedApps: installed).groups.first)

        #expect(group.items.map(\.kind) == [.applicationSupport, .caches])
        #expect(group.items.first?.size == nil)
        #expect(!group.total.isComplete)
        #expect(group.total.known >= 50_000)
    }

    /// A crash reporter keeps a folder for each app inside its own. When macOS will not let Peel list that folder,
    /// what it holds is not known, so it is not reported as nobody's, the same as a folder that did not answer.
    @Test func aFolderThatCannotBeListedIsNotNobodys() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Application Support/com.vendor.reports/com.installed.app/report.log")
        try directory.setPermissions(0, of: "home/Library/Application Support/com.vendor.reports")
        defer { try? directory.setPermissions(0o755, of: "home/Library/Application Support/com.vendor.reports") }

        let groups = await scanner(in: directory).scan(installedApps: installed).groups

        #expect(!groups.contains { $0.identifier == "com.vendor.reports" }, "a folder nobody could read was called nobody's")
    }

    /// An item that needs an administrator, in a place the helper does not serve, is left alone rather than
    /// offered and then refused.
    @Test func whatTheHelperMayNotMoveIsLeftAlone() async throws {
        let directory = try TemporaryDirectory()
        let served = try directory.directory("root/Library/Application Support/com.gone.app")
        let beyond = try directory.directory("root/Users/Shared/com.gone.app")
        for folder in [served, beyond] {
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path(percentEncoded: false))
        }
        defer {
            for folder in [served, beyond] {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path(percentEncoded: false))
            }
        }

        let group = try #require(await scanner(in: directory).scan(installedApps: installed).groups.first { $0.identifier == "com.gone.app" })
        func item(_ url: URL) throws -> OrphanItem {
            try #require(group.items.first { PathPattern.comparablePath(of: $0.url) == PathPattern.comparablePath(of: url) })
        }

        #expect(try item(served).requiresPrivileges)
        #expect(try item(served).leftAlone == nil)
        #expect(try item(beyond).requiresPrivileges)
        #expect(try item(beyond).leftAlone == .beyondTheHelper)
    }

    /// An agent writes to a log two folders down, while the folder's own date is from the day of the install.
    @Test func readsTheNewestWriteInsideAFolderNotTheFoldersOwnDate() async throws {
        let directory = try TemporaryDirectory()
        let log = try directory.file("home/Library/Application Support/com.gone.app/logs/agent.log")
        let folder = log.deletingLastPathComponent().deletingLastPathComponent()
        let lastYear = Date(timeIntervalSinceNow: -400 * 24 * 60 * 60)
        for old in [log.deletingLastPathComponent(), folder] {
            try FileManager.default.setAttributes([.modificationDate: lastYear], ofItemAtPath: old.path(percentEncoded: false))
        }

        let group = try #require(await scanner(in: directory).scan(installedApps: installed).groups.first)

        #expect(group.confidence.level == .unsure)
        #expect(try #require(group.lastModified).timeIntervalSinceNow > -60)
    }

    /// An installed app may not claim a group container from its old team, but the app has not left, so the
    /// container is not attributed to it as a leftover.
    @Test func anAppThatIsStillInstalledIsNotTheOneThatLeft() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Group Containers/OLDTEAM123.com.installed.app/data.db")
        let remembered = [
            RememberedApp(bundleIdentifier: "com.installed.app", name: "Installed", teamIdentifier: nil, lastSeen: .now, lastPath: "/Applications/Installed.app"),
        ]

        let group = try #require(await scanner(in: directory).scan(installedApps: installed, remembered: remembered).groups.first)

        #expect(group.rememberedApp == nil)
        #expect(group.confidence.level != .certain)
    }

    /// An app installed since the scan owns what the list still calls orphaned.
    @Test func whatAnAppInstalledSinceClaimsIsNoLongerOrphaned() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Preferences/com.back.again.plist")
        try directory.file("home/Library/Application Support/com.back.again/data.db")
        try directory.file("home/Library/Caches/com.gone.app/cache.db")
        let scanner = scanner(in: directory)
        let listed = await scanner.scan(installedApps: installed).groups.flatMap(\.items)
        #expect(listed.count == 3)

        let back = InstalledApp(url: URL(filePath: "/Applications/Back.app"), bundleIdentifier: "com.back.again", name: "Back")
        let still = await scanner.stillOrphaned(listed, installedApps: installed + [back])

        #expect(still.map(\.url.lastPathComponent) == ["com.gone.app"])
    }

    @Test func reportsOnlyUnclaimedAppItems() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Preferences/com.gone.app.plist")
        try directory.file("home/Library/Caches/com.gone.app/cache.db", bytes: 50_000)
        try directory.directory("home/Library/Caches/com.gone.app.helper")
        try directory.file("root/Library/LaunchAgents/com.gone.app.updater.plist")
        try directory.directory("home/Library/Group Containers/ABCDE12345.shared")
        try directory.directory("home/Library/Group Containers/ABCDE12345.com.gone.app")
        try directory.directory("home/Library/Containers/com.installed.app")
        try directory.directory("home/Library/Caches/com.installed.app.ShipIt")
        try directory.directory("home/Library/Group Containers/UBF8T346G9.Office")
        try directory.file("home/Library/Preferences/com.microsoft.autoupdate2.plist")
        try directory.directory("home/Library/Caches/com.apple.Safari")
        try directory.file("root/Library/Preferences/org.cups.printers.plist")
        try directory.directory("home/Library/Application Support/SomeFolder")
        try directory.directory("home/Library/Caches/com.elsewhere.tool")
        try directory.directory("home/Library/Caches/com.elsewhere.tool.helper")

        let scan = await scanner(in: directory, registered: ["com.elsewhere.tool"]).scan(installedApps: installed)

        #expect(scan.groups.map(\.identifier) == ["com.gone.app", "ABCDE12345.shared"])
        let gone = try #require(scan.groups.first)
        #expect(Set(gone.items.map(\.url.lastPathComponent)) == [
            "com.gone.app.plist", "com.gone.app", "com.gone.app.helper", "com.gone.app.updater.plist", "ABCDE12345.com.gone.app",
        ])
        #expect(gone.items.first?.url.lastPathComponent == "com.gone.app")
        #expect(gone.total.isComplete)
        #expect(gone.total.known >= 50_000)
        #expect(gone.lastModified != nil)
        #expect(scan.unreadableLocations.isEmpty)
    }

    /// With the app gone, what it kept in `Data/Documents` may be the only copy of what its user made.
    @Test func anOrphanedContainerThatHoldsDocumentsSaysSo() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Containers/com.gone.notes/Data/Documents/novel.txt")
        try directory.file("home/Library/Containers/com.gone.cache/Data/Library/Caches/cache.db")

        let scan = await scanner(in: directory).scan(installedApps: installed)
        let items = scan.groups.flatMap(\.items)

        #expect(items.first { $0.url.lastPathComponent == "com.gone.notes" }?.leftAlone == .holdsDocuments)
        #expect(items.first { $0.url.lastPathComponent == "com.gone.cache" }?.leftAlone == nil)
    }

    /// The same for a library kept by an app that is gone: `RemovalGuard` refuses the folder around it.
    @Test func anOrphanedFolderThatHoldsALibrarySaysSo() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Application Support/com.gone.photos/Main.photoslibrary/database/Photos.sqlite")

        let items = await scanner(in: directory).scan(installedApps: installed).groups.flatMap(\.items)

        #expect(items.first?.leftAlone == .holdsALibrary)
    }

    /// An app that is gone can leave its wallet behind in its container, and `RemovalGuard` refuses the
    /// container around it.
    @Test func anOrphanedFolderThatHoldsAProtectedWalletSaysSo() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Containers/io.bluewallet.bluewallet/Data/Library/Caches/keyvalue.realm")

        let items = await scanner(in: directory).scan(installedApps: installed).groups.flatMap(\.items)

        #expect(items.first?.leftAlone == .holdsKeys)
    }

    /// The apps macOS ships claim their folders like any other app, and none of them is in the list Peel scans.
    @Test func ignoresGroupsDeclaredBySystemApps() async throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/Library/Group Containers/group.is.workflow.shortcuts")
        let shortcuts = InstalledApp(
            url: URL(filePath: "/System/Applications/Shortcuts.app"),
            bundleIdentifier: "is.workflow.my.app",
            name: "Shortcuts",
            applicationGroups: ["group.is.workflow.shortcuts"]
        )

        #expect(await scanner(in: directory, systemApps: [shortcuts]).scan(installedApps: installed).groups.isEmpty)
        #expect(await !scanner(in: directory).scan(installedApps: installed).groups.isEmpty, "with no rival it is nobody's")
    }

    @Test(arguments: [
        ("S8EX82NJP6.com.macpaw.CleanMyMac5", "com.macpaw.CleanMyMac5"),
        ("6H4HRTU5E3.group.com.avast.osx", "com.avast.osx"),
        ("group.is.workflow.my.app", "is.workflow.my.app"),
        ("ABCDE12345.shared", "ABCDE12345.shared"),
    ])
    func groupsTeamContainersWithTheirApp(identifier: String, expected: String) {
        #expect(OrphanScanner.groupingKey(for: identifier) == expected)
    }

    @Test(arguments: [
        ("com.example.app", SearchLocation.Kind.caches, "com.example.app"),
        ("group.com.example.shared", .groupContainers, "com.example.shared"),
        ("ABCDE12345.shared", .groupContainers, "ABCDE12345.shared"),
        ("ABCDE12345.shared", .caches, nil),
        ("com.apple.Safari", .caches, nil),
        ("group.com.apple.notes", .groupContainers, nil),
        ("243LU875E5.groups.com.apple.podcasts", .groupContainers, nil),
        ("homebrew.mxcl.postgresql", .launchAgents, nil),
        ("Spotify", .applicationSupport, nil),
        ("com.example", .caches, nil),
        ("Com.Example.App", .caches, nil),
    ] as [(String, SearchLocation.Kind, String?)])
    func identifiesAppShapedNames(key: String, kind: SearchLocation.Kind, expected: String?) {
        #expect(OrphanScanner.orphanIdentifier(forKey: key, kind: kind) == expected)
    }
    /// A crash reporter keeps a folder per app inside its own. The folder is named after the reporter, which
    /// nothing installed answers to, but what is inside belongs to an app that is still here.
    @Test func leavesAloneAFolderHoldingAnInstalledAppsFiles() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/com.plausiblelabs.crashreporter.data/com.installed.app/report.plist")
        try directory.file("home/Library/Caches/com.otherreporter.data/com.gone.app/report.plist")

        let scan = await scanner(in: directory).scan(installedApps: installed)

        #expect(scan.groups.map(\.identifier) == ["com.otherreporter.data"])
    }

    private func job(_ label: String, runs arguments: [String]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["Label": label, "ProgramArguments": arguments], format: .xml, options: 0)
    }

    /// A job that Nix, MacPorts, or Tailscale installed belongs to no app bundle, and its file is as old as the
    /// install. It is still not a leftover while the program it runs is there.
    @Test func aJobThatStillHasSomethingToRunIsNobodysLeftover() async throws {
        let directory = try TemporaryDirectory()
        let daemon = try directory.file("root/nix/bin/nix-daemon").path(percentEncoded: false)
        let gone = directory.url.appending(path: "root/opt/gone/bin/helper").path(percentEncoded: false)
        try directory.file("root/Library/LaunchDaemons/org.nixos.nix-daemon.plist", contents: job("org.nixos.nix-daemon", runs: [daemon]))
        try directory.file("home/Library/LaunchAgents/org.example.sync.plist", contents: job("org.example.sync", runs: ["sh", "-c", "exit 0"]))
        try directory.file("root/Library/LaunchDaemons/com.gone.app.helper.plist", contents: job("com.gone.app.helper", runs: [gone]))
        // A plist kept in a dotfiles repository and linked into place is read through the link.
        try FileManager.default.createSymbolicLink(
            at: directory.url.appending(path: "home/Library/LaunchAgents/org.example.linked.plist"),
            withDestinationURL: try directory.file("home/dotfiles/linked.plist", contents: job("org.example.linked", runs: [daemon]))
        )

        let scan = await scanner(in: directory).scan(installedApps: installed)

        #expect(scan.groups.flatMap(\.items).map(\.url.lastPathComponent) == ["com.gone.app.helper.plist"])
    }

    /// A file that cannot be read is not called a leftover on its name; one that is no job at all still is.
    @Test func aJobThatCannotBeReadIsNotCalledALeftover() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/LaunchAgents/org.example.closed.plist", contents: job("org.example.closed", runs: ["/bin/sh"]))
        try directory.setPermissions(0o000, of: "home/Library/LaunchAgents/org.example.closed.plist")
        try directory.file("home/Library/LaunchAgents/org.example.empty.plist", contents: Data())

        let scan = await scanner(in: directory).scan(installedApps: installed)

        #expect(scan.groups.flatMap(\.items).map(\.url.lastPathComponent) == ["org.example.empty.plist"])
    }

    /// A plug-in is named for what it does, so it is listed under the identifier it declares inside. One whose
    /// identifier an installed app claims is not an orphan.
    @Test func listsAPlugInUnderTheIdentifierItDeclares() async throws {
        let directory = try TemporaryDirectory()
        let info = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>%@</string></dict></plist>
        """
        try directory.file(
            "root/Library/Audio/Plug-Ins/VST3/Gone.vst3/Contents/Info.plist",
            contents: Data(info.replacingOccurrences(of: "%@", with: "com.gonevendor.gone").utf8)
        )
        try directory.file(
            "root/Library/QuickLook/Still Here.qlgenerator/Contents/Info.plist",
            contents: Data(info.replacingOccurrences(of: "%@", with: "com.installed.app.quicklook").utf8)
        )

        let scan = await scanner(in: directory, registered: ["com.installed.app"]).scan(installedApps: installed)

        #expect(scan.groups.map(\.identifier) == ["com.gonevendor.gone"])
        #expect(scan.groups.flatMap(\.items).map(\.url.lastPathComponent) == ["Gone.vst3"])
    }

    /// A link to a tool inside an app that is gone leads nowhere, and an app's uninstaller can leave such links
    /// behind. A tool's name says nothing about its app, so the group is named after the app the link led into,
    /// or given that app's identifier when Peel remembers it.
    @Test func listsLinksIntoAnAppThatIsGone() async throws {
        let directory = try TemporaryDirectory()
        let root = directory.url.appending(path: "root", directoryHint: .isDirectory)
        let bin = try directory.directory("root/usr/local/bin")
        try directory.file("root/Applications/Here.app/Contents/MacOS/here")
        try directory.file("home/Library/Application Support/com.remembered.app/state.db")
        func link(_ name: String, to destination: String) throws {
            try FileManager.default.createSymbolicLink(atPath: bin.appending(path: name).path(percentEncoded: false), withDestinationPath: destination)
        }
        try link("docker", to: root.appending(path: "Applications/Gone.app/Contents/MacOS/xbin/docker").path(percentEncoded: false))
        try link("orb", to: "../../../Applications/Gone.app/Contents/MacOS/bin/orb")
        try link("here", to: root.appending(path: "Applications/Here.app/Contents/MacOS/here").path(percentEncoded: false))
        try link("node", to: root.appending(path: "opt/node/bin/node").path(percentEncoded: false))
        try link("rem", to: root.appending(path: "Applications/Remembered.app/Contents/MacOS/rem").path(percentEncoded: false))
        let remembered = [
            RememberedApp(bundleIdentifier: "com.remembered.app", name: "Remembered", teamIdentifier: nil, lastSeen: .now, lastPath: root.appending(path: "Applications/Remembered.app").path(percentEncoded: false)),
        ]

        let scan = await scanner(in: directory).scan(installedApps: installed, remembered: remembered)
        let groups = Dictionary(uniqueKeysWithValues: scan.groups.map { ($0.identifier, $0) })

        #expect(Set(groups.keys) == ["Gone", "com.remembered.app"])
        let gone = try #require(groups["Gone"])
        #expect(Set(gone.items.map(\.url.lastPathComponent)) == ["docker", "orb"])
        #expect(gone.items.allSatisfy { $0.kind == .commandLineTools })
        #expect(gone.confidence.level == .certain)
        #expect(gone.confidence.reasons == [.leadsIntoAnAppThatIsGone])
        #expect(Set(try #require(groups["com.remembered.app"]).items.map(\.url.lastPathComponent)) == ["rem", "com.remembered.app"])
    }

    /// A socket or a pipe holds nothing, and a live one belongs to something running. A name such as JetBrains
    /// Toolbox's `jb.station.<user>.sock` reads as reverse DNS, so the item's type is checked before its name.
    @Test func aSocketOrAPipeIsNobodysLeftover() async throws {
        let directory = try TemporaryDirectory()
        // A socket's path has to fit in 104 bytes, and the test folder's does not.
        let temporary = URL(filePath: "/private/tmp/peel-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporary.appending(path: "com.gone.app"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let listening = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(listening) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { path in
            path.copyBytes(from: temporary.appending(path: "jb.station.someone.sock").path(percentEncoded: false).utf8.prefix(path.count - 1))
        }
        let bound = withUnsafePointer(to: address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listening, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        try #require(bound == 0)
        try #require(mkfifo(temporary.appending(path: "com.gone.pipe").path(percentEncoded: false), 0o600) == 0)
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory),
            userTemporaryDirectory: temporary
        )

        let scan = await OrphanScanner(environment: environment, isRegisteredApp: { _ in false }, systemApps: []).scan(installedApps: installed)

        #expect(scan.groups.flatMap(\.items).map(\.url.lastPathComponent) == ["com.gone.app"])
    }
}
