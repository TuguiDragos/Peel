import Foundation
@testable import PeelCore
import Testing

struct VersionComparisonTests {
    @Test(arguments: [
        ("2.11", "2.11.0", ComparisonResult.orderedSame),
        ("1.34.0", "1.33.9", .orderedDescending),
        ("1.9", "1.10", .orderedAscending),
        ("2259", "2258", .orderedDescending),
        ("2.0", "2.0b3", .orderedDescending),
        ("v3.1.0", "3.1", .orderedSame),
        ("2.19.0.2258 release", "2.19.0.2258", .orderedAscending),
        // A component too large for an `Int` counts as the largest there is, so the rest keep their places.
        ("1.99999999999999999999.5", "1.2.9", .orderedDescending),
        // Build metadata and a build number in parentheses say nothing about which is newer.
        ("1.2.3+45", "1.2.3", .orderedSame),
        ("1.2.3 (456)", "1.2.3", .orderedSame),
    ])
    func compares(lhs: String, rhs: String, expected: ComparisonResult) {
        #expect(VersionComparison.compare(lhs, rhs) == expected)
    }
}

struct AppcastTests {
    private func latestItem(in feed: String, systemVersion: String = "26.7.0") -> AppcastItem? {
        if case .latest(let item) = Appcast.read(Data(feed.utf8), systemVersion: systemVersion, isAppleSilicon: true) { item } else { nil }
    }

    /// A feed shared with WinSparkle lists a Windows build beside the Mac one, and the last release for an
    /// older macOS can set a maximum system version below this one. Sparkle skips both, so Peel does too, or
    /// it would announce an update the app itself says does not exist.
    @Test func skipsItemsForAnotherSystemOrAnOlderMacOS() throws {
        let feed = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><enclosure url="https://example.com/win.exe" sparkle:version="510" sparkle:os="windows" /></item>
        <item><sparkle:version>505</sparkle:version><sparkle:maximumSystemVersion>15.9</sparkle:maximumSystemVersion></item>
        <item><enclosure url="https://example.com/mac.zip" sparkle:version="500" sparkle:os="macos" /></item>
        </channel></rss>
        """
        #expect(try #require(latestItem(in: feed)).version == "500")
    }

    /// Sparkle does not offer an Intel Mac a release that lists `arm64` among its hardware requirements, so neither
    /// does Peel. The list is split at spaces and commas and read without case, as Sparkle reads it.
    @Test func skipsAReleaseForAppleSiliconOnAnIntelMac() throws {
        let feed = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><sparkle:version>600</sparkle:version><sparkle:hardwareRequirements>ARM64</sparkle:hardwareRequirements></item>
        <item><sparkle:version>550</sparkle:version><sparkle:hardwareRequirements>metal,arm64</sparkle:hardwareRequirements></item>
        <item><sparkle:version>500</sparkle:version><sparkle:hardwareRequirements>metal</sparkle:hardwareRequirements></item>
        </channel></rss>
        """
        let read = { (isAppleSilicon: Bool) in Appcast.read(Data(feed.utf8), systemVersion: "26.7.0", isAppleSilicon: isAppleSilicon) }
        guard case .latest(let onIntel) = read(false), case .latest(let onAppleSilicon) = read(true) else {
            Issue.record("the feed was not read")
            return
        }
        #expect(onIntel.version == "500")
        #expect(onAppleSilicon.version == "600")
        #expect(onAppleSilicon.hardwareRequirements == ["arm64"])

        let onlyForAppleSilicon = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><sparkle:version>600</sparkle:version><sparkle:hardwareRequirements>arm64 metal</sparkle:hardwareRequirements></item>
        </channel></rss>
        """
        #expect(Appcast.read(Data(onlyForAppleSilicon.utf8), systemVersion: "26.7.0", isAppleSilicon: false) == .nothingForThisMac)
    }

    @Test func tellsAHealthyFeedWithNothingForThisMacFromOneItCannotRead() {
        let future = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><sparkle:version>4</sparkle:version><sparkle:minimumSystemVersion>99.0</sparkle:minimumSystemVersion></item>
        </channel></rss>
        """
        #expect(Appcast.read(Data(future.utf8), systemVersion: "26.7.0", isAppleSilicon: true) == .nothingForThisMac)
        #expect(Appcast.read(Data("<rss><channel>".utf8), systemVersion: "26.7.0", isAppleSilicon: true) == .unreadable)
    }

