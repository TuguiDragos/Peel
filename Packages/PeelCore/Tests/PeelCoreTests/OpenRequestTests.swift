import Foundation
import PeelCore
import Testing

/// What Peel's own notifications and the Finder menu send: `peel://open?path=` and the path of a bundle.
struct OpenRequestTests {
    /// Built the way `PeelNotifications` and the Finder extension build it.
    private func link(for app: URL) throws -> URL {
        var components = try #require(URLComponents(string: "peel://open"))
        components.queryItems = [URLQueryItem(name: "path", value: app.path(percentEncoded: false))]
        return try #require(components.url)
    }

    /// A bundle is a folder, and a folder URL's path ends in a slash, which is the form every sender uses.
    @Test func opensABundleHoweverItsPathIsWritten() throws {
        let asAFolder = URL(filePath: "/Users/x/.Trash/Foo.app", directoryHint: .isDirectory)
        let plain = URL(filePath: "/Applications/Foo Bar.app")
        #expect(asAFolder.path(percentEncoded: false).hasSuffix("/"))

        for app in [asAFolder, plain] {
            let opened = try #require(OpenRequest.applicationURL(from: try link(for: app)), "\(app.path(percentEncoded: false)) was refused")
            #expect(opened.pathExtension == "app")
            #expect(opened.lastPathComponent == app.lastPathComponent)
            #expect(OpenRequest.applicationURL(from: app) == app)
        }
    }

    @Test func refusesWhatIsNotABundleOrNotALinkOfPeels() throws {
        #expect(OpenRequest.applicationURL(from: try link(for: URL(filePath: "/Users/x/Documents/notes.txt"))) == nil)
        #expect(OpenRequest.applicationURL(from: try link(for: URL(filePath: "/Users/x/Foo.app/Contents"))) == nil)
        #expect(OpenRequest.applicationURL(from: try #require(URL(string: "peel://open?path=relative/Foo.app"))) == nil)
        #expect(OpenRequest.applicationURL(from: try #require(URL(string: "peel://other?path=/Applications/Foo.app"))) == nil)
        #expect(OpenRequest.applicationURL(from: try #require(URL(string: "https://example.com/Foo.app"))) == nil)
        #expect(OpenRequest.applicationURL(from: URL(filePath: "/Users/x/Documents/notes.txt")) == nil)
    }
}
