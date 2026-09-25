import Foundation
@testable import PeelCore
import Synchronization
import Testing

/// Records what would have been asked, and sends nothing.
private final class RecordingProtocol: URLProtocol, @unchecked Sendable {
    static let hosts = Mutex<[String]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.hosts.withLock { $0.append(request.url?.host() ?? "") }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
}

/// Peel says it never sends the list of installed apps. Asking Apple about every app, one identifier at a time,
/// would send that list.
@Suite(.serialized) struct UpdatePrivacyTests {
    private var checker: UpdateChecker {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingProtocol.self]
        return UpdateChecker(session: URLSession(configuration: configuration))
    }

    @Test func asksAppleOnlyAboutAnAppItSold() async {
        RecordingProtocol.hosts.withLock { $0 = [] }
        let downloaded = InstalledApp(url: URL(filePath: "/Applications/Editor.app"), bundleIdentifier: "com.example.editor", name: "Editor", version: "1.0")
        let sold = InstalledApp(url: URL(filePath: "/Applications/Notes Pro.app"), bundleIdentifier: "com.example.notes", name: "Notes Pro", version: "1.0", isFromAppStore: true)

        #expect(await checker.status(for: downloaded, preference: .appStore) == .unsupported)
        #expect(RecordingProtocol.hosts.withLock { $0 }.isEmpty, "Apple was told about an app that did not come from its store")

        #expect(await checker.status(for: sold, preference: .appStore) == .failed)
        #expect(RecordingProtocol.hosts.withLock { $0 } == ["itunes.apple.com"])
    }

    /// A feed server can make an `ETag` or a date unique to one Mac and read it back in the next request (RFC 9110,
    /// section 17.14), so the session keeps no cache that would send one back.
    @Test func keepsNothingAFeedServerCouldReadBack() {
        let configuration = UpdateChecker.configuration
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(configuration.httpCookieStorage == nil)
    }
}
