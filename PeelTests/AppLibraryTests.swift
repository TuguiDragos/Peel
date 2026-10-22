import Foundation
@testable import Peel
import PeelCore
import Synchronization
import Testing

/// Answers every request with one appcast, and sends nothing anywhere.
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

    private func library(with defaults: UserDefaults, notesIn folder: URL) -> AppLibrary {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppcastProtocol.self]
        return AppLibrary(
            defaults: defaults,
            updateChecker: UpdateChecker(session: URLSession(configuration: configuration)),
            releaseNotesStore: ReleaseNotesStore(url: folder.appending(path: "release-notes.json"))
        )
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
}