    /// Sparkle reads the version from the enclosure's attribute first, and from the element only when there is
    /// none. An item's `<link>` is usually the product page, not the release notes.
    @Test func followsSparklesOrderForVersionsAndNotes() throws {
        let feed = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
        <link>https://example.com/product</link>
        <sparkle:version>1</sparkle:version>
        <sparkle:releaseNotesLink>https://example.com/notes.html</sparkle:releaseNotesLink>
        <enclosure url="https://example.com/a.zip" sparkle:version="2" />
        </item></channel></rss>
        """
        let item = try #require(latestItem(in: feed))
        #expect(item.version == "2")
        #expect(item.releaseNotes == URL(string: "https://example.com/notes.html"))
    }

    /// Sparkle lets a feed give release notes per language with `xml:lang`. The reader's language comes first,
    /// then notes with no language. A language the reader did not ask for is the last resort.
    @Test func picksTheReleaseNotesInTheReadersLanguage() throws {
        let feed = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
        <sparkle:version>2</sparkle:version>
        <sparkle:releaseNotesLink xml:lang="de">https://example.com/de.html</sparkle:releaseNotesLink>
        <sparkle:releaseNotesLink>https://example.com/en.html</sparkle:releaseNotesLink>
        <sparkle:releaseNotesLink xml:lang="fr">https://example.com/fr.html</sparkle:releaseNotesLink>
        </item></channel></rss>
        """
        let item = try #require(latestItem(in: feed))
        #expect(item.releaseNotes != nil)
        let links: [(language: String, url: URL)] = [
            ("de", URL(string: "https://example.com/de.html")!), ("", URL(string: "https://example.com/en.html")!),
            ("fr", URL(string: "https://example.com/fr.html")!),
        ]
        #expect(Appcast.preferred(links, languages: ["fr-FR", "en"]) == URL(string: "https://example.com/fr.html"))
        #expect(Appcast.preferred(links, languages: ["ro-RO", "en"]) == URL(string: "https://example.com/en.html"))
        #expect(Appcast.preferred(Array(links.filter { !$0.language.isEmpty }), languages: ["ro"]) == URL(string: "https://example.com/de.html"))
    }

    @Test func readsNewestItemFromElements() throws {
        let feed = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><sparkle:version>2257</sparkle:version><sparkle:shortVersionString>2.18.9</sparkle:shortVersionString></item>
        <item>
          <sparkle:version>2258</sparkle:version>
          <sparkle:shortVersionString>2.19.0.2258 release</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>12.7.6</sparkle:minimumSystemVersion>
          <enclosure url="https://example.com/app.dmg" length="1" />
        </item>
        </channel></rss>
        """
        let item = try #require(latestItem(in: feed))
        #expect(item.version == "2258")
        #expect(item.displayVersion == "2.19.0.2258 release")
    }

    @Test func readsVersionsFromEnclosureAttributes() throws {
        let feed = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><enclosure url="https://example.com/a.zip" sparkle:version="310" sparkle:shortVersionString="3.1" /></item>
        </channel></rss>
        """
        let item = try #require(latestItem(in: feed))
        #expect(item.version == "310")
        #expect(item.displayVersion == "3.1")
    }

