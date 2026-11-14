import AppKit
import Foundation
@testable import PeelCore
import Testing
import UniformTypeIdentifiers

struct DefaultAppsTests {
    private func app(_ path: String = "/Applications/Example.app") -> InstalledApp {
        InstalledApp(url: URL(filePath: path, directoryHint: .isDirectory), bundleIdentifier: "com.example.app", name: "Example")
    }

    @Test func groupsWhatWouldOpenEachKindAndJoinsTheKindsOfOneName() {
        func file(_ name: String, _ fileExtension: String?, _ next: String?) -> DefaultRole {
            DefaultRole(
                kind: .fileKind, identifier: "org.example.\(fileExtension ?? name)", name: name,
                others: next.map { [$0, "Later"] } ?? [], fileExtension: fileExtension
            )
        }
        let named = ["JPEG image", "PNG image", "TIFF image", "HEIF image", "WebP image", "OpenEXR image",
                     "Targa image", "Photoshop document", "Amiga disk archive"]
        var roles = ["erf", "mos", "x3f"].map { file("Image File", $0, nil) }
        roles += named.map { file($0, nil, "Preview") }
        roles += ["dng", "cr2", "cr3", "nef", "nrw", "pef", "srw", "rwl", "dcr", "kdc", "mrw", "iiq", "3fr"]
            .map { file("Image File", $0, "Preview") }
        roles += ["arw", "raf", "orf", "rw2", "srf", "sr2"].map { file("Image File", $0, "Photos") }
        roles += [file("Image File", "dng", "Photos"), file("Odd kind", nil, nil)]
        roles.append(DefaultRole(kind: .link, identifier: "example", name: "example:", others: ["Mail"]))

        let files = DefaultApps.handOvers(roles, of: .fileKind)

        #expect(files.map(\.app) == ["Preview", "Photos", nil])
        #expect(files.map(\.count) == [22, 7, 4])
        #expect(files[0].kinds.first == "Amiga disk archive")
        #expect(files[0].kinds.contains("Image File (.dng, .cr2, .cr3, .nef, .nrw, .pef, .srw, .rwl, .dcr, .kdc, .mrw, .iiq, .3fr)"))
        #expect(files[1].kinds == ["Image File (.arw, .raf, .orf, .rw2, .srf, .sr2, .dng)"])
        #expect(files[2].kinds == ["Image File (.erf, .mos, .x3f)", "Odd kind"])
        #expect(DefaultApps.handOvers(roles, of: .link).map(\.app) == ["Mail"])
        #expect(DefaultApps.handOvers(roles, of: .link).first?.kinds == ["example:"])
    }

    @Test func joinsAKindOfOneNameWithNoExtensionOrTheSameOneTwice() {
        let roles = [
            DefaultRole(kind: .fileKind, identifier: "org.example.a", name: "Notes", others: [], fileExtension: "note"),
            DefaultRole(kind: .fileKind, identifier: "org.example.b", name: "Notes", others: [], fileExtension: "note"),
            DefaultRole(kind: .fileKind, identifier: "org.example.c", name: "Notes", others: [], fileExtension: nil),
            DefaultRole(kind: .fileKind, identifier: "org.example.d", name: "Plain", others: [], fileExtension: nil),
            DefaultRole(kind: .fileKind, identifier: "org.example.e", name: "Plain", others: [], fileExtension: nil),
        ]

        #expect(DefaultApps.handOvers(roles, of: .fileKind).map(\.kinds) == [["Notes (.note)", "Plain"]])
        #expect(DefaultApps.handOvers(roles, of: .link).isEmpty)
    }

    @Test func knowsWhenTheAppIsTheOneThatOpensSomething() {
        let subject = app()

        #expect(DefaultApps.isDefault(subject, for: URL(filePath: "/Applications/Example.app", directoryHint: .isDirectory)))
        // A folder URL carries a trailing slash and a plain one doesn't; both mean the same app.
        #expect(DefaultApps.isDefault(subject, for: URL(filePath: "/Applications/Example.app")))
        #expect(!DefaultApps.isDefault(subject, for: URL(filePath: "/Applications/Other.app")))
        #expect(!DefaultApps.isDefault(subject, for: nil))
    }

