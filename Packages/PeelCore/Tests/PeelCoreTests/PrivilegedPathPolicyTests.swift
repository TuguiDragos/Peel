import Foundation
import PeelPrivileged
import Testing

struct PrivilegedPathPolicyTests {
    /// A policy over a fabricated root and home folder. The helper trusts only root (`trustedOwner` 0), and a
    /// test cannot make a file root's, so a test may pass its own user ID instead.
    private func policy(in directory: borrowing TemporaryDirectory, trustedOwner: uid_t = 0) throws -> PrivilegedPathPolicy {
        try directory.directory("root/Library/LaunchDaemons")
        try directory.directory("root/Applications")
        try directory.directory("root/Library/Caches")
        try directory.directory("home/Library")
        try directory.directory("root/usr/local/bin")
        let root = directory.url.path(percentEncoded: false)
        return PrivilegedPathPolicy(
            homeDirectory: root + "home",
            systemLocations: [root + "root/Library/LaunchDaemons", root + "root/Applications", root + "root/Library/Caches"],
            applicationLocations: [root + "root/Applications"],
            restoreLocations: [root + "root/Applications", root + "root/Library/Caches"],
            linkLocations: [root + "root/usr/local/bin"],
            trustedOwner: trustedOwner
        )
    }

    /// Creates a file in the fabricated Trash and opens it the way the helper does.
    private func trashed(_ name: String, permissions: Int = 0o644, in directory: borrowing TemporaryDirectory, by policy: PrivilegedPathPolicy) throws -> OpenItem {
        try directory.file("home/.Trash/\(name)")
        try directory.setPermissions(permissions, of: "home/.Trash/\(name)")
        let trash = try #require(policy.openTrash(ownedBy: getuid()))
        return try #require(policy.openInTrash(path("home/.Trash/\(name)", in: directory), trash: trash))
    }

    private func path(_ relative: String, in directory: borrowing TemporaryDirectory) -> String {
        directory.url.appending(path: relative).path(percentEncoded: false)
    }

    @Test func acceptsItemsInsideAllowedLocations() throws {
        let directory = try TemporaryDirectory()
        let policy = try policy(in: directory)
        try directory.file("root/Library/LaunchDaemons/com.example.helper.plist")
        try directory.directory("root/Applications/Example.app")
        try directory.directory("home/Library/Application Support/Example")

        for item in ["root/Library/LaunchDaemons/com.example.helper.plist", "root/Applications/Example.app", "home/Library/Application Support/Example"] {
            let expected = try #require(PrivilegedPathPolicy.resolvedPath(path(item, in: directory)))
            #expect(policy.open(path(item, in: directory)).map(\.path) == .success(expected))
        }
    }

    /// From the folders command-line tools are linked into, the helper takes a link and never a file, and only one
    /// that leads nowhere: Peel sends a tool's link once the app it leads into is gone, and a link that still leads
    /// somewhere stays. Only a link goes back there.
    @Test func takesOnlyALinkThatLeadsNowhereFromTheToolFolders() throws {
        let directory = try TemporaryDirectory()
        let policy = try policy(in: directory, trustedOwner: getuid())
        try directory.file("root/Applications/Tool.app/Contents/MacOS/tool")
        try directory.file("root/usr/local/bin/real")
        try directory.directory("root/usr/local/bin/folder")
        func link(_ name: String, to destination: String) throws {
            try FileManager.default.createSymbolicLink(atPath: path("root/usr/local/bin/\(name)", in: directory), withDestinationPath: destination)
        }
        try link("gone", to: path("root/Applications/Gone.app/Contents/MacOS/gone", in: directory))
        try link("relative", to: "../../../Applications/Gone.app/Contents/MacOS/gone")
        try link("loop", to: "loop")
        try link("tool", to: path("root/Applications/Tool.app/Contents/MacOS/tool", in: directory))
        try link("folder/deeper", to: "nowhere")

        for name in ["gone", "relative", "loop"] {
            #expect(policy.refusal(of: path("root/usr/local/bin/\(name)", in: directory)) == nil)
            #expect((try? policy.open(path("root/usr/local/bin/\(name)", in: directory)).get()) != nil, "\(name) was refused")
        }
        #expect(policy.open(path("root/usr/local/bin/tool", in: directory)).map(\.name) == .failure(.leadsSomewhere))
        #expect(policy.open(path("root/usr/local/bin/real", in: directory)).map(\.name) == .failure(.notALink))
        #expect(policy.open(path("root/usr/local/bin/folder", in: directory)).map(\.name) == .failure(.notALink))
        #expect(policy.refusal(of: path("root/usr/local/bin/folder/deeper", in: directory)) == .outsideAllowedLocations)

        let file = try trashed("gone", in: directory, by: policy)
        #expect(policy.openDestination(path("root/usr/local/bin/gone2", in: directory), for: file).map(\.name) == .failure(.notALink))
        try FileManager.default.createSymbolicLink(atPath: path("home/.Trash/link", in: directory), withDestinationPath: "nowhere")
        let trash = try #require(policy.openTrash(ownedBy: getuid()))
        let trashedLink = try #require(policy.openInTrash(path("home/.Trash/link", in: directory), trash: trash))
        #expect(policy.openDestination(path("root/usr/local/bin/gone2", in: directory), for: trashedLink).map(\.name) == .success("gone2"))
    }

