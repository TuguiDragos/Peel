import Foundation
@testable import PeelPrivileged
import Testing

/// What the privileged helper accepts on its own, with no help from the app.
struct AttackHelperPolicyTests {
    private func policy(_ directory: borrowing TemporaryDirectory) -> PrivilegedPathPolicy {
        PrivilegedPathPolicy(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory).path(percentEncoded: false),
            systemLocations: [],
            applicationLocations: []
        )
    }

    /// The helper serves all of `<home>/Library`, so it must refuse the irreplaceable parts on its own.
    @Test func theHelperRefusesICloudDriveAndKeychains() throws {
        let directory = try TemporaryDirectory()
        let paths = [
            "home/Library/Mobile Documents/com~apple~CloudDocs/Thesis.pages",
            "home/Library/Keychains/login.keychain-db",
            "home/Library/Messages/chat.db",
        ]
        for path in paths {
            try directory.file(path)
        }

        for path in paths {
            let result = policy(directory).open(directory.url.appending(path: path).path(percentEncoded: false))
            #expect(result.isFailure, "ATTACK SUCCEEDED: the helper would move \(path)")
        }
    }

    /// "Is this protected" is half the question. The helper runs as root and must ask the other half on its
    /// own too: would moving this take something protected along.
    @Test func theHelperRefusesAFolderThatHoldsWhatIsProtected() throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Application Support/MobileSync/Backup/device/Manifest.db")
        try directory.file("home/Library/Containers/com.example.notes/Data/Documents/novel.txt")
        try directory.file("home/Library/Caches/JetBrains/IntelliJIdea2026.2/LocalHistory/changes.storageData")
        try directory.file("home/Library/Caches/com.example.app/cache.db")
        try directory.file("home/Library/Application Support/Vendor/Shared/Family.photoslibrary/database/Photos.sqlite")

        let kept = [
            "home/Library/Application Support", "home/Library/Containers/com.example.notes", "home/Library/Caches/JetBrains",
            "home/Library/Application Support/Vendor",
        ]
        for path in kept {
            let result = policy(directory).open(directory.url.appending(path: path).path(percentEncoded: false))
            #expect(result.isFailure, "ATTACK SUCCEEDED: root would move \(path) and what it holds")
        }
        #expect(!policy(directory).open(directory.url.appending(path: "home/Library/Caches/com.example.app").path(percentEncoded: false)).isFailure)
    }

    /// A `String` reads a slash followed by a combining mark as one character, so a path split on `"/"` keeps
    /// that slash inside a name, and the kernel still walks through it. Here `Caches/dir` is a link into the
    /// keychains, and the name after it begins with a combining mark.
    @Test func aCombiningMarkAfterASlashHidesNoFolder() throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Keychains/\u{301}login.keychain-db")
        try directory.directory("home/Library/Caches")
        try FileManager.default.createSymbolicLink(
            at: directory.url.appending(path: "home/Library/Caches/dir"),
            withDestinationURL: directory.url.appending(path: "home/Library/Keychains", directoryHint: .isDirectory)
        )

        let caches = directory.url.appending(path: "home/Library/Caches").path(percentEncoded: false)
        let result = policy(directory).open(caches + "/dir/\u{301}login.keychain-db")

        #expect(result.isFailure, "ATTACK SUCCEEDED: the helper would move a keychain through a link it never saw")
    }

    /// The rules read a Swift string, and the kernel reads a C string that ends at the first NUL. So
    /// `Folder` + NUL + `.app` passes "only apps in /Applications" while the kernel moves `Folder`.
    @Test func aNameTheKernelWouldReadDifferently() throws {
        let directory = try TemporaryDirectory()
        try directory.file("root/Applications/Folder/notes.txt")
        try directory.file("root/Applications/Real.app/Contents/Info.plist")
        try directory.directory("home/.Trash")
        let policy = servingPolicy(directory)

        for name in ["Folder\u{0}.app", "Real.app\u{0}", "Real\n.app", "Real\u{7F}.app"] {
            let result = policy.open(path("root/Applications/", in: directory) + name)
            #expect(result.isFailure, "ATTACK SUCCEEDED: \(name.debugDescription) was accepted")
        }
        let trash = try #require(policy.openTrash(ownedBy: getuid()))
        #expect(policy.openInTrash(path("home/.Trash/", in: directory) + "Real.app\u{0}.txt", trash: trash) == nil)
        #expect(!policy.open(path("root/Applications/Real.app", in: directory)).isFailure)
    }

    /// A symbolic link in a parent folder that leads into iCloud Drive.
    @Test func theHelperResolvesASymlinkedParent() throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Mobile Documents/com~apple~CloudDocs/Thesis.pages")
        try directory.directory("home/Library/Caches")
        try FileManager.default.createSymbolicLink(
            atPath: directory.url.appending(path: "home/Library/Caches/Vendor").path(percentEncoded: false),
            withDestinationPath: "../Mobile Documents/com~apple~CloudDocs"
        )

        let result = policy(directory).open(
            directory.url.appending(path: "home/Library/Caches/Vendor/Thesis.pages").path(percentEncoded: false)
        )
        // The helper resolves the link and then refuses what is behind it, on its own.
        #expect(result.isFailure, "ATTACK SUCCEEDED: a symlinked parent reached iCloud Drive")
    }

    /// `realpath(3)` fixes the case as well as the links, so the helper reads a differently cased path as the
    /// one file it really is.
    @Test func theHelperCanonicalizesTheCase() throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/thing.db")
        let disguised = directory.url.appending(path: "home/library/caches/thing.db").path(percentEncoded: false)

        let resolved = try #require(try? policy(directory).open(disguised).get())
        #expect(resolved.path.hasSuffix("/Library/Caches/thing.db"), "realpath did not canonicalize the case")
    }
}

