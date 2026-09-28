import Foundation
@testable import PeelCore
import Testing

struct AppInspectorTests {
    private static let thinX86_64: [UInt8] = [0xCF, 0xFA, 0xED, 0xFE, 0x07, 0x00, 0x00, 0x01]

    private static let universal: [UInt8] = [0xCA, 0xFE, 0xBA, 0xBE, 0x00, 0x00, 0x00, 0x02]
        + [0x01, 0x00, 0x00, 0x07] + [UInt8](repeating: 0, count: 16)
        + [0x01, 0x00, 0x00, 0x0C] + [UInt8](repeating: 0, count: 16)

    @Test func aCopyInATrashIsNotInstalledWhateverItsNameBeginsWith() {
        #expect(AppInspector.isInATrash(URL(filePath: "/Users/x/.Trash/Example.app")))
        #expect(AppInspector.isInATrash(URL(filePath: "/Users/x/.Trash/\u{301}Example.app")))
        #expect(AppInspector.isInATrash(URL(filePath: "/Volumes/Disk/.Trashes/501/Example.app")))
        #expect(!AppInspector.isInATrash(URL(filePath: "/Applications/Example.app")))
        #expect(!AppInspector.isInATrash(URL(filePath: "/Users/x/.Trash Old/Example.app")))
    }

    /// The shapes a binary comes in: thin (the usual shape of an Intel-only app), and fat with 20-byte or 32-byte
    /// entries. A fat header that claims too many architectures to be real is read as nothing: a Java class file
    /// also starts with `cafebabe`, and its version sits where the count would be.
    @Test func readsMachOArchitectures() {
        let thinARM64: [UInt8] = [0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0x00, 0x00, 0x01]
        let fat64: [UInt8] = [0xCA, 0xFE, 0xBA, 0xBF, 0x00, 0x00, 0x00, 0x01]
            + [0x01, 0x00, 0x00, 0x07] + [UInt8](repeating: 0, count: 28)
        let javaClass: [UInt8] = [0xCA, 0xFE, 0xBA, 0xBE, 0x00, 0x00, 0x00, 0x34] + [UInt8](repeating: 0, count: 64)

        #expect(MachOHeader.architectures(inHeader: Self.thinX86_64) == [.x86_64])
        #expect(MachOHeader.architectures(inHeader: thinARM64) == [.arm64])
        #expect(MachOHeader.architectures(inHeader: Self.universal) == [.arm64, .x86_64])
        #expect(MachOHeader.architectures(inHeader: fat64) == [.x86_64])
        #expect(MachOHeader.architectures(inHeader: javaClass).isEmpty)
        // Cut off after the count: an incomplete entry is not read.
        #expect(MachOHeader.architectures(inHeader: Array(Self.universal.prefix(10))).isEmpty)
        #expect(MachOHeader.architectures(inHeader: [0x00, 0x01]).isEmpty)
    }

    /// Reads `/usr/bin/true`, the real binary the `universal` fixture above is modeled on.
    /// Spotlight names the apps whose identifier begins with a maker's, wherever they are: every Mac has the
    /// dictation input method in its input methods folder, outside the Applications folders. A Mac with Spotlight off
    /// answers nothing, and the test waits for one that indexes. The other tests' scans ask Spotlight at the same
    /// time, so this one is given longer than a scan waits.
    @Test(.enabled("Spotlight indexes this Mac") { await !AppInspector.indexedIdentifiers(beginningWith: "com.apple.", within: 60).isEmpty })
    func spotlightNamesTheAppsOfOneMaker() async {
        let found = await AppInspector.indexedIdentifiers(beginningWith: "com.apple.inputmethod.", within: 60)

        #expect(found.contains("com.apple.inputmethod.ironwood"))
        #expect(found.allSatisfy { $0.lowercased().hasPrefix("com.apple.inputmethod.") })
    }

    /// A bundle writes its own identifier, and a maker's prefix taken from it goes into a Spotlight query. One that
    /// could change the query asks nothing.
    @Test func aPrefixThatCouldChangeTheQueryAsksNothing() async {
        for prefix in ["com.example\" || kMDItemFSName == \"*", "com.example *", "", "com.example.\\"] {
            #expect(await AppInspector.indexedIdentifiers(beginningWith: prefix).isEmpty, "\(prefix)")
        }
    }

    @Test func readsARealBinaryTheSameWay() {
        #expect(MachOHeader.architectures(ofExecutableAt: URL(filePath: "/usr/bin/true")).contains(.arm64))
    }

