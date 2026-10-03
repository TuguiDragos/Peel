import Darwin
import Foundation
@testable import PeelCore
import Testing

struct InventoryTests {
    private func app(
        _ name: String,
        bundleIdentifier: String,
        isFromAppStore: Bool = false,
        feed: UpdateFeed? = nil
    ) -> InstalledApp {
        InstalledApp(
            url: URL(filePath: "/Applications/\(name).app", directoryHint: .isDirectory),
            bundleIdentifier: bundleIdentifier,
            name: name,
            version: "1.0",
            teamIdentifier: "ABCDE12345",
            isFromAppStore: isFromAppStore,
            updateFeed: feed
        )
    }

    /// An app's update feed says where Peel asks about new versions, not where the app came from. Only the
    /// receipt inside the bundle says App Store.
    @Test func namesWhereEachAppCameFrom() {
        let cask = HomebrewPackage(name: "bear", kind: .cask, installedVersion: "2.0", appNames: ["Bear.app"])
        let inventory = Inventory.build(
            apps: [
                app("Bear", bundleIdentifier: "net.shinyfrog.bear"),
                app("Shazam", bundleIdentifier: "com.shazam.mac", isFromAppStore: true),
                app("AdGuard", bundleIdentifier: "com.adguard.mac", feed: .sparkle(URL(string: "https://example.com/appcast.xml")!)),
                app("Code", bundleIdentifier: "com.microsoft.VSCode", feed: .appStore),
                app("Nothing", bundleIdentifier: "com.example.nothing"),
                app("Sample", bundleIdentifier: "org.example.Sample-setapp", feed: .sparkle(URL(string: "https://example.com/setapp.xml")!)),
            ],
            casks: [cask]
        )

        let sources = Dictionary(inventory.entries.map { ($0.name, $0.source) }, uniquingKeysWith: { first, _ in first })
        #expect(sources["Bear"] == "Homebrew")
        #expect(sources["Shazam"] == "App Store")
        #expect(sources["AdGuard"] == "Sparkle")
        #expect(sources["Code"] == "Unknown")
        #expect(sources["Nothing"] == "Unknown")
        #expect(sources["Sample"] == "Setapp", "Setapp keeps the app up to date, whatever feed it also carries")
        #expect(inventory.entries.first { $0.name == "Bear" }?.sourceDetail == "bear")
        #expect(inventory.entries.first { $0.name == "AdGuard" }?.sourceDetail == "https://example.com/appcast.xml")
    }

    @Test func onlyTheCopyHomebrewInstalledIsHomebrews() {
        let cask = HomebrewPackage(
            name: "sample", kind: .cask, installedVersion: "1.0",
            appNames: ["Sample.app"], appTargets: ["/Applications/Sample.app"]
        )
        let homebrews = app("Sample", bundleIdentifier: "org.example.Sample")
        let copy = InstalledApp(
            url: URL(filePath: "/Users/Shared/Applications/Sample.app", directoryHint: .isDirectory),
            bundleIdentifier: "org.example.Sample",
            name: "Sample",
            updateFeed: .sparkle(URL(string: "https://example.org/appcast.xml")!)
        )

        let entries = Inventory.build(apps: [homebrews, copy], casks: [cask]).entries

        #expect(entries.first { $0.path == "/Applications/Sample.app" }?.source == "Homebrew")
        #expect(entries.first { $0.path == "/Users/Shared/Applications/Sample.app" }?.source == "Sparkle")
    }

