import Foundation
@testable import PeelCore
import Testing

struct AppExtensionsTests {
    @Test func readsWhatPluginkitSaysAboutEachExtension() {
        let line = "     net.whatsapp.WhatsApp.Intents(26.37.22)\t99D7BB9C-5DFD\t2026-09-17 18:44:09 +0000\t/Applications/WhatsApp.app/Contents/PlugIns/Intents.appex"
        let parsed = AppExtensions.parse(line)

        #expect(parsed?.identifier == "net.whatsapp.WhatsApp.Intents")
        #expect(parsed?.election == .asItCame)
        #expect(parsed?.path == "/Applications/WhatsApp.app/Contents/PlugIns/Intents.appex")
    }

    /// `pluginkit` writes `((null))` for a bundle with no version. Cutting at the last `(` would leave the first
    /// one stuck to the identifier.
    @Test func keepsTheIdentifierWhenPluginkitPrintsNoVersion() {
        let line = "     com.apple.Keyboard-Settings.extension((null))\t6BF7FA43-C328-5B72-BF7B-99923B7E8F70\t2026-09-15 18:22:16 +0000\t/System/Library/ExtensionKit/Extensions/KeyboardSettings.appex"

        #expect(AppExtensions.parse(line)?.identifier == "com.apple.Keyboard-Settings.extension")
        #expect(AppExtensions.identifier(before: "net.example.thing((null))") == "net.example.thing")
        #expect(AppExtensions.identifier(before: "net.example.thing(1.0 (23))") == "net.example.thing")
        #expect(AppExtensions.identifier(before: "net.example.thing") == "net.example.thing")
    }

    /// `man pluginkit` names five tags in the first column, and each one is one character.
    @Test func readsTheChoiceSomeoneMadeAboutAnExtension() {
        func parse(_ tag: String) -> (identifier: String, election: AppExtension.Election, path: String)? {
            AppExtensions.parse("\(tag)    com.example.thing(1.0)\tUUID\tdate\t/Applications/Thing.app/Contents/PlugIns/A.appex")
        }

        #expect(parse("+")?.election == .on)
        #expect(parse("-")?.election == .off)
        #expect(parse("!")?.election == .on)
        #expect(parse("=")?.election == .superseded)
        #expect(parse("?")?.election == .unknown)
        #expect(parse(" ")?.election == .asItCame)
        // The tag is not part of the name, whichever one it is.
        for tag in ["+", "-", "!", "=", "?", " "] {
            #expect(parse(tag)?.identifier == "com.example.thing")
        }
    }

    @Test func ignoresLinesThatArentAnExtension() {
        #expect(AppExtensions.parse(" (442 plug-ins)") == nil)
        #expect(AppExtensions.parse("") == nil)
        #expect(AppExtensions.parse("com.example(1.0)\tUUID\tdate\tnot-a-path") == nil)
    }

    /// An extension inside Instruments inside Xcode belongs to Xcode, the app the user installed.
    @Test func creditsTheAppSomeoneWouldRecognize() {
        #expect(AppExtensions.owner(ofExtensionAt: "/Applications/WhatsApp.app/Contents/PlugIns/Intents.appex") == "WhatsApp")
        #expect(AppExtensions.owner(ofExtensionAt: "/Applications/Xcode.app/Contents/Applications/Instruments.app/Contents/PlugIns/A.appex") == "Xcode")
        #expect(AppExtensions.owner(ofExtensionAt: "/Library/SystemExtensions/x/y.systemextension") == nil)
    }

