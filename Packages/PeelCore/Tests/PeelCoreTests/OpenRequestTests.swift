import Foundation
import PeelLink
import Testing

/// What Peel's own notifications and the Finder menu send: `peel://open?path=` and the path of a bundle.
struct OpenRequestTests {
    private func link(for app: URL) throws -> URL {
        try #require(OpenRequest.link(toApplicationAt: app.path(percentEncoded: false)))
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

    @Test func opensTheAppItsLinkNamesWhateverItsName() throws {
        for name in ["Tom & Jerry.app", "a=b.app", "C++ #1 100%.app", "Ünïcode ?.app", "plus+sign.app"] {
            let app = URL(filePath: "/Applications/\(name)", directoryHint: .isDirectory)
            let opened = try #require(OpenRequest.applicationURL(from: try link(for: app)), "\(name) was refused")
            #expect(opened.path(percentEncoded: false) == app.path(percentEncoded: false))
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

    @Test func theFinderMenuIsForExactlyOneApp() {
        let app = URL(filePath: "/Applications/Foo.app", directoryHint: .isDirectory)
        let other = URL(filePath: "/Applications/Bar.app", directoryHint: .isDirectory)
        let document = URL(filePath: "/Users/x/Documents/notes.txt")

        #expect(OpenRequest.application(amongSelected: [app]) == app)
        #expect(OpenRequest.application(amongSelected: []) == nil)
        #expect(OpenRequest.application(amongSelected: [document]) == nil)
        #expect(OpenRequest.application(amongSelected: [app, other]) == nil)
        #expect(OpenRequest.application(amongSelected: [app, document]) == nil)
    }

    @Test func theLinkGoesToTheCopyThatHoldsTheExtension() {
        let inside = URL(filePath: "/Applications/Peel.app/Contents/PlugIns/PeelFinder.appex")
        let alone = URL(filePath: "/Users/x/Build/Products/Debug/PeelFinder.appex")

        #expect(OpenRequest.hostApplication(ofExtensionAt: inside) == URL(filePath: "/Applications/Peel.app/"))
        #expect(OpenRequest.hostApplication(ofExtensionAt: alone) == nil)
    }
}
