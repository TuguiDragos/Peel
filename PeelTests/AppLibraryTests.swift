import Foundation
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
        let memory = try JSONDecoder().decode([String: UpdateMemory].self, from: saved)
        #expect(memory["org.example.fed"]?.schedule.isRetrying == true, "the feed failed")

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
        let memory = try JSONDecoder().decode([String: UpdateMemory].self, from: saved)
        #expect(memory["org.example.fed"] == nil, "its feed answers at the next round")
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
