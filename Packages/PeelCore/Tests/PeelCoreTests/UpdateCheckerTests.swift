import Foundation
@testable import PeelCore
import Synchronization
import Testing

/// Answers every request from a table of canned replies, keyed by host, and sends nothing anywhere.
private final class CannedProtocol: URLProtocol, @unchecked Sendable {
    struct Reply {
        var status = 200
        var body = Data()
    }

    static let replies = Mutex<[String: Reply]>([:])
    static let asked = Mutex<[String]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let host = request.url?.host() ?? ""
        Self.asked.withLock { $0.append(host) }
        guard let reply = Self.replies.withLock({ $0[host] }), let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// The part of the update check that talks to the network, against replies written here.
@Suite(.serialized) struct UpdateCheckerTests {
    private var checker: UpdateChecker {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CannedProtocol.self]
        return UpdateChecker(session: URLSession(configuration: configuration))
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
        let antarctic = UpdateChecker(session: URLSession(configuration: configuration), locale: Locale(identifier: "en_AQ"))
        let sold = InstalledApp(url: URL(filePath: "/Applications/Notes Pro.app"), bundleIdentifier: "com.example.notes", name: "Notes Pro", version: "1.0", isFromAppStore: true, updateFeed: .appStore)
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
        #expect(await checker.status(for: sparkleApp()) == .updateAvailable(version: "1.0", source: .developer, releaseNotes: nil))

        reply("feed.example.com", appcast("<item><enclosure url=\"https://feed.example.com/a.zip\" sparkle:version=\"100\" sparkle:shortVersionString=\"1.0\" /></item>"))
        #expect(await checker.status(for: sparkleApp()) == .upToDate)
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

    /// Many apps installed with Homebrew carry no update feed of their own. In the automatic mode, Homebrew's
    /// answer is used for them rather than "Can't check for updates".
    @Test func automaticFallsBackToWhatHomebrewKnows() async {
        let app = InstalledApp(url: URL(filePath: "/Applications/Example.app"), bundleIdentifier: "com.example.app", name: "Example", version: "1.0")
        let current = HomebrewPackage(name: "example", kind: .cask, installedVersion: "1.0", latestVersion: "1.0", isOutdated: false, appNames: ["Example.app"])
        reply("nowhere.example.com", "")

        #expect(await checker.status(for: app, preference: .automatic, casks: [current]) == .upToDate)
        #expect(await checker.status(for: app, preference: .automatic, casks: []) == .unsupported)
        #expect(CannedProtocol.asked.withLock { $0 }.isEmpty)

        // Its own feed fails: Homebrew's answer still stands.
        reply("feed.example.com", status: 500, "")
        var fed = sparkleApp()
        fed = InstalledApp(url: app.url, bundleIdentifier: app.bundleIdentifier, name: app.name, version: "1.0", updateFeed: fed.updateFeed)
        #expect(await checker.status(for: fed, preference: .automatic, casks: [current]) == .upToDate)
    }

    /// Peel asks GitHub for its own latest release, the newest that is neither a draft nor a prerelease, and says a
    /// newer one is out with the release's page, where it is downloaded. A page anywhere but GitHub is not believed,
    /// and an answer in another form, or none, is a failed check.
    @Test func peelLearnsOfItsOwnNewReleaseFromGitHub() async {
        let peel = InstalledApp(url: URL(filePath: "/Applications/Peel.app"), bundleIdentifier: "com.tuguidragos.Peel", name: "Peel", version: "1.0.1", updateFeed: .gitHubRelease(GitHubRelease.peel))
        let page = "https://github.com/TuguiDragos/Peel/releases/tag/v1.0.2"

        reply("api.github.com", #"{"tag_name":"v1.0.2","html_url":"\#(page)","draft":false,"prerelease":false}"#)
        #expect(await checker.status(for: peel) == .updateAvailable(version: "1.0.2", source: .developer, releaseNotes: URL(string: page)))
        #expect(CannedProtocol.asked.withLock { $0 } == ["api.github.com"])

        reply("api.github.com", #"{"tag_name":"v1.0.2","html_url":"https://example.com/peel.dmg"}"#)
        #expect(await checker.status(for: peel) == .updateAvailable(version: "1.0.2", source: .developer, releaseNotes: nil))

        reply("api.github.com", #"{"tag_name":"v1.0.1","html_url":"https://github.com/TuguiDragos/Peel/releases/tag/v1.0.1"}"#)
        #expect(await checker.status(for: peel) == .upToDate)

        reply("api.github.com", status: 404, #"{"message":"Not Found"}"#)
        #expect(await checker.status(for: peel) == .failed)

        reply("api.github.com", "<html>")
        #expect(await checker.status(for: peel) == .failed)
    }

    /// An app sold once for iPhone, iPad, and Mac has one record, of kind "software", whose version is the
    /// iPhone's. For an app the store doesn't sell in this region, or anymore, Apple answers with no record at
    /// all. Neither is a failed check: there is no Mac version to read, so the app is `.unsupported` and is asked
    /// about again in a week, rather than read as a feed that is down and asked again every few hours.
    @Test func aUniversalPurchaseIsNotAFailedCheck() async {
        let sold = InstalledApp(url: URL(filePath: "/Applications/Notes Pro.app"), bundleIdentifier: "com.example.notes", name: "Notes Pro", version: "1.0", isFromAppStore: true, updateFeed: .appStore)

        reply("itunes.apple.com", #"{"resultCount":1,"results":[{"kind":"software","version":"3.6.7","trackViewUrl":"https://apps.apple.com/app/id1"}]}"#)
        #expect(await checker.status(for: sold) == .unsupported)

        reply("itunes.apple.com", #"{"resultCount":1,"results":[{"kind":"mac-software","version":"2.0","trackViewUrl":"https://apps.apple.com/app/id1"}]}"#)
        #expect(await checker.status(for: sold) == .updateAvailable(version: "2.0", source: .appStore, releaseNotes: URL(string: "https://apps.apple.com/app/id1")))

        reply("itunes.apple.com", #"{"resultCount":0,"results":[]}"#)
        #expect(await checker.status(for: sold) == .unsupported)

        reply("itunes.apple.com", "<html>")
        #expect(await checker.status(for: sold) == .failed, "an answer Peel can't read is still a failed check")
    }
}
