import Darwin
import Foundation
@testable import PeelCore
import PeelPrivileged
import Testing

/// Attacks on `RemovalGuard`, the last check before anything moves. Every file these tests write or move is in a
/// temporary directory.
struct AttackRemovalGuardTests {
    private func inode(_ path: String) -> (dev_t, ino_t)? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return (info.st_dev, info.st_ino)
    }

    private func link(_ target: String, at path: String) throws {
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target)
    }

    /// The folders every account starts with are never removed, whatever is inside them. The scanner shares this
    /// list, so a change made for one must not quietly widen the other.
    @Test func theFoldersEveryAccountStartsWithAreRefused() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let guardian = RemovalGuard(environment: SearchEnvironment(
            homeDirectory: home,
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        ))

        #expect(Set(ProtectedData.accountFolders) == ["Applications", "Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures", "Public"])
        for name in ProtectedData.accountFolders {
            try directory.file("home/\(name)/something.txt")
            #expect(!guardian.allowsRemoval(of: home.appending(path: name, directoryHint: .isDirectory)), "~/\(name) could be moved")
        }
        #expect(!guardian.allowsRemoval(of: home))
        // What is inside them is another matter: a duplicate in Downloads is still removable.
        #expect(guardian.allowsRemoval(of: home.appending(path: "Downloads/something.txt")))
    }

    /// Attack 1: write the protected folder in a different case. APFS is case-insensitive by default, so the
    /// path still names the same file, and comparing strings must not miss it.
    @Test func caseSpellingOfAProtectedTree() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let real = try directory.file("home/Library/Mobile Documents/com~apple~CloudDocs/Thesis.pages")
        let disguised = home.appending(path: "Library/mobile documents/com~apple~CloudDocs/Thesis.pages")

        // The kernel agrees the two spellings are one file.
        #expect(FileManager.default.fileExists(atPath: disguised.path(percentEncoded: false)))
        #expect(inode(real.path(percentEncoded: false)) != nil)
        #expect(inode(real.path(percentEncoded: false))! == inode(disguised.path(percentEncoded: false))!)

        let guardian = RemovalGuard(environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root")))
        #expect(!guardian.allowsRemoval(of: real), "canonical spelling must be refused")
        #expect(!guardian.allowsRemoval(of: disguised), "ATTACK SUCCEEDED: lower-cased iCloud Drive is allowed")
    }

    /// The same trick against other protected trees and the photo library extension check.
    @Test func caseSpellingOfEveryProtectedName() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try directory.directory("home/Library")
        let guardian = RemovalGuard(environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root")))

        let disguises = [
            "Library/mobile documents/com~apple~CloudDocs/Thesis.pages",
            "Library/cloudstorage/Dropbox/taxes.pdf",
            "Library/keychains/login.keychain-db",
            "Library/messages/chat.db",
            "Library/mail/V10",
            "Library/safari/Bookmarks.plist",
            "Pictures/Photos Library.PhotosLibrary/database/Photos.sqlite",
            "Library/Containers/net.whatsapp.WhatsApp/Data/documents/file.pdf",
            ".SSH/id_ed25519",
        ]
        for path in disguises {
            #expect(!guardian.allowsRemoval(of: home.appending(path: path)), "ATTACK SUCCEEDED: the guard allows \(path)")
        }
    }

    /// Attack 1b: the guard lower-cases the path it is given, so `protectedPrefixes` must be lower-case too, or
    /// those entries would match nothing.
    @Test func protectedPrefixesSurviveTheLowerCasing() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let guardian = RemovalGuard(environment: SearchEnvironment(homeDirectory: home, rootDirectory: URL(filePath: "/")))

        // The data volume's own mount point is not SIP-restricted, and Spotlight hands back paths under it.
        let reachable = [
            "/System/Volumes/Data",
            "/System/Volumes/Data/Users",
            "/Library/Updates",
            "/Library/Updates/001-12345",
        ]
        for path in reachable {
            #expect(!guardian.allowsRemoval(of: URL(filePath: path)), "ATTACK SUCCEEDED: the guard allows \(path)")
        }
    }

    /// Attack 2: a `..` that walks back out of a symbolic link. Folded as text, before the link is resolved, the
    /// path names a folder the kernel never visits.
    @Test func parentComponentAcrossASymbolicLink() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try directory.directory("home/Library/Caches")
        let real = try directory.file("home/Library/Mobile Documents/Thesis.pages")
        try link("../Mobile Documents/com~apple~CloudDocs", at: home.appending(path: "Library/Caches/alias").path(percentEncoded: false))
        try directory.directory("home/Library/Mobile Documents/com~apple~CloudDocs")

        let disguised = home.appending(path: "Library/Caches/alias/../Thesis.pages")
        #expect(FileManager.default.fileExists(atPath: disguised.path(percentEncoded: false)), "the kernel reaches the iCloud file")
        #expect(inode(real.path(percentEncoded: false))! == inode(disguised.path(percentEncoded: false))!)

        let guardian = RemovalGuard(environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root")))
        #expect(!guardian.allowsRemoval(of: disguised), "ATTACK SUCCEEDED: `..` out of a link reaches iCloud Drive")
    }

    /// Attack 3: a plain symbolic link in a parent component, with no `..` at all.
    @Test func symbolicLinkInAParentComponent() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try directory.directory("home/Library/Caches")
        try directory.file("home/Library/Mobile Documents/com~apple~CloudDocs/Thesis.pages")
        try link("../Mobile Documents/com~apple~CloudDocs", at: home.appending(path: "Library/Caches/Vendor").path(percentEncoded: false))

        let disguised = home.appending(path: "Library/Caches/Vendor/Thesis.pages")
        let guardian = RemovalGuard(environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root")))
        #expect(!guardian.allowsRemoval(of: disguised), "ATTACK SUCCEEDED: a symlinked cache folder reaches iCloud Drive")
    }

    /// Attack 4, end to end: a differently cased iCloud Drive path is handed to `TrashService`.
    @Test func trashServiceRemovesICloudThroughACaseSpelling() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let real = try directory.file("home/Library/Mobile Documents/com~apple~CloudDocs/Thesis.pages")
        let trash = try directory.directory("FakeTrash")
        let service = TrashService(
            environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root"))
        ) { url in
            let destination = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }

        let disguised = home.appending(path: "Library/mobile documents/com~apple~CloudDocs/Thesis.pages")
        let result = await service.trash([disguised])

        #expect(result.failures.map(\.reason) == [.protectedLocation], "ATTACK SUCCEEDED: TrashService moved an iCloud Drive file")
        #expect(
            FileManager.default.fileExists(atPath: real.path(percentEncoded: false)),
            "ATTACK SUCCEEDED: the real iCloud file is gone, which syncs the deletion to every device"
        )
    }

    /// Attack 5: a file named in another case than the user's exclusion must still be excluded.
    @Test func exclusionsAreCaseSensitive() throws {
        let directory = try TemporaryDirectory()
        let vault = try directory.directory("home/Documents/Vault")
        let file = try directory.file("home/Documents/Vault/passwords.kdbx")
        let exclusions = Exclusions(paths: [vault])

        #expect(exclusions.excludes(file))
        let disguised = directory.url.appending(path: "home/documents/vault/passwords.kdbx")
        #expect(FileManager.default.fileExists(atPath: disguised.path(percentEncoded: false)))
        #expect(exclusions.excludes(disguised), "ATTACK SUCCEEDED: an excluded file is not excluded under another case")
    }

    /// Attack 6: an exclusion written through a symbolic link.
    @Test func exclusionsThroughASymbolicLink() throws {
        let directory = try TemporaryDirectory()
        let real = try directory.directory("home/Archive")
        try directory.file("home/Archive/taxes.pdf")
        try FileManager.default.createSymbolicLink(
            atPath: directory.url.appending(path: "home/Shortcut").path(percentEncoded: false),
            withDestinationPath: real.path(percentEncoded: false)
        )

        // The user excludes the name they know, and the scanner reports the resolved one.
        let exclusions = Exclusions(paths: [directory.url.appending(path: "home/Shortcut")])
        let asScanned = directory.url.appending(path: "home/Archive/taxes.pdf")
        #expect(exclusions.excludes(asScanned), "ATTACK SUCCEEDED: an exclusion written through a link protects nothing")
    }

    /// Attack: ask for the folder around a protected tree. `~/Library/Keychains` is refused, so ask for
    /// `~/Library` instead, and the keychains would go with it. The same check is what makes protecting a
    /// single file worth anything.
    @Test func theFolderAroundAProtectedTree() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try directory.file("home/Library/Keychains/login.keychain-db")
        try directory.file("home/Library/Mobile Documents/com~apple~CloudDocs/Thesis.pages")
        let guardian = RemovalGuard(environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root")))

        #expect(!guardian.allowsRemoval(of: home.appending(path: "Library")), "ATTACK SUCCEEDED: the folder holding the keychains is allowed")
        #expect(!guardian.allowsRemoval(of: home), "ATTACK SUCCEEDED: the home folder is allowed")

        // "Is this protected" and "would taking this take something protected" are different questions. Only the
        // second may refuse a folder on the way up, because a scanner asks the first about every folder it walks
        // into.
        let homePath = home.path(percentEncoded: false)
        #expect(ProtectedData.holds(homePath + "/Library", home: homePath))
        #expect(!ProtectedData.refuses(homePath + "/Library", home: homePath), "a scanner could no longer walk into Library")
        #expect(!ProtectedData.holds(homePath + "/Library/Caches/com.example.app", home: homePath))
    }

    /// The hidden items tools share in the home folder, such as `.config` and `.zshrc`, are refused whatever an
    /// app calls itself. Anything else inside a shared folder can still go.
    @Test func theFoldersTheWholeMacShares() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try directory.file("home/.local/share/local/state.json")
        try directory.file("home/.kube/config")
        try directory.file("home/.zshrc")
        let guardian = RemovalGuard(environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root")))

        for item in [".local", ".config", ".cache", ".kube", ".kube/config", ".zshrc", ".gitconfig", ".npmrc"] {
            #expect(!guardian.allowsRemoval(of: home.appending(path: item)), "\(item) may be removed")
        }
        #expect(guardian.allowsRemoval(of: home.appending(path: ".local/share/local")))
    }

    /// A key is protected on its own, so the cache around it can still be cleaned. The key cannot go, the folder
    /// holding it cannot go, and the cache beside it still can.
    @Test func aKeyIsProtectedWithoutProtectingTheCacheAroundIt() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try directory.file("home/.android/debug.keystore")
        try directory.file("home/.android/avd/Pixel.avd/userdata.img", bytes: 4_096)
        try directory.file("home/.m2/settings-security.xml")
        try directory.file("home/.m2/repository/org/example/thing.jar")
        try directory.file("home/.gradle/gradle.properties")
        try directory.file("home/.gradle/caches/modules-2/thing.jar")
        try directory.file("home/.electrum/wallets/default_wallet")
        try directory.file("home/.electrum/blockchain_headers", bytes: 4_096)
        try directory.file("home/Library/Application Support/Bitcoin/wallets/wallet.dat")
        try directory.file("home/Library/Application Support/Bitcoin/blocks/blk00000.dat", bytes: 4_096)
        let guardian = RemovalGuard(environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root")))
        let homePath = home.path(percentEncoded: false)

        for key in ProtectedData.homeKeys + ProtectedData.walletKeys {
            let url = home.appending(path: key)
            #expect(!guardian.allowsRemoval(of: url), "\(key) may be removed")
            #expect(ProtectedData.refuses(url.path(percentEncoded: false), home: homePath))
            let folder = url.deletingLastPathComponent()
            #expect(!guardian.allowsRemoval(of: folder), "the folder holding \(key) may be removed")
            #expect(ProtectedData.holds(folder.path(percentEncoded: false), home: homePath))
        }

        // What comes back on its own is still cleanable, which is the whole point of naming the key alone.
        for cache in [".android/avd", ".m2/repository", ".gradle/caches", ".electrum/blockchain_headers", "Library/Application Support/Bitcoin/blocks"] {
            #expect(guardian.allowsRemoval(of: home.appending(path: cache)), "\(cache) is refused")
        }
    }

    /// The place Put Back writes to does not exist yet, so asking about the file itself resolves nothing. The
    /// guard has to find out where it would really land: through a linked parent, or under a name the disk
    /// folds into a protected one (`ß` for `ss`, the long `ſ` for `s`).
    @Test func aDestinationThatDoesNotExistYet() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let cloud = try directory.directory("home/Library/Mobile Documents/com~apple~CloudDocs")
        try directory.directory("home/Library/Messages")
        try directory.directory("home/Library/Caches")
        try link(cloud.path(percentEncoded: false), at: home.appending(path: "Library/Caches/Vendor").path(percentEncoded: false))
        let guardian = RemovalGuard(environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root")))

        let destinations = [
            "Library/Caches/Vendor/not-there-yet.pdf",
            "Library/Caches/Vendor/New Folder/not-there-yet.pdf",
            "Library/Meßages/planted.db",
            "Library/Meſſages/planted.db",
            "Library/Caches/New Folder/../../Messages/planted.db",
        ]
        for path in destinations {
            #expect(!guardian.allowsRemoval(of: home.appending(path: path)), "ATTACK SUCCEEDED: the guard allows \(path)")
        }
        #expect(guardian.allowsRemoval(of: home.appending(path: "Library/Caches/New Folder/not-there-yet.pdf")))
    }

    /// A home folder kept on another disk is reached through a link, and Spotlight names files by where they
    /// really are. What is protected has to be known under that name too.
    @Test func aHomeReachedThroughALink() throws {
        let directory = try TemporaryDirectory()
        let thesis = try directory.file("disk/me/Library/Mobile Documents/com~apple~CloudDocs/Thesis.pages")
        let cache = try directory.file("disk/me/Library/Caches/com.example.app/cache.db")
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try link(directory.url.appending(path: "disk/me").path(percentEncoded: false), at: directory.url.appending(path: "home").path(percentEncoded: false))
        let guardian = RemovalGuard(environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root")))

        #expect(!guardian.allowsRemoval(of: thesis), "ATTACK SUCCEEDED: iCloud Drive is allowed under the name of the disk it is on")
        #expect(!guardian.allowsRemoval(of: home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Thesis.pages")))
        #expect(!guardian.allowsRemoval(of: directory.url.appending(path: "disk/me/Library")))
        #expect(guardian.allowsRemoval(of: cache.deletingLastPathComponent()))
    }

    /// `trashItem` moves a link, not what it points at, so an item is judged where it sits, not where it leads.
    @Test func anItemUnderALinkedParentThatIsItselfALink() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let mail = try directory.directory("home/Library/Mail")
        let harmless = try directory.file("elsewhere/note.txt")
        try link(harmless.path(percentEncoded: false), at: mail.appending(path: "V10").path(percentEncoded: false))
        try link(mail.path(percentEncoded: false), at: home.appending(path: "shortcut").path(percentEncoded: false))
        let guardian = RemovalGuard(environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root")))

        #expect(!guardian.allowsRemoval(of: home.appending(path: "shortcut/V10")), "ATTACK SUCCEEDED: a file inside Mail can be removed through a link")
    }

    /// Where macOS 26 keeps what its own apps hold for the user. Apple moves these from release to release (Calendar
    /// left `~/Library/Calendars` for a group container), so its group containers are known by their shape.
    @Test func whatApplesOwnAppsKeepForYou() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try directory.directory("home/Library/Group Containers")
        try directory.directory("home/Library/Containers")
        let guardian = RemovalGuard(environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root")))
        let homePath = home.path(percentEncoded: false)

        let stores = [
            "Library/Group Containers/group.com.apple.notes/NoteStore.sqlite",
            "Library/Group Containers/group.com.apple.calendar",
            "Library/Group Containers/group.com.apple.reminders",
            "Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings/New Recording.m4a",
            "Library/Group Containers/243LU875E5.groups.com.apple.podcasts",
            "Library/Group Containers/com.apple.Home.group",
            "Library/Group Containers/systemgroup.com.apple.configurationprofiles",
            "Library/Group Containers/group.is.workflow.shortcuts",
            "Library/Containers/com.apple.freeform",
            "Library/Containers/com.apple.journal/Data/Library/Journal.sqlite",
            "Library/Containers/com.apple.Stickies/Data/Library/Stickies",
            "Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db",
            "Library/Shortcuts", "Library/HomeKit", "Library/Accounts", "Library/Finance", "Library/IdentityServices",
            "Library/Reminders", "Library/Calendars",
            "Library/Application Support/CallHistoryTransactions", "Library/Application Support/FaceTime",
        ]
        for store in stores {
            let url = home.appending(path: store)
            #expect(!guardian.allowsRemoval(of: url), "\(store) may be removed")
            #expect(ProtectedData.refuses(url.path(percentEncoded: false), home: homePath), "\(store) is not refused for the helper")
        }

        // What an app leaves behind next to them still goes: another maker's group, and an Apple app's own caches.
        for leftover in ["Library/Group Containers/ABCDE12345.com.example.app", "Library/Group Containers/group.com.example.shared", "Library/Containers/com.apple.TextEdit/Data/Library/Caches"] {
            #expect(guardian.allowsRemoval(of: home.appending(path: leftover)), "\(leftover) is refused")
        }
    }

    /// The guard refuses what is inside a container's `Data/Documents`, where a sandboxed app keeps what its
    /// user made. An uninstall lists the container around it, so the container is refused too while that folder
    /// holds anything or cannot be read.
    @Test func theContainerAroundSomebodysDocuments() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try directory.file("home/Library/Containers/com.example.notes/Data/Documents/thesis.txt")
        try directory.file("home/Library/Containers/com.example.notes/Data/Library/Caches/cache.db")
        try directory.file("home/Library/Containers/com.example.empty/Data/Documents/.DS_Store")
        try directory.file("home/Library/Containers/com.example.empty/Data/Library/Caches/cache.db")
        let guardian = RemovalGuard(environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root")))

        for path in ["Library/Containers/com.example.notes", "Library/containers/COM.EXAMPLE.NOTES/data", "Library/Containers/com.example.notes/Data/Documents/thesis.txt"] {
            #expect(!guardian.allowsRemoval(of: home.appending(path: path)), "ATTACK SUCCEEDED: \(path) goes, and the thesis with it")
        }
        for path in ["Library/Containers/com.example.empty", "Library/Containers/com.example.notes/Data/Library/Caches"] {
            #expect(guardian.allowsRemoval(of: home.appending(path: path)), "\(path) is refused")
        }
        // The rule is about that folder of a container, not about two words side by side anywhere on the disk.
        for path in ["Library/Application Support/Vendor/data/documents.db", "Library/Application Support/Vendor/Data/Documents-old/a.txt"] {
            try directory.file("home/" + path)
            #expect(guardian.allowsRemoval(of: home.appending(path: path)), "\(path) is refused, and the reason given would be wrong")
        }

        try directory.setPermissions(0o000, of: "home/Library/Containers/com.example.empty/Data/Documents")
        defer { try? directory.setPermissions(0o755, of: "home/Library/Containers/com.example.empty/Data/Documents") }
        #expect(!guardian.allowsRemoval(of: home.appending(path: "Library/Containers/com.example.empty")), "a folder that cannot be read was taken for empty")
    }

    /// Every account on the Mac has a keychain and a mailbox. Like the helper, the guard refuses another
    /// account's as well as those of the account Peel runs in.
    @Test func whatAnotherAccountKeeps() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let guardian = RemovalGuard(environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root")))

        for path in ["/Users/somebody/Library/Keychains/login.keychain-db", "/Users/somebody/Library/Mail", "/Users/somebody/.ssh/id_ed25519", "/Users/somebody/Library"] {
            #expect(!guardian.allowsRemoval(of: URL(filePath: path)), "ATTACK SUCCEEDED: \(path) is allowed")
        }
        #expect(guardian.allowsRemoval(of: URL(filePath: "/Users/somebody/Library/Caches/com.example.app")))
    }

    /// A photo, music, or video library is refused by its name wherever it sits, so no list can say where one is.
    /// A folder that holds one a level or two down is refused too, since moving it would take the library along.
    @Test func theFolderAroundSomebodysLibrary() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try directory.file("home/Movies/Archive/Family.photoslibrary/database/Photos.sqlite")
        try directory.file("home/Movies/Old/2019/Trip.tvlibrary/Library.db")
        try directory.file("home/Movies/Clips/holiday.mov")
        let guardian = RemovalGuard(environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root")))

        for path in ["Movies/Archive", "Movies/Old", "Movies/Old/2019", "Movies/Archive/Family.photoslibrary"] {
            #expect(!guardian.allowsRemoval(of: home.appending(path: path)), "ATTACK SUCCEEDED: \(path) goes, and a library with it")
        }
        #expect(guardian.allowsRemoval(of: home.appending(path: "Movies/Clips")))
        #expect(guardian.allowsRemoval(of: home.appending(path: "Movies/Clips/holiday.mov")))
    }

    /// Work that lives in a cache folder and nowhere else, asked both ways: the folder itself, what is inside
    /// it, and every folder above it that would take it along.
    @Test func workKeptInsideACacheFolder() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try directory.file("home/Library/Caches/JetBrains/IntelliJIdea2026.2/LocalHistory/changes.storageData")
        try directory.file("home/Library/Caches/JetBrains/IntelliJIdea2026.2/caches/names.dat")
        try directory.file("home/Library/Caches/deno/location_data/abc/kv.sqlite3")
        try directory.file("home/Library/Caches/deno/deps/https/x.ts")
        let guardian = RemovalGuard(environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root")))

        let kept = [
            "Library/Caches/JetBrains", "Library/Caches/JetBrains/IntelliJIdea2026.2",
            "Library/Caches/JetBrains/IntelliJIdea2026.2/LocalHistory", "Library/Caches/JetBrains/IntelliJIdea2026.2/LocalHistory/changes.storageData",
            "Library/Caches/deno", "Library/Caches/deno/location_data", "Library/Caches/deno/location_data/abc/kv.sqlite3",
        ]
        for path in kept {
            #expect(!guardian.allowsRemoval(of: home.appending(path: path)), "\(path) may be removed")
        }
        for path in ["Library/Caches/JetBrains/IntelliJIdea2026.2/caches", "Library/Caches/deno/deps"] {
            #expect(guardian.allowsRemoval(of: home.appending(path: path)), "\(path) is refused")
        }
    }

    /// On macOS 26 a path can name a file in ways no list of spellings covers: `/.vol/<device>/<inode>` reaches a
    /// folder by its numbers, `/.nofollow/` and `/.resolve/<flags>/` take any whole path after them, and
    /// `realpath` resolves none of the three. So the guard asks the disk what a path names and compares that with
    /// the protected folders.
    @Test func aNameTheDiskAnswersToAndNoListKnows() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let mail = try directory.directory("home/Library/Mail")
        let letter = try directory.file("home/Library/Mail/V10/letter.emlx")
        let cache = try directory.file("home/Library/Caches/com.example.app/cache.db")
        let guardian = RemovalGuard(environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root")))
        let (device, number) = try #require(inode(mail.path(percentEncoded: false)))
        let library = try #require(inode(home.appending(path: "Library").path(percentEncoded: false)))

        let byNumber = URL(filePath: "/.vol/\(device)/\(number)/V10/letter.emlx")
        try #require(FileManager.default.fileExists(atPath: byNumber.path(percentEncoded: false)), "this Mac does not answer to volfs names")
        #expect(!guardian.allowsRemoval(of: byNumber), "ATTACK SUCCEEDED: a letter in Mail is allowed under its volume and inode numbers")
        #expect(!guardian.allowsRemoval(of: URL(filePath: "/.vol/\(device)/\(number)")), "ATTACK SUCCEEDED: Mail itself, by its numbers")
        #expect(!guardian.allowsRemoval(of: URL(filePath: "/.vol/\(library.0)/\(library.1)")), "ATTACK SUCCEEDED: the Library around Mail, by its numbers")
        // A file by its own numbers sits in no folder the text shows: only the kernel can say where it is.
        let numbered = try #require(inode(letter.path(percentEncoded: false)))
        #expect(!guardian.allowsRemoval(of: URL(filePath: "/.vol/\(numbered.0)/\(numbered.1)")), "ATTACK SUCCEEDED: a letter in Mail, by its own numbers")
        #expect(!guardian.allowsRemoval(of: URL(filePath: "/.nofollow/.vol/\(numbered.0)/\(numbered.1)")), "ATTACK SUCCEEDED: the two together")
        // The kernel gives each of these one name, the file's real path, and that is the name the guard goes by.
        let real = PathPattern.canonical(letter).path(percentEncoded: false)
        for sideways in ["/.vol/\(numbered.0)/\(numbered.1)", "/.nofollow/.vol/\(numbered.0)/\(numbered.1)", "/.nofollow" + real, "/.resolve/0" + real] {
            #expect(PathPattern.kernelName(of: sideways, followingLinks: false) == real, "\(sideways) is not named by the kernel as the file it is")
        }

        // Neither prefix follows a link, and the temporary folder is reached through one (`/var`).
        for prefix in ["/.nofollow", "/.resolve/0"] {
            let renamed = URL(filePath: prefix + real)
            try #require(FileManager.default.fileExists(atPath: renamed.path(percentEncoded: false)), "this Mac does not answer to \(prefix)")
            #expect(!guardian.allowsRemoval(of: renamed), "ATTACK SUCCEEDED: a letter in Mail is allowed behind \(prefix)")
        }
        #expect(guardian.allowsRemoval(of: cache.deletingLastPathComponent()), "an ordinary cache is no longer removable")
    }

    /// A `String` treats a slash and a combining mark after it as one character, so `hasPrefix("…/mail/")` is
    /// false for a file in Mail whose name begins with one, and every rule that reads names misses it. The disk
    /// still says the file is in Mail.
    @Test func aNameThatBeginsWithACombiningMark() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let letter = try directory.file("home/Library/Mail/\u{301}letter.emlx")
        let guardian = RemovalGuard(environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root")))

        #expect(!guardian.allowsRemoval(of: letter), "ATTACK SUCCEEDED: a letter in Mail whose name begins with a combining mark")
        #expect(!guardian.allowsRemoval(of: home.appending(path: "Library/Mail/\u{301}not there yet")), "ATTACK SUCCEEDED: Put Back into Mail")
    }

    /// The Trash would take the files of the global preferences domain like any other, but they belong to no app.
    @Test func theFilesOfTheGlobalDomain() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try directory.directory("home/Library/Preferences/ByHost")
        let guardian = RemovalGuard(environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root")))
        let homePath = home.path(percentEncoded: false)

        let global = [
            home.appending(path: "Library/Preferences/.GlobalPreferences.plist"),
            home.appending(path: "Library/Preferences/.globalpreferences_m.plist"),
            home.appending(path: "Library/Preferences/ByHost/.GlobalPreferences.0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9.plist"),
            URL(filePath: "/Library/Preferences/.GlobalPreferences.plist"),
        ]
        for url in global {
            #expect(!guardian.allowsRemoval(of: url), "\(url.lastPathComponent) may be removed")
            #expect(ProtectedData.refuses(url.path(percentEncoded: false), home: homePath))
        }
        #expect(guardian.allowsRemoval(of: home.appending(path: "Library/Preferences/com.example.app.plist")))
        #expect(guardian.allowsRemoval(of: home.appending(path: "Documents/.GlobalPreferences.plist")))
    }
}
