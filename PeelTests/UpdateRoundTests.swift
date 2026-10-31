import Foundation
import Network
@testable import Peel
@testable import PeelCore
import Synchronization
import Testing

private nonisolated final class TransportProtocol: URLProtocol, @unchecked Sendable {
    /// The hosts that answer. Every other request ends in a failed TLS handshake, as behind a captive portal.
    static let answering = Mutex<Set<String>>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, Self.answering.withLock({ $0.contains(url.host() ?? "") }),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.secureConnectionFailed))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><enclosure url="https://example.com/a.zip" sparkle:version="100" sparkle:shortVersionString="1.0"/></item></channel></rss>"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized) @MainActor struct UpdateRoundTests {
    private func app(_ name: String, in folder: URL, feed: String) throws -> URL {
        let bundle = folder.appending(path: "\(name).app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: bundle.appending(path: "Contents"), withIntermediateDirectories: true
        )
        let info: [String: Any] = [
            "CFBundleIdentifier": "org.example.\(name.lowercased())", "CFBundleName": name,
            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.0", "CFBundleVersion": "100",
            "SUFeedURL": feed,
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundle.appending(path: "Contents/Info.plist"))
        return bundle
    }

    private func library(_ defaults: UserDefaults, notesIn folder: URL) -> AppLibrary {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransportProtocol.self]
        return AppLibrary(
            defaults: defaults,
            updateChecker: UpdateChecker(
                session: URLSession(configuration: configuration), appStoreWindow: .appStore, isOnline: { true }
            ),
            releaseNotesStore: ReleaseNotesStore(url: folder.appending(path: "release-notes.json"))
        )
    }

    @Test func aRoundNoServerAnswersLearnsNothing() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let bundles = try [
            app("One", in: folder, feed: "https://one.example.com/appcast.xml"),
            app("Two", in: folder, feed: "https://two.example.com/appcast.xml"),
        ]
        let library = library(made.defaults, notesIn: folder)
        #expect(await library.reveal(bundles))
        let apps = library.apps.filter { $0.bundleIdentifier?.hasPrefix("org.example.") == true }
        TransportProtocol.answering.withLock { $0 = ["one.example.com", "two.example.com"] }
        await library.checkForUpdates(apps, force: true)
        #expect(apps.allSatisfy { library.shownUpdateStatus(of: $0) == .upToDate })
        let known = made.defaults.data(forKey: SettingsKey.updateMemory).flatMap(UpdateMemories.init(data:))

        TransportProtocol.answering.withLock { $0 = [] }
        await library.checkForUpdates(apps, force: true)

        #expect(apps.allSatisfy { library.shownUpdateStatus(of: $0) == .upToDate })
        let remembered = made.defaults.data(forKey: SettingsKey.updateMemory).flatMap(UpdateMemories.init(data:))
        #expect(known != nil && remembered == known, "nothing learned, nothing put off")
    }

    @Test func aReadingAskedForDuringTheFirstLeavesWhatEarlierRunsLearned() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let chosen = folder.appending(path: "Chosen", directoryHint: .isDirectory)
        let bundle = try app("Saved", in: chosen, feed: "https://one.example.com/appcast.xml")
        TransportProtocol.answering.withLock { $0 = ["one.example.com"] }
        let earlier = library(made.defaults, notesIn: folder)
        #expect(await earlier.reveal([bundle]))
        await earlier.checkForUpdates(earlier.apps.filter { $0.bundleIdentifier == "org.example.saved" }, force: true)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransportProtocol.self]
        let library = AppLibrary(
            defaults: made.defaults,
            updateChecker: UpdateChecker(session: URLSession(configuration: configuration)),
            releaseNotesStore: ReleaseNotesStore(url: folder.appending(path: "release-notes.json")),
            appFolders: AppFolders(url: folder.appending(path: "app-folders.json")),
            appMemory: AppMemory(url: folder.appending(path: "apps.json"))
        )
        library.addFolders([chosen])

        let first = Task { await library.load() }
        while !library.scanRun.isRunning { await Task.yield() }
        await library.refresh()
        await first.value

        let saved = try #require(library.apps.first { $0.bundleIdentifier == "org.example.saved" })
        #expect(library.shownUpdateStatus(of: saved) == .upToDate)
    }

    @Test func aFeedThatReachesNoServerFailsWhileAnotherAnswers() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let bundles = try [
            app("One", in: folder, feed: "https://one.example.com/appcast.xml"),
            app("Two", in: folder, feed: "https://two.example.com/appcast.xml"),
        ]
        let library = library(made.defaults, notesIn: folder)
        #expect(await library.reveal(bundles))
        let apps = library.apps.filter { $0.bundleIdentifier?.hasPrefix("org.example.") == true }
        let one = try #require(apps.first { $0.bundleIdentifier == "org.example.one" })
        let two = try #require(apps.first { $0.bundleIdentifier == "org.example.two" })

        TransportProtocol.answering.withLock { $0 = ["one.example.com"] }
        await library.checkForUpdates(apps, force: true)

        #expect(library.shownUpdateStatus(of: one) == .upToDate)
        #expect(library.shownUpdateStatus(of: two) == .failed)
    }
}