    @Test func inspectsBundleOnDisk() throws {
        let directory = try TemporaryDirectory()
        try plist(["CFBundleIdentifier": "com.example.fake", "CFBundleName": "Fake", "CFBundleShortVersionString": "1.2", "CFBundleExecutable": "Fake"],
                  at: "Fake.app/Contents/Info.plist", in: directory)
        try Data(Self.thinX86_64).write(to: directory.file("Fake.app/Contents/MacOS/Fake"))
        try plist(["CFBundleIdentifier": "com.example.fake.login"], at: "Fake.app/Contents/Library/LoginItems/Login.app/Contents/Info.plist", in: directory)
        try directory.file("Fake.app/Contents/Library/LaunchServices/com.example.fake.privileged")
        try plist(["Label": "com.example.fake.daemon"], at: "Fake.app/Contents/Library/LaunchDaemons/daemon.plist", in: directory)

        let app = try #require(AppInspector.inspect(directory.url.appending(path: "Fake.app")))

        #expect(app.bundleIdentifier == "com.example.fake")
        #expect(app.bundleName == "Fake")
        #expect(app.version == "1.2")
        #expect(app.embeddedBundleIdentifiers == ["com.example.fake.daemon", "com.example.fake.login", "com.example.fake.privileged"])
        #expect(app.isIntelOnly)
        #expect(!app.isFromAppStore)
        #expect(!app.isSystemProtected)
    }

    /// Reading a bundle costs its `Info.plist`, its signature, its Mach-O header, and a Spotlight lookup, and the
    /// list of apps is read again often. So a bundle is read again only when it has changed.
    @Test func readsABundleAgainOnlyWhenItChanged() async throws {
        let directory = try TemporaryDirectory()
        try plist(["CFBundleIdentifier": "com.example.fake", "CFBundleName": "Fake", "CFBundleShortVersionString": "1.0"],
                  at: "Applications/Fake.app/Contents/Info.plist", in: directory)
        let folder = directory.url.appending(path: "Applications", directoryHint: .isDirectory)

        let first = await AppCatalog.installedApps(in: [folder])
        #expect(first.map(\.version) == ["1.0"])

        // Rewritten with another version: the bundle's identity changes, so it is read again.
        try plist(["CFBundleIdentifier": "com.example.fake", "CFBundleName": "Fake", "CFBundleShortVersionString": "2.0"],
                  at: "Applications/Fake.app/Contents/Info.plist", in: directory)
        let second = await AppCatalog.installedApps(in: [folder])
        #expect(second.map(\.version) == ["2.0"], "a bundle that changed was answered from what was known about the old one")

        // Nothing changed: the same answer, and the bundle is not read again.
        let third = await AppCatalog.installedApps(in: [folder])
        #expect(third == second)
    }

    /// A launchd plist too large to be a job is not read, and neither is a link to something that is not a file
    /// (reading `/dev/zero` never ends). A link to a real job is followed.
    @Test func readsThroughALinkedLaunchdJobAndRefusesWhatIsNoJob() throws {
        let directory = try TemporaryDirectory()
        try plist(["CFBundleIdentifier": "com.example.fake", "CFBundleName": "Fake"], at: "Fake.app/Contents/Info.plist", in: directory)
        try plist(["Label": "com.example.fake.agent"], at: "Fake.app/Contents/Library/LaunchAgents/agent.plist", in: directory)
        let elsewhere = try plist(["Label": "com.example.linked"], at: "elsewhere.plist", in: directory)
        let agents = "Fake.app/Contents/Library/LaunchAgents"
        for (name, target) in [("linked.plist", elsewhere), ("endless.plist", URL(filePath: "/dev/zero"))] {
            try FileManager.default.createSymbolicLink(at: directory.url.appending(path: "\(agents)/\(name)"), withDestinationURL: target)
        }
        let huge = ["Label": "com.example.huge", "Padding": String(repeating: "x", count: BoundedRead.maximumBytes)]
        try plist(huge, at: "\(agents)/huge.plist", in: directory)

        let app = try #require(AppInspector.inspect(directory.url.appending(path: "Fake.app")))

        #expect(app.embeddedBundleIdentifiers == ["com.example.fake.agent", "com.example.linked"])
    }

    /// A short version that is a number or an empty string must not hide the build number.
    @Test func fallsBackToTheBuildWhenTheShortVersionIsNotText() throws {
        let directory = try TemporaryDirectory()
        let info: [String: Any] = ["CFBundleIdentifier": "com.example.fake", "CFBundleShortVersionString": 2, "CFBundleVersion": "2041"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: directory.file("Number.app/Contents/Info.plist"))
        try plist(["CFBundleIdentifier": "com.example.fake", "CFBundleShortVersionString": "", "CFBundleVersion": "7"], at: "Empty.app/Contents/Info.plist", in: directory)

        #expect(AppInspector.inspect(directory.url.appending(path: "Number.app"))?.version == "2041")
        #expect(AppInspector.inspect(directory.url.appending(path: "Empty.app"))?.version == "7")
    }

    @Test func rejectsFoldersWithoutBundleIdentifier() throws {
        let directory = try TemporaryDirectory()
        try plist(["CFBundleName": "Broken"], at: "Broken.app/Contents/Info.plist", in: directory)
        #expect(AppInspector.inspect(directory.url.appending(path: "Broken.app")) == nil)
    }

    @Test func marksSystemAppsAsProtected() throws {
        let calculator = try #require(AppInspector.inspect(URL(filePath: "/System/Applications/Calculator.app")))
        #expect(calculator.bundleIdentifier == "com.apple.calculator")
        #expect(calculator.isSystemProtected)
        #expect(calculator.architectures.contains(.arm64))
        #expect(calculator.developer == "Apple", "Apple signs its own apps as Software Signing")
    }