    /// A browser profile with a wallet extension's vault stays, and so does every folder around it, while the rest
    /// of the profile can still go.
    @Test func refusesAFolderHoldingABrowserWallet() throws {
        let directory = try TemporaryDirectory()
        let policy = try policy(in: directory)
        let profile = "root/Library/Caches/Vendor/Browser/Default"
        try directory.file("\(profile)/Local Extension Settings/\(WalletIDs.metaMask)/000003.log")
        try directory.file("\(profile)/Cache/data_0")

        #expect(policy.refusal(of: path("root/Library/Caches/Vendor", in: directory)) == .irreplaceable)
        #expect(policy.refusal(of: path(profile, in: directory)) == .irreplaceable)
        #expect(policy.refusal(of: path("\(profile)/Local Extension Settings/\(WalletIDs.metaMask)", in: directory)) == .irreplaceable)
        #expect(policy.refusal(of: path("\(profile)/Cache", in: directory)) == nil)
    }

    /// Peel calls `refusal(of:)` before it offers the helper anything, so it must give the same answer as `open`.
    @Test func saysBeforeOpeningAnythingWhatOpeningWouldRefuse() throws {
        let directory = try TemporaryDirectory()
        let policy = try policy(in: directory)
        try directory.directory("root/Applications/Example.app")
        try directory.directory("root/Applications/Example Tools")
        try directory.directory("root/Library/Frameworks/Example.framework")
        try directory.file("root/Library/Caches/com.example.cache")

        let answers: [(String, PrivilegedPathPolicy.Rejection?)] = [
            ("root/Applications/Example.app", nil),
            ("root/Library/Caches/com.example.cache", nil),
            ("root/Applications/Example Tools", .notAnApplication),
            ("root/Library/Frameworks/Example.framework", .outsideAllowedLocations),
        ]
        for (relative, expected) in answers {
            let item = path(relative, in: directory)
            let opened: PrivilegedPathPolicy.Rejection? = if case .failure(let rejection) = policy.open(item) { rejection } else { nil }
            #expect(policy.refusal(of: item) == expected, "\(relative)")
            #expect(policy.refusal(of: item) == opened, "\(relative): opening answers \(String(describing: opened))")
        }
    }

    @Test func rejectsUnsafePaths() throws {
        let directory = try TemporaryDirectory()
        let policy = try policy(in: directory)
        try directory.file("root/Applications/notes.txt")
        try directory.file("outside/secret")
        try FileManager.default.createSymbolicLink(
            atPath: path("root/Library/LaunchDaemons/redirect", in: directory),
            withDestinationPath: path("outside", in: directory)
        )

        func refusal(_ path: String) -> PrivilegedPathPolicy.Rejection? { policy.open(path).rejection }

        #expect(refusal("relative/path") == .notAbsolute)
        #expect(refusal(path("root/Library/LaunchDaemons/../../outside/secret", in: directory)) == .relativeComponent)
        #expect(refusal(path("root/Library/LaunchDaemons/redirect/secret", in: directory)) == .outsideAllowedLocations)
        #expect(refusal(path("outside/secret", in: directory)) == .outsideAllowedLocations)
        #expect(refusal(path("root/Library/LaunchDaemons", in: directory)) == .outsideAllowedLocations)
        #expect(refusal(path("root/Applications/notes.txt", in: directory)) == .notAnApplication)
        #expect(refusal(path("root/Library/LaunchDaemons/missing.plist", in: directory)) == .missing)
        #expect(refusal(path("root/Library/Missing/item", in: directory)) == .unresolvableParent)
    }

    @Test func movesSymlinksThemselvesNotTheirTargets() throws {
        let directory = try TemporaryDirectory()
        let policy = try policy(in: directory)
        try directory.file("outside/secret")
        let link = path("root/Library/LaunchDaemons/link.plist", in: directory)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: path("outside/secret", in: directory))

