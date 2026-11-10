import Foundation
@testable import PeelCore
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

    /// Neither a protected place nor one Peel searches, such a folder is kept only by the helper's own question.
    @Test func theHelperRefusesAFolderThatOnlyHoldsAWalletsKeys() throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Application Support/Bitcoin/wallets/wallet.dat")
        try directory.file("home/Library/Application Support/Bitcoin/blocks/blk00000.dat")
        try directory.file("home/Library/Ethereum/keystore/UTC--key")
        func refusal(_ path: String) -> PrivilegedPathPolicy.Rejection? {
            policy(directory).refusal(of: directory.url.appending(path: path).path(percentEncoded: false))
        }

        for holder in ["home/Library/Application Support/Bitcoin", "home/Library/Ethereum"] {
            #expect(refusal(holder) == .irreplaceable, "ATTACK SUCCEEDED: root would move \(holder) and the keys in it")
        }
        #expect(refusal("home/Library/Application Support/Bitcoin/blocks") == nil, "the blockchain beside the keys")
    }

    @Test func whatMacOSKeepsUnderAPlainNameInTheMacsLibraryStays() throws {
        let directory = try TemporaryDirectory()
        let guardian = RemovalGuard(environment: SearchEnvironment(
            homeDirectory: try directory.directory("home"), rootDirectory: try directory.directory("root")
        ))
        let macOSs = [
            "/Library/Preferences/OpenDirectory", "/Library/Preferences/Logging", "/Library/Application Support/Apple",
            "/Library/Application Support/CrashReporter", "/private/var/db/receipts/com.apple.pkg.example.bom",
        ]
        for path in macOSs {
            #expect(ProtectedData.refuses(path, home: "/Users/someone"), "the helper's rules would move \(path)")
            #expect(guardian.refusal(of: URL(filePath: path)) != nil, "the guard would move \(path)")
        }
        #expect(!ProtectedData.refuses("/private/var/db/receipts/org.example.vendor.pkg.bom", home: "/Users/someone"))
        #expect(!ProtectedData.refuses("/Library/Application Support/org.example.vendor", home: "/Users/someone"))
    }

    /// The helper serves all of `<home>/Library`, so it must refuse the irreplaceable parts on its own.
    @Test func theHelperRefusesICloudDriveAndKeychains() throws {
        let directory = try TemporaryDirectory()
        let paths = [
            "home/Library/Mobile Documents/com~apple~CloudDocs/Thesis.pages",
            "home/Library/Keychains/login.keychain-db",
            "home/Library/Messages/chat.db",
            "home/Library/Application Support/CloudDocs/session/db/client.db",
            "home/Library/Caches/CloudKit/CloudKitMetadata",
            "home/Library/Caches/com.apple.FileProviderDaemon.AppStoreService/cache.db",
        ]
        for path in paths {
            try directory.file(path)
        }

        for path in paths {
            let result = policy(directory).open(directory.url.appending(path: path).path(percentEncoded: false))
            #expect(result.rejection == .irreplaceable, "ATTACK SUCCEEDED: the helper would move \(path)")
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
            #expect(result.rejection == .irreplaceable, "ATTACK SUCCEEDED: root would move \(path) and what it holds")
        }
        #expect(!policy(directory).open(directory.url.appending(path: "home/Library/Caches/com.example.app").path(percentEncoded: false)).isFailure)
    }

    @Test func whatTheHelperJudgesIsTheFolderItOpens() throws {
        let directory = try TemporaryDirectory()
        let vendor = try directory.directory("home/Library/Caches/Vendor/item")
        try directory.file("home/Library/Caches/Other/item/Family.photoslibrary/database/Photos.sqlite")
        let caches = vendor.deletingLastPathComponent().deletingLastPathComponent()

        let result = policy(directory).open(vendor.path(percentEncoded: false)) {
            try? FileManager.default.moveItem(at: caches.appending(path: "Vendor"), to: caches.appending(path: "Aside"))
            try? FileManager.default.moveItem(at: caches.appending(path: "Other"), to: caches.appending(path: "Vendor"))
        }

        #expect(result.rejection == .irreplaceable, "ATTACK SUCCEEDED: root would move a photo library from a folder swapped in after the check")
    }

    @Test func anItemSwappedForAnotherAfterItWasOpenedStays() throws {
        let directory = try TemporaryDirectory()
        let judged = try directory.file("home/Library/Caches/org.example.app/cache.db").deletingLastPathComponent()
        let other = try directory.file("home/Library/Caches/org.example.kept/keep.db").deletingLastPathComponent()
        let item = try policy(directory).open(judged.path(percentEncoded: false)).get()
        try FileManager.default.moveItem(at: judged, to: judged.deletingLastPathComponent().appending(path: "Aside"))
        try FileManager.default.moveItem(at: other, to: judged)
        let trash = try DirectoryHandle.at(try directory.directory("Trash").path(percentEncoded: false)).get()

        #expect(TrashMover.move(item, into: trash).posixCode == .ENOENT, "ATTACK SUCCEEDED: another item at the checked name moved")
        #expect(FileManager.default.fileExists(atPath: judged.appending(path: "keep.db").path(percentEncoded: false)))
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

        #expect(result.rejection == .irreplaceable, "ATTACK SUCCEEDED: the helper would move a keychain through a link it never saw")
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
            #expect(result.rejection == .controlCharacter, "ATTACK SUCCEEDED: \(name.debugDescription) was accepted")
        }
        let trash = try #require(policy.openTrash(ownedBy: getuid()))
        #expect(policy.openInTrash(path("home/.Trash/", in: directory) + "Real.app\u{0}.txt", trash: trash) == nil)
        #expect(!policy.open(path("root/Applications/Real.app", in: directory)).isFailure)
    }

    /// A case insensitive APFS volume reads `ſ` as `s` and `ß` as `ss`, so another spelling of a protected
    /// folder's last name finds the folder itself. The helper judges the name the disk gives the item it found.
    @Test func anotherSpellingOfAProtectedNameFindsNoWayIn() throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Messages/chat.db")
        try directory.file("home/Library/Keychains/login.keychain-db")
        let library = directory.url.appending(path: "home/Library").path(percentEncoded: false)

        for spelling in ["Meſſages", "Keychainſ", "Keychains/login.keychain-db".replacingOccurrences(of: "s", with: "ſ")] {
            let result = policy(directory).open(library + "/" + spelling)
            #expect(result.rejection == .irreplaceable, "ATTACK SUCCEEDED: the helper would move \(spelling)")
        }
    }

    @Test func anotherSpellingOfAFolderPeelSearchesFindsNoWayIn() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/Library/Logs/org.example.app")
        try directory.directory("home/Library/LaunchAgents")
        try directory.directory("home/Library/Audio/Plug-Ins/Components")
        let library = directory.url.appending(path: "home/Library").path(percentEncoded: false)

        for spelling in ["Log\u{17F}", "LaunchAgent\u{17F}", "Audio/Plug-Ins/Component\u{17F}", "Audio/Plug-In\u{17F}"] {
            let result = policy(directory).open(library + "/" + spelling)
            #expect(result.rejection == .irreplaceable, "ATTACK SUCCEEDED: the helper would move \(spelling) whole")
            #expect(policy(directory).refusal(of: library + "/" + spelling) == .irreplaceable)
        }
        let asked = try policy(directory).open(library + "/Log\u{17F}/ORG.EXAMPLE.APP").get()
        #expect(asked.name == "ORG.EXAMPLE.APP", "the ledger records the name History asks to put back")
    }

    @Test func aFolderSwappedForAnotherSpellingBeforeItsNameIsReadStays() throws {
        let directory = try TemporaryDirectory()
        let decoy = try directory.directory("home/Library/Log\u{17F}")
        let aside = try directory.directory("home/Library/Aside")
        let library = decoy.deletingLastPathComponent()
        let logs = library.appending(path: "Logs"), other = library.appending(path: "Other")
        func move(_ from: URL, to: URL) { try? FileManager.default.moveItem(at: from, to: to) }

        let result = policy(directory).open(
            decoy.path(percentEncoded: false),
            beforeOpening: { move(decoy, to: other); move(aside, to: logs) },
            beforeReadingItsName: { move(logs, to: aside); move(other, to: decoy) }
        )

        #expect(result.rejection == .missing, "ATTACK SUCCEEDED: the rules judged another folder than the Logs that moves")
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
        #expect(result.rejection == .irreplaceable, "ATTACK SUCCEEDED: a symlinked parent reached iCloud Drive")
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

    /// macOS keeps the Mac's own settings and jobs under Apple's name in `/Library`, beside every vendor's, and
    /// nothing but macOS makes them again, so the helper refuses them by name, before anything is opened.
    @Test func theHelperRefusesWhatMacOSKeepsUnderApplesNameInTheMacsLibrary() {
        let policy = PrivilegedPathPolicy(homeDirectory: NSHomeDirectory())
        let macOSs = [
            "/Library/Preferences/com.apple.example.plist",
            "/Library/Preferences/SystemConfiguration",
            "/Library/Preferences/SystemConfiguration/preferences.plist",
            "/Library/LaunchDaemons/com.apple.example.plist",
            "/Library/LaunchAgents/com.apple.example.plist",
            "/Library/PrivilegedHelperTools/com.apple.example",
            "/Library/Application Support/com.apple.example/Settings.plist",
        ]
        for path in macOSs {
            #expect(policy.refusal(of: path) == .irreplaceable, "ATTACK SUCCEEDED: the helper would move \(path)")
        }
        let vendors = ["/Library/Preferences/org.example.vendor.plist", "/Library/LaunchDaemons/org.example.vendor.plist"]
        for path in vendors {
            #expect(policy.refusal(of: path) == nil, "\(path) refused")
        }
    }
}

