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

struct AppLibraryTests {
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
        let suite = "org.example.peel-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
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
}