        guard case .success(let resolved) = policy.open(link) else {
            Issue.record("symlink inside an allowed location should be accepted")
            return
        }
        #expect(resolved.path.hasSuffix("/root/Library/LaunchDaemons/link.plist"))
    }

    @Test(arguments: [
        ("com.example.helper", true),
        ("com.apple.securityd", false),
        ("com.example.helper; rm -rf /", false),
        ("../../etc", false),
        ("-rf", false),
        ("", false),
    ])
    func validatesLabels(label: String, isValid: Bool) {
        #expect(PrivilegedPathPolicy.isValidLabel(label) == isValid)
    }

    @Test func acceptsARestoreDestinationThatDoesNotExistYet() throws {
        let directory = try TemporaryDirectory()
        let policy = try policy(in: directory)

        let destination = path("root/Library/Caches/com.example.helper.plist", in: directory)
        let item = try trashed("com.example.helper.plist", in: directory, by: policy)
        let resolved = try policy.openDestination(destination, for: item).get()
        #expect(resolved.path.hasSuffix("/root/Library/Caches/com.example.helper.plist"))
    }

    /// A folder that root loads code from takes back only items owned by root and writable by no one else.
    /// Anything else could have been rewritten while it sat in the user's Trash.
    @Test func restoresIntoAFolderThatLoadsCodeOnlyWhatIsRootsAlone() throws {
        let directory = try TemporaryDirectory()
        let destination = path("root/Library/LaunchDaemons/com.example.helper.plist", in: directory)

        let helper = try policy(in: directory)
        #expect(helper.openDestination(destination, for: try trashed("users.plist", in: directory, by: helper)).rejection == .loadsCode)

        let trusting = try policy(in: directory, trustedOwner: getuid())
        #expect(trusting.openDestination(destination, for: try trashed("writable.plist", permissions: 0o664, in: directory, by: trusting)).rejection == .loadsCode)
        #expect(try trusting.openDestination(destination, for: try trashed("roots.plist", in: directory, by: trusting)).get().path.hasSuffix("/LaunchDaemons/com.example.helper.plist"))
    }

    @Test func refusesRestoreDestinationsThatAreWrong() throws {
        let directory = try TemporaryDirectory()
        let policy = try policy(in: directory)
        try directory.file("root/Library/Caches/taken.plist")
        try directory.file("root/Applications/Example.txt")
        try directory.directory("home/Documents")
        let item = try trashed("item.plist", in: directory, by: policy)

        #expect(policy.openDestination(path("root/Library/Caches/taken.plist", in: directory), for: item).rejection == .alreadyExists)
        #expect(policy.openDestination(path("root/Applications/New.txt", in: directory), for: item).rejection == .notAnApplication)
        #expect(policy.openDestination(path("root/Library/Other/new.plist", in: directory), for: item).rejection == .unresolvableParent)
        #expect(policy.openDestination(path("home/Documents/new.plist", in: directory), for: item).rejection == .outsideAllowedLocations)
        #expect(policy.openDestination("relative/path", for: item).rejection == .notAbsolute)
        #expect(policy.openDestination(path("root/Library/Caches/../../escape.plist", in: directory), for: item).rejection == .relativeComponent)
    }

    /// Without Full Disk Access, macOS refuses to open `~/.Trash` for reading, the helper included, but allows
    /// opening it for search. Moving an item in needs no reading, so a Trash that can be entered but not listed
    /// stands in for it here.
    @Test func movesIntoATrashItMayNotRead() throws {
        let directory = try TemporaryDirectory()
        let policy = try policy(in: directory)
        try directory.directory("home/.Trash")
        try directory.file("root/Library/Caches/com.example.cache/data.db")
        try directory.setPermissions(0o300, of: "home/.Trash")
        defer { try? directory.setPermissions(0o755, of: "home/.Trash") }

        let trash = try #require(policy.openTrash(ownedBy: getuid()), "a Trash that cannot be listed was taken for no Trash at all")
        let item = try policy.open(path("root/Library/Caches/com.example.cache", in: directory)).get()
        let moved = try TrashMover.move(item, into: trash).get()

        try directory.setPermissions(0o755, of: "home/.Trash")
        #expect(FileManager.default.fileExists(atPath: moved + "/data.db"))
        #expect(policy.openInTrash(moved, trash: trash) != nil)
    }

    @Test func movesIntoTrashWithoutOverwriting() throws {
        let directory = try TemporaryDirectory()
        let policy = try policy(in: directory)
        try directory.file("home/.Trash/Example.app/Contents/Info.plist")
        try directory.file("root/Applications/Example.app/Contents/Info.plist")
        let trash = try #require(policy.openTrash(ownedBy: getuid()))

        let first = try #require(try? policy.open(path("root/Applications/Example.app", in: directory)).get())
        let firstResult = TrashMover.move(first, into: trash)
        try directory.file("root/Applications/Example.app/Contents/Info.plist")
        let second = try #require(try? policy.open(path("root/Applications/Example.app", in: directory)).get())
        let secondResult = TrashMover.move(second, into: trash)

        #expect(try firstResult.get().hasSuffix("/.Trash/Example 2.app"))
        #expect(try secondResult.get().hasSuffix("/.Trash/Example 3.app"))
        #expect(FileManager.default.fileExists(atPath: path("home/.Trash/Example.app/Contents/Info.plist", in: directory)))
    }

    @Test func readsDaemonLabelsFromInsideThePlistNotTheFileName() throws {
        let directory = try TemporaryDirectory()
        let daemons = try directory.directory("System/Library/LaunchDaemons").path(percentEncoded: false)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["Label": "com.openssh.sshd"], format: .xml, options: 0)
        try directory.file("System/Library/LaunchDaemons/ssh.plist", contents: plist)

        let labels = SystemDaemons.labels(in: daemons)
        #expect(labels == ["com.openssh.sshd"])
        #expect(!PrivilegedPathPolicy.allowsDaemon("com.openssh.sshd", shipped: labels))
        #expect(PrivilegedPathPolicy.allowsDaemon("com.example.helper", shipped: labels))
    }

    /// A job is started from the file that declares its label, not the file named after it. Here
    /// `com.vendor.daemon.plist` declares another job, so going by the file name would load that job as root.
    @Test func findsTheFileThatDeclaresADaemonNotTheOneNamedAfterIt() throws {
        let directory = try TemporaryDirectory()
        let daemons = try directory.directory("Library/LaunchDaemons").path(percentEncoded: false)
        @discardableResult
        func plist(_ name: String, label: String) throws -> URL {
            try directory.file("Library/LaunchDaemons/\(name)", contents: PropertyListSerialization.data(fromPropertyList: ["Label": label], format: .xml, options: 0))
        }
        let real = try plist("vendor-daemon.plist", label: "com.vendor.daemon")
        try plist("com.vendor.daemon.plist", label: "com.somebody.else")
        let linked = try directory.file("elsewhere.plist", contents: PropertyListSerialization.data(fromPropertyList: ["Label": "com.linked.daemon"], format: .xml, options: 0))
        try FileManager.default.createSymbolicLink(atPath: daemons + "/linked.plist", withDestinationPath: linked.path(percentEncoded: false))
        try plist("one.plist", label: "com.twice.daemon")
        try plist("two.plist", label: "com.twice.daemon")

        #expect(SystemDaemons.file(declaring: "com.vendor.daemon", in: daemons) == real.path(percentEncoded: false))
        #expect(SystemDaemons.file(declaring: "com.linked.daemon", in: daemons) == nil, "a link out of the folder was followed")
        #expect(SystemDaemons.file(declaring: "com.twice.daemon", in: daemons) == nil, "two files declare it, and one was picked")
        #expect(SystemDaemons.file(declaring: "com.nobody.daemon", in: daemons) == nil)
    }

    /// The helper opens only what really sits in the user's Trash. The path comes from the app, which reads it
    /// from a file any process can rewrite.
    @Test func opensOnlyWhatIsReallyInTheTrash() throws {
        let directory = try TemporaryDirectory()
        let policy = try policy(in: directory)
        try directory.file("home/.Trash/nested/deep.plist")
        try directory.file("outside/secret")
        try FileManager.default.createSymbolicLink(
            atPath: path("home/.Trash/link.plist", in: directory),
            withDestinationPath: path("outside/secret", in: directory)
        )
        let trash = try #require(policy.openTrash(ownedBy: getuid()))

        #expect(policy.openInTrash(path("home/.Trash/nested/deep.plist", in: directory), trash: trash)?.name == "deep.plist")
        #expect(policy.openInTrash(path("outside/secret", in: directory), trash: trash) == nil)
        #expect(policy.openInTrash(path("home/.Trash/missing.plist", in: directory), trash: trash) == nil)
        // The link itself is in the Trash; what it leads to is not, and it is the link that would move.
        #expect(policy.openInTrash(path("home/.Trash/link.plist", in: directory), trash: trash)?.name == "link.plist")
    }

    /// The helper sends each refusal to the app as an English sentence. The app translates a sentence it
    /// recognizes and shows any other as it is, so each must be distinct and read as a sentence.
    @Test func everyRefusalIsWrittenForAPerson() {
        // Every case, so one added later is held to the same wording.
        let rejections = PrivilegedPathPolicy.Rejection.allCases
        let explanations = rejections.map(\.explanation)

        #expect(Set(explanations).count == rejections.count)
        for explanation in explanations {
            #expect(explanation.hasSuffix("."))
            #expect(explanation.first?.isUppercase == true || explanation.hasPrefix("macOS"))
            // No dash or hyphen of any kind, since this text is shown in the interface.
            #expect(!explanation.contains(where: { ("\u{2010}"..."\u{2015}").contains($0) || $0 == "-" }))
        }
    }
}

private extension Result where Failure == PrivilegedPathPolicy.Rejection {
    var rejection: PrivilegedPathPolicy.Rejection? {
        switch self {
        case .success: nil
        case .failure(let rejection): rejection
        }
    }
}
