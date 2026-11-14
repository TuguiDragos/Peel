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

    @Test func aBundleWhoseContentsIsALinkIsNoApp() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try fixture(in: directory)
        let wrapped = try directory.directory("Applications/Wrapped.app")
        try FileManager.default.createSymbolicLink(
            at: wrapped.appending(path: "Contents"), withDestinationURL: fixture.real.appending(path: "Contents")
        )

        #expect(!AppInspector.isABundle(wrapped))
        #expect(AppInspector.inspect(wrapped) == nil)
        #expect(!AppCatalog.appBundles(in: fixture.applications).bundles.contains { $0.lastPathComponent == "Wrapped.app" })
        #expect(AppInspector.isABundle(fixture.real))
    }

    @Test func aWrapperWhoseWrapperIsALinkIsNoApp() throws {
        let directory = try TemporaryDirectory()
        let applications = try directory.directory("Applications")
        let phone = try directory.directory("Applications/Phone.app")
        _ = try directory.file("Applications/Phone.app/Wrapper/Phone.app/Info.plist", contents: Data("""
        <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>\
        <key>CFBundleIdentifier</key><string>org.example.phone</string>\
        <key>CFBundlePackageType</key><string>APPL</string></dict></plist>
        """.utf8))
        let fake = try directory.directory("Applications/FakePhone.app")
        for bundle in [phone, fake] {
            try FileManager.default.createSymbolicLink(
                atPath: bundle.appending(path: "WrappedBundle").path(percentEncoded: false),
                withDestinationPath: "Wrapper/Phone.app"
            )
        }
        try FileManager.default.createSymbolicLink(
            atPath: fake.appending(path: "Wrapper").path(percentEncoded: false), withDestinationPath: "../Phone.app/Wrapper"
        )

        #expect(AppInspector.isABundle(phone))
        #expect(!AppInspector.isABundle(fake), "another wrapper's app is read as this one")
        #expect(AppInspector.inspect(fake) == nil)
        #expect(AppCatalog.appBundles(in: applications).bundles.map(\.lastPathComponent) == ["Phone.app"])
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

    @Test(.permissionsHold) func aBundleWithADamagedInfoPlistKeepsNothingFromBeingRead() async throws {
        let directory = try TemporaryDirectory()
        let applications = try directory.directory("Applications")
        let dangling = try directory.directory("Applications/Dangling.app/Contents")
        try FileManager.default.createSymbolicLink(
            at: dangling.appending(path: "Info.plist"), withDestinationURL: directory.url.appending(path: "nowhere")
        )
        _ = try directory.directory("Applications/Folder.app/Contents/Info.plist")
        let closed = try directory.file("Applications/Closed.app/Contents/Info.plist", contents: Data("{}".utf8))
        try directory.setPermissions(0o000, of: closed)
        defer { try? directory.setPermissions(0o644, of: closed) }

        let scan = await AppCatalog.scan(in: [applications])

        #expect(scan.unreadable.map(\.lastPathComponent) == ["Closed.app"])
        #expect(AppInspector.whyUnreadable(applications.appending(path: "Dangling.app")) == .noInfo)
        #expect(AppInspector.whyUnreadable(applications.appending(path: "Folder.app")) == .infoDamaged)
        #expect(AppInspector.whyUnreadable(applications.appending(path: "Closed.app")) == .infoClosed)
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