extension AttackHelperPolicyTests {
    private func servingPolicy(
        _ directory: borrowing TemporaryDirectory,
        trusting owner: uid_t = 0
    ) -> PrivilegedPathPolicy {
        let root = directory.url.path(percentEncoded: false)
        return PrivilegedPathPolicy(
            homeDirectory: root + "home",
            systemLocations: [root + "root/Applications", root + "root/Library/LaunchDaemons", root + "root/Library/Caches"],
            applicationLocations: [root + "root/Applications"],
            restoreLocations: [root + "root/Applications", root + "root/Library/Caches"],
            trustedOwner: owner
        )
    }

    private func movedByTheHelper(
        _ relative: String,
        _ text: String,
        policy: PrivilegedPathPolicy,
        ledger: HelperLedger,
        in directory: borrowing TemporaryDirectory
    ) throws -> String {
        try Data(text.utf8).write(to: try directory.file(relative))
        let item = try policy.open(path(relative, in: directory)).get()
        #expect(ledger.record([item], movedBy: getuid()))
        return try TrashMover.move(item, into: try #require(policy.openTrash(ownedBy: getuid()))).get()
    }

    /// A process of the user swaps its own object into the item's name right before the helper renames it.
    private func swappingIn(_ payload: String) -> TrashMover.ExclusiveRename {
        { item, name, folder in
            _ = renameatx_np(item.parent.descriptor, item.name, item.parent.descriptor, payload, UInt32(RENAME_SWAP))
            return TrashMover.renameExclusively(item, to: name, in: folder)
        }
    }

    /// The request comes from a record any process of the account can rewrite, so only the ledger says where to.
    @Test func putBackGoesOnlyWhereTheLedgerSaysTheItemCameFrom() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("root/Library/Caches")
        try directory.directory("root/Library/LaunchDaemons")
        try directory.directory("home/.Trash")
        let policy = servingPolicy(directory, trusting: getuid())
        let ledger = try #require(HelperLedger(at: directory.url.appending(path: "private/moved.plist")))
        let original = path("root/Library/Caches/org.example.settings.plist", in: directory)
        let trashed = try movedByTheHelper(
            "root/Library/Caches/org.example.settings.plist", "the app's", policy: policy, ledger: ledger,
            in: directory
        )

        for elsewhere in ["root/Library/Caches/org.example.other.plist", "root/Library/LaunchDaemons/org.example.job.plist"] {
            let destination = path(elsewhere, in: directory)
            let refusal = HelperPutBack.run(trashed, to: destination, for: getuid(), policy: policy, ledger: { ledger })
            #expect(refusal == HelperRefusal.notInRecord.rawValue, "ATTACK SUCCEEDED: an item went back to \(elsewhere)")
            #expect(!FileManager.default.fileExists(atPath: destination))
        }
        #expect(FileManager.default.fileExists(atPath: trashed))
        #expect(HelperPutBack.run(trashed, to: original, for: getuid(), policy: policy, ledger: { ledger }) == nil)
    }

