import Foundation
import Observation
@testable import Peel
import PeelCore
import Synchronization
import Testing

private nonisolated final class AppcastProtocol: URLProtocol, @unchecked Sendable {
    static let body = Mutex(Data())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body.withLock { $0 })
        client?.urlProtocolDidFinishLoading(self)
    }
}

private nonisolated final class HeldProtocol: URLProtocol, @unchecked Sendable {
    static let body = Mutex(Data())
    static let arrived = Mutex<AsyncStream<Void>.Continuation?>(nil)
    static let gate = DispatchSemaphore(value: 0)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        _ = Self.arrived.withLock { $0?.yield() }
        _ = Self.gate.wait(timeout: .now() + 10)
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body.withLock { $0 })
        client?.urlProtocolDidFinishLoading(self)
    }
}

private nonisolated final class SometimesOfflineProtocol: URLProtocol, @unchecked Sendable {
    static let isOffline = Mutex(false)
    static let body = Mutex(Data())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard !Self.isOffline.withLock({ $0 }), let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body.withLock { $0 })
        client?.urlProtocolDidFinishLoading(self)
    }
}

private nonisolated final class NotesProtocol: URLProtocol, @unchecked Sendable {
    /// What the notes page answers, or nil to hold it until it is stopped.
    static let notesStatus = Mutex<Int?>(503)
    static let asked = Mutex<[String]>([])
    static let arrived = Mutex<AsyncStream<Void>.Continuation?>(nil)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, let host = url.host() else { return }
        Self.asked.withLock { $0.append(host) }
        let isFeed = host == "feed.example.com"
        if !isFeed { _ = Self.arrived.withLock { $0?.yield() } }
        guard let status = isFeed ? 200 : Self.notesStatus.withLock({ $0 }),
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if isFeed {
            client?.urlProtocol(self, didLoad: Data(#"<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><enclosure url="https://feed.example.com/u.zip" sparkle:version="101" sparkle:shortVersionString="1.1" /><sparkle:releaseNotesLink>https://notes.example.com/1.1.html</sparkle:releaseNotesLink></item></channel></rss>"#.utf8))
        }
        client?.urlProtocolDidFinishLoading(self)
    }
}

private nonisolated final class TwoFeedsProtocol: URLProtocol, @unchecked Sendable {
    static let arrived = Mutex<AsyncStream<Void>.Continuation?>(nil)
    /// A request to the held feed, with the thread it started on, where its answer has to be given.
    private struct Held: @unchecked Sendable {
        let load: TwoFeedsProtocol
        let thread: Thread
    }

    private static let held = Mutex<[Held]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard request.url?.host() == "held.example.com" else { return answer() }
        let request = Held(load: self, thread: .current)
        Self.held.withLock { $0.append(request) }
        _ = Self.arrived.withLock { $0?.yield() }
    }

    static func answerHeld() {
        let loads = held.withLock { loads in
            defer { loads = [] }
            return loads
        }
        for request in loads {
            request.load.perform(#selector(answer), on: request.thread, with: nil, waitUntilDone: false)
        }
    }

    @objc private func answer() {
        guard let url = request.url, let host = url.host(),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)
        else { return }
        let (build, version) = host == "held.example.com" ? ("100", "1.0") : ("101", "1.1")
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("""
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>\
            <enclosure url="https://\(host)/u.zip" sparkle:version="\(build)" \
            sparkle:shortVersionString="\(version)" /></item></channel></rss>
            """.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private nonisolated final class TestClock: Sendable {
    private let moment: Mutex<Date>

    init(_ moment: Date) {
        self.moment = Mutex(moment)
    }

    func now() -> Date {
        moment.withLock { $0 }
    }

    func set(_ moment: Date) {
        self.moment.withLock { $0 = moment }
    }
}

@Suite(.serialized) struct AppLibraryTests {
    @Test func aRoundRemembersItsAnswerInTheStoresItWasGiven() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = folder.appending(path: "Updated.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: bundle.appending(path: "Contents"), withIntermediateDirectories: true
        )
        let info: [String: Any] = [
            "CFBundleIdentifier": "org.example.updated", "CFBundleName": "Updated", "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0", "CFBundleVersion": "100",
            "SUFeedURL": "https://feed.example.com/appcast.xml",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundle.appending(path: "Contents/Info.plist"))
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let defaults = made.defaults
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppcastProtocol.self]
        AppcastProtocol.body.withLock {
            $0 = Data("""
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>\
            <enclosure url="https://feed.example.com/u.zip" sparkle:version="101" sparkle:shortVersionString="1.1" />\
            </item></channel></rss>
            """.utf8)
        }
        let notes = ReleaseNotesStore(url: folder.appending(path: "release-notes.json"))
        let standardBefore = UserDefaults.standard.data(forKey: SettingsKey.updateMemory)
        let library = AppLibrary(
            defaults: defaults,
            updateChecker: UpdateChecker(session: URLSession(configuration: configuration)),
            releaseNotesStore: notes
        )

        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.updated" })
        await library.checkForUpdates([app], force: true)

        #expect(library.hasUpdate(app))
        #expect(library.shownUpdateStatus(of: app)?.version == "1.1")
        let remembered = try #require(defaults.data(forKey: SettingsKey.updateMemory))
        #expect(String(decoding: remembered, as: UTF8.self).contains("org.example.updated"))
        #expect(FileManager.default.fileExists(atPath: notes.url.path(percentEncoded: false)))
        #expect(UserDefaults.standard.data(forKey: SettingsKey.updateMemory) == standardBefore)
    }

    private func soldApp(in folder: URL) throws -> URL {
        let bundle = folder.appending(path: "Sold.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: bundle.appending(path: "Contents/_MASReceipt"), withIntermediateDirectories: true
        )
        let info: [String: Any] = [
            "CFBundleIdentifier": "org.example.sold", "CFBundleName": "Sold", "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0", "CFBundleVersion": "100",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundle.appending(path: "Contents/Info.plist"))
        try Data().write(to: bundle.appending(path: "Contents/_MASReceipt/receipt"))
        return bundle
    }

    private func library(
        with defaults: UserDefaults,
        notesIn folder: URL,
        clock: TestClock? = nil,
        answeredBy answering: URLProtocol.Type = AppcastProtocol.self
    ) -> AppLibrary {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [answering]
        let session = URLSession(configuration: configuration)
        return AppLibrary(
            defaults: defaults,
            updateChecker: clock.map { clock in UpdateChecker(session: session, clock: { clock.now() }) }
                ?? UpdateChecker(session: session),
            releaseNotesStore: ReleaseNotesStore(url: folder.appending(path: "release-notes.json"))
        )
    }

    private let homebrewChecked = Date(timeIntervalSince1970: 1_792_315_250)

    private func caskApp(_ name: String, in folder: URL, feed: String? = nil) throws -> URL {
        let bundle = folder.appending(path: "\(name).app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: bundle.appending(path: "Contents"), withIntermediateDirectories: true
        )
        var info: [String: Any] = [
            "CFBundleIdentifier": "org.example.\(name.lowercased())", "CFBundleName": name,
            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.0", "CFBundleVersion": "100",
        ]
        info["SUFeedURL"] = feed
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundle.appending(path: "Contents/Info.plist"))
        return bundle
    }

    private func cask(_ name: String, latest: String = "1.0", checked: Date?) -> HomebrewPackage {
        HomebrewPackage(
            name: name.lowercased(), kind: .cask, installedVersion: "1.0", latestVersion: latest,
            isOutdated: latest != "1.0", appNames: ["\(name).app"]
        ).noting(lastUpdateCheck: checked)
    }

    private func listing(_ version: String) -> Data {
        Data(#"{"resultCount":1,"results":[{"kind":"mac-software","version":"\#(version)"}]}"#.utf8)
    }

    @Test func anOlderAppStoreAnswerLeavesTheUpdateItFound() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = try soldApp(in: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let library = library(with: made.defaults, notesIn: folder)

        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.sold" })
        AppcastProtocol.body.withLock { $0 = listing("1.2") }
        await library.checkForUpdates([app], force: true)
        #expect(library.shownUpdateStatus(of: app)?.version == "1.2")

        AppcastProtocol.body.withLock { $0 = listing("1.1") }
        await library.checkForUpdates([app], force: true)
        #expect(library.shownUpdateStatus(of: app)?.version == "1.2")
    }

    @Test func checkingEveryAppAgainAsksAnAppThatIsNotDue() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = try soldApp(in: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let library = library(with: made.defaults, notesIn: folder)

        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.sold" })
        AppcastProtocol.body.withLock { $0 = listing("1.0") }
        await library.checkForUpdates([app], force: true)
        #expect(library.shownUpdateStatus(of: app) == .upToDate)

        AppcastProtocol.body.withLock { $0 = listing("1.1") }
        await library.checkForUpdates([app])
        #expect(library.shownUpdateStatus(of: app) == .upToDate, "not due yet")
        library.checkEveryAppAgain()
        library.checkEveryAppAgain()
        await library.recheck?.value
        #expect(library.shownUpdateStatus(of: app)?.version == "1.1")
    }

    @Test func showsWhatHomebrewSaysOfAnAppWithNoFeedAsSoonAsHomebrewIsRead() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = try caskApp("Tool", in: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let clock = TestClock(homebrewChecked + 60 * 60)
        let library = library(with: made.defaults, notesIn: folder, clock: clock)

        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.tool" })
        library.loadHomebrewCasks([cask("Tool", checked: homebrewChecked)], knowsItsOwnApps: true)
        #expect(library.shownUpdateStatus(of: app) == .upToDate)

        library.loadHomebrewCasks([cask("Tool", latest: "2.0", checked: homebrewChecked)], knowsItsOwnApps: true)
        #expect(library.shownUpdateStatus(of: app)?.version == "2.0")

        clock.set(homebrewChecked + 2 * Homebrew.autoUpdateInterval)
        library.loadHomebrewCasks([cask("Tool", checked: homebrewChecked)], knowsItsOwnApps: true)
        #expect(library.shownUpdateStatus(of: app) == .unsupported)
    }

    @Test func anUpdateHomebrewLearnsOfReplacesTheUpToDateItGaveBefore() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = try caskApp("Tool", in: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let library = library(with: made.defaults, notesIn: folder, clock: TestClock(homebrewChecked + 60 * 60))

        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.tool" })
        library.loadHomebrewCasks([cask("Tool", checked: homebrewChecked)], knowsItsOwnApps: true)
        await library.checkForUpdates([app], force: true)
        #expect(library.shownUpdateStatus(of: app) == .upToDate)

        library.loadHomebrewCasks([cask("Tool", latest: "2.0", checked: homebrewChecked)], knowsItsOwnApps: true)
        #expect(library.shownUpdateStatus(of: app)?.version == "2.0")
    }

    @Test func aRoundTakesBackHomebrewsUpToDateOnceItsCheckIsADayOld() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = try caskApp("Tool", in: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let clock = TestClock(homebrewChecked + 60 * 60)
        let library = library(with: made.defaults, notesIn: folder, clock: clock)

        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.tool" })
        library.loadHomebrewCasks([cask("Tool", checked: homebrewChecked)], knowsItsOwnApps: true)
        await library.checkForUpdates([app], force: true)
        #expect(library.shownUpdateStatus(of: app) == .upToDate)

        clock.set(homebrewChecked + 2 * Homebrew.autoUpdateInterval)
        await library.checkForUpdates([app])
        #expect(library.shownUpdateStatus(of: app) == .unsupported, "not due, yet Homebrew can no longer tell")
    }

    @Test func homebrewsUpToDateInPlaceOfAFailedFeedEndsADayAfterHomebrewsCheck() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = try caskApp("Fed", in: folder, feed: "https://feed.example.com/appcast.xml")
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        AppcastProtocol.body.withLock { $0 = Data() }
        let clock = TestClock(homebrewChecked + 60 * 60)
        let library = library(with: made.defaults, notesIn: folder, clock: clock)

        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.fed" })
        library.loadHomebrewCasks([cask("Fed", checked: homebrewChecked)], knowsItsOwnApps: true)
        await library.checkForUpdates([app], force: true)
        #expect(library.shownUpdateStatus(of: app) == .upToDate)
        let saved = try #require(made.defaults.data(forKey: SettingsKey.updateMemory))
        let memory = try #require(UpdateMemories(data: saved))
        #expect(memory.entry(for: app)?.schedule.isRetrying == true, "the feed failed")

        clock.set(homebrewChecked + 2 * Homebrew.autoUpdateInterval)
        library.loadHomebrewCasks([cask("Fed", checked: homebrewChecked)], knowsItsOwnApps: true)
        #expect(library.shownUpdateStatus(of: app) == .failed)
    }

    @Test func homebrewsUpToDateInPlaceOfAFailedFeedEndsWhenHomebrewNoLongerHasTheApp() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = try caskApp("Fed", in: folder, feed: "https://feed.example.com/appcast.xml")
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        AppcastProtocol.body.withLock { $0 = Data() }
        let library = library(with: made.defaults, notesIn: folder, clock: TestClock(homebrewChecked + 60 * 60))

        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.fed" })
        library.loadHomebrewCasks([cask("Fed", checked: homebrewChecked)], knowsItsOwnApps: true)
        await library.checkForUpdates([app], force: true)
        #expect(library.shownUpdateStatus(of: app) == .upToDate)

        library.loadHomebrewCasks([], knowsItsOwnApps: true)
        #expect(library.shownUpdateStatus(of: app) == .failed)
    }

    @Test func homebrewsUpToDateInPlaceOfAFailedFeedLeavesTheUpdateTheFeedFound() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = try caskApp("Fed", in: folder, feed: "https://feed.example.com/appcast.xml")
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let clock = TestClock(homebrewChecked + 60 * 60)
        let library = library(with: made.defaults, notesIn: folder, clock: clock)

        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.fed" })
        library.loadHomebrewCasks([cask("Fed", checked: homebrewChecked)], knowsItsOwnApps: true)
        AppcastProtocol.body.withLock {
            $0 = Data(#"<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><enclosure url="https://feed.example.com/u.zip" sparkle:version="101" sparkle:shortVersionString="1.1" /></item></channel></rss>"#.utf8)
        }
        await library.checkForUpdates([app], force: true)
        #expect(library.shownUpdateStatus(of: app)?.version == "1.1")

        AppcastProtocol.body.withLock { $0 = Data() }
        await library.checkForUpdates([app], force: true)
        #expect(library.shownUpdateStatus(of: app)?.version == "1.1", "the feed failed")

        clock.set(homebrewChecked + 2 * Homebrew.autoUpdateInterval)
        library.loadHomebrewCasks([cask("Fed", checked: homebrewChecked)], knowsItsOwnApps: true)
        #expect(library.shownUpdateStatus(of: app)?.version == "1.1")
    }

    @Test func aFeedThatFailedKeepsNoUpdateHomebrewNoLongerReports() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = try caskApp("Fed", in: folder, feed: "https://feed.example.com/appcast.xml")
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        AppcastProtocol.body.withLock { $0 = Data() }
        let clock = TestClock(homebrewChecked + 60 * 60)
        let library = library(with: made.defaults, notesIn: folder, clock: clock)

        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.fed" })
        library.loadHomebrewCasks([cask("Fed", latest: "2.0", checked: homebrewChecked)], knowsItsOwnApps: true)
        await library.checkForUpdates([app], force: true)
        #expect(library.shownUpdateStatus(of: app)?.version == "2.0")

        clock.set(homebrewChecked + 2 * Homebrew.autoUpdateInterval)
        library.loadHomebrewCasks([cask("Fed", checked: homebrewChecked)], knowsItsOwnApps: true)
        await library.checkForUpdates([app], force: true)
        #expect(library.shownUpdateStatus(of: app) == .failed)
    }

    @Test func anUpdateHomebrewNoLongerReportsGoesAsSoonAsHomebrewIsRead() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = try caskApp("Fed", in: folder, feed: "https://feed.example.com/appcast.xml")
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let library = library(with: made.defaults, notesIn: folder, clock: TestClock(homebrewChecked + 60 * 60))

        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.fed" })
        library.loadHomebrewCasks([cask("Fed", latest: "2.0", checked: homebrewChecked)], knowsItsOwnApps: true)
        await library.checkForUpdates([app], force: true)
        #expect(library.shownUpdateStatus(of: app)?.version == "2.0")

        library.loadHomebrewCasks([cask("Fed", latest: "2.1", checked: homebrewChecked)], knowsItsOwnApps: true)
        #expect(library.shownUpdateStatus(of: app)?.version == "2.1")

        library.loadHomebrewCasks([cask("Fed", checked: homebrewChecked)], knowsItsOwnApps: true)
        #expect(library.shownUpdateStatus(of: app) == nil)
        let saved = try #require(made.defaults.data(forKey: SettingsKey.updateMemory))
        let memory = try #require(UpdateMemories(data: saved))
        #expect(memory.entry(for: app) == nil, "its feed answers at the next round")
    }

    @Test func aRoundAsksEveryAppEvenWhenAppsLeaveTheListBeforeTheirAnswers() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let bundles = try (1...9).map { try caskApp("App\($0)", in: folder, feed: "https://feed.example.com/appcast.xml") }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        AppcastProtocol.body.withLock {
            $0 = Data(#"<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><enclosure url="https://feed.example.com/u.zip" sparkle:version="101" sparkle:shortVersionString="1.1" /></item></channel></rss>"#.utf8)
        }
        let library = library(with: made.defaults, notesIn: folder)
        #expect(await library.reveal(Array(bundles.prefix(8))))
        let asked = library.apps.filter { $0.name.hasPrefix("App") }.sorted { $0.name < $1.name }
        for bundle in bundles.prefix(7) { try FileManager.default.removeItem(at: bundle) }
        #expect(await library.reveal([bundles[8]]))

        await library.checkForUpdates(asked, force: true)

        let last = try #require(asked.last)
        #expect(asked.count == 8 && last.name == "App8")
        #expect(library.hasUpdate(last), "the eighth app was asked once the first seven left the list")
    }

    @Test func aRoundWhileThisMacIsntOnlineKeepsWhatWasKnown() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = try caskApp("Fed", in: folder, feed: "https://feed.example.com/appcast.xml")
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        SometimesOfflineProtocol.body.withLock {
            $0 = Data(#"<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><enclosure url="https://feed.example.com/u.zip" sparkle:version="100" sparkle:shortVersionString="1.0" /></item></channel></rss>"#.utf8)
        }
        SometimesOfflineProtocol.isOffline.withLock { $0 = false }
        defer { SometimesOfflineProtocol.isOffline.withLock { $0 = false } }
        let library = library(with: made.defaults, notesIn: folder, answeredBy: SometimesOfflineProtocol.self)
        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.fed" })
        await library.checkForUpdates([app], force: true)
        let remembered = { () -> UpdateMemories? in
            made.defaults.data(forKey: SettingsKey.updateMemory).flatMap(UpdateMemories.init(data:))
        }
        let known = remembered()
        #expect(library.shownUpdateStatus(of: app) == .upToDate)

        SometimesOfflineProtocol.isOffline.withLock { $0 = true }
        await library.checkForUpdates([app], force: true)

        #expect(library.shownUpdateStatus(of: app) == .upToDate)
        #expect(known != nil && remembered() == known, "nothing learned, nothing put off")
    }

    @Test func anAppStoreUpdateStaysUntilTwoAnswersInARowListNoSuchApp() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = try soldApp(in: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let library = library(with: made.defaults, notesIn: folder)

        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.sold" })
        AppcastProtocol.body.withLock { $0 = listing("1.2") }
        await library.checkForUpdates([app], force: true)
        #expect(library.shownUpdateStatus(of: app)?.version == "1.2")

        AppcastProtocol.body.withLock { $0 = Data(#"{"resultCount":0,"results":[]}"#.utf8) }
        await library.checkForUpdates([app], force: true)
        #expect(library.shownUpdateStatus(of: app)?.version == "1.2")

        await library.checkForUpdates([app], force: true)
        #expect(library.shownUpdateStatus(of: app) == .unsupported)
    }

    @Test func notesNoServerAnsweredWaitForTheirTurnUnlessThePersonAsks() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = try caskApp("Fed", in: folder, feed: "https://feed.example.com/appcast.xml")
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        NotesProtocol.notesStatus.withLock { $0 = 503 }
        NotesProtocol.asked.withLock { $0 = [] }
        let library = library(with: made.defaults, notesIn: folder, answeredBy: NotesProtocol.self)
        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.fed" })

        await library.checkForUpdates([app], force: true)
        #expect(library.hasUpdate(app))
        #expect(NotesProtocol.asked.withLock { $0 } == ["feed.example.com", "notes.example.com"])

        await library.checkForUpdates([app])
        #expect(NotesProtocol.asked.withLock { $0 }.count == 2, "the next round asks nothing")

        await library.checkForUpdates([app], force: true)
        #expect(NotesProtocol.asked.withLock { $0 }.suffix(2) == ["feed.example.com", "notes.example.com"])
    }

    @Test func aStoppedRoundPutsNoNotesOff() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = try caskApp("Fed", in: folder, feed: "https://feed.example.com/appcast.xml")
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        NotesProtocol.notesStatus.withLock { $0 = nil }
        defer { NotesProtocol.notesStatus.withLock { $0 = 503 } }
        let (arrivals, arrival) = AsyncStream.makeStream(of: Void.self)
        NotesProtocol.arrived.withLock { $0 = arrival }
        defer { NotesProtocol.arrived.withLock { $0 = nil } }
        let library = library(with: made.defaults, notesIn: folder, answeredBy: NotesProtocol.self)
        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.fed" })

        let round = Task { await library.checkForUpdates([app], force: true) }
        for await _ in arrivals { break }
        round.cancel()
        await round.value

        #expect(library.hasUpdate(app))
        #expect(library.releaseNotes.asks("org.example.fed", version: "1.1"))
    }

    @Test func anUpToDateNoCheckRenewsSaysNothingAfterTheLongestWait() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = try caskApp("Fed", in: folder, feed: "https://feed.example.com/appcast.xml")
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        AppcastProtocol.body.withLock {
            $0 = Data("""
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>\
            <enclosure url="https://feed.example.com/u.zip" sparkle:version="100" sparkle:shortVersionString="1.0" />\
            </item></channel></rss>
            """.utf8)
        }
        let now = Date.now
        let clock = TestClock(now)
        let library = library(with: made.defaults, notesIn: folder, clock: clock)
        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.fed" })
        await library.checkForUpdates([app], force: true)
        #expect(library.shownUpdateStatus(of: app) == .upToDate)

        made.defaults.set(false, forKey: SettingsKey.checksForAppUpdates)
        clock.set(now + 24 * 60 * 60)
        #expect(library.shownUpdateStatus(of: app) == .upToDate)
        clock.set(now + 30 * 24 * 60 * 60)
        #expect(library.shownUpdateStatus(of: app) == nil)
    }

    @Test func theRoundRescanStartsSaysWhenItEnds() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = try caskApp("Fed", in: folder, feed: "https://feed.example.com/appcast.xml")
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        AppcastProtocol.body.withLock { $0 = Data() }
        let library = library(with: made.defaults, notesIn: folder)
        #expect(await library.reveal([bundle]))

        library.checkEveryAppAgain()
        #expect(library.isCheckingEveryApp)
        let replaced = library.recheck
        library.checkEveryAppAgain()
        await replaced?.value
        #expect(library.isCheckingEveryApp, "the end of a round a newer one replaced says nothing")
        await library.recheck?.value
        #expect(!library.isCheckingEveryApp)
    }

    @Test func anAppShownFromElsewhereIsNeitherCountedNorExported() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = try caskApp("Fed", in: folder, feed: "https://feed.example.com/appcast.xml")
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        AppcastProtocol.body.withLock {
            $0 = Data("""
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>\
            <enclosure url="https://feed.example.com/u.zip" sparkle:version="101" sparkle:shortVersionString="1.1" />\
            </item></channel></rss>
            """.utf8)
        }
        let library = library(with: made.defaults, notesIn: folder)
        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.fed" })

        await library.checkForUpdates([app], force: true)

        #expect(library.hasUpdate(app))
        #expect(library.visibleApps(matching: "").waiting.map(\.id) == [app.id])
        #expect(library.installedApps.isEmpty)
        #expect(library.appsWithUpdates.isEmpty)
        #expect(library.menuBarUpdateCount == 0)
    }

    @Test func anExportMarksNoAppAsHomebrewsWhenHomebrewDidNotAnswer() {
        let earlier = [HomebrewPackage(name: "fed", kind: .cask, installedVersion: "1.0", appNames: ["Fed.app"])]

        let silent = InventoryExport.casks(isInstalled: true, hasAnswered: false, packages: earlier)
        let answered = InventoryExport.casks(isInstalled: true, hasAnswered: true, packages: earlier)
        let none = InventoryExport.casks(isInstalled: false, hasAnswered: false, packages: nil)
        #expect(silent.casks.isEmpty && silent.didNotAnswer)
        #expect(answered.casks == earlier && !answered.didNotAnswer)
        #expect(none.casks.isEmpty && !none.didNotAnswer)
    }

    @Test func twoCopiesOfAnAppAtTwoBuildsKeepAnAnswerEach() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        func copy(_ name: String, version: String, build: String, feed: String?) throws -> URL {
            let bundle = folder.appending(path: "\(name).app", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(
                at: bundle.appending(path: "Contents"), withIntermediateDirectories: true
            )
            var info: [String: Any] = [
                "CFBundleIdentifier": "org.example.twin", "CFBundleName": name, "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": version, "CFBundleVersion": build,
            ]
            info["SUFeedURL"] = feed
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: bundle.appending(path: "Contents/Info.plist"))
            return bundle
        }
        let released = try copy("Twin", version: "1.0", build: "100", feed: "https://feed.example.com/appcast.xml")
        let beta = try copy("Twin Beta", version: "2.0", build: "200", feed: nil)
        let made = try MadeUpDefaults()
        defer { made.forget() }
        AppcastProtocol.body.withLock {
            $0 = Data("""
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>\
            <enclosure url="https://feed.example.com/u.zip" sparkle:version="101" sparkle:shortVersionString="1.1" />\
            </item></channel></rss>
            """.utf8)
        }
        let library = library(with: made.defaults, notesIn: folder)
        #expect(await library.reveal([released, beta]))
        let copies = library.apps.filter { $0.bundleIdentifier == "org.example.twin" }
        #expect(copies.count == 2)

        await library.checkForUpdates(copies, force: true)

        let data = made.defaults.data(forKey: SettingsKey.updateMemory)
        let saved = try #require(data.flatMap(UpdateMemories.init(data:)))
        let releasedCopy = try #require(copies.first { $0.version == "1.0" })
        let betaCopy = try #require(copies.first { $0.version == "2.0" })
        #expect(saved.entry(for: releasedCopy)?.status.version == "1.1")
        #expect(saved.entry(for: betaCopy)?.status == .unsupported)
    }

    @Test func theListMovesAnUpdateFoundDuringARoundOnceTheRoundEnds() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let quick = try caskApp("Quick", in: folder, feed: "https://quick.example.com/appcast.xml")
        let held = try caskApp("Held", in: folder, feed: "https://held.example.com/appcast.xml")
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let (arrivals, arrival) = AsyncStream.makeStream(of: Void.self)
        TwoFeedsProtocol.arrived.withLock { $0 = arrival }
        defer { TwoFeedsProtocol.arrived.withLock { $0 = nil } }
        let library = library(with: made.defaults, notesIn: folder, answeredBy: TwoFeedsProtocol.self)
        #expect(await library.reveal([quick, held]))
        let apps = library.apps.filter { ["org.example.quick", "org.example.held"].contains($0.bundleIdentifier) }
        let found = try #require(apps.first { $0.bundleIdentifier == "org.example.quick" })

        let round = Task { await library.checkForUpdates(apps, force: true) }
        for await _ in arrivals { break }
        for await hasIt in Observations({ library.hasUpdate(found) }) where hasIt { break }
        #expect(library.visibleApps(matching: "").waiting.isEmpty, "rows stay put while the round runs")

        TwoFeedsProtocol.answerHeld()
        await round.value
        #expect(library.visibleApps(matching: "").waiting.map(\.id) == [found.id])
    }

    @Test func anAppFromACaskThatInstallsTheNewestCanNotBeChecked() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = try caskApp("Tool", in: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let library = library(with: made.defaults, notesIn: folder, clock: TestClock(homebrewChecked + 60 * 60))

        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.tool" })
        let newest = HomebrewPackage(
            name: "tool", kind: .cask, installedVersion: "latest", latestVersion: "latest", appNames: ["Tool.app"]
        ).noting(lastUpdateCheck: homebrewChecked)
        library.loadHomebrewCasks([newest], knowsItsOwnApps: true)

        #expect(library.shownUpdateStatus(of: app) == .unsupported)
        guard case .homebrewCannotTell(let silence) = library.whyItCannotCheck(app) else {
            Issue.record("Homebrew is the reason")
            return
        }
        #expect(silence.reason == .installsTheNewest)
    }

    @Test func aWebAppIsNotCheckedForUpdates() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = folder.appending(path: "Wiki.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: bundle.appending(path: "Contents"), withIntermediateDirectories: true
        )
        let info: [String: Any] = [
            "CFBundleIdentifier": "org.example.Browser.app.wiki", "CFBundleName": "Wiki",
            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1",
            "CrBundleIdentifier": "org.example.Browser", "CrAppModeShortcutID": "wiki",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundle.appending(path: "Contents/Info.plist"))
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let library = library(with: made.defaults, notesIn: folder)
        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.Browser.app.wiki" })
        #expect(app.webApp == .browser(identifier: "org.example.Browser"))

        await library.checkForUpdates([app], force: true)

        #expect(library.updateStatuses[app.id] == nil)
        #expect(library.shownUpdateStatus(of: app) == nil)
    }

    @Test func anAppPeelNeverChecksGetsNothingFromHomebrew() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = try caskApp("Tool", in: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let library = library(with: made.defaults, notesIn: folder, clock: TestClock(homebrewChecked + 60 * 60))

        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.tool" })
        library.setIgnored(true, for: app)
        library.loadHomebrewCasks([cask("Tool", latest: "2.0", checked: homebrewChecked)], knowsItsOwnApps: true)
        #expect(library.updateStatuses[app.id] == nil)
    }

    @Test func anAnswerThatCrossedANewReadingOfHomebrewGivesWayToItsCasks() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = try caskApp("Fed", in: folder, feed: "https://feed.example.com/appcast.xml")
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        HeldProtocol.body.withLock {
            $0 = Data(#"<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><enclosure url="https://feed.example.com/u.zip" sparkle:version="100" sparkle:shortVersionString="1.0" /></item></channel></rss>"#.utf8)
        }
        let (arrivals, arrival) = AsyncStream.makeStream(of: Void.self)
        HeldProtocol.arrived.withLock { $0 = arrival }
        defer { HeldProtocol.arrived.withLock { $0 = nil } }
        let clock = TestClock(homebrewChecked + 60 * 60)
        let library = library(with: made.defaults, notesIn: folder, clock: clock, answeredBy: HeldProtocol.self)

        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.fed" })
        library.loadHomebrewCasks([cask("Fed", checked: homebrewChecked)], knowsItsOwnApps: true)
        let round = Task { await library.checkForUpdates([app], force: true) }
        for await _ in arrivals { break }
        library.loadHomebrewCasks([cask("Fed", latest: "2.0", checked: homebrewChecked)], knowsItsOwnApps: true)
        #expect(library.shownUpdateStatus(of: app)?.version == "2.0")

        HeldProtocol.gate.signal()
        await round.value
        #expect(library.shownUpdateStatus(of: app)?.version == "2.0", "the feed was asked with what Homebrew said before")
    }

    @Test func withTheAppsOwnFeedPreferredHomebrewAnswersForAnAppWithNoFeed() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = try caskApp("Tool", in: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        made.defaults.set(UpdateSource.developer.rawValue, forKey: SettingsKey.updateSource)
        let clock = TestClock(homebrewChecked + 60 * 60)
        let library = library(with: made.defaults, notesIn: folder, clock: clock)

        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.tool" })
        library.loadHomebrewCasks([cask("Tool", checked: homebrewChecked)], knowsItsOwnApps: true)
        #expect(library.shownUpdateStatus(of: app) == .upToDate)

        library.loadHomebrewCasks([cask("Tool", latest: "2.0", checked: homebrewChecked)], knowsItsOwnApps: true)
        #expect(library.shownUpdateStatus(of: app)?.version == "2.0")

        clock.set(homebrewChecked + 2 * Homebrew.autoUpdateInterval)
        library.loadHomebrewCasks([cask("Tool", checked: homebrewChecked)], knowsItsOwnApps: true)
        #expect(library.shownUpdateStatus(of: app) == .unsupported)
    }

    @Test func aFeedThatFailedGivesWayToWhatHomebrewKnowsOnceHomebrewIsRead() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let bundle = try caskApp("Fed", in: folder, feed: "https://feed.example.com/appcast.xml")
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        made.defaults.set(UpdateSource.developer.rawValue, forKey: SettingsKey.updateSource)
        AppcastProtocol.body.withLock { $0 = Data() }
        let library = library(with: made.defaults, notesIn: folder, clock: TestClock(homebrewChecked + 60 * 60))

        #expect(await library.reveal([bundle]))
        let app = try #require(library.apps.first { $0.bundleIdentifier == "org.example.fed" })
        await library.checkForUpdates([app], force: true)
        #expect(library.shownUpdateStatus(of: app) == .failed)

        library.loadHomebrewCasks([cask("Fed", checked: homebrewChecked)], knowsItsOwnApps: true)
        #expect(library.shownUpdateStatus(of: app) == .upToDate)
    }
}