    /// For an app with no receipt, cask, or feed, the source is the download macOS recorded: the address a
    /// browser gives the file (`kMDItemWhereFroms`), or the download its quarantine record names in Launch
    /// Services' own list. Only a web address is kept, without what follows the path: a signed download carries
    /// its token there.
    @Test func namesWhereADownloadedAppCameFrom() throws {
        let directory = try TemporaryDirectory()
        let tagged = try directory.directory("Applications/Tagged.app")
        let quarantined = try directory.directory("Applications/Quarantined.app")
        let local = try directory.directory("Applications/Local.app")
        try directory.directory("Applications/Plain.app")
        try setAttribute("com.apple.metadata:kMDItemWhereFroms", PropertyListSerialization.data(fromPropertyList: ["https://example.com/Tagged-2.dmg?token=secret#top", "https://example.com/"], format: .binary, options: 0), on: tagged)
        try setAttribute("com.apple.metadata:kMDItemWhereFroms", PropertyListSerialization.data(fromPropertyList: ["file:///Users/me/Tagged.dmg"], format: .binary, options: 0), on: local)
        try setAttribute("com.apple.quarantine", Data("0083;66f0f0f0;Safari;7F3A6E0C-1B2D-4C5E-8F90-A1B2C3D4E5F6".utf8), on: quarantined)
        let events = directory.url.appending(path: "QuarantineEventsV2")
        try sqlite(events, [
            "CREATE TABLE LSQuarantineEvent (LSQuarantineEventIdentifier TEXT PRIMARY KEY NOT NULL, LSQuarantineTimeStamp REAL, LSQuarantineAgentBundleIdentifier TEXT, LSQuarantineAgentName TEXT, LSQuarantineDataURLString TEXT, LSQuarantineSenderName TEXT, LSQuarantineSenderAddress TEXT, LSQuarantineTypeNumber INTEGER, LSQuarantineOriginTitle TEXT, LSQuarantineOriginURLString TEXT, LSQuarantineOriginAlias BLOB)",
            "INSERT INTO LSQuarantineEvent (LSQuarantineEventIdentifier, LSQuarantineDataURLString, LSQuarantineOriginURLString) VALUES ('7F3A6E0C-1B2D-4C5E-8F90-A1B2C3D4E5F6', 'https://downloads.example.org/Quarantined.zip?Expires=1', 'https://example.org/download')",
        ])
        let apps = ["Tagged", "Quarantined", "Local", "Plain"].map { name in
            InstalledApp(url: directory.url.appending(path: "Applications/\(name).app", directoryHint: .isDirectory), bundleIdentifier: "com.example.\(name.lowercased())", name: name)
        }

        let inventory = Inventory.build(apps: apps, origins: DownloadOrigins(events: events))

        let entries = Dictionary(inventory.entries.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        #expect(entries["Tagged"]?.source == "Downloaded")
        #expect(entries["Tagged"]?.sourceDetail == "https://example.com/Tagged-2.dmg")
        #expect(entries["Quarantined"]?.source == "Downloaded")
        #expect(entries["Quarantined"]?.sourceDetail == "https://downloads.example.org/Quarantined.zip")
        #expect(entries["Local"]?.source == "Unknown", "a file address says nothing about where the app came from")
        #expect(entries["Plain"]?.source == "Unknown")
    }

    @Test func everyDownloadedAppGetsItsOwnAddress() throws {
        let directory = try TemporaryDirectory()
        let events = directory.url.appending(path: "QuarantineEventsV2")
        let identifiers = (0..<3).map { _ in UUID().uuidString }
        try sqlite(events, [
            "CREATE TABLE LSQuarantineEvent (LSQuarantineEventIdentifier TEXT PRIMARY KEY NOT NULL, LSQuarantineTimeStamp REAL, LSQuarantineAgentBundleIdentifier TEXT, LSQuarantineAgentName TEXT, LSQuarantineDataURLString TEXT, LSQuarantineSenderName TEXT, LSQuarantineSenderAddress TEXT, LSQuarantineTypeNumber INTEGER, LSQuarantineOriginTitle TEXT, LSQuarantineOriginURLString TEXT, LSQuarantineOriginAlias BLOB)",
            "INSERT INTO LSQuarantineEvent (LSQuarantineEventIdentifier, LSQuarantineDataURLString) VALUES ('\(identifiers[0])', 'https://example.org/First.zip'), ('\(identifiers[2])', 'https://example.org/Third.zip')",
        ])
        let names = ["First", "Second", "Third"]
        let apps = try zip(names, identifiers).map { name, identifier in
            let bundle = try directory.directory("Applications/\(name).app")
            try setAttribute("com.apple.quarantine", Data("0083;66f0f0f0;Safari;\(identifier)".utf8), on: bundle)
            return InstalledApp(url: bundle, bundleIdentifier: "org.example.\(name.lowercased())", name: name)
        }

        let entries = Inventory.build(apps: apps, origins: DownloadOrigins(events: events)).entries

        #expect(entries.map(\.sourceDetail) == ["https://example.org/First.zip", nil, "https://example.org/Third.zip"])
    }

    private func setAttribute(_ name: String, _ value: Data, on url: URL) throws {
        let status = value.withUnsafeBytes { setxattr(url.path(percentEncoded: false), name, $0.baseAddress, value.count, 0, XATTR_NOFOLLOW) }
        #expect(status == 0)
    }

    private func sqlite(_ url: URL, _ statements: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/sqlite3")
        process.arguments = [url.path(percentEncoded: false), statements.joined(separator: ";") + ";"]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test func listsAppsInOrderAndKeepsTheirPathsClean() {
        let inventory = Inventory.build(apps: [
            app("Zed", bundleIdentifier: "dev.zed.Zed"),
            app("Bear", bundleIdentifier: "net.shinyfrog.bear"),
        ])

        #expect(inventory.entries.map(\.name) == ["Bear", "Zed"])
        #expect(inventory.entries.first?.path == "/Applications/Bear.app")
    }

    @Test func aBrewfileIsWhatHomebrewWrote() throws {
        let homebrews = """
            tap "org-example/tools", "git@git.example.org:org-example/homebrew-tools.git", trusted: true
            brew "org-example/tools/probe"
            cask "sample"

            """

        #expect(try Inventory.build(apps: [], brewfile: homebrews).written(as: .brewfile) == homebrews)
    }

    @Test func writesNoBrewfileWhenHomebrewDidNotAnswer() throws {
        let unread = Inventory.build(apps: [])

        #expect(throws: Inventory.HomebrewDidNotAnswer.self) { try unread.written(as: .brewfile) }
        #expect(try unread.written(as: .text) == "\n")
    }

    @Test func writesTheDayWhereTheReaderIs() throws {
        let halfPastOneInBucharest = try Date("2026-09-18T22:30:00Z", strategy: .iso8601)
        let bucharest = try #require(TimeZone(identifier: "Europe/Bucharest"))

        #expect(Inventory.day(halfPastOneInBucharest, timeZone: bucharest) == "2026-09-19")
        #expect(Inventory.day(halfPastOneInBucharest, timeZone: try #require(TimeZone(secondsFromGMT: 0))) == "2026-09-18")
    }

    @Test func writesCsvThatSurvivesCommasAndQuotes() throws {
        let odd = InstalledApp(
            url: URL(filePath: "/Applications/Odd, \"One\".app", directoryHint: .isDirectory),
            bundleIdentifier: "com.example.odd",
            name: "Odd, \"One\""
        )

        let csv = try Inventory.build(apps: [odd]).written(as: .csv)
        let lines = csv.split(separator: "\n")
        #expect(lines.first?.hasPrefix("Name,Bundle Identifier,") == true)
        #expect(lines.last?.hasPrefix("\"Odd, \"\"One\"\"\",com.example.odd,") == true)
    }

    @Test func writesJsonThatReadsBackTheSame() throws {
        let inventory = Inventory.build(apps: [app("Bear", bundleIdentifier: "net.shinyfrog.bear")])
        let json = try inventory.written(as: .json)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let read = try decoder.decode([InventoryEntry].self, from: Data(json.utf8))
        #expect(read == inventory.entries)
    }

    /// Names and versions come from another app's Info.plist. A spreadsheet treats a field that starts with `=`,
    /// `+`, `-`, or `@` as a formula, so an app could otherwise choose what opening the export does.
    @Test func csvNeverHandsASpreadsheetAFormula() throws {
        let hostile = InventoryEntry(
            name: "=HYPERLINK(\"http://example.com\",\"Click\")",
            bundleIdentifier: "com.example.app",
            version: "+1",
            build: "-2",
            source: "@Unknown",
            sourceDetail: "\t=1+1",
            teamIdentifier: "\r=2+2",
            architectures: [],
            path: "/Applications/Example.app",
            installedOn: nil,
            lastOpened: nil
        )

        let csv = try Inventory(entries: [hostile]).written(as: .csv)
        let fields = csv.split(separator: "\n")[1].split(separator: ",", omittingEmptySubsequences: false)

        for field in fields {
            let start = field.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            #expect(!["=", "+", "-", "@", "\t", "\r"].contains { start.hasPrefix($0) }, "a spreadsheet would treat \(field) as a formula")
        }
    }

    /// Every record has to have the same keys, whatever is missing from a particular app.
    @Test func jsonWritesEveryKeyOfEveryRecord() throws {
        let full = InventoryEntry(
            name: "Full", bundleIdentifier: "com.example.full", version: "1.0", build: "1",
            source: "Homebrew", sourceDetail: "full", teamIdentifier: "ABCDE12345",
            architectures: ["arm64"], path: "/Applications/Full.app", installedOn: .now, lastOpened: .now
        )
        let bare = InventoryEntry(
            name: "Bare", bundleIdentifier: "com.example.bare", version: nil, build: nil,
            source: "Unknown", sourceDetail: nil, teamIdentifier: nil,
            architectures: [], path: "/Applications/Bare.app", installedOn: nil, lastOpened: nil
        )

        let json = try Inventory(entries: [full, bare]).written(as: .json)
        let records = try #require(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
        )

        #expect(records.count == 2)
        #expect(Set(records[0].keys) == Set(records[1].keys))
        #expect(records[1]["version"] is NSNull)
        #expect(records[1]["teamIdentifier"] is NSNull)
    }
}