    @Test func anObjectSwappedInDuringPutBackNeverReachesAFolderCodeIsLoadedFrom() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("root/Library/LaunchDaemons")
        try directory.directory("home/.Trash")
        let policy = servingPolicy(directory, trusting: getuid())
        let ledger = try #require(HelperLedger(at: directory.url.appending(path: "private/moved.plist")))
        let original = path("root/Library/LaunchDaemons/org.example.daemon.plist", in: directory)
        let trashed = try movedByTheHelper(
            "root/Library/LaunchDaemons/org.example.daemon.plist", "the daemon's", policy: policy, ledger: ledger,
            in: directory
        )
        try Data("the user's".utf8).write(to: URL(filePath: path("home/.Trash/payload", in: directory)))

        let refusal = HelperPutBack.run(
            trashed, to: original, for: getuid(), policy: policy, ledger: { ledger }, exclusively: swappingIn("payload")
        )

        #expect(
            refusal == HelperRefusal.notInRecord.rawValue,
            "ATTACK SUCCEEDED: root put the user's own object back where launchd reads daemons"
        )
        #expect(!FileManager.default.fileExists(atPath: original))
        let inTheTrash = Set(try FileManager.default.contentsOfDirectory(atPath: path("home/.Trash", in: directory)))
        #expect(inTheTrash.count == 2, "both objects stay in the Trash")
    }

    @Test func anItemChangedInTheTrashAfterTheLookNeverGoesBackWhereCodeIsLoaded() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("root/Library/LaunchDaemons")
        try directory.directory("home/.Trash")
        let policy = servingPolicy(directory, trusting: getuid())
        let ledger = try #require(HelperLedger(at: directory.url.appending(path: "private/moved.plist")))
        let original = path("root/Library/LaunchDaemons/org.example.daemon.plist", in: directory)
        let trashed = try movedByTheHelper(
            "root/Library/LaunchDaemons/org.example.daemon.plist", "the daemon's", policy: policy, ledger: ledger,
            in: directory
        )
        let openedToEveryone: TrashMover.ExclusiveRename = { item, name, folder in
            _ = fchmodat(item.parent.descriptor, item.name, 0o666, AT_SYMLINK_NOFOLLOW)
            return TrashMover.renameExclusively(item, to: name, in: folder)
        }

        let refusal = HelperPutBack.run(
            trashed, to: original, for: getuid(), policy: policy, ledger: { ledger }, exclusively: openedToEveryone
        )

        #expect(
            refusal == PrivilegedPathPolicy.Rejection.loadsCode.explanation,
            "ATTACK SUCCEEDED: a file anyone could rewrite went back where launchd reads daemons"
        )
        #expect(!FileManager.default.fileExists(atPath: original))
        #expect(FileManager.default.fileExists(atPath: trashed))
    }

    @Test func anObjectSwappedInDuringPutBackNeverReachesAFolderThatTakesAnything() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("root/Library/Caches")
        try directory.directory("home/.Trash")
        let policy = servingPolicy(directory)
        let ledger = try #require(HelperLedger(at: directory.url.appending(path: "private/moved.plist")))
        let original = path("root/Library/Caches/org.example.cache", in: directory)
        let trashed = try movedByTheHelper(
            "root/Library/Caches/org.example.cache", "the app's", policy: policy, ledger: ledger, in: directory
        )
        try Data("the user's".utf8).write(to: URL(filePath: path("home/.Trash/payload", in: directory)))

        let refusal = HelperPutBack.run(
            trashed, to: original, for: getuid(), policy: policy, ledger: { ledger }, exclusively: swappingIn("payload")
        )

        #expect(
            refusal == HelperRefusal.notInRecord.rawValue,
            "ATTACK SUCCEEDED: root put back an object the helper never moved"
        )
        #expect(!FileManager.default.fileExists(atPath: original))
    }

    @Test func aMoveToTheTrashTakesOnlyTheItemThatWasOpened() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/.Trash")
        try directory.file("root/Library/Caches/org.example.cache", contents: Data("the app's".utf8))
        try directory.file("root/Library/Caches/payload", contents: Data("the user's".utf8))
        let policy = servingPolicy(directory)
        let ledger = try #require(HelperLedger(at: directory.url.appending(path: "private/moved.plist")))
        let original = path("root/Library/Caches/org.example.cache", in: directory)
        let item = try policy.open(original).get()
        let trash = try #require(policy.openTrash(ownedBy: getuid()))

        let result = try #require(TrashMover.moveRecorded(
            [(original, item)], into: trash, ledger: ledger, movedBy: getuid(), exclusively: swappingIn("payload")
        ))

        #expect(result.moved.isEmpty, "ATTACK SUCCEEDED: root moved an object it never judged")
        #expect(result.failed[original] == PrivilegedPathPolicy.Rejection.missing.explanation)
        #expect(try FileManager.default.contentsOfDirectory(atPath: path("home/.Trash", in: directory)).isEmpty)
        #expect(try String(contentsOfFile: original, encoding: .utf8) == "the user's")
        #expect(try ledger.origin(of: item, movedBy: getuid()) == nil)
    }

    @Test func anItemThatCannotGoBackToItsFolderKeepsItsRecord() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/.Trash")
        let vendor = try directory.directory("home/Library/org.example.vendor").path(percentEncoded: false)
        try directory.file("home/Library/org.example.vendor/tool", contents: Data("the tool".utf8))
        let rules = policy(directory)
        let ledger = try #require(HelperLedger(at: directory.url.appending(path: "private/moved.plist")))
        let original = path("home/Library/org.example.vendor/tool", in: directory)
        let item = try rules.open(original).get()
        let trash = try #require(rules.openTrash(ownedBy: getuid()))
        let losingBothFolders: TrashMover.ExclusiveRename = { item, name, folder in
            let result = TrashMover.renameExclusively(item, to: name, in: folder)
            _ = rmdir(vendor)
            _ = rmdir(trash.path)
            return result
        }

        let result = try #require(TrashMover.moveRecorded(
            [(original, item)], into: trash, ledger: ledger, movedBy: getuid(), exclusively: losingBothFolders
        ))

        #expect(result.moved.isEmpty)
        #expect(result.failed[original] == HelperRefusal.keptByTheHelper.rawValue)
        let staging = path("private/Staging", in: directory)
        let left = try #require(try FileManager.default.contentsOfDirectory(atPath: staging).first)
        let staged = try OpenItem.at(staging + "/" + left).get()
        #expect(try ledger.origin(of: staged, movedBy: getuid()) == item.path, "an item that left its folder has no record")
    }

    @Test func anItemPutBackThatCannotReturnToTheTrashKeepsItsRecord() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("root/Library/Caches")
        try directory.directory("home/.Trash")
        let policy = servingPolicy(directory, trusting: getuid())
        let ledger = try #require(HelperLedger(at: directory.url.appending(path: "private/moved.plist")))
        let original = path("root/Library/Caches/org.example.settings.plist", in: directory)
        let trashed = try movedByTheHelper(
            "root/Library/Caches/org.example.settings.plist", "the app's", policy: policy, ledger: ledger, in: directory
        )
        let caches = path("root/Library/Caches", in: directory), trash = path("home/.Trash", in: directory)
        let losingBothFolders: TrashMover.ExclusiveRename = { item, name, folder in
            let result = TrashMover.renameExclusively(item, to: name, in: folder)
            _ = rmdir(caches)
            _ = rmdir(trash)
            return result
        }

        let answer = HelperPutBack.run(
            trashed, to: original, for: getuid(), policy: policy, ledger: { ledger }, exclusively: losingBothFolders
        )

        #expect(answer == HelperRefusal.keptByTheHelper.rawValue)
        let staging = path("private/Staging", in: directory)
        let left = try #require(try FileManager.default.contentsOfDirectory(atPath: staging).first)
        #expect(try ledger.origin(of: OpenItem.at(staging + "/" + left).get(), movedBy: getuid()) != nil)
    }

    @Test func theHelperMovesNothingWhereARenameCannotRefuseToReplace() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("root/Library/Caches")
        try directory.directory("home/.Trash")
        let policy = servingPolicy(directory)
        let ledger = try #require(HelperLedger(at: directory.url.appending(path: "private/moved.plist")))
        let original = path("root/Library/Caches/org.example.cache", in: directory)
        let trashed = try movedByTheHelper(
            "root/Library/Caches/org.example.cache", "the app's", policy: policy, ledger: ledger, in: directory
        )
        let unsupported: TrashMover.ExclusiveRename = { _, _, _ in .failure(POSIXError(.ENOTSUP)) }
        try directory.file("root/Library/Caches/org.example.other")
        let other = path("root/Library/Caches/org.example.other", in: directory)
        let trash = try #require(policy.openTrash(ownedBy: getuid()))

        let refusal = HelperPutBack.run(
            trashed, to: original, for: getuid(), policy: policy, ledger: { ledger }, exclusively: unsupported
        )
        let result = try #require(TrashMover.moveRecorded(
            [(other, try policy.open(other).get())], into: trash, ledger: ledger, movedBy: getuid(),
            exclusively: unsupported
        ))

        #expect(refusal == POSIXError(.ENOTSUP).localizedDescription)
        #expect(!FileManager.default.fileExists(atPath: original), "the helper replaced a placeholder by name")
        #expect(FileManager.default.fileExists(atPath: trashed))
        #expect(result.failed[other] == POSIXError(.ENOTSUP).localizedDescription)
        #expect(FileManager.default.fileExists(atPath: other))
    }

    @Test func aNameTakenMeanwhileSendsTheItemBackToTheTrash() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("root/Library/Caches")
        try directory.directory("home/.Trash")
        let policy = servingPolicy(directory)
        let ledger = try #require(HelperLedger(at: directory.url.appending(path: "private/moved.plist")))
        let original = path("root/Library/Caches/org.example.cache", in: directory)
        let trashed = try movedByTheHelper(
            "root/Library/Caches/org.example.cache", "the app's", policy: policy, ledger: ledger, in: directory
        )
        let takingTheName: TrashMover.ExclusiveRename = { item, name, folder in
            FileManager.default.createFile(atPath: original, contents: Data("another".utf8))
            return TrashMover.renameExclusively(item, to: name, in: folder)
        }

        let refusal = HelperPutBack.run(
            trashed, to: original, for: getuid(), policy: policy, ledger: { ledger }, exclusively: takingTheName
        )

        #expect(refusal == POSIXError(.EEXIST).localizedDescription)
        #expect(try String(contentsOfFile: original, encoding: .utf8) == "another")
        #expect(try String(contentsOfFile: trashed, encoding: .utf8) == "the app's")
        let trash = try #require(policy.openTrash(ownedBy: getuid()))
        let back = try #require(policy.openInTrash(trashed, trash: trash))
        #expect(try ledger.origin(of: back, movedBy: getuid()) != nil, "it could never be put back again")
    }

    @Test func anItemOnAnotherDiskThanTheHelpersFolderStaysInTheTrash() throws {
        let directory = try TemporaryDirectory()
        let disk = try ScratchVolume(fileSystem: "APFS", mountedAt: directory.url.appending(path: "Disk"))
        let home = disk.url.appending(path: "home").path(percentEncoded: false)
        try FileManager.default.createDirectory(atPath: home + "/.Trash", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: home + "/Library/Caches", withIntermediateDirectories: true)
        let policy = PrivilegedPathPolicy(homeDirectory: home, systemLocations: [], applicationLocations: [])
        let ledger = try #require(HelperLedger(at: directory.url.appending(path: "private/moved.plist")))
        let original = home + "/Library/Caches/org.example.cache"
        try Data("the app's".utf8).write(to: URL(filePath: original))
        let item = try policy.open(original).get()
        #expect(ledger.record([item], movedBy: getuid()))
        let trashed = try TrashMover.move(item, into: try #require(policy.openTrash(ownedBy: getuid()))).get()

        let refusal = HelperPutBack.run(trashed, to: original, for: getuid(), policy: policy, ledger: { ledger })

        #expect(
            refusal == POSIXError(.EXDEV).localizedDescription,
            "the helper moved an item by name with nowhere to check it first"
        )
        #expect(FileManager.default.fileExists(atPath: trashed))
        #expect(!FileManager.default.fileExists(atPath: original))
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
    @Test func restoreRefusesToPlantALaunchDaemon() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("root/Library/LaunchDaemons")
        try directory.directory("root/Library/Caches")
        try directory.directory("root/Applications")
        let policy = servingPolicy(directory)

        try directory.file("home/.Trash/com.attacker.plist")
        let trash = try #require(policy.openTrash(ownedBy: getuid()))
        let payload = try #require(policy.openInTrash(path("home/.Trash/com.attacker.plist", in: directory), trash: trash))

        let planted = path("root/Library/LaunchDaemons/com.attacker.plist", in: directory)
        #expect(policy.openDestination(planted, for: payload).rejection == .loadsCode, "ATTACK SUCCEEDED: a root launch daemon can be planted")
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

    @Test func anInstanceOfADaemonMacOSShipsIsRefused() {
        let shipped: Set<String> = ["com.openssh.sshd", "org.cups.cups-lpd"]
        let instances = [
            "com.openssh.sshd.DFF8D2B5-E315-46B4-9087-D4072EBC64DC",
            "org.cups.cups-lpd.11111111-2222-3333-4444-555555555555",
        ]
        for label in instances {
            #expect(!PrivilegedPathPolicy.allowsDaemon(label, shipped: shipped), "ATTACK SUCCEEDED: the helper would stop \(label)")
        }
        #expect(PrivilegedPathPolicy.allowsDaemon("com.openssh.sshd-wrapper", shipped: shipped))
        #expect(PrivilegedPathPolicy.allowsDaemon("org.example.vendor.daemon", shipped: shipped))
    }

    /// The helper builds its whole policy around this string: which home is the caller's, which Trash is opened.
    @Test func theHelperRefusesWhatAContainersDocumentsHoldOnItsOwn() throws {
        let directory = try TemporaryDirectory()
        let path = "home/Library/Containers/com.example.notes/Data/Documents/novel.txt"
        try directory.file(path)

        let result = policy(directory).open(directory.url.appending(path: path).path(percentEncoded: false))
        #expect(result.rejection == .irreplaceable, "ATTACK SUCCEEDED: root would move a document out of an app's container")
    }

    /// Peel looks inside each of these folders and offers what an app left there, never the folder itself.
    @Test func theHelperRefusesEveryFolderPeelSearchesInTheUsersLibrary() throws {
        let directory = try TemporaryDirectory()
        for folder in LibraryFolder.inTheUsersLibrary {
            let path = "home/Library/" + folder.rawValue
            try directory.directory(path)
            let result = policy(directory).open(directory.url.appending(path: path).path(percentEncoded: false))
            #expect(result.rejection == .irreplaceable, "ATTACK SUCCEEDED: root would move \(path) whole")
        }
        let inside = try directory.directory("home/Library/Caches/com.example.app")
        #expect(!policy(directory).open(inside.path(percentEncoded: false)).isFailure)
    }

    @Test func theHelperRefusesAFolderItServesThatSitsInsideAnotherItServes() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("root/Library/Application Support/Avid/Audio/Plug-Ins/Example.aaxplugin")
        try directory.directory("root/Library/Application Support/Mail/Plug-ins/Bundles/Example.mailbundle")
        let served = [
            "Application Support", "Application Support/Avid/Audio/Plug-Ins", "Application Support/Mail/Plug-ins/Bundles",
        ].map { directory.url.appending(path: "root/Library/" + $0).path(percentEncoded: false) }
        let rules = PrivilegedPathPolicy(
            homeDirectory: directory.url.appending(path: "home").path(percentEncoded: false),
            systemLocations: served, applicationLocations: []
        )

        for folder in served.dropFirst() {
            #expect((try? rules.open(folder).get()) == nil, "root would move \(folder) whole, with every vendor's plug-in in it")
            #expect(rules.refusal(ofPuttingBack: folder, owner: 0, mode: S_IFDIR | 0o755) == nil)
        }
        #expect((try? rules.open(served[1] + "/Example.aaxplugin").get()) != nil)
    }

    @Test func theHelperRefusesAFolderAroundOnePeelSearches() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/Library/Application Support/Avid/Audio/Plug-Ins")
        try directory.directory("home/Library/Application Support/Avid/Pro Tools")
        try directory.directory("home/Library/Audio/Plug-Ins/Components")
        try directory.directory("root/Library/Application Support/Avid/Audio/Plug-Ins")
        try directory.directory("root/Library/Application Support/Avid/Pro Tools")
        try directory.directory("root/Library/Application Support/Chromium/NativeMessagingHosts")
        try directory.directory("home/Library/Application Support/Google/Chrome/NativeMessagingHosts")
        let root = directory.url.path(percentEncoded: false) + "/"
        let policy = PrivilegedPathPolicy(
            homeDirectory: root + "home",
            systemLocations: [root + "root/Library/Application Support", root + "root/Library/Application Support/Avid/Audio/Plug-Ins"],
            restoreLocations: [],
            manifestLocations: [root + "root/Library/Application Support/Chromium/NativeMessagingHosts"]
        )
        func opens(_ path: String) -> Bool {
            policy.open(directory.url.appending(path: path).path(percentEncoded: false)).rejection == nil
        }
        func refusal(_ path: String) -> PrivilegedPathPolicy.Rejection? {
            policy.open(directory.url.appending(path: path).path(percentEncoded: false)).rejection
        }

        for holder in [
            "home/Library/Application Support/Avid", "home/Library/Application Support/Avid/Audio", "home/Library/Audio",
            "home/Library/Audio/Plug-Ins", "root/Library/Application Support/Avid", "root/Library/Application Support/AVID",
        ] {
            #expect(refusal(holder) == .irreplaceable, "ATTACK SUCCEEDED: root would move \(holder) whole, and a folder Peel searches with it")
        }
        #expect(opens("home/Library/Application Support/Avid/Pro Tools"))
        #expect(opens("root/Library/Application Support/Avid/Pro Tools"))
        // A browser's own data goes with the browser, the folder it reads manifests from included.
        #expect(opens("home/Library/Application Support/Google/Chrome"))
        #expect(opens("root/Library/Application Support/Chromium"))
    }

    @Test func theHelperRefusesACachesFolderWithAnIDEsLocalHistoryThreeLevelsDown() throws {
        let directory = try TemporaryDirectory()
        let caches = "home/Library/Containers/com.example.ide/Data/Library/Caches"
        try directory.file(caches + "/JetBrains/IntelliJIdea2026.2/LocalHistory/changes.storageData")

        let result = policy(directory).open(directory.url.appending(path: caches).path(percentEncoded: false))
        #expect(result.rejection == .irreplaceable, "ATTACK SUCCEEDED: root would move a Caches folder and the local history inside it")
    }

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

private extension Result where Failure == PrivilegedPathPolicy.Rejection {
    var rejection: PrivilegedPathPolicy.Rejection? {
        if case .failure(let rejection) = self { rejection } else { nil }
    }
}

private extension Result where Failure == POSIXError {
    var posixCode: POSIXError.Code? {
        if case .failure(let error) = self { error.code } else { nil }
    }
}
