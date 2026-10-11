import Foundation
@testable import PeelCore
import PeelPrivileged
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

    @Test func knowsWhenAnotherCopyOfATrashedAppIsInstalled() throws {
        let directory = try TemporaryDirectory()
        func bundle(_ path: String, _ identifier: String?) throws -> URL {
            var info: [String: Any] = ["CFBundleName": "Probe", "CFBundlePackageType": "APPL"]
            info["CFBundleIdentifier"] = identifier
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try directory.file("\(path)/Contents/Info.plist", contents: data)
            return directory.url.appending(path: path, directoryHint: .isDirectory)
        }
        let trashed = try bundle("home/.Trash/Probe.app", "org.example.inspector.copy")
        let kept = try bundle("home/Applications/Probe.app", "org.example.inspector.copy")
        let alone = try bundle("home/.Trash/Alone.app", "org.example.inspector.alone")
        let nameless = try bundle("home/.Trash/Nameless.app", nil)
        let installed = [kept, trashed, nameless].compactMap(AppInspector.inspect)

        #expect(AppInspector.anotherCopyIsInstalled(of: trashed, among: installed))
        #expect(!AppInspector.anotherCopyIsInstalled(of: alone, among: installed))
        #expect(!AppInspector.anotherCopyIsInstalled(of: nameless, among: installed))
        #expect(!AppInspector.anotherCopyIsInstalled(of: trashed, among: [trashed].compactMap(AppInspector.inspect)))
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

    /// Spotlight names the apps whose identifier begins with any prefix asked, wherever they are: every Mac has the
    /// dictation input method in its input methods folder, outside the Applications folders, and TextEdit. A Mac with
    /// Spotlight off answers nothing, so the test waits for a Mac where macOS's own `mdfind` finds TextEdit. It waits
    /// for Spotlight's whole answer, since a busy Mac answers late, never wrong.
    @Test(.enabled("Spotlight indexes this Mac") {
        let query = "kMDItemCFBundleIdentifier == \"com.apple.TextEdit\""
        return (try? await Subprocess.run("/usr/bin/mdfind", [query], timeout: nil).get())?.text.isEmpty == false
    })
    func spotlightNamesTheAppsOfOneMaker() async {
        let prefixes = ["com.apple.inputmethod.", "com.apple.TextEdit"]
        let found = await Self.indexed(beginningWith: prefixes)

        #expect(found.contains("com.apple.inputmethod.ironwood"))
        #expect(found.contains("com.apple.TextEdit"))
        let lowercased = prefixes.map { $0.lowercased() }
        #expect(found.allSatisfy { identifier in lowercased.contains { identifier.lowercased().hasPrefix($0) } })
    }

    private static func indexed(beginningWith prefixes: [String]) async -> Set<String> {
        guard let query = AppInspector.spotlightQuery(forIdentifiersBeginningWith: prefixes) else { return [] }
        return await withCheckedContinuation { continuation in
            Thread { continuation.resume(returning: AppInspector.identifiers(answering: query)) }.start()
        }
    }

    /// A bundle writes its own identifier, and a maker's prefix taken from it goes into a Spotlight query. One that
    /// could change the query asks nothing.
    @Test func aPrefixThatCouldChangeTheQueryAsksNothing() async {
        for prefix in ["com.example\" || kMDItemFSName == \"*", "com.example *", "", "com.example.\\"] {
            #expect(await AppInspector.indexedIdentifiers(beginningWith: [prefix]).isEmpty, "\(prefix)")
            #expect(await AppInspector.indexedIdentifiers(beginningWith: ["com.apple.", prefix]).isEmpty, "\(prefix)")
        }
        #expect(await AppInspector.indexedIdentifiers(beginningWith: []).isEmpty)
    }

    /// Reads `/usr/bin/true`, the real binary the `universal` fixture above is modeled on.
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

    /// Spotlight does not index the temporary folder, and answers there with the bundle's modification date for when
    /// it was last used.
    @Test func anAppSpotlightDoesNotIndexHasNoRecordOfBeingOpened() throws {
        let directory = try TemporaryDirectory()
        try plist(["CFBundleIdentifier": "org.example.unindexed"], at: "Unindexed.app/Contents/Info.plist", in: directory)
        let bundle = directory.url.appending(path: "Unindexed.app")
        let written = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: written],
            ofItemAtPath: bundle.path(percentEncoded: false)
        )

        let app = try #require(AppInspector.inspect(bundle))

        #expect(app.lastUsedDate == nil)
        #expect(!app.isUseRecorded)
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

    /// The system apps are read on their own, and reading them must not forget what the Applications folders hold.
    @Test func readingSomeFoldersForgetsOnlyWhatLeftThem() async throws {
        let directory = try TemporaryDirectory()
        try plist(["CFBundleIdentifier": "org.example.one", "CFBundleName": "One"], at: "One/One.app/Contents/Info.plist", in: directory)
        try plist(["CFBundleIdentifier": "org.example.two", "CFBundleName": "Two"], at: "Two/Two.app/Contents/Info.plist", in: directory)
        let (one, two) = (directory.url.appending(path: "One"), directory.url.appending(path: "Two"))

        _ = await AppCatalog.installedApps(in: [one])
        _ = await AppCatalog.installedApps(in: [two])
        #expect(AppCatalog.remembers(one.appending(path: "One.app")))

        try FileManager.default.moveItem(at: one.appending(path: "One.app"), to: directory.url.appending(path: "One.app"))
        _ = await AppCatalog.installedApps(in: [one])
        #expect(!AppCatalog.remembers(one.appending(path: "One.app")))
        #expect(AppCatalog.remembers(two.appending(path: "Two.app")))
    }

    @Test(.permissionsHold) func saysWhatItCouldNotReadAndNotWhatIsNotThere() async throws {
        let directory = try TemporaryDirectory()
        try plist(["CFBundleIdentifier": "org.example.one", "CFBundleName": "One"], at: "Open/One.app/Contents/Info.plist", in: directory)
        try plist(["CFBundleIdentifier": "org.example.sealed", "CFBundleName": "Sealed"], at: "Open/Sealed.app/Contents/Info.plist", in: directory)
        try plist(["CFBundleIdentifier": "org.example.two", "CFBundleName": "Two"], at: "Closed/Two.app/Contents/Info.plist", in: directory)
        try directory.setPermissions(0o000, of: "Closed")
        try directory.setPermissions(0o000, of: "Open/Sealed.app/Contents/Info.plist")
        defer {
            try? directory.setPermissions(0o755, of: "Closed")
            try? directory.setPermissions(0o644, of: "Open/Sealed.app/Contents/Info.plist")
        }

        let scan = await AppCatalog.scan(in: ["Open", "Closed", "Missing"].map { directory.url.appending(path: $0) })

        #expect(scan.apps.map(\.bundleIdentifier) == ["org.example.one"])
        #expect(scan.unreadable.map(\.lastPathComponent) == ["Closed", "Sealed.app"])
    }

    @Test func aListOfFoldersThatCannotBeReadIsAmongWhatWasNotRead() async throws {
        let directory = try TemporaryDirectory()
        let list = try directory.file("app-folders.json", contents: Data("not a list".utf8))

        let scan = await AppCatalog.scan(choices: AppFolders(url: list))

        #expect(scan.unreadable.contains(list))
    }

    /// Launch Services would answer Loud Name, and asking it registers the bundle.
    @Test func anAppMacOSDoesNotKnowIsNamedByItsFile() throws {
        let directory = try TemporaryDirectory()
        let info = ["CFBundleIdentifier": "org.example.quiet", "CFBundleName": "Quiet", "LSHasLocalizedDisplayName": "1"]
        try plist(info, at: "Quiet.app/Contents/Info.plist", in: directory)
        try directory.file(
            "Quiet.app/Contents/Resources/en.lproj/InfoPlist.strings",
            contents: Data(#""CFBundleDisplayName" = "Loud Name";"#.utf8)
        )

        let app = try #require(AppInspector.inspect(directory.url.appending(path: "Quiet.app", directoryHint: .isDirectory)))

        #expect(app.name == "Quiet")
    }

    @Test func anAppMacOSKnowsIsNamedAsFinderNamesIt() {
        let calculator = URL(filePath: "/System/Applications/Calculator.app", directoryHint: .isDirectory)
        let shown = FileManager.default.displayName(atPath: calculator.path(percentEncoded: false))
        // Finder shows the extension when Show all filename extensions is on, and an app's name never carries it.
        let finder = shown.hasSuffix(".app") ? String(shown.dropLast(4)) : shown

        #expect(AppInspector.displayName(of: calculator) == finder)
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

    @Test func readsAnAppWhoseInfoPlistNamesNoIdentifier() throws {
        let directory = try TemporaryDirectory()
        try plist(["CFBundleName": "Plain Editor", "CFBundleVersion": "4.0"], at: "Plain Editor.app/Contents/Info.plist", in: directory)
        try plist(["CFBundleIdentifier": ""], at: "Empty.app/Contents/Info.plist", in: directory)
        try directory.directory("Folder.app/Contents")

        let app = try #require(AppInspector.inspect(directory.url.appending(path: "Plain Editor.app")))

        #expect(app.bundleIdentifier == nil)
        #expect(app.name == "Plain Editor")
        #expect(app.version == "4.0")
        #expect(app.reference == PathPattern.comparablePath(of: directory.url.appending(path: "Plain Editor.app")))
        #expect(AppInspector.inspect(directory.url.appending(path: "Empty.app"))?.bundleIdentifier == nil)
        #expect(AppInspector.inspect(directory.url.appending(path: "Folder.app")) == nil)
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
    private func copy(
        of original: String,
        claiming identifier: String?,
        in directory: borrowing TemporaryDirectory
    ) throws -> URL {
        let copy = directory.url.appending(path: UUID().uuidString + ".app", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: URL(filePath: original), to: copy)
        if let identifier {
            let info = copy.appending(path: "Contents/Info.plist")
            var contents = try #require(
                try PropertyListSerialization.propertyList(from: Data(contentsOf: info), format: nil) as? [String: Any]
            )
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
    private func plist(
        _ dictionary: [String: String],
        at path: String,
        in directory: borrowing TemporaryDirectory
    ) throws -> URL {
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        let url = try directory.file(path)
        try data.write(to: url)
        return url
    }

    /// An iPhone or iPad app on a Mac keeps its own bundle, with no `Contents`, where `WrappedBundle` leads.
    @Test func readsAnIPhoneAppFromTheBundleItWraps() throws {
        let directory = try TemporaryDirectory()
        let inner = try directory.directory("Example.app/Wrapper/example.app")
        let info: [String: Any] = [
            "CFBundleIdentifier": "org.example.wrapped", "CFBundleName": "example", "CFBundleExecutable": "example",
            "CFBundleShortVersionString": "3.4", "CFBundleVersion": "189",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: inner.appending(path: "Info.plist"))
        try directory.file("Example.app/Wrapper/example.app/example")
        try directory.file("Example.app/Wrapper/iTunesMetadata.plist")
        let bundle = directory.url.appending(path: "Example.app")
        try FileManager.default.createSymbolicLink(
            atPath: bundle.appending(path: "WrappedBundle").path(percentEncoded: false),
            withDestinationPath: "Wrapper/example.app"
        )

        let share = try directory.directory("Example.app/Wrapper/example.app/PlugIns/Share.appex")
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "org.example.wrapped.share"], format: .xml, options: 0)
            .write(to: share.appending(path: "Info.plist"))

        let app = try #require(AppInspector.inspect(bundle))
        #expect(app.bundleIdentifier == "org.example.wrapped")
        #expect(app.embeddedBundleIdentifiers == ["org.example.wrapped.share"])
        #expect(app.name == "Example")
        #expect(app.version == "3.4")
        #expect(app.isFromAppStore)
    }

    /// Safari writes each web app as a template of its own `com.apple.Safari.WebApp`, named by the UUID it gives it.
    @Test func knowsASafariWebAppByTheTemplateSafariWrote() throws {
        let directory = try TemporaryDirectory()
        let uuid = "0E4F6A2C-1B3D-4E5F-8A9B-0C1D2E3F4A5B"
        func webApp(_ name: String, identifier: String, template: String = "com.apple.Safari.WebApp") throws -> URL {
            let info: [String: Any] = [
                "CFBundleIdentifier": identifier, "CFBundleName": name, "LSTemplateApplication": true,
                "LSTemplateApplicationParameters": [
                    "CFBundleIdentifier": template, "TemplateAppUUID": uuid, "teamIdentifier": "0000000000",
                ],
            ]
            let contents = try directory.directory("\(name).app/Contents")
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appending(path: "Info.plist"))
            return directory.url.appending(path: "\(name).app")
        }

        let wiki = try #require(AppInspector.inspect(try webApp("Wiki", identifier: "com.apple.Safari.WebApp.\(uuid)")))
        #expect(wiki.isASafariWebApp)
        let otherUUID = try #require(
            AppInspector.inspect(try webApp("Other", identifier: "com.apple.Safari.WebApp.1A2B3C4D-0000-4000-8000-000000000000"))
        )
        #expect(!otherUUID.isASafariWebApp)
        let otherTemplate = try #require(
            AppInspector.inspect(try webApp("Mail", identifier: "com.apple.mail.\(uuid)", template: "com.apple.mail"))
        )
        #expect(!otherTemplate.isASafariWebApp)
    }

    /// A Chromium browser writes each web app's shortcut with the browser's identifier and the app's own in its
    /// Info.plist, under an identifier of the browser's followed by `.app.`.
    @Test func knowsAWebAppOfAChromiumBrowserByTheShortcutItWrote() throws {
        let directory = try TemporaryDirectory()
        func shortcut(_ name: String, identifier: String, browser: String = "org.example.Browser") throws -> URL {
            let info: [String: Any] = [
                "CFBundleIdentifier": identifier, "CFBundleName": name, "CFBundleExecutable": "app_mode_loader",
                "CrAppModeShortcutID": "abcdefghijklmnopabcdefghijklmnop", "CrBundleIdentifier": browser,
            ]
            let contents = try directory.directory("\(name).app/Contents")
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appending(path: "Info.plist"))
            return directory.url.appending(path: "\(name).app")
        }

        let music = try #require(AppInspector.inspect(try shortcut(
            "Music Site", identifier: "org.example.Browser.app.abcdefghijklmnopabcdefghijklmnop"
        )))
        #expect(music.webApp == .browser(identifier: "org.example.Browser"))
        #expect(!music.isASafariWebApp)
        let other = try #require(AppInspector.inspect(try shortcut("Other", identifier: "org.example.other")))
        #expect(other.webApp == nil)
    }

    @Test func aWrappedBundleLinkThatLeadsOutOfTheWrapperIsNoApp() throws {
        let directory = try TemporaryDirectory()
        let elsewhere = try directory.directory("Elsewhere/example.app")
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "org.example.elsewhere"], format: .xml, options: 0)
            .write(to: elsewhere.appending(path: "Info.plist"))
        let bundle = try directory.directory("Example.app")
        try directory.directory("Example.app/Wrapper")
        try FileManager.default.createSymbolicLink(
            atPath: bundle.appending(path: "WrappedBundle").path(percentEncoded: false),
            withDestinationPath: "../Elsewhere/example.app"
        )

        #expect(AppInspector.inspect(bundle) == nil)
    }
}