    /// macOS runs one copy of an extension per identifier. When it runs another Peel's copy, or one that is gone,
    /// the running Peel reads its own Finder extension as off while System Settings shows it on.
    @Test func tellsWhenMacOSRunsAnotherCopyOfAnExtension() throws {
        let directory = try TemporaryDirectory()
        let own = try directory.directory("Peel.app/Contents/PlugIns/PeelFinder.appex")
        let other = try directory.directory("Downloads/Peel.app/Contents/PlugIns/PeelFinder.appex")
        let identifier = "com.tuguidragos.Peel.FinderExtension"
        func listing(_ tag: String, _ path: String) -> String {
            "\(tag)    \(identifier)(1.0.1)\t6299ACC7-6EDA-4A38-9BD4-89444C604682\t2026-09-20 17:23:02 +0000\t\(path)\n (1 plug-in)"
        }
        func runsAnother(_ listing: String) -> Bool {
            AppExtensions.runsAnotherCopy(of: identifier, than: own, in: listing)
        }

        let gone = "/Users/me/Library/Developer/Xcode/DerivedData/Peel-dxhbpnznlojqqafmobkqhxqsivhm/Build/Products/Debug/Peel.app/Contents/PlugIns/PeelFinder.appex"
        #expect(runsAnother(listing("+", gone)))
        #expect(runsAnother(listing("+", other.path(percentEncoded: false))))
        #expect(!runsAnother(listing("+", own.path(percentEncoded: false))))
        // The same folder reached through a link is still this copy.
        let link = directory.url.appending(path: "Link.appex")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: own)
        #expect(
            !AppExtensions.runsAnotherCopy(
                of: identifier,
                than: link,
                in: listing("+", own.path(percentEncoded: false))
            )
        )
        // Unless the user turned the extension on, the answer is no, even when the listed copy is another one.
        #expect(!runsAnother(listing("-", other.path(percentEncoded: false))))
        #expect(!runsAnother(listing(" ", other.path(percentEncoded: false))))
        #expect(!runsAnother("  (no matches)"))
        #expect(!AppExtensions.runsAnotherCopy(of: "com.example.else", than: own, in: listing("+", other.path(percentEncoded: false))))
    }

    /// macOS ships hundreds of its own; showing them would bury the ones an app brought.
    @Test func leavesTheSystemsOwnExtensionsOut() {
        #expect(AppExtensions.isTheSystemsOwn("/System/Library/ExtensionKit/Extensions/A.appex"))
        #expect(AppExtensions.isTheSystemsOwn("/usr/libexec/A.appex"))
        #expect(!AppExtensions.isTheSystemsOwn("/Applications/WhatsApp.app/Contents/PlugIns/Intents.appex"))
        // System Integrity Protection leaves `/usr/local` to administrators and Homebrew, and the data volume,
        // which macOS also names under `/System/Volumes/Data`, holds what anybody installed.
        #expect(!AppExtensions.isTheSystemsOwn("/usr/local/lib/Tool.app/Contents/PlugIns/A.appex"))
        #expect(!AppExtensions.isTheSystemsOwn("/System/Volumes/Data/Applications/WhatsApp.app/Contents/PlugIns/Intents.appex"))
    }

    @Test func readsASystemExtensionFromItsRow() {
        let rows = """
        2 extension(s)
        --- com.apple.system_extension.network_extension (Go to 'System Settings' to modify)
        enabled\tactive\tteamID\tbundleID (version)\tname\t[state]
        *\t*\tTC3Q7MAJXF\tcom.adguard.mac.adguard.network-extension (2.19.0/2258)\tAdGuard Network Extension\t[activated enabled]
        \t*\t2MMRE5MTB8\tcom.obsproject.obs-studio.mac-camera-extension (32.2.2/31845296735)\tOBS Virtual Camera\t[activated waiting for user]
        """
        let parsed = rows.split(whereSeparator: \.isNewline).compactMap {
            AppExtensions.parseSystemExtension(String($0))
        }

        #expect(parsed.count == 2, "the header row was read as an extension")
        #expect(parsed.first?.identifier == "com.adguard.mac.adguard.network-extension")
        #expect(parsed.first?.name == "AdGuard Network Extension")
        #expect(parsed.first?.teamIdentifier == "TC3Q7MAJXF")
        #expect(parsed.first?.state == "activated enabled")
        #expect(parsed.first?.version == "2.19.0/2258")
        #expect(parsed.last?.state == "activated waiting for user")
    }

    /// While an app updates its extension, macOS lists the old and the new version under one identifier. Each row
    /// needs an id of its own, because a list picks a row by its id.
    @Test func keepsTwoVersionsOfOneSystemExtensionApart() throws {
        let rows = """
        enabled\tactive\tteamID\tbundleID (version)\tname\t[state]
        *\t*\tTC3Q7MAJXF\tcom.example.filter (1.0/100)\tExample Filter\t[activated waiting to upgrade]
        \t\tTC3Q7MAJXF\tcom.example.filter (2.0/200)\tExample Filter\t[activated enabled]
        """
        let parsed = rows.split(whereSeparator: \.isNewline).compactMap {
            AppExtensions.parseSystemExtension(String($0))
        }
        #expect(parsed.map(\.version) == ["1.0/100", "2.0/200"])

        let made = parsed.map { row in
            AppExtension(
                id: [row.identifier, row.version].compactMap(\.self).joined(separator: " "),
                identifier: row.identifier, name: row.name, kind: .systemExtension, point: nil, owner: nil,
                url: nil, election: .on, teamIdentifier: row.teamIdentifier, reportedState: row.state
            )
        }
        #expect(Set(made.map(\.id)).count == 2)
    }

    /// macOS's own record, `/Library/SystemExtensions/db.plist`, says where it staged each system extension and
    /// which app asked for it.
    @Test func readsWhereMacOSStagedASystemExtension() throws {
        let directory = try TemporaryDirectory()
        let database: [String: Any] = ["extensions": [
            [
                "identifier": "com.example.filter",
                "bundleVersion": ["CFBundleShortVersionString": "2.0", "CFBundleVersion": "200"],
                "stagedBundleURL": ["relative": "file:///Library/SystemExtensions/UUID/com.example.filter.systemextension/"],
                "container": ["bundlePath": "/Applications/Example.app"],
            ],
            ["identifier": "com.example.broken"],
        ]]
        let url = try directory.file(
            "db.plist",
            contents: PropertyListSerialization.data(fromPropertyList: database, format: .xml, options: 0)
        )

        let records = AppExtensions.systemExtensionRecords(at: url)

        #expect(records.map(\.identifier) == ["com.example.filter", "com.example.broken"])
        #expect(records.first?.version == "2.0/200")
        #expect(records.first?.staged?.lastPathComponent == "com.example.filter.systemextension")
        #expect(records.first?.container == "/Applications/Example.app")
        #expect(records.last?.staged == nil)
    }

    /// During an update one identifier has two records, one per version. A row is paired with its own version's
    /// record, and with another version's never: no path is better than the path of the other copy. With only
    /// one record, the identifier is enough.
    @Test func pairsARowOnlyWithItsOwnVersionsRecord() {
        func record(_ version: String) -> AppExtensions.SystemExtensionRecord {
            .init(identifier: "com.example.filter", version: version, staged: URL(filePath: "/Library/SystemExtensions/\(version)/filter.systemextension"), container: nil)
        }
        let old = record("1.0/100")
        let new = record("2.0/200")

        #expect(AppExtensions.record(for: "com.example.filter", version: "2.0/200", among: [old, new])?.version == "2.0/200")
        #expect(AppExtensions.record(for: "com.example.filter", version: "2.0", among: [old, new]) == nil, "paired with another version's copy")
        #expect(AppExtensions.record(for: "com.example.filter", version: "2.0", among: [new])?.version == "2.0/200")
        #expect(AppExtensions.record(for: "com.example.other", version: nil, among: [old, new]) == nil)
    }

    /// An extension that waits for the user's approval has not been turned off. Calling it off would send the user
    /// looking for a switch to turn back on.
    @Test func tellsWaitingForApprovalApartFromTurnedOff() {
        #expect(AppExtensions.election(forSystemExtensionState: "activated enabled") == .on)
        #expect(AppExtensions.election(forSystemExtensionState: "activated disabled") == .off)
        #expect(AppExtensions.election(forSystemExtensionState: "activated waiting for user") == .waitingForApproval)
        #expect(AppExtensions.election(forSystemExtensionState: "terminated waiting to uninstall on reboot") == .beingRemoved)
        #expect(AppExtensions.election(forSystemExtensionState: "uninstalling") == .beingRemoved)
        #expect(AppExtensions.election(forSystemExtensionState: "activated enabling") == .changing)
        #expect(AppExtensions.election(forSystemExtensionState: "activated waiting to upgrade") == .changing)
        #expect(AppExtensions.election(forSystemExtensionState: "something macOS added later") == .unknown)
    }

    /// Reads the system extensions of the Mac the test runs on, so it runs only when asked for
    /// (`PEEL_TEST_THIS_MAC=1`). A Mac with no system extension fails it, since there would be nothing to check.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PEEL_TEST_THIS_MAC"] != nil))
    func pointsAtTheStagedCopyAndNamesTheAppThatBroughtIt() async throws {
        let scan = await AppExtensions.scan()
        try #require(!scan.unanswered.contains(.systemExtension), "systemextensionsctl gave no answer")
        let found = scan.extensions.filter { $0.kind == .systemExtension }
        try #require(!found.isEmpty, "this Mac has no system extension to read")

        for item in found {
            let path = try #require(item.url, "\(item.identifier) reported no path").path(percentEncoded: false)
            #expect(path.hasPrefix("/Library/SystemExtensions/"), "\(item.identifier) is at \(path)")
            #expect(path.hasSuffix(".systemextension/") || path.hasSuffix(".dext/"), "\(item.identifier) is at \(path)")
            #expect(FileManager.default.fileExists(atPath: path), "\(item.identifier) is at \(path), which isn't there")
            #expect(item.reportedState?.isEmpty == false, "\(item.identifier) reported no state")
            #expect(item.owner != nil, "nothing says which app brought \(item.identifier)")
        }
    }

    /// An ExtensionKit bundle says what it plugs into under its own key, and has no `NSExtension` at all.
    @Test func readsTheExtensionPointOfBothKindsOfBundle() {
        let old: [String: Any] = ["NSExtension": ["NSExtensionPointIdentifier": "com.apple.share-services"]]
        let new: [String: Any] = ["EXAppExtensionAttributes": ["EXExtensionPointIdentifier": "com.apple.appintents-extension"]]

        #expect(AppExtensions.extensionPoint(in: old) == "com.apple.share-services")
        #expect(AppExtensions.extensionPoint(in: new) == "com.apple.appintents-extension")
        #expect(AppExtensions.extensionPoint(in: ["CFBundleName": "Thing"]) == nil)
        #expect(AppExtensions.extensionPoint(in: nil) == nil)
    }

    /// Each kind comes from its own tool, so a tool that gives no answer leaves out its own kind and nothing
    /// else, and the scan says which kind is missing: what it lists is then only part of what is installed.
    @Test func saysWhichKindMacOSGaveNoAnswerAbout() async {
        let none = "0 extension(s)"
        let appsOnly: AppExtensions.Runner = { tool, _ in tool.hasSuffix("/pluginkit") ? Self.pluginkit : nil }
        let systemOnly: AppExtensions.Runner = { tool, _ in tool.hasSuffix("/systemextensionsctl") ? none : nil }
        let both: AppExtensions.Runner = { tool, _ in tool.hasSuffix("/pluginkit") ? Self.pluginkit : none }

        #expect(await AppExtensions.scan(exclusions: .none, run: appsOnly).unanswered == [.systemExtension])
        #expect(await AppExtensions.scan(exclusions: .none, run: systemOnly).unanswered == [.appExtension])
        #expect(
            await AppExtensions.scan(exclusions: .none, run: { _, _ in nil }).unanswered
                == Set(AppExtension.Kind.allCases)
        )
        #expect(await AppExtensions.scan(exclusions: .none, run: both).unanswered.isEmpty)
    }

    private static let pluginkit = """
             com.apple.example.Sample(1.0)\t6299ACC7-6EDA-4A38-9BD4-89444C604682\t2026-09-20 17:23:02 +0000\t\
        /System/Library/Sample.appex
         (1 plug-in)
        """

    /// `pluginkit` always lists macOS's own extensions and ends by counting them, and `systemextensionsctl` starts
    /// by counting its rows. A listing read short of its count is one Peel no longer understands, not a Mac with none.
    @Test func aListingReadShortOfItsCountIsNoAnswer() async {
        let rows = """
        2 extension(s)
        enabled\tactive\tteamID\tbundleID (version)\tname\t[state]
        *\t*\tTC3Q7MAJXF\torg.example.filter (1.0/100)\tExample Filter\t[activated enabled]
        """
        let spaced = Self.pluginkit.replacing("\t", with: "   ")

        #expect(await AppExtensions.appExtensions { _, _ in Self.pluginkit } == [])
        #expect(await AppExtensions.appExtensions { _, _ in spaced } == nil)
        #expect(await AppExtensions.appExtensions { _, _ in "" } == nil)
        #expect(await AppExtensions.systemExtensions { _, _ in "0 extension(s)" } == [])
        #expect(await AppExtensions.systemExtensions { _, _ in rows } == nil)
        let one = rows.replacing("2 extension(s)", with: "1 extension(s)")
        #expect(await AppExtensions.systemExtensions { _, _ in one }?.count == 1)
        #expect(await AppExtensions.systemExtensions { _, _ in "" } == nil)
    }

    /// Scans the Mac the test runs on. The scan only reads, so the test runs every time.
    @Test func readsThisMacWithoutTouchingIt() async {
        let scan = await AppExtensions.scan()
        let found = scan.extensions
        #expect(scan.unanswered.isEmpty, "this Mac's listing was not read whole")
        #expect(
            found.allSatisfy { $0.url.map { !AppExtensions.isTheSystemsOwn($0.path(percentEncoded: false)) } ?? true }
        )
        #expect(Set(found.map(\.id)).count == found.count, "the same extension was listed twice")
    }

    @Test func readsTheSystemExtensionsAnAppCarries() throws {
        let directory = try TemporaryDirectory()
        let app = try directory.directory("Example.app")
        let extensions = "Example.app/Contents/Library/SystemExtensions"
        func info(_ identifier: String, _ name: String) throws -> Data {
            try PropertyListSerialization.data(
                fromPropertyList: ["CFBundleIdentifier": identifier, "CFBundleName": name], format: .xml, options: 0
            )
        }
        try directory.file(
            "\(extensions)/org.example.filter.systemextension/Contents/Info.plist",
            contents: info("org.example.filter", "Example Filter")
        )
        try directory.file("\(extensions)/org.example.driver.dext/Info.plist", contents: info("org.example.driver", "Example Driver"))
        try directory.file("\(extensions)/notes.txt")

        let carried = AppExtensions.systemExtensions(carriedBy: app)

        #expect(carried.map(\.identifier) == ["org.example.driver", "org.example.filter"])
        #expect(carried.map(\.name) == ["Example Driver", "Example Filter"])
    }
}
