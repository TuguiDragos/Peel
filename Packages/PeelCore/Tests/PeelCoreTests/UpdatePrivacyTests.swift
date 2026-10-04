import Darwin
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

/// A server on this Mac's loopback that answers one request with a feed and keeps the request's headers.
private final class OneRequestServer: Sendable {
    let port: UInt16
    private let headers = Mutex<[String: String]?>(nil)
    private let answered = DispatchSemaphore(value: 0)

    init() throws {
        let listening = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listening, $0, length) == 0 && getsockname(listening, $0, &length) == 0 }
        }
        guard bound, listen(listening, 1) == 0 else {
            close(listening)
            throw POSIXError(.EADDRNOTAVAIL)
        }
        port = UInt16(bigEndian: address.sin_port)
        Thread { [self] in serve(listening) }.start()
    }

    func receivedHeaders() -> [String: String]? {
        guard answered.wait(timeout: .now() + 10) == .success else { return nil }
        return headers.withLock { $0 }
    }

    private func serve(_ listening: Int32) {
        defer { close(listening) }
        let connection = accept(listening, nil, nil)
        guard connection >= 0 else { return }
        defer { close(connection) }
        var request = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while !request.suffix(4).elementsEqual(Array("\r\n\r\n".utf8)) {
            let count = read(connection, &buffer, buffer.count)
            guard count > 0 else { return }
            request += buffer[..<count]
        }
        let lines = String(decoding: request, as: UTF8.self).components(separatedBy: "\r\n").dropFirst()
        headers.withLock { found in
            found = Dictionary(lines.compactMap { line in
                line.firstIndex(of: ":").map { (String(line[..<$0]), line[line.index(after: $0)...].trimmingCharacters(in: .whitespaces)) }
            }, uniquingKeysWith: { first, _ in first })
        }
        let body = #"<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>2</sparkle:version></item></channel></rss>"#
        let reply = "HTTP/1.1 200 OK\r\nContent-Type: application/xml\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        _ = Array(reply.utf8).withUnsafeBytes { write(connection, $0.baseAddress, $0.count) }
        answered.signal()
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

    @Test func tellsAFeedServerNothingButPeelsName() async throws {
        let server = try OneRequestServer()
        let feed = try #require(URL(string: "http://127.0.0.1:\(server.port)/appcast.xml"))
        let app = InstalledApp(
            url: URL(filePath: "/Applications/Editor.app"), bundleIdentifier: "org.example.editor", name: "Editor",
            version: "1", updateFeed: .sparkle(feed)
        )

        #expect(await UpdateChecker().status(for: app, preference: .developer) != .failed)

        let headers = try #require(server.receivedHeaders())
        #expect(headers["User-Agent"] == "Peel")
        #expect(headers["Accept-Language"] == "*")
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