    @Test func skipsChannelsAndItemsForNewerSystems() throws {
        let feed = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><sparkle:version>5</sparkle:version><sparkle:channel>beta</sparkle:channel></item>
        <item><sparkle:version>4</sparkle:version><sparkle:minimumSystemVersion>28.0</sparkle:minimumSystemVersion></item>
        <item><sparkle:version>3</sparkle:version></item>
        </channel></rss>
        """
        let item = try #require(latestItem(in: feed))
        #expect(item.version == "3")
    }

}

struct ElectronUpdaterTests {
    @Test func buildsFeedURLs() {
        let generic = "provider: generic\nurl: https://cdn-desktop.tunein.com/release/\nupdaterCacheDirName: example-desktop-updater\n"
        #expect(ElectronUpdater.feedURL(fromConfiguration: generic)?.absoluteString == "https://cdn-desktop.tunein.com/release/latest-mac.yml")

        let github = "owner: example\nrepo: 'tool'\nprovider: github\nchannel: beta\n"
        #expect(ElectronUpdater.feedURL(fromConfiguration: github)?.absoluteString == "https://github.com/example/tool/releases/latest/download/beta-mac.yml")

        #expect(ElectronUpdater.feedURL(fromConfiguration: "provider: generic\nurl: http://insecure.example.com/\n") == nil)
        #expect(ElectronUpdater.feedURL(fromConfiguration: "provider: s3\nbucket: example\n") == nil)

        // An app that updates from a company's own GitHub server names it with `host`. Asking github.com
        // instead would send its owner and repository to a server they were never meant for.
        #expect(ElectronUpdater.feedURL(fromConfiguration: "provider: github\nhost: git.example.com\nowner: example\nrepo: tool\n") == nil)
        #expect(ElectronUpdater.feedURL(fromConfiguration: "provider: github\nhost: github.com\nowner: example\nrepo: tool\n") != nil)
    }

    @Test func readsVersionFromFeed() {
        let feed = "version: 1.33.0\nfiles:\n  - url: TuneIn-1.33.0-universal-mac.zip\n    version: 9.9.9\nreleaseDate: '2026-03-30T19:23:16.416Z'\n"
        #expect(ElectronUpdater.version(fromFeed: feed) == "1.33.0")
    }
}

struct AppStoreLookupTests {
    /// Only a Mac record counts: an iPhone app can share the identifier, but its version is not the Mac's. An
    /// answer with no Mac record is still an answer, unlike a reply that cannot be read.
    @Test func usesOnlyMacApps() {
        let mac = #"{"resultCount":1,"results":[{"kind":"mac-software","version":"2.11"}]}"#
        #expect(AppStoreLookup.answer(in: Data(mac.utf8)) == .mac(version: "2.11", page: nil, developer: nil))
        // The developer is `artistName`, the name the App Store shows. For Apple's apps that is "Apple", the
        // name Peel also gives the apps Apple signs outside the store; `sellerName` would say "Apple Inc."
        let sold = #"{"resultCount":1,"results":[{"kind":"mac-software","version":"26.1","artistName":"Apple","sellerName":"Apple Inc."}]}"#
        #expect(AppStoreLookup.answer(in: Data(sold.utf8)) == .mac(version: "26.1", page: nil, developer: "Apple"))

        let iPhone = #"{"resultCount":1,"results":[{"kind":"software","version":"26.36.74"}]}"#
        #expect(AppStoreLookup.answer(in: Data(iPhone.utf8)) == .noMacRecord)

        // No record at all: the store doesn't sell the app in this region, or anymore. That is an answer too.
        #expect(AppStoreLookup.answer(in: Data(#"{"resultCount":0,"results":[]}"#.utf8)) == .noMacRecord)
        #expect(AppStoreLookup.answer(in: Data("<html>".utf8)) == .unreadable)
    }

    @Test func encodesLookupURL() {
        let url = AppStoreLookup.url(bundleIdentifier: "com.shazam.mac.Shazam", country: "ro")
        #expect(url?.absoluteString == "https://itunes.apple.com/lookup?bundleId=com.shazam.mac.Shazam&country=ro")
    }
}

struct UpdateFeedDetectionTests {
    private func bundle(info: [String: String], files: [String: String] = [:], in directory: borrowing TemporaryDirectory) throws -> URL {
        var plist = info
        plist["CFBundleIdentifier"] = "com.example.app"
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: directory.file("Example.app/Contents/Info.plist"))
        for (path, contents) in files {
            try Data(contents.utf8).write(to: directory.file("Example.app/Contents/\(path)"))
        }
        return directory.url.appending(path: "Example.app")
    }

    @Test func detectsSparkleOverHTTPSOnly() throws {
        let secure = try TemporaryDirectory()
        let app = try #require(AppInspector.inspect(try bundle(info: ["SUFeedURL": "https://example.com/appcast.xml"], in: secure)))
        #expect(app.updateFeed == .sparkle(URL(string: "https://example.com/appcast.xml")!))

        let insecure = try TemporaryDirectory()
        let other = try #require(AppInspector.inspect(try bundle(info: ["SUFeedURL": "http://example.com/appcast.xml"], in: insecure)))
        #expect(other.updateFeed == nil)
    }

    /// Only an app that came from the App Store is looked up there. Sending every other app's identifier to
    /// itunes.apple.com would send the list of installed apps, which Peel's Privacy settings say it never sends.
    @Test func doesNotAskAppleAboutAppsThatDidNotComeFromTheAppStore() throws {
        let directory = try TemporaryDirectory()
        let app = try #require(AppInspector.inspect(try bundle(info: [:], in: directory)))
        #expect(app.updateFeed == nil)

        let store = try TemporaryDirectory()
        let fromStore = try #require(AppInspector.inspect(try bundle(info: [:], files: ["_MASReceipt/receipt": ""], in: store)))
        #expect(fromStore.updateFeed == .appStore)
    }

    @Test func prefersAppStoreReceiptAndDetectsElectron() throws {
        let store = try TemporaryDirectory()
        let storeApp = try #require(AppInspector.inspect(try bundle(info: ["SUFeedURL": "https://example.com/appcast.xml"], files: ["_MASReceipt/receipt": ""], in: store)))
        #expect(storeApp.updateFeed == .appStore)

        let electron = try TemporaryDirectory()
        let electronApp = try #require(AppInspector.inspect(try bundle(info: [:], files: ["Resources/app-update.yml": "provider: generic\nurl: https://example.com/updates/"], in: electron)))
        #expect(electronApp.updateFeed == .electron(URL(string: "https://example.com/updates/latest-mac.yml")!))
    }

    /// Apps that come with macOS are kept current by Software Update, whatever feed their bundle names. The test
    /// uses a bundle with a feed, since Calculator names none and would pass with or without the rule.
    @Test func skipsSystemApps() throws {
        let directory = try TemporaryDirectory()
        let contents = try directory.directory("Example.app/Contents")
        let info = ["SUFeedURL": "https://example.com/appcast.xml"]

        #expect(UpdateFeed.detect(info: info, contents: contents, isFromAppStore: false, isSystemProtected: true) == nil)
        #expect(UpdateFeed.detect(info: info, contents: contents, isFromAppStore: false, isSystemProtected: false) == .sparkle(try #require(URL(string: "https://example.com/appcast.xml"))))
    }

    /// Peel's own copy is checked against its releases on GitHub. No other app says where it is released, so no
    /// other app is asked about there.
    @Test func onlyPeelAsksGitHubForItsLatestRelease() throws {
        let directory = try TemporaryDirectory()
        let contents = try directory.directory("Peel.app/Contents")
        let peel = UpdateFeed.detect(info: ["CFBundleIdentifier": "com.tuguidragos.Peel"], contents: contents, isFromAppStore: false, isSystemProtected: false)
        #expect(peel == .gitHubRelease(GitHubRelease.peel))
        #expect(UpdateFeed.detect(info: ["CFBundleIdentifier": "com.example.editor"], contents: contents, isFromAppStore: false, isSystemProtected: false) == nil)
    }
}

struct TeamRegistryTests {
    private func app(_ identifier: String, team: String?) -> InstalledApp {
        InstalledApp(url: URL(filePath: "/Applications/\(identifier).app"), bundleIdentifier: identifier, name: identifier, teamIdentifier: team)
    }

    /// A registry that leads nowhere cannot be read, so it reports nothing, says so, and is left as it is.
    @Test func leavesARegistryItCannotReachAsItIs() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "teams.json")
        let path = url.path(percentEncoded: false)
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: "/nowhere/teams.json")

        #expect(await TeamRegistry(url: url).check([app("com.example.app", team: "AAAA111111")]) == .init(changes: [], problem: .unreadable))

        let kind = try FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType
        #expect(kind == .typeSymbolicLink, "the registry was written over")
    }

    /// A change of signer is the one security warning the Applications tool gives. It is kept on disk and
    /// reported at every launch until the user acknowledges it.
    @Test func keepsSayingAnAppChangedHandsUntilItIsAcknowledged() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "teams.json")

        #expect(await TeamRegistry(url: url).check([app("com.example.app", team: "AAAA111111"), app("com.example.other", team: nil)]).changes.isEmpty)
        #expect(await TeamRegistry(url: url).check([app("com.example.app", team: "AAAA111111")]).changes.isEmpty)

        let changed = await TeamRegistry(url: url).check([app("com.example.app", team: "BBBB222222")]).changes
        #expect(changed.map(\.previous) == ["AAAA111111"])
        #expect(changed.map(\.current) == ["BBBB222222"])

        let nextLaunch = await TeamRegistry(url: url).check([app("com.example.app", team: "BBBB222222")]).changes
        #expect(nextLaunch.map(\.previous) == ["AAAA111111"], "the change was said once and then forgotten")
        #expect(nextLaunch.map(\.current) == ["BBBB222222"])

        #expect(await TeamRegistry(url: url).acknowledge("com.example.app") == nil)
        #expect(await TeamRegistry(url: url).check([app("com.example.app", team: "BBBB222222")]).changes.isEmpty)
    }

    /// An app signed again by the team it had has no change left to report.
    @Test func forgetsAChangeThatWasUndone() async throws {
        let directory = try TemporaryDirectory()
        let registry = TeamRegistry(url: directory.url.appending(path: "teams.json"))
        _ = await registry.check([app("com.example.app", team: "AAAA111111")])
        #expect(await registry.check([app("com.example.app", team: "BBBB222222")]).changes.count == 1)

        #expect(await registry.check([app("com.example.app", team: "AAAA111111")]).changes.isEmpty)
    }

    /// Someone who tampers with an app has no Developer ID for it, so a known team followed by none is the
    /// strongest sign of tampering. A bundle caught halfway through an update looks the same for a moment, so
    /// the change is reported only once it has lasted longer than `TeamRegistry.settlingTime`.
    @Test func saysWhenAnAppIsNoLongerSignedByADeveloper() async throws {
        let directory = try TemporaryDirectory()
        let registry = TeamRegistry(url: directory.url.appending(path: "teams.json"))
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        _ = await registry.check([app("com.example.app", team: "AAAA111111")], now: start)

        #expect(await registry.check([app("com.example.app", team: nil)], now: start.addingTimeInterval(60)).changes.isEmpty, "said at once, which an update in progress would trigger")
        let later = await registry.check([app("com.example.app", team: nil)], now: start.addingTimeInterval(60 + TeamRegistry.settlingTime + 1)).changes
        #expect(later.map(\.previous) == ["AAAA111111"])
        #expect(later.map(\.current) == [""])

        #expect(await registry.check([app("com.example.app", team: "AAAA111111")], now: start.addingTimeInterval(7_200)).changes.isEmpty, "signed again by the team it had")
    }

    /// Two copies of one app signed by different teams are acknowledged once. Otherwise each copy would count as
    /// a change from the other at every launch.
    @Test func acknowledgesASecondTeamForTheSameAppOnce() async throws {
        let directory = try TemporaryDirectory()
        let registry = TeamRegistry(url: directory.url.appending(path: "teams.json"))
        let copies = [app("com.example.app", team: "AAAA111111"), app("com.example.app", team: "BBBB222222")]
        _ = await registry.check([copies[0]])

        #expect(await registry.check(copies).changes.map(\.current) == ["BBBB222222"])
        #expect(await registry.acknowledge("com.example.app") == nil)
        #expect(await registry.check(copies).changes.isEmpty)
        #expect(await registry.check(copies.reversed()).changes.isEmpty)
    }

    @Test func writesNothingWhenNothingChanged() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "teams.json")
        _ = await TeamRegistry(url: url).check([app("com.example.app", team: "AAAA111111")])
        let written = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.modificationDate] as? Date
        try await Task.sleep(for: .milliseconds(50))

        _ = await TeamRegistry(url: url).check([app("com.example.app", team: "AAAA111111")])

        #expect(try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.modificationDate] as? Date == written)
    }

    /// A registry that cannot be read is never written over. Rebuilt from today's apps, it would hide for good a
    /// change of signer made since it was last read.
    @Test func leavesARegistryItCannotReadAlone() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "teams.json")
        _ = await TeamRegistry(url: url).check([app("com.example.app", team: "AAAA111111")])
        let before = try Data(contentsOf: url)
        try directory.setPermissions(0o000, of: "teams.json")
        defer { try? directory.setPermissions(0o644, of: "teams.json") }

        #expect(await TeamRegistry(url: url).check([app("com.example.app", team: "BBBB222222")]) == .init(changes: [], problem: .unreadable))

        try directory.setPermissions(0o644, of: "teams.json")
        #expect(try Data(contentsOf: url) == before)
        #expect(await TeamRegistry(url: url).check([app("com.example.app", team: "BBBB222222")]).changes.count == 1)
    }

    /// A registry that cannot be read says so on every check, never silently, and starting it over keeps the old
    /// file beside a new one, which records who signs each app from then on.
    @Test func startsARegistryItCannotReadOverWhenAsked() async throws {
        let directory = try TemporaryDirectory()
        let url = try directory.file("teams.json", contents: Data("{".utf8))
        let registry = TeamRegistry(url: url)

        #expect(await registry.check([app("com.example.app", team: "AAAA111111")]) == .init(changes: [], problem: .unreadable))
        #expect(await registry.acknowledge("com.example.app") == .unreadable)
        #expect(try Data(contentsOf: url) == Data("{".utf8))

        #expect(await registry.startOver())
        let kept = try FileManager.default.contentsOfDirectory(atPath: directory.url.path(percentEncoded: false))
        #expect(kept.contains { $0.hasPrefix("teams-damaged-") && $0.hasSuffix(".json") })
        #expect(await registry.check([app("com.example.app", team: "AAAA111111")]) == .init(changes: [], problem: nil))
        #expect(await registry.check([app("com.example.app", team: "BBBB222222")]).changes.map(\.current) == ["BBBB222222"])
    }

    /// Starting over sets aside only a registry that cannot be read. One that reads is what tells a change of
    /// signer apart, so it stays.
    @Test func startsOverOnlyARegistryItCannotRead() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "teams.json")
        let registry = TeamRegistry(url: url)
        _ = await registry.check([app("com.example.app", team: "AAAA111111")])

        #expect(await registry.startOver())
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.url.path(percentEncoded: false))
        #expect(!files.contains { $0.hasPrefix("teams-damaged-") })
        #expect(await registry.check([app("com.example.app", team: "BBBB222222")]).changes.map(\.previous) == ["AAAA111111"])
    }

    /// A registry that cannot be saved has not recorded what the check learned, so it says so rather than let the
    /// next launch start again from the apps as they are then.
    @Test func saysWhenTheRegistryCannotBeSaved() async throws {
        let directory = try TemporaryDirectory()
        _ = try directory.directory("Peel")
        let url = directory.url.appending(path: "Peel/teams.json")
        try directory.setPermissions(0o555, of: "Peel")
        defer { try? directory.setPermissions(0o755, of: "Peel") }

        #expect(await TeamRegistry(url: url).check([app("com.example.app", team: "AAAA111111")]) == .init(changes: [], problem: .unsaved))
        #expect(url.isMissing)

        try directory.setPermissions(0o755, of: "Peel")
        #expect(await TeamRegistry(url: url).check([app("com.example.app", team: "AAAA111111")]) == .init(changes: [], problem: nil))
        #expect(!url.isMissing)
    }

    /// A registry written by an earlier version of Peel has no pending changes in it, and still reads.
    @Test func readsARegistryWrittenBeforeChangesWereKept() async throws {
        let directory = try TemporaryDirectory()
        let url = try directory.file("teams.json", contents: Data(#"{"com.example.app":{"firstSeen":"2026-01-01T00:00:00Z","team":"AAAA111111"}}"#.utf8))

        #expect(await TeamRegistry(url: url).check([app("com.example.app", team: "BBBB222222")]).changes.map(\.previous) == ["AAAA111111"])
    }
}

struct UpdateSourceTests {
    @Test func prefersHomebrewWhenTheCaskIsOutdated() {
        let app = InstalledApp(url: URL(filePath: "/Applications/Example.app"), bundleIdentifier: "com.example.app", name: "Example")
        let cask = HomebrewPackage(
            name: "example",
            kind: .cask,
            homepage: URL(string: "https://example.com"),
            installedVersion: "1.0",
            latestVersion: "2.0",
            isOutdated: true,
            appNames: ["Example.app"]
        )

        let status = UpdateChecker().homebrewStatus(for: app, casks: [cask])
        #expect(status == .updateAvailable(version: "2.0", source: .homebrew, releaseNotes: URL(string: "https://example.com")))
        #expect(UpdateChecker().homebrewStatus(for: app, casks: []) == nil)
    }

    /// `firefox`, `firefox@beta`, and `firefox@esr` all install `Firefox.app`. With `firefox@esr` installed, the
    /// base cask, which Homebrew only knows of, matches the app too and sorts first, but has no installed
    /// version. The installed cask is the one to ask, or the waiting update is missed.
    @Test func asksTheCaskThatIsInstalledNotItsBetterKnownSibling() {
        let firefox = InstalledApp(url: URL(filePath: "/Applications/Firefox.app"), bundleIdentifier: "org.mozilla.firefox", name: "Firefox")
        let known = HomebrewPackage(name: "firefox", kind: .cask, latestVersion: "140.0", appNames: ["Firefox.app"])
        let installed = HomebrewPackage(name: "firefox@esr", kind: .cask, installedVersion: "128.1", latestVersion: "128.2", isOutdated: true, appNames: ["Firefox.app"])
        let casks = CaskEvidence.combined(installed: [installed], known: [known], receipts: [])

        #expect(casks.map(\.name) == ["firefox", "firefox@esr"], "the base cask sorts first, which is what hid the other")
        #expect(UpdateChecker().homebrewStatus(for: firefox, casks: casks) == .updateAvailable(version: "128.2", source: .homebrew, releaseNotes: nil))
        #expect(CaskEvidence.cask(for: firefox, in: casks)?.name == "firefox@esr")
    }

    @Test func showsAHomebrewVersionWithoutWhatTheDownloadNeeds() {
        let cask = UpdateStatus.updateAvailable(version: "26.10.22,802", source: .homebrew)
        #expect(cask.displayVersion == "26.10.22")
        #expect(cask.version == "26.10.22,802", "the whole string is what Skip This Version stores")
        #expect(UpdateStatus.updateAvailable(version: "1,5", source: .developer).displayVersion == "1,5")
        #expect(UpdateStatus.upToDate.displayVersion == nil)
    }

    @Test func readsReleaseNotesFromAnAppcast() {
        let feed = """
        <rss><channel><item>
        <sparkle:shortVersionString>3.2</sparkle:shortVersionString>
        <sparkle:releaseNotesLink>https://example.com/notes.html</sparkle:releaseNotesLink>
        </item></channel></rss>
        """
        guard case .latest(let item) = Appcast.read(Data(feed.utf8), systemVersion: "26.0.0", isAppleSilicon: true) else {
            Issue.record("the feed was not read")
            return
        }
        #expect(item.displayVersion == "3.2")
        #expect(item.releaseNotes == URL(string: "https://example.com/notes.html"))
    }
}

struct UpdatePreferencesTests {
    /// An app's page shows the last answer about it, but not an update the user muted: a skipped version, or an
    /// app Peel was told never to check, is not announced there again.
    @Test func aMutedUpdateIsNotShownAsAvailable() {
        let editor = InstalledApp(url: URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.editor", name: "Editor", version: "1.0")
        let notes = InstalledApp(url: URL(filePath: "/Applications/Notes.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.notes", name: "Notes", version: "2.0")
        let waiting = UpdateStatus.updateAvailable(version: "3.0")
        let newer = UpdateStatus.updateAvailable(version: "4.0")
        let preferences = UpdatePreferences(source: .automatic, ignoredIdentifiers: ["com.example.notes"], skippedVersions: ["com.example.editor": "3.0"])

        #expect(preferences.shownStatus(waiting, for: editor) == nil, "a skipped version was shown as available")
        #expect(preferences.shownStatus(waiting, for: notes) == nil, "an update of an ignored app was shown as available")
        #expect(preferences.shownStatus(newer, for: editor) == newer)
        #expect(preferences.shownStatus(.upToDate, for: editor) == .upToDate)
        #expect(preferences.shownStatus(.failed, for: notes) == .failed)
    }
}
