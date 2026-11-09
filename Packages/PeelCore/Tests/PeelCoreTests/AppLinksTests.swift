import Foundation
@testable import PeelCore
import Testing

/// A name ending in `.app` is no app by itself: a link names the app it leads to, and a file named like one is none.
struct AppLinksTests {
    /// An Applications folder holding a link to an app elsewhere, a link that leads nowhere, a file and an empty folder
    /// named as apps.
    private func fixture(
        in directory: borrowing TemporaryDirectory
    ) throws -> (real: URL, applications: URL, link: URL) {
        let real = try directory.directory("Elsewhere/Real.app")
        _ = try directory.file("Elsewhere/Real.app/Contents/Info.plist", contents: Data("""
        <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>\
        <key>CFBundleIdentifier</key><string>org.example.real</string>\
        <key>CFBundleName</key><string>Real</string><key>CFBundlePackageType</key><string>APPL</string>\
        </dict></plist>
        """.utf8))
        let applications = try directory.directory("Applications")
        let link = applications.appending(path: "Linked.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        try FileManager.default.createSymbolicLink(
            at: applications.appending(path: "Gone.app"), withDestinationURL: directory.url.appending(path: "Nowhere.app")
        )
        _ = try directory.file("Applications/Plain File.app", bytes: 10)
        _ = try directory.directory("Applications/Empty.app")
        return (real, applications, link)
    }

    @Test func theCatalogReadsOnlyAFolderNamedAsAnAppAsOne() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try fixture(in: directory)

        let walked = AppCatalog.appBundles(in: fixture.applications)
        #expect(walked.bundles.map(\.lastPathComponent) == ["Empty.app"])
        let scan = await AppCatalog.scan(in: [fixture.applications], within: 8) { folder, _ in
            AppCatalog.appBundles(in: folder)
        }
        #expect(scan.apps.isEmpty)
        #expect(scan.unreadable.isEmpty, "\(scan.unreadable)")
    }

    @Test func aLinkIsReadAsTheAppItLeadsTo() throws {
        let directory = try TemporaryDirectory()
        let fixture = try fixture(in: directory)
        let gone = fixture.applications.appending(path: "Gone.app", directoryHint: .isDirectory)
        let plain = fixture.applications.appending(path: "Plain File.app", directoryHint: .isDirectory)

        let asked = URL(filePath: fixture.link.path(percentEncoded: false), directoryHint: .isDirectory)
        let app = try #require(AppInspector.inspect(asked))
        let real = PathPattern.canonicalWithoutOpening(fixture.real)
        #expect(PathPattern.comparablePath(of: app.url) == PathPattern.comparablePath(of: real))
        #expect(app.bundleIdentifier == "org.example.real")
        #expect(AppInspector.inspect(gone) == nil)
        #expect(AppInspector.isABundle(fixture.real))
        #expect(![fixture.link, plain, gone].contains(where: AppInspector.isABundle))
        #expect(AppInspector.whyUnreadable(gone) == .gone)
        #expect(AppInspector.whyUnreadable(plain) == .notAnApp)
    }

    /// A link that leads nowhere, or round to itself, is gone however its path is written, a drop's without a slash
    /// at the end included, and nothing follows it for ever.
    @Test func aLinkThatLeadsNowhereIsGone() throws {
        let directory = try TemporaryDirectory()
        let fixture = try fixture(in: directory)
        let gone = fixture.applications.appending(path: "Gone.app", directoryHint: .notDirectory)
        let loop = fixture.applications.appending(path: "Loop.app", directoryHint: .notDirectory)
        try FileManager.default.createSymbolicLink(at: loop, withDestinationURL: loop)

        #expect(AppInspector.whyUnreadable(gone) == .gone)
        #expect(AppInspector.whyUnreadable(loop) == .gone)
        #expect(AppInspector.inspect(loop) == nil)
    }

    /// A link thrown into the Trash is no app leaving this Mac, while the app it leads to stays where it is.
    @Test func aLinkInTheTrashIsNoAppThatLeft() throws {
        let directory = try TemporaryDirectory()
        let fixture = try fixture(in: directory)
        let trash = try directory.directory(".Trash")
        let thrown = trash.appending(path: "Linked.app")
        try FileManager.default.createSymbolicLink(at: thrown, withDestinationURL: fixture.real)
        let copy = try directory.directory(".Trash/Real.app")
        try FileManager.default.copyItem(
            at: fixture.real.appending(path: "Contents"), to: copy.appending(path: "Contents")
        )

        #expect(!AppInspector.isAnAppThatLeft(thrown, among: []))
        #expect(AppInspector.isAnAppThatLeft(copy, among: []))
    }
}
