import Foundation
@testable import PeelCore
import Synchronization
import Testing

/// Answers every request from a table of canned replies, keyed by host, and sends nothing anywhere.
private final class CannedProtocol: URLProtocol, @unchecked Sendable {
    struct Reply {
        var status = 200
        var body = Data()
        var headers: [String: String]?
    }

    static let replies = Mutex<[String: Reply]>([:])
    static let asked = Mutex<[String]>([])
    static let addresses = Mutex<[String]>([])
    static let times = Mutex<[ContinuousClock.Instant]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let host = request.url?.host() ?? ""
        Self.asked.withLock { $0.append(host) }
        Self.times.withLock { $0.append(.now) }
        Self.addresses.withLock { $0.append(request.url?.absoluteString ?? "") }
        guard let reply = Self.replies.withLock({ $0[host] }), let url = request.url,
              let response = HTTPURLResponse(
                url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Fails every request as macOS does when this Mac isn't online.
private final class OfflineProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
}

/// The part of the update check that talks to the network, against replies written here.
@Suite(.serialized) struct UpdateCheckerTests {
    private var checker: UpdateChecker {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CannedProtocol.self]
        return UpdateChecker(session: URLSession(configuration: configuration), appStoreWindow: .forTheAppStore())
    }

    @Test func aCheckFromAMacThatIsntOnlineLearnsNothing() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineProtocol.self]
        let offline = UpdateChecker(
            session: URLSession(configuration: configuration), appStoreWindow: .forTheAppStore()
        )
        let app = InstalledApp(
            url: URL(filePath: "/Applications/Fed.app"), bundleIdentifier: "org.example.fed", name: "Fed",
            version: "1.0", updateFeed: .sparkle(URL(string: "https://feed.example.com/appcast.xml")!)
        )

        let away = await offline.answer(for: app)
        let down = await checker.answer(for: app)

        #expect(away.status == .failed && away.wasOffline)
        #expect(down.status == .failed && !down.wasOffline)
        let page = UpdateAnswer(
            status: .updateAvailable(version: "1.1", source: .developer, releaseNotes: nil),
            notesPage: URL(string: "https://notes.example.com/1.1.html")
        )
        #expect(await offline.releaseNotes(for: app, answer: page) == .offline)
        #expect(UpdateChecker.configuration.waitsForConnectivity)
    }

    /// Apple's lookup answers HTTP 400 for a region with no store, such as `150` (Europe), `001` (the world), or
    /// `AQ`. A region that is not two letters, or no region at all, asks the US store.
    @Test func asksAStoreThatExists() {
        #expect(UpdateChecker.storefront(of: Locale(identifier: "ro_RO")) == "ro")
        #expect(UpdateChecker.storefront(of: Locale(identifier: "en_US@rg=dezzzz")) == "de")
        #expect(UpdateChecker.storefront(of: Locale(identifier: "en_150")) == "us")
        #expect(UpdateChecker.storefront(of: Locale(identifier: "en_001")) == "us")
        #expect(UpdateChecker.storefront(of: Locale(identifier: "en")) == "us")
    }

    /// A two-letter region with no store, such as `AQ`, is refused too, so a 400 is retried with the US store.
    @Test func aRefusedStoreIsAskedOnceMoreAsTheUnitedStates() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CannedProtocol.self]
        let antarctic = UpdateChecker(
            session: URLSession(configuration: configuration), locale: Locale(identifier: "en_AQ"),
            appStoreWindow: .forTheAppStore()
        )
        let sold = InstalledApp(
            url: URL(filePath: "/Applications/Notes Pro.app"),
            bundleIdentifier: "com.example.notes",
            name: "Notes Pro",
            version: "1.0",
            isFromAppStore: true,
            updateFeed: .appStore(.mac)
        )
        reply("itunes.apple.com", status: 400, #"{"errorMessage":"Invalid value(s) for key(s): [country]"}"#)
        #expect(await antarctic.status(for: sold) == .failed)
        #expect(CannedProtocol.asked.withLock { $0 } == ["itunes.apple.com", "itunes.apple.com"])
        reply("itunes.apple.com", status: 503, "")
        #expect(await antarctic.status(for: sold) == .failed)
        #expect(CannedProtocol.asked.withLock { $0 } == ["itunes.apple.com"], "only a refusal is asked again")
    }

    private func sparkleApp(version: String = "1.0", build: String = "100") -> InstalledApp {
        InstalledApp(
            url: URL(filePath: "/Applications/Editor.app"), bundleIdentifier: "com.example.editor", name: "Editor",
            version: version, buildVersion: build, updateFeed: .sparkle(URL(string: "https://feed.example.com/appcast.xml")!)
        )
    }

    private func reply(_ host: String, status: Int = 200, _ body: String) {
        CannedProtocol.replies.withLock { $0 = [host: .init(status: status, body: Data(body.utf8))] }
        CannedProtocol.asked.withLock { $0 = [] }
    }

    private func appcast(_ items: String) -> String {
        "<rss xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\"><channel>\(items)</channel></rss>"
    }

    /// Sparkle compares build numbers, so a feed's `sparkle:version` is compared with the app's `CFBundleVersion`.
    @Test func comparesTheFeedsBuildWithTheAppsBuild() async {
        reply("feed.example.com", appcast("<item><enclosure url=\"https://feed.example.com/a.zip\" sparkle:version=\"101\" sparkle:shortVersionString=\"1.0\" /></item>"))
        #expect(
            await checker.status(for: sparkleApp())
                == .updateAvailable(version: "1.0", source: .developer, releaseNotes: nil)
        )

        reply("feed.example.com", appcast("<item><enclosure url=\"https://feed.example.com/a.zip\" sparkle:version=\"100\" sparkle:shortVersionString=\"1.0\" /></item>"))
        #expect(await checker.status(for: sparkleApp()) == .upToDate)
    }

    @Test func asksNothingAboutAnAppFromSetapp() async throws {
        reply("feed.example.com", appcast("<item><enclosure url=\"https://feed.example.com/a.zip\" sparkle:version=\"200\" sparkle:shortVersionString=\"2.0\" /></item>"))
        func inspected(_ identifier: String, in directory: borrowing TemporaryDirectory) throws -> InstalledApp {
            let info = [
                "CFBundleIdentifier": identifier, "CFBundleShortVersionString": "1.0", "CFBundleVersion": "100",
                "SUFeedURL": "https://feed.example.com/appcast.xml",
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try data.write(to: directory.file("Sample.app/Contents/Info.plist"))
            return try #require(AppInspector.inspect(directory.url.appending(path: "Sample.app")))
        }

        let fromSetapp = try TemporaryDirectory()
        #expect(await checker.status(for: try inspected("org.example.Sample-setapp", in: fromSetapp)) == .unsupported)
        #expect(CannedProtocol.asked.withLock { $0 }.isEmpty)

        let sold = try TemporaryDirectory()
        #expect(
            await checker.status(for: try inspected("org.example.Sample", in: sold))
                == .updateAvailable(version: "2.0", source: .developer, releaseNotes: nil)
        )
        #expect(CannedProtocol.asked.withLock { $0 } == ["feed.example.com"])
    }

    @Test func asksTheAppStoreNoFasterThanItsWindowLets() async {
        CannedProtocol.replies.withLock {
            $0 = ["itunes.apple.com": .init(body: Data(#"{"resultCount":0,"results":[]}"#.utf8))]
        }
        CannedProtocol.times.withLock { $0 = [] }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CannedProtocol.self]
        let checker = UpdateChecker(
            session: URLSession(configuration: configuration),
            appStoreWindow: RequestWindow(limit: 2, window: .milliseconds(600))
        )
        let apps = (1...3).map { index in
            InstalledApp(
                url: URL(filePath: "/Applications/Store \(index).app"), bundleIdentifier: "org.example.store\(index)",
                name: "Store \(index)", version: "1.0", isFromAppStore: true, updateFeed: .appStore(.mac)
            )
        }

        await withTaskGroup(of: Void.self) { group in
            for app in apps {
                group.addTask { _ = await checker.status(for: app, preference: .appStore) }
            }
        }

        let times = CannedProtocol.times.withLock { $0 }.sorted()
        #expect(times.count == 3)
        #expect(times.count == 3 && times[2] - times[0] >= .milliseconds(400), "\(times)")
    }

    /// Only a 200 is an answer, and what is not an appcast is a failed check.
    @Test func readsOnlyAProperAnswer() async {
        reply("feed.example.com", status: 404, appcast("<item><sparkle:version>999</sparkle:version></item>"))
        #expect(await checker.status(for: sparkleApp()) == .failed)

        reply("feed.example.com", "<html>Sign in to continue</html")
        #expect(await checker.status(for: sparkleApp()) == .failed)
    }

    /// A working feed whose every release needs a newer macOS is not a feed that is down. Counted as a failure,
    /// it would read "Update check failed" and be retried every two days, forever.
    @Test func aFeedWithNothingForThisMacIsUpToDate() async {
        reply("feed.example.com", appcast("<item><sparkle:version>200</sparkle:version><sparkle:minimumSystemVersion>99.0</sparkle:minimumSystemVersion></item>"))
        #expect(await checker.status(for: sparkleApp()) == .upToDate)
    }

    /// A release for Apple silicon only is an update on this Mac when it has Apple silicon, and nothing at all when
    /// it has an Intel processor.
    @Test func aReleaseForAppleSiliconIsAnUpdateOnlyOnAppleSilicon() async {
        reply("feed.example.com", appcast("<item><sparkle:version>200</sparkle:version><sparkle:shortVersionString>2.0</sparkle:shortVersionString><sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements></item>"))
        let expected: UpdateStatus = HostArchitecture.isAppleSilicon
            ? .updateAvailable(version: "2.0", source: .developer, releaseNotes: nil)
            : .upToDate
        #expect(await checker.status(for: sparkleApp()) == expected)
    }

    private let homebrewChecked = Date(timeIntervalSince1970: 1_792_315_250)

    private func checking(at now: Date) -> UpdateChecker {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CannedProtocol.self]
        return UpdateChecker(
            session: URLSession(configuration: configuration), clock: { now }, appStoreWindow: .forTheAppStore()
        )
    }

    private var feedlessApp: InstalledApp {
        InstalledApp(url: URL(filePath: "/Applications/Example.app"), bundleIdentifier: "com.example.app", name: "Example", version: "1.0")
    }

    private var fedApp: InstalledApp {
        InstalledApp(
            url: feedlessApp.url, bundleIdentifier: feedlessApp.bundleIdentifier, name: feedlessApp.name,
            version: "1.0", buildVersion: "100", updateFeed: sparkleApp().updateFeed
        )
    }

    private func cask(latest: String = "1.0", checked: Date?) -> HomebrewPackage {
        HomebrewPackage(
            name: "example", kind: .cask, installedVersion: "1.0", latestVersion: latest, isOutdated: latest != "1.0",
            appNames: ["Example.app"]
        ).noting(lastUpdateCheck: checked)
    }

    /// Many apps installed with Homebrew carry no update feed of their own. In the automatic mode, Homebrew's
    /// answer is used for them rather than "Can't check for updates".
    @Test func automaticFallsBackToWhatHomebrewKnows() async {
        let app = feedlessApp
        let current = cask(checked: homebrewChecked)
        let checker = checking(at: homebrewChecked + 60 * 60)
        reply("nowhere.example.com", "")

        #expect(await checker.status(for: app, preference: .automatic, casks: [current]) == .upToDate)
        #expect(await checker.status(for: app, preference: .automatic, casks: []) == .unsupported)
        #expect(CannedProtocol.asked.withLock { $0 }.isEmpty)

        // Its own feed fails: Homebrew's answer still stands.
        reply("feed.example.com", status: 500, "")
        var fed = sparkleApp()
        fed = InstalledApp(
            url: app.url,
            bundleIdentifier: app.bundleIdentifier,
            name: app.name,
            version: "1.0",
            updateFeed: fed.updateFeed
        )
        #expect(await checker.status(for: fed, preference: .automatic, casks: [current]) == .upToDate)
    }

    @Test func homebrewCanNotSayAnAppIsUpToDateADayAfterItChecked() async {
        let later = checking(at: homebrewChecked + 2 * Homebrew.autoUpdateInterval)
        let current = [cask(checked: homebrewChecked)]
        reply("nowhere.example.com", "")

        #expect(await later.status(for: feedlessApp, preference: .automatic, casks: current) == .unsupported)
        #expect(await later.status(for: feedlessApp, preference: .homebrew, casks: current) == .unsupported)
        #expect(
            await later.status(for: feedlessApp, preference: .automatic, casks: [cask(checked: nil)]) == .unsupported,
            "no check known"
        )
        #expect(
            await later.status(for: feedlessApp, casks: [cask(latest: "2.0", checked: nil)])
                == .updateAvailable(version: "2.0", source: .homebrew, releaseNotes: nil)
        )
        #expect(CannedProtocol.asked.withLock { $0 }.isEmpty)

        reply("feed.example.com", appcast("<item><enclosure url=\"https://feed.example.com/a.zip\" sparkle:version=\"200\" sparkle:shortVersionString=\"2.0\" /></item>"))
        #expect(
            await later.status(for: fedApp, preference: .homebrew, casks: current)
                == .updateAvailable(version: "2.0", source: .developer, releaseNotes: nil)
        )
        #expect(CannedProtocol.asked.withLock { $0 } == ["feed.example.com"])

        reply("feed.example.com", status: 500, "")
        #expect(await later.status(for: fedApp, preference: .automatic, casks: current) == .failed)
    }

    @Test func answersWithoutAServerWhatHomebrewAndTheAppAloneDecide() async {
        let recent = checking(at: homebrewChecked + 60 * 60)
        let later = checking(at: homebrewChecked + 2 * Homebrew.autoUpdateInterval)
        let current = [cask(checked: homebrewChecked)]
        let outdated = [cask(latest: "2.0", checked: nil)]
        let update = UpdateStatus.updateAvailable(version: "2.0", source: .homebrew, releaseNotes: nil)
        reply("nowhere.example.com", "")

        for preference in UpdateSource.allCases {
            for casks in [outdated, current, []] {
                for checker in [recent, later] {
                    let decided = checker.statusWithoutAsking(for: feedlessApp, preference: preference, casks: casks)
                    #expect(decided != nil)
                    #expect(await decided == checker.status(for: feedlessApp, preference: preference, casks: casks))
                }
            }
        }
        #expect(CannedProtocol.asked.withLock { $0 }.isEmpty)

        #expect(recent.statusWithoutAsking(for: feedlessApp, preference: .automatic, casks: current) == .upToDate)
        #expect(later.statusWithoutAsking(for: feedlessApp, preference: .automatic, casks: current) == .unsupported)
        #expect(later.statusWithoutAsking(for: feedlessApp, preference: .developer, casks: outdated) == update)
        #expect(later.statusWithoutAsking(for: fedApp, preference: .automatic, casks: outdated) == update)
        #expect(recent.statusWithoutAsking(for: fedApp, preference: .automatic, casks: current) == nil, "feed first")
        #expect(recent.statusWithoutAsking(for: fedApp, preference: .homebrew, casks: current) == .upToDate)
        #expect(later.statusWithoutAsking(for: fedApp, preference: .homebrew, casks: current) == nil, "its feed answers")
        #expect(recent.statusWithoutAsking(for: fedApp, preference: .developer, casks: outdated) == nil)
    }

    @Test func namesTheCaskHomebrewHasNotCheckedForADay() {
        let recent = checking(at: homebrewChecked + 60 * 60)
        let later = checking(at: homebrewChecked + 2 * Homebrew.autoUpdateInterval)
        let current = [cask(checked: homebrewChecked)]
        let unknown = [cask(checked: nil)]
        let outdated = [cask(latest: "2.0", checked: homebrewChecked)]

        #expect(later.homebrewCannotTell(about: feedlessApp, preference: .automatic, casks: current)?.cask.name == "example")
        #expect(later.homebrewCannotTell(about: feedlessApp, preference: .homebrew, casks: current)?.cask.name == "example")
        #expect(recent.homebrewCannotTell(about: feedlessApp, preference: .automatic, casks: unknown)?.cask.name == "example")
        #expect(recent.homebrewCannotTell(about: feedlessApp, preference: .automatic, casks: current) == nil)
        #expect(
            later.homebrewCannotTell(about: feedlessApp, preference: .automatic, casks: outdated) == nil,
            "an update Homebrew knows of is an answer"
        )
        #expect(later.homebrewCannotTell(about: feedlessApp, preference: .developer, casks: current)?.cask.name == "example")
        #expect(later.homebrewCannotTell(about: feedlessApp, preference: .appStore, casks: current)?.cask.name == "example")
        #expect(later.homebrewCannotTell(about: soldApp, preference: .appStore, casks: current) == nil, "Apple asked")
        #expect(later.homebrewCannotTell(about: fedApp, preference: .automatic, casks: current) == nil, "its feed")
        #expect(later.homebrewCannotTell(about: feedlessApp, preference: .automatic, casks: []) == nil)
        let notChecked = later.homebrewCannotTell(about: feedlessApp, preference: .automatic, casks: current)
        #expect(notChecked?.reason == .notCheckedRecently)
    }

    @Test func saysWhyItCanNotCheckAnApp() {
        let checker = checking(at: homebrewChecked)
        let iPad = InstalledApp(
            url: URL(filePath: "/Applications/Board.app"), bundleIdentifier: "org.example.board", name: "Board",
            version: "1.0", isFromAppStore: true, updateFeed: .appStore(.iPhoneAndiPad(item: 1, store: "de"))
        )
        let mac = InstalledApp(
            url: URL(filePath: "/Applications/Notes Pro.app"), bundleIdentifier: "org.example.notes", name: "Notes Pro",
            version: "1.0", isFromAppStore: true, updateFeed: .appStore(.mac)
        )
        let unversioned = InstalledApp(
            url: URL(filePath: "/Applications/Tool.app"), bundleIdentifier: "org.example.tool", name: "Tool"
        )

        #expect(checker.whyItCannotCheck(iPad, preference: .automatic, casks: []) == .notInTheAppStore(store: "de"))
        #expect(checker.whyItCannotCheck(mac, preference: .automatic, casks: []) == .notInTheAppStore(store: nil))
        #expect(checker.whyItCannotCheck(feedlessApp, preference: .automatic, casks: []) == .namesNoFeed)
        #expect(checker.whyItCannotCheck(unversioned, preference: .automatic, casks: []) == .namesNoVersion)
        let stale = checking(at: homebrewChecked + 2 * Homebrew.autoUpdateInterval)
        let current = cask(checked: homebrewChecked)
        let reason = stale.whyItCannotCheck(feedlessApp, preference: .automatic, casks: [current])
        #expect(reason == .homebrewCannotTell(HomebrewCannotTell(cask: current, reason: .notCheckedRecently)))
    }

    @Test func anAnswerHoldsForTheLongestWaitBetweenTwoChecks() {
        let day: TimeInterval = 24 * 60 * 60
        #expect(checking(at: homebrewChecked + 6 * day).stillHolds(answeredAt: homebrewChecked))
        #expect(!checking(at: homebrewChecked + 8 * day).stillHolds(answeredAt: homebrewChecked))
        #expect(!checking(at: homebrewChecked).stillHolds(answeredAt: nil))
    }

    @Test func takesNoUpToDateFromHomebrewWhereItComparesNoVersion() {
        let recent = checking(at: homebrewChecked + 60 * 60)
        let newest = HomebrewPackage(
            name: "example", kind: .cask, installedVersion: "latest", latestVersion: "latest", appNames: ["Example.app"]
        ).noting(lastUpdateCheck: homebrewChecked)
        let updatesItself = HomebrewPackage(
            name: "example", kind: .cask, installedVersion: "1.0", latestVersion: "1.0", appNames: ["Example.app"],
            appUpdatesItself: true
        ).noting(lastUpdateCheck: homebrewChecked)
        let leftToTheApp = updatesItself.noting([.leavesAppsThatUpdateThemselves])
        let compared = updatesItself.noting([])

        #expect(recent.statusWithoutAsking(for: feedlessApp, preference: .automatic, casks: [newest]) == .unsupported)
        #expect(
            recent.statusWithoutAsking(for: feedlessApp, preference: .automatic, casks: [leftToTheApp]) == .unsupported
        )
        #expect(recent.statusWithoutAsking(for: feedlessApp, preference: .automatic, casks: [compared]) == .upToDate)
        #expect(recent.statusWithoutAsking(for: fedApp, preference: .homebrew, casks: [newest]) == nil, "its feed answers")
        let installsTheNewest = recent.homebrewCannotTell(about: feedlessApp, preference: .automatic, casks: [newest])
        let leftToItsApp = recent.homebrewCannotTell(about: feedlessApp, preference: .homebrew, casks: [leftToTheApp])
        #expect(installsTheNewest?.reason == .installsTheNewest)
        #expect(leftToItsApp?.reason == .leftToTheApp)
        #expect(recent.homebrewCannotTell(about: feedlessApp, preference: .automatic, casks: [compared]) == nil)
    }

    private var soldApp: InstalledApp {
        InstalledApp(
            url: feedlessApp.url, bundleIdentifier: feedlessApp.bundleIdentifier, name: feedlessApp.name,
            version: "1.0", isFromAppStore: true, updateFeed: .appStore(.mac)
        )
    }

    @Test func everyPreferenceTurnsToHomebrewOnceItsOwnSourceCanNotAnswer() async {
        let recent = checking(at: homebrewChecked + 60 * 60)
        let later = checking(at: homebrewChecked + 2 * Homebrew.autoUpdateInterval)
        let current = [cask(checked: homebrewChecked)]
        let outdated = [cask(latest: "2.0", checked: homebrewChecked)]
        let update = UpdateStatus.updateAvailable(version: "2.0", source: .homebrew, releaseNotes: nil)
        reply("nowhere.example.com", "")

        #expect(await recent.status(for: feedlessApp, preference: .developer, casks: current) == .upToDate)
        #expect(await recent.status(for: feedlessApp, preference: .appStore, casks: current) == .upToDate)
        #expect(await recent.status(for: feedlessApp, preference: .developer, casks: outdated) == update)
        #expect(await later.status(for: feedlessApp, preference: .developer, casks: current) == .unsupported)
        #expect(CannedProtocol.asked.withLock { $0 }.isEmpty)

        reply("feed.example.com", status: 500, "")
        #expect(await recent.status(for: fedApp, preference: .developer, casks: current) == .upToDate)
        #expect(await recent.answer(for: fedApp, preference: .developer, casks: current).standsInFor == .failed)
        #expect(await recent.answer(for: fedApp, preference: .developer, casks: []).standsInFor == nil)

        reply("feed.example.com", appcast("<item><enclosure url=\"https://feed.example.com/a.zip\" sparkle:version=\"100\" sparkle:shortVersionString=\"1.0\" /></item>"))
        #expect(await recent.status(for: fedApp, preference: .developer, casks: outdated) == .upToDate, "its feed first")
        #expect(await recent.status(for: fedApp, preference: .automatic, casks: outdated) == update)
    }

    @Test func aSourceThatHadNoAnswerGivesWayToWhatHomebrewKnowsNow() {
        let recent = checking(at: homebrewChecked + 60 * 60)
        let later = checking(at: homebrewChecked + 2 * Homebrew.autoUpdateInterval)
        let current = [cask(checked: homebrewChecked)]
        let found = UpdateStatus.updateAvailable(version: "1.1", source: .developer, releaseNotes: nil)
        let decided = { (checker: UpdateChecker, preference: UpdateSource, known: UpdateStatus?) in
            checker.statusWithoutAsking(for: fedApp, preference: preference, casks: current, known: known)
        }

        #expect(decided(recent, .developer, .failed) == .upToDate)
        #expect(decided(recent, .appStore, .unsupported) == .upToDate)
        #expect(decided(recent, .automatic, .failed) == .upToDate)
        #expect(decided(recent, .developer, .upToDate) == nil)
        #expect(decided(recent, .developer, found) == nil)
        #expect(decided(recent, .developer, nil) == nil)
        #expect(decided(later, .developer, .failed) == .failed, "Homebrew can no longer tell")
        #expect(decided(later, .appStore, .unsupported) == .unsupported)
    }

    @Test func aMacAppReadsNoIPhoneRecord() async {
        let sold = InstalledApp(
            url: URL(filePath: "/Applications/Notes Pro.app"),
            bundleIdentifier: "com.example.notes",
            name: "Notes Pro",
            version: "1.0",
            isFromAppStore: true,
            updateFeed: .appStore(.mac)
        )

        reply("itunes.apple.com", #"{"resultCount":1,"results":[{"kind":"software","version":"3.6.7","supportedDevices":["MacDesktop-MacDesktop","iPhone5s-iPhone5s","iPadAir-iPadAir"],"trackViewUrl":"https://apps.apple.com/app/id1"}]}"#)
        #expect(await checker.status(for: sold) == .unsupported)

        reply("itunes.apple.com", #"{"resultCount":1,"results":[{"kind":"mac-software","version":"2.0","trackViewUrl":"https://apps.apple.com/app/id1"}]}"#)
        #expect(
            await checker.status(for: sold)
                == .updateAvailable(
                    version: "2.0",
                    source: .appStore,
                    releaseNotes: URL(string: "https://apps.apple.com/app/id1")
                )
        )

        reply("itunes.apple.com", #"{"resultCount":0,"results":[]}"#)
        #expect(await checker.status(for: sold) == .unsupported)

        reply("itunes.apple.com", "<html>")
        #expect(await checker.status(for: sold) == .failed, "an answer Peel can't read is still a failed check")
    }

    @Test func keepsAnAppStoreUpdateWhenALaterAnswerNamesAnOlderVersion() async {
        let notes = InstalledApp(
            url: URL(filePath: "/Applications/Notes Pro.app"), bundleIdentifier: "com.example.notes", name: "Notes Pro",
            version: "1.0", isFromAppStore: true, updateFeed: .appStore(.mac)
        )
        let found = UpdateStatus.updateAvailable(version: "1.2", source: .appStore)
        let mac = { (version: String) in #"{"resultCount":1,"results":[{"kind":"mac-software","version":"\#(version)"}]}"# }

        reply("itunes.apple.com", mac("1.1"))
        #expect(await checker.status(for: notes, earlier: found) == .failed)
        reply("itunes.apple.com", mac("1.0"))
        #expect(await checker.status(for: notes, earlier: found) == .failed)
        reply("itunes.apple.com", mac("1.3"))
        #expect(await checker.status(for: notes, earlier: found) == .updateAvailable(version: "1.3", source: .appStore))
        reply("itunes.apple.com", mac("1.1"))
        #expect(await checker.status(for: notes) == .updateAvailable(version: "1.1", source: .appStore))
    }

    @Test func believesTheAppStoreNoLongerListsAnAppWithAnUpdateFoundOnlyOnTheSecondAnswer() async {
        let notes = InstalledApp(
            url: URL(filePath: "/Applications/Notes Pro.app"), bundleIdentifier: "com.example.notes", name: "Notes Pro",
            version: "1.0", isFromAppStore: true, updateFeed: .appStore(.mac)
        )
        let found = UpdateStatus.updateAvailable(version: "1.2", source: .appStore)
        reply("itunes.apple.com", #"{"resultCount":0,"results":[]}"#)

        let first = await checker.answer(for: notes, earlier: found)
        #expect(first.status == .failed && first.isNotListed)
        #expect(first.following(found) == found)
        #expect(await checker.status(for: notes, earlier: found, notListedBefore: true) == .unsupported)
        #expect(await checker.status(for: notes) == .unsupported, "with no update found, it is believed at once")
    }

    @Test func asksTheMacListingOfAMacAppSoldWithItsIPhoneVersion() async {
        let notes = { (version: String) in
            InstalledApp(
                url: URL(filePath: "/Applications/Notes.app"), bundleIdentifier: "org.example.notes", name: "Notes",
                version: version, isFromAppStore: true, updateFeed: .appStore(.mac)
            )
        }
        CannedProtocol.addresses.withLock { $0 = [] }
        reply("itunes.apple.com", #"{"resultCount":1,"results":[{"kind":"software","version":"7.1.30","supportedDevices":["MacDesktop-MacDesktop"],"trackViewUrl":"https://apps.apple.com/app/id1"}]}"#)
        #expect(
            await checker.status(for: notes("7.1.27"))
                == .updateAvailable(version: "7.1.30", source: .appStore, releaseNotes: URL(string: "https://apps.apple.com/app/id1"))
        )
        #expect(await checker.status(for: notes("7.1.30")) == .upToDate)
        let addresses = CannedProtocol.addresses.withLock { $0 }
        #expect(addresses.count == 2 && addresses.allSatisfy { $0.contains("entity=desktopSoftware") })
    }

    @Test func asksAboutAnIPhoneAppByItsListingNumberInTheStoreItCameFrom() async {
        let weather = InstalledApp(
            url: URL(filePath: "/Applications/Weather.app"), bundleIdentifier: "org.example.weather", name: "Weather",
            version: "6.9.1", isFromAppStore: true, updateFeed: .appStore(.iPhoneAndiPad(item: 1234, store: "de"))
        )
        CannedProtocol.addresses.withLock { $0 = [] }
        reply("itunes.apple.com", #"{"resultCount":1,"results":[{"kind":"software","trackId":1234,"version":"6.9.2","trackViewUrl":"https://apps.apple.com/de/app/id1234"}]}"#)
        #expect(
            await checker.status(for: weather)
                == .updateAvailable(version: "6.9.2", source: .appStore, releaseNotes: URL(string: "https://apps.apple.com/de/app/id1234"))
        )
        #expect(CannedProtocol.addresses.withLock { $0 } == ["https://itunes.apple.com/lookup?id=1234&country=de"])

        reply("itunes.apple.com", #"{"resultCount":1,"results":[{"kind":"software","trackId":5678,"version":"9.0"}]}"#)
        #expect(await checker.status(for: weather) == .unsupported, "another listing's record says nothing of this app")
    }

    @Test func checksAnIPhoneOrIPadAppOnTheMacAgainstItsOwnListing() async {
        let wrapped = { (version: String) in
            InstalledApp(
                url: URL(filePath: "/Applications/Weather.app"), bundleIdentifier: "org.example.weather",
                name: "Weather", version: version, isFromAppStore: true,
                updateFeed: .appStore(.iPhoneAndiPad(item: nil, store: nil))
            )
        }
        CannedProtocol.addresses.withLock { $0 = [] }
        reply("itunes.apple.com", #"{"resultCount":1,"results":[{"kind":"software","version":"6.9.2","trackViewUrl":"https://apps.apple.com/app/id1","artistName":"Example LLC"}]}"#)
        #expect(
            await checker.status(for: wrapped("6.9.1"))
                == .updateAvailable(version: "6.9.2", source: .appStore, releaseNotes: URL(string: "https://apps.apple.com/app/id1"))
        )
        #expect(await checker.answer(for: wrapped("6.9.1")).developer == "Example LLC")
        #expect(await checker.status(for: wrapped("6.9.2")) == .upToDate)
        #expect(CannedProtocol.addresses.withLock { $0 }.allSatisfy { !$0.contains("entity=") })

        reply("itunes.apple.com", #"{"resultCount":1,"results":[{"kind":"mac-software","version":"7.0","trackViewUrl":"https://apps.apple.com/app/id1"}]}"#)
        #expect(await checker.status(for: wrapped("6.9.2")) == .unsupported, "a Mac record says nothing of an iPad build")
    }

    /// An app whose bundle names no version, neither `CFBundleShortVersionString` nor `CFBundleVersion`, has nothing
    /// to compare a release with. Read as an empty version, any release was newer, forever. It claims no update, and
    /// nobody is asked.
    @Test func anAppThatNamesNoVersionClaimsNoUpdate() async {
        CannedProtocol.replies.withLock {
            $0 = [
                "feed.example.com": .init(body: Data(appcast("<item><sparkle:version>200</sparkle:version><sparkle:shortVersionString>2.0</sparkle:shortVersionString></item>").utf8)),
                "electron.example.com": .init(body: Data("version: 2.0.0\n".utf8)),
                "itunes.apple.com": .init(body: Data(#"{"resultCount":1,"results":[{"kind":"mac-software","version":"2.0","trackViewUrl":"https://apps.apple.com/app/id1"}]}"#.utf8)),
            ]
        }
        CannedProtocol.asked.withLock { $0 = [] }
        let feeds: [UpdateFeed] = [
            .sparkle(URL(string: "https://feed.example.com/appcast.xml")!),
            .electron(URL(string: "https://electron.example.com/latest-mac.yml")!),
            .appStore(.mac),
        ]
        for feed in feeds {
            let unversioned = InstalledApp(
                url: URL(filePath: "/Applications/Editor.app"), bundleIdentifier: "com.example.editor", name: "Editor",
                isFromAppStore: feed == .appStore(.mac), updateFeed: feed
            )
            #expect(await checker.status(for: unversioned) == .unsupported, "\(feed)")
        }
        #expect(CannedProtocol.asked.withLock { $0 }.isEmpty)
    }
    private var storeApp: InstalledApp {
        InstalledApp(
            url: URL(filePath: "/Applications/Notes Pro.app"), bundleIdentifier: "com.example.notes", name: "Notes Pro",
            version: "1.0", isFromAppStore: true, updateFeed: .appStore(.mac)
        )
    }

    @Test func readsTheNotesInTheAnswerThatFoundTheUpdate() async {
        reply("feed.example.com", appcast("<item><enclosure url=\"https://feed.example.com/a.zip\" sparkle:version=\"200\" sparkle:shortVersionString=\"2.0\" /><description><![CDATA[<ul><li>New search</li></ul>]]></description></item>"))
        #expect(await checker.answer(for: sparkleApp()).notes == ReleaseNotes("<ul><li>New search</li></ul>", format: .html))

        reply("itunes.apple.com", #"{"resultCount":1,"results":[{"kind":"mac-software","version":"2.0","releaseNotes":"• Faster search\n• Fixed a crash"}]}"#)
        #expect(await checker.answer(for: storeApp).notes == ReleaseNotes("• Faster search\n• Fixed a crash", format: .plainText))

        let chat = InstalledApp(
            url: URL(filePath: "/Applications/Chat.app"), bundleIdentifier: "com.example.chat", name: "Chat",
            version: "1.0", updateFeed: .electron(URL(string: "https://updates.example.com/latest-mac.yml")!)
        )
        reply("updates.example.com", "version: 2.0\nreleaseNotes: Fixed a crash\nfiles:\n  - url: a.zip\n")
        #expect(await checker.answer(for: chat).notes == ReleaseNotes("Fixed a crash", format: .markdown))

        reply("feed.example.com", appcast("<item><enclosure url=\"https://feed.example.com/a.zip\" sparkle:version=\"100\" sparkle:shortVersionString=\"1.0\" /><description>Old</description></item>"))
        #expect(await checker.answer(for: sparkleApp()).notes == nil, "nothing waits for an app that is up to date")
    }

    @Test func asksTheAppsOwnFeedForTheNotesOfAnUpdateHomebrewFound() async throws {
        let cask = HomebrewPackage(
            name: "editor", kind: .cask, installedVersion: "1.0", latestVersion: "2.0,200", isOutdated: true,
            appNames: ["Editor.app"]
        )
        reply("feed.example.com", appcast("<item><sparkle:version>300</sparkle:version><sparkle:shortVersionString>3.0</sparkle:shortVersionString><description>Too new</description></item><item><sparkle:version>200</sparkle:version><sparkle:shortVersionString>2.0</sparkle:shortVersionString><description>New search</description></item>"))
        let answer = await checker.answer(for: sparkleApp(), preference: .automatic, casks: [cask])

        #expect(answer.status.source == .homebrew)
        #expect(answer.notes == nil)
        #expect(CannedProtocol.asked.withLock { $0 }.isEmpty, "Homebrew's answer is found without asking anyone")
        let notes = try #require(ReleaseNotes("New search", format: .html))
        #expect(await checker.releaseNotes(for: sparkleApp(), answer: answer) == .found(notes))
        #expect(CannedProtocol.asked.withLock { $0 } == ["feed.example.com"])

        reply("feed.example.com", appcast("<item><sparkle:version>300</sparkle:version><sparkle:shortVersionString>3.0</sparkle:shortVersionString></item>"))
        #expect(await checker.releaseNotes(for: sparkleApp(), answer: answer) == .notGiven)

        reply("feed.example.com", status: 503, "")
        #expect(await checker.releaseNotes(for: sparkleApp(), answer: answer) == .unanswered)

        reply("feed.example.com", status: 404, "")
        #expect(await checker.releaseNotes(for: sparkleApp(), answer: answer) == .notGiven)
    }

    @Test func readsTheNotesPageAFeedLinksToAsSparkleDoes() async throws {
        func answer(linking page: String, _ body: Data, type: String) async -> UpdateAnswer {
            let item = "<item><enclosure url=\"https://feed.example.com/a.zip\" sparkle:version=\"200\" sparkle:shortVersionString=\"2.0\" /><sparkle:releaseNotesLink>https://notes.example.com/\(page)</sparkle:releaseNotesLink></item>"
            CannedProtocol.replies.withLock {
                $0 = [
                    "feed.example.com": .init(body: Data(appcast(item).utf8)),
                    "notes.example.com": .init(body: body, headers: ["Content-Type": type]),
                ]
            }
            CannedProtocol.asked.withLock { $0 = [] }
            return await checker.answer(for: sparkleApp())
        }

        let html = await answer(linking: "2.0.html", Data("<h2>2.0</h2><ul><li>New search</li></ul>".utf8), type: "text/html")
        #expect(html.notes == nil)
        #expect(html.notesPage == URL(string: "https://notes.example.com/2.0.html"))
        let page = try #require(ReleaseNotes("<h2>2.0</h2><ul><li>New search</li></ul>", format: .html))
        #expect(await checker.releaseNotes(for: sparkleApp(), answer: html) == .found(page))
        #expect(CannedProtocol.asked.withLock { $0 } == ["feed.example.com", "notes.example.com"])

        let markdown = await answer(linking: "2.0.md", Data("## 2.0\n- New search".utf8), type: "text/plain")
        let markdownNotes = try #require(ReleaseNotes("## 2.0\n- New search", format: .markdown))
        #expect(await checker.releaseNotes(for: sparkleApp(), answer: markdown) == .found(markdownNotes))

        let text = await answer(linking: "notes", Data("New search".utf8), type: "text/plain")
        let textNotes = try #require(ReleaseNotes("New search", format: .plainText))
        #expect(await checker.releaseNotes(for: sparkleApp(), answer: text) == .found(textNotes))

        let latin = await answer(linking: "2.0.html", "<p>Café</p>".data(using: .isoLatin1)!, type: "text/html; charset=iso-8859-1")
        let latinNotes = try #require(ReleaseNotes("<p>Café</p>", format: .html))
        #expect(await checker.releaseNotes(for: sparkleApp(), answer: latin) == .found(latinNotes))
    }

    @Test func takesANotesPageTheServerRefusesForNoNotes() async {
        let item = "<item><enclosure url=\"https://feed.example.com/a.zip\" sparkle:version=\"200\" sparkle:shortVersionString=\"2.0\" /><sparkle:releaseNotesLink>https://notes.example.com/2.0.html</sparkle:releaseNotesLink></item>"
        reply("feed.example.com", appcast(item))
        let answer = await checker.answer(for: sparkleApp())

        for status in [403, 404, 410] {
            reply("notes.example.com", status: status, "")
            #expect(await checker.releaseNotes(for: sparkleApp(), answer: answer) == .notGiven, "\(status)")
        }
        reply("notes.example.com", status: 503, "")
        #expect(await checker.releaseNotes(for: sparkleApp(), answer: answer) == .unanswered)
    }

    @Test func readsANotesPagesFormatInSparklesOrder() {
        let page = URL(string: "https://notes.example.com/2.0")!

        #expect(UpdateChecker.format(ofNotesAt: page.appendingPathExtension("md"), type: "text/plain") == .markdown)
        #expect(UpdateChecker.format(ofNotesAt: page, type: "text/x-markdown") == .markdown)
        #expect(UpdateChecker.format(ofNotesAt: page.appendingPathExtension("txt"), type: "text/html") == .plainText)
        #expect(UpdateChecker.format(ofNotesAt: page, type: "Text/Plain") == .plainText)
        #expect(UpdateChecker.format(ofNotesAt: page, type: nil) == .html)
    }

    @Test func asksForNoNotesWhereNoAddressOfTheAppGivesThem() async {
        reply("feed.example.com", appcast("<item><enclosure url=\"https://feed.example.com/a.zip\" sparkle:version=\"200\" sparkle:shortVersionString=\"2.0\" /><link>https://feed.example.com/product</link></item>"))
        let product = await checker.answer(for: sparkleApp())
        #expect(product.status.releaseNotes == URL(string: "https://feed.example.com/product"), "the product page stays the link")
        #expect(product.notesPage == nil)
        #expect(await checker.releaseNotes(for: sparkleApp(), answer: product) == .notGiven)
        #expect(CannedProtocol.asked.withLock { $0 } == ["feed.example.com"], "only the check itself")

        reply("example.com", "<p>A product page</p>")
        let named = InstalledApp(url: URL(filePath: "/Applications/Example.app"), bundleIdentifier: "com.example.app", name: "Example", version: "1.0")
        let homepage = UpdateAnswer(status: .updateAvailable(version: "2.0", source: .homebrew, releaseNotes: URL(string: "https://example.com")))
        #expect(await checker.releaseNotes(for: named, answer: homepage) == .notGiven)
        let store = UpdateAnswer(status: .updateAvailable(version: "2.0", source: .appStore, releaseNotes: URL(string: "https://example.com/app")))
        #expect(await checker.releaseNotes(for: storeApp, answer: store) == .notGiven)
        #expect(await checker.releaseNotes(for: sparkleApp(), answer: UpdateAnswer(status: .upToDate)) == .notGiven)
        #expect(CannedProtocol.asked.withLock { $0 }.isEmpty)
    }
}