extension AttackHelperPolicyTests {
    private func servingPolicy(_ directory: borrowing TemporaryDirectory) -> PrivilegedPathPolicy {
        let root = directory.url.path(percentEncoded: false)
        return PrivilegedPathPolicy(
            homeDirectory: root + "home",
            systemLocations: [root + "root/Applications", root + "root/Library/LaunchDaemons", root + "root/Library/Caches"],
            applicationLocations: [root + "root/Applications"],
            restoreLocations: [root + "root/Applications", root + "root/Library/Caches"]
        )
    }

    private func path(_ relative: String, in directory: borrowing TemporaryDirectory) -> String {
        directory.url.appending(path: relative).path(percentEncoded: false)
    }

    /// A swap between the check and the move: after the helper approves a path, the folder it approved is moved
    /// aside and a link to somewhere else takes its name. The helper holds the folder open instead of using the
    /// name again, so the move cannot be sent elsewhere.
    @Test func aParentSwappedAfterTheCheckRedirectsNothing() throws {
        let directory = try TemporaryDirectory()
        try directory.file("root/Applications/Example.app/Contents/Info.plist")
        try directory.file("decoy/Example.app/Contents/Info.plist")
        try directory.directory("home/.Trash")
        let policy = servingPolicy(directory)

        let item = try #require(try? policy.open(path("root/Applications/Example.app", in: directory)).get())
        let trash = try #require(policy.openTrash(ownedBy: getuid()))

        let applications = path("root/Applications", in: directory)
        try FileManager.default.moveItem(atPath: applications, toPath: applications + ".real")
        try FileManager.default.createSymbolicLink(atPath: applications, withDestinationPath: path("decoy", in: directory))

        _ = TrashMover.move(item, into: trash)

        #expect(
            FileManager.default.fileExists(atPath: path("decoy/Example.app/Contents/Info.plist", in: directory)),
            "ATTACK SUCCEEDED: swapping the parent after the check sent the move somewhere else"
        )
        #expect(FileManager.default.fileExists(atPath: path("home/.Trash/Example.app/Contents/Info.plist", in: directory)))
    }

    /// Put Back is driven by a JSON file that any process running as the user can rewrite. A crafted record must
    /// not plant a file in a folder that something running as root loads code from.
    @Test func restoreRefusesEveryFolderThatLoadsCode() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("root/Library/LaunchDaemons")
        try directory.directory("root/Library/Caches")
        try directory.directory("root/Applications")
        let policy = servingPolicy(directory)

        try directory.file("home/.Trash/com.attacker.plist")
        let trash = try #require(policy.openTrash(ownedBy: getuid()))
        let payload = try #require(policy.openInTrash(path("home/.Trash/com.attacker.plist", in: directory), trash: trash))

        let planted = path("root/Library/LaunchDaemons/com.attacker.plist", in: directory)
        #expect(policy.openDestination(planted, for: payload).isFailure, "ATTACK SUCCEEDED: a root launch daemon can be planted")
    }

    /// `~/.Trash` belongs to the user, so they can put a link there. Following it would let them choose
    /// where root drops the files it moves.
    @Test func aLinkWhereTheTrashShouldBeIsRefused() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home")
        try directory.directory("root/Library/LaunchDaemons")
        try FileManager.default.createSymbolicLink(
            atPath: path("home/.Trash", in: directory),
            withDestinationPath: path("root/Library/LaunchDaemons", in: directory)
        )

        #expect(servingPolicy(directory).openTrash(ownedBy: getuid()) == nil, "ATTACK SUCCEEDED: root would move files into LaunchDaemons")
    }

    /// The helper serves only a Trash that belongs to the caller.
    @Test func aTrashOwnedBySomebodyElseIsRefused() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/.Trash")

        #expect(servingPolicy(directory).openTrash(ownedBy: getuid()) != nil)
        #expect(servingPolicy(directory).openTrash(ownedBy: getuid() &+ 1) == nil)
    }

    /// macOS ships daemons whose labels say nothing about Apple, so refusing the `com.apple.` prefix is not
    /// enough. Reads the `/System/Library/LaunchDaemons` of the Mac the test runs on.
    @Test func macOSsOwnDaemonsAreRefusedWhateverTheyAreCalled() throws {
        try #require(FileManager.default.fileExists(atPath: "/System/Library/LaunchDaemons"))
        let shipped = SystemDaemons.shipped
        try #require(!shipped.isEmpty)

        for label in ["com.openssh.sshd", "org.cups.cupsd", "com.vix.cron", "org.apache.httpd"] {
            #expect(shipped.contains(label), "\(label) is not in this Mac's system daemons; the test is stale")
            #expect(!PrivilegedPathPolicy.allowsDaemon(label), "ATTACK SUCCEEDED: the helper would stop \(label)")
        }
        // Stopping itself kills the helper before it can answer, and `disable` persists across boots with
        // nothing left to undo it. Its own daemon is managed from Settings, not from a list of background items.
        #expect(!PrivilegedPathPolicy.allowsDaemon(HelperIdentity.helperIdentifier), "the helper would stop or disable itself")
        #expect(PrivilegedPathPolicy.allowsDaemon("com.example.helper"))
    }

    /// The helper builds its whole policy around this string: which home is the caller's, which Trash is opened.
    @Test func readsTheCallersHomeFolder() throws {
        let home = try #require(UserAuthorization.homeDirectory(of: getuid()))
        #expect(home == String(cString: getpwuid(getuid()).pointee.pw_dir))
        #expect(home.hasPrefix("/"))
        #expect(UserAuthorization.homeDirectory(of: 4_000_000_000) == nil, "an account nobody has was given a home")
    }

    /// Not knowing what macOS ships is not the same as macOS shipping nothing.
    @Test func aListOfShippedDaemonsThatCouldNotBeReadAllowsNothing() throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("LaunchDaemons").path(percentEncoded: false)
        try directory.file("LaunchDaemons/ssh.plist", contents: Data("not a property list".utf8))

        #expect(!PrivilegedPathPolicy.allowsDaemon("com.example.helper", shipped: SystemDaemons.labels(in: "/no/such/folder")))
        #expect(!PrivilegedPathPolicy.allowsDaemon("com.example.helper", shipped: []))
        // A file that cannot be read still says something: its name is refused, which is what it usually declares.
        #expect(SystemDaemons.labels(in: folder) == ["ssh"])
    }

    /// The Mach service is advertised in the system domain, so every account on the Mac can reach it,
    /// including the ones nobody signs into. Checks every account on the Mac the test runs on against
    /// Directory Services' own answer.
    @Test func onlyAdministratorsAreAnswered() throws {
        #expect(UserAuthorization.isAdministrator(0), "root is an administrator")
        #expect(UserAuthorization.isAdministrator(getuid()) == isCurrentUserAnAdministrator())

        let administrators = Set(Self.run("/usr/bin/dscl", [".", "-read", "/Groups/admin", "GroupMembership"])
            .replacingOccurrences(of: "GroupMembership:", with: "")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init))
        try #require(administrators.contains("root"))

        var checked = 0
        for name in Self.run("/usr/bin/dscl", [".", "-list", "/Users"]).split(whereSeparator: \.isNewline) {
            let name = String(name)
            guard let entry = getpwnam(name) else { continue }
            checked += 1
            #expect(
                UserAuthorization.isAdministrator(entry.pointee.pw_uid) == administrators.contains(name),
                "\(name) (uid \(entry.pointee.pw_uid)) was answered wrongly"
            )
        }
        #expect(checked > 10, "only \(checked) accounts were checked; the test proves little")

        // Named outright, because these are accounts that code without administrator rights runs as.
        for name in ["_spotlight", "_windowserver", "daemon", "nobody"] {
            guard let entry = getpwnam(name) else { continue }
            #expect(!UserAuthorization.isAdministrator(entry.pointee.pw_uid), "ATTACK SUCCEEDED: \(name) reaches the helper")
        }
    }

    private static func run(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: output, as: UTF8.self)
    }

    private func isCurrentUserAnAdministrator() -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/id")
        process.arguments = ["-Gn"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return output.split(separator: " ").contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "admin" }
    }
}

private extension Result {
    var isFailure: Bool {
        switch self {
        case .success: false
        case .failure: true
        }
    }
}