    /// A Developer ID leaf certificate names who it was issued to, and the team in parentheses after the name must
    /// be the team the signature carries. Apple signs an App Store app again with a leaf that names nobody, and a
    /// development certificate names a person, not whoever ships the app.
    @Test func namesTheMakerTheCertificateWasIssuedTo() {
        #expect(CodeSignature.developer(fromLeaf: "Developer ID Application: Microsoft Corporation (UBF8T346G9)", team: "UBF8T346G9") == "Microsoft Corporation")
        #expect(CodeSignature.developer(fromLeaf: "Developer ID Application: Acme (Europe) Ltd (ABCDE12345)", team: "ABCDE12345") == "Acme (Europe) Ltd")
        #expect(CodeSignature.developer(fromLeaf: "Developer ID Application: Microsoft Corporation (UBF8T346G9)", team: "ABCDE12345") == nil)
        #expect(CodeSignature.developer(fromLeaf: "Software Signing", team: nil) == "Apple")
        #expect(CodeSignature.developer(fromLeaf: "macOS Software Signing", team: nil) == "Apple")
        #expect(CodeSignature.developer(fromLeaf: "Apple Mac OS Application Signing", team: "59GAB85EFG") == nil)
        #expect(CodeSignature.developer(fromLeaf: "Apple Development: Someone (ZZZZZ99999)", team: "ZZZZZ99999") == nil)
    }

    /// Setapp's documentation: a bundle identifier "must use the -setapp suffix", and apps go to
    /// `/Applications/Setapp`, or `~/Applications/Setapp` for an account that is not an administrator's.
    @Test func knowsAnAppSetappInstalled() {
        func app(_ path: String, _ identifier: String) -> InstalledApp {
            InstalledApp(url: URL(filePath: path, directoryHint: .isDirectory), bundleIdentifier: identifier, name: "App")
        }
        #expect(app("/Applications/Sample.app", "org.example.Sample-setapp").isFromSetapp)
        #expect(app("/Applications/Sample.app", "org.example.Sample-Setapp").isFromSetapp)
        #expect(app("/Applications/Setapp/Sample.app", "org.example.Sample").isFromSetapp)
        #expect(app("/Users/me/Applications/Setapp/Sample.app", "org.example.Sample").isFromSetapp)
        #expect(!app("/Applications/Setapp.app", "com.setapp.DesktopClient").isFromSetapp, "Setapp itself is not an app from Setapp")
        #expect(!app("/Applications/Setapp Tools/Thing.app", "com.example.thing").isFromSetapp)
        #expect(!app("/Applications/Thing.app", "com.example.setappish").isFromSetapp)
    }

    /// Copies `original`, an app Apple signed, and writes `identifier` into the copy's `Info.plist` when one is
    /// given. That breaks the signature, but what it says, Apple's team included, can still be read as a string.
    private func copy(of original: String, claiming identifier: String?, in directory: borrowing TemporaryDirectory) throws -> URL {
        let copy = directory.url.appending(path: UUID().uuidString + ".app", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: URL(filePath: original), to: copy)
        if let identifier {
            let info = copy.appending(path: "Contents/Info.plist")
            var contents = try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: info), format: nil) as? [String: Any])
            contents["CFBundleIdentifier"] = identifier
            try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0).write(to: info)
        }
        return copy
    }

    @Test func readsNothingFromASignatureThatDoesNotHold() throws {
        let directory = try TemporaryDirectory()
        let untouched = try copy(of: "/System/Applications/TextEdit.app", claiming: nil, in: directory)
        let forged = try copy(of: "/System/Applications/TextEdit.app", claiming: "com.apple.Music", in: directory)

        #expect(CodeSignature.information(at: untouched)?[kSecCodeInfoIdentifier as String] as? String == "com.apple.TextEdit")
        #expect(CodeSignature.information(at: forged) == nil)
        #expect(CodeSignature.information(at: directory.url) == nil)
    }

    private static let fileMerge = "/Applications/Xcode.app/Contents/Applications/FileMerge.app"

    /// A copy of FileMerge that calls itself `com.apple.Music` must not be read as Apple's team, or it could
    /// claim Apple's own files.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: fileMerge)))
    func believesNoTeamFromABundleWhoseSignatureIsBroken() throws {
        let directory = try TemporaryDirectory()
        let untouched = try #require(AppInspector.inspect(try copy(of: Self.fileMerge, claiming: nil, in: directory)))
        let forged = try #require(AppInspector.inspect(try copy(of: Self.fileMerge, claiming: "com.apple.Music", in: directory)))

        #expect(untouched.teamIdentifier == "59GAB85EFG")
        #expect(forged.bundleIdentifier == "com.apple.Music")
        #expect(forged.teamIdentifier == nil, "ATTACK SUCCEEDED: a broken signature is believed about its team")
        #expect(forged.applicationGroups.isEmpty)
    }

    @discardableResult
    private func plist(_ dictionary: [String: String], at path: String, in directory: borrowing TemporaryDirectory) throws -> URL {
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        let url = try directory.file(path)
        try data.write(to: url)
        return url
    }
}