    @Test func namesWhoCouldTakeOverWithoutNamingItself() {
        let handlers = [
            URL(filePath: "/Applications/Example.app"),
            URL(filePath: "/Applications/Preview.app"),
            URL(filePath: "/System/Applications/TextEdit.app"),
        ]

        #expect(DefaultApps.names(of: handlers, without: app()) == ["Preview", "TextEdit"])
        #expect(DefaultApps.names(of: [], without: app()).isEmpty)
    }

    /// macOS names an app by where it really is. `/Applications/Safari.app` is a hidden link into a cryptex, and
    /// Launch Services answers with the path inside it, so both paths are resolved before they are compared.
    @Test func knowsAnAppReachedThroughALink() throws {
        let directory = try TemporaryDirectory()
        let real = try directory.directory("Cryptexes/Real.app")
        let link = directory.url.appending(path: "Applications.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let subject = app(link.path(percentEncoded: false))

        #expect(DefaultApps.isDefault(subject, for: real))
        #expect(DefaultApps.names(of: [real, URL(filePath: "/Applications/Preview.app")], without: subject) == ["Preview"])
    }

    /// An app that declares a URL scheme, but is not the app that opens it, has no role to report.
    @Test func reportsNothingForAnAppThatIsNotTheDefault() throws {
        let directory = try TemporaryDirectory()
        let info: [String: Any] = ["CFBundleURLTypes": [["CFBundleURLSchemes": ["mailto"]]]]
        let subject = app(try directory.directory("Example.app").path(percentEncoded: false))

        #expect(DefaultApps.links(declaredIn: info, app: subject).isEmpty)
    }

    /// Asks the Mac running the tests which app opens `mailto:`. That app declares the scheme, so its roles must
    /// include it, and reading them must change nothing.
    @Test func findsTheRoleOfWhateverOpensMailOnThisMac() async throws {
        let mailto = try #require(URL(string: "mailto:"))
        guard let handler = await MainActor.run(body: { NSWorkspace.shared.urlForApplication(toOpen: mailto) }) else {
            return
        }
        let subject = InstalledApp(
            url: handler,
            bundleIdentifier: "",
            name: handler.deletingPathExtension().lastPathComponent
        )

        let roles = await DefaultApps.roles(of: subject)

        #expect(roles.contains { $0.id == "link:mailto" })
        #expect(Set(roles.map(\.id)).count == roles.count, "the same thing was reported twice")
        #expect(roles.allSatisfy { !$0.others.contains(subject.name) }, "it named itself as an alternative")
    }

    /// An older app may declare its document types by file extension alone, which is read as the type each
    /// extension stands for.
    @Test func readsDocumentTypesDeclaredByExtensionOnly() {
        let info: [String: Any] = ["CFBundleDocumentTypes": [
            ["CFBundleTypeExtensions": ["PDF", "*"]],
            ["LSItemContentTypes": ["public.png"], "CFBundleTypeExtensions": ["png"]],
        ]]

        #expect(DefaultApps.declaredTypes(in: info).map(\.identifier) == ["com.adobe.pdf", "public.png"])
    }

    /// A type no app registers is called what the app that opens it calls that kind of document, as Finder does.
    @Test func namesAKindMacOSCannotDescribeAsTheAppDoes() throws {
        let directory = try TemporaryDirectory()
        let app = try directory.directory("Example.app")
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.example.app",
            "CFBundleDocumentTypes": [
                ["CFBundleTypeExtensions": ["peelsamplekind"], "CFBundleTypeName": "Sample Kind"],
            ],
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try directory.file("Example.app/Contents/Info.plist", contents: plist)
        let strings = Data("\"Sample Kind\" = \"Translated Sample Kind\";".utf8)
        try directory.file("Example.app/Contents/Resources/en.lproj/InfoPlist.strings", contents: strings)
        let bundle = Bundle(url: app)
        let type = try #require(UTType(filenameExtension: "peelsamplekind"))
        let declared = try #require(DefaultApps.declaredTypes(in: info).first)

        #expect(type.isDynamic)
        #expect(declared.identifier == type.identifier)
        #expect(DefaultApps.name(of: type, calledByTheApp: declared.appName, in: bundle) == "Translated Sample Kind")
        #expect(DefaultApps.name(of: type, calledByTheApp: nil, in: bundle) == ".peelsamplekind")
        let pdf = DefaultApps.name(of: .pdf, calledByTheApp: "Sample Kind", in: bundle)
        #expect(pdf == UTType.pdf.localizedDescription)
    }
}
